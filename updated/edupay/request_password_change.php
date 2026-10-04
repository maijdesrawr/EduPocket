<?php

declare(strict_types=1);

require_once __DIR__ . '/password_change_common.php';
require_once __DIR__ . '/app_session_common.php';

pc_bootstrap_json_endpoint();

$conn = null;
$transactionStarted = false;

try {
    pc_require_post();

    $role = pc_normalize_role(pc_post_string('role'));
    $userId = pc_post_string('id');
    $currentPassword = pc_post_string('current_password', false);
    $newPassword = pc_post_string('new_password', false);
    $method = pc_normalize_method(pc_post_string('method'));
    $requestedEmail = pc_post_string('email');

    pc_validate_user_id($userId);
    if ($currentPassword === '' || $newPassword === '') {
        pc_reject('Current password and new password are required.');
    }

    $config = pc_security_config();
    if ($method === 'email') {
        pc_email_config($config);
    }

    $conn = pc_open_database();
    $appSession = as_require_session($conn, false);
    as_assert_session_identity($appSession, $role, $userId);
    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Password-change transaction could not start.');
    }
    $transactionStarted = true;

    $account = pc_fetch_account_for_update(
        $conn,
        $role,
        $userId,
        (string)$appSession['account_source']
    );
    $userId = (string)$account['user_id'];
    $accountSource = $account['account_source'];
    as_assert_session_identity($appSession, $role, $userId, $accountSource);
    $currentCredential = $account['password_value'];
    pc_assert_current_password($currentPassword, $currentCredential);
    pc_assert_password_not_reused(
        $conn,
        $role,
        $accountSource,
        $userId,
        $newPassword,
        $currentCredential
    );
    pc_validate_strong_password($newPassword);

    $accountFingerprint = pc_account_fingerprint(
        $role,
        $accountSource,
        $userId,
        $currentCredential,
        $config
    );
    $newPasswordHash = pc_hash_password($newPassword);
    $tokenData = pc_new_challenge_token();
    $challengeToken = $tokenData['token'];
    $challengeTokenHash = $tokenData['hash'];

    $emailOtp = null;
    $destination = null;
    $maskedDestination = null;
    $pendingTotpSecretEncrypted = null;
    $requiresTotpSetup = false;
    $totpSetupKey = null;
    $otpauthUri = null;

    if ($method === 'email') {
        $destination = pc_resolve_email_destination(
            $conn,
            $config,
            $role,
            $accountSource,
            $userId,
            $requestedEmail
        );
        $maskedDestination = pc_mask_email($destination);
        $destinationEncrypted = pc_encrypt_email_destination(
            $destination,
            $role,
            $accountSource,
            $userId,
            $config
        );
        $emailOtp = pc_generate_email_otp();
        $otpHash = pc_email_otp_hash($challengeTokenHash, $emailOtp, $config);
    } else {
        $authenticator = pc_authenticator_for_update(
            $conn,
            $role,
            $accountSource,
            $userId
        );
        if ($authenticator === null) {
            $requiresTotpSetup = true;
            $totpSetupKey = pc_base32_encode(random_bytes(20));
            $pendingTotpSecretEncrypted = pc_encrypt_totp_secret(
                $totpSetupKey,
                $role,
                $accountSource,
                $userId,
                $config
            );
            $otpauthUri = pc_otpauth_uri($totpSetupKey, $role, $userId, $config);
        } else {
            pc_decrypt_totp_secret(
                (string)$authenticator['totp_secret_encrypted'],
                $role,
                $accountSource,
                $userId,
                $config
            );
        }
    }

    pc_cancel_pending_challenges($conn, $role, $accountSource, $userId);

    if ($method === 'email') {
        $statement = pc_prepare(
            $conn,
            'INSERT INTO password_change_challenges '
                . '(challenge_token_hash, role, account_source, user_id, '
                . 'method, new_password_hash, '
                . 'account_fingerprint, otp_hash, otp_expires_at, '
                . 'destination_encrypted, destination_masked, '
                . 'pending_totp_secret_encrypted, requires_totp_setup, '
                . 'failed_attempts, resend_count, last_sent_at, expires_at, status) '
                . "VALUES (?, ?, ?, ?, ?, ?, ?, ?, DATE_ADD(NOW(6), INTERVAL 5 MINUTE), "
                . "?, ?, NULL, 0, 0, 0, NOW(6), "
                . "DATE_ADD(NOW(6), INTERVAL 5 MINUTE), 'pending')"
        );
        $statement->bind_param(
            'ssssssssss',
            $challengeTokenHash,
            $role,
            $accountSource,
            $userId,
            $method,
            $newPasswordHash,
            $accountFingerprint,
            $otpHash,
            $destinationEncrypted,
            $maskedDestination
        );
    } else {
        $requiresSetupInt = $requiresTotpSetup ? 1 : 0;
        $statement = pc_prepare(
            $conn,
            'INSERT INTO password_change_challenges '
                . '(challenge_token_hash, role, account_source, user_id, '
                . 'method, new_password_hash, '
                . 'account_fingerprint, otp_hash, otp_expires_at, '
                . 'destination_encrypted, destination_masked, '
                . 'pending_totp_secret_encrypted, requires_totp_setup, '
                . 'failed_attempts, resend_count, last_sent_at, expires_at, status) '
                . "VALUES (?, ?, ?, ?, ?, ?, ?, NULL, NULL, NULL, NULL, ?, ?, "
                . "0, 0, NULL, DATE_ADD(NOW(6), INTERVAL 5 MINUTE), 'pending')"
        );
        $statement->bind_param(
            'ssssssssi',
            $challengeTokenHash,
            $role,
            $accountSource,
            $userId,
            $method,
            $newPasswordHash,
            $accountFingerprint,
            $pendingTotpSecretEncrypted,
            $requiresSetupInt
        );
    }

    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Password-change challenge could not be created.');
    }
    $statement->close();
    as_record_activity(
        $conn,
        $appSession,
        'password_change_requested',
        ['verification_method' => $method],
        'server',
        'info',
        $config
    );

    if (!$conn->commit()) {
        throw new RuntimeException('Password-change transaction could not be committed.');
    }
    $transactionStarted = false;

    if ($method === 'email') {
        $sent = pc_send_email_otp(
            $config,
            (string)$destination,
            (string)$emailOtp,
            [
                'purpose' => 'password_change',
                'role' => $role,
                'account_source' => $accountSource,
                'user_id' => $userId,
                'expires_in' => PC_CHALLENGE_TTL_SECONDS,
            ]
        );
        if (!$sent) {
            if ($conn->begin_transaction()) {
                pc_mark_challenge_cancelled($conn, $challengeTokenHash);
                $conn->commit();
            }
            $conn->close();
            $conn = null;
            pc_reject(
                'The verification email could not be sent. Please try again later.'
            );
        }
    }

    $conn->close();
    $conn = null;
    pc_respond([
        'status' => 'success',
        'message' => $method === 'email'
            ? 'A 6-digit verification code was sent to your email.'
            : ($requiresTotpSetup
                ? 'Add EduPocket to your authenticator, then enter its 6-digit code.'
                : 'Enter the 6-digit code from your authenticator.'),
        'challenge_token' => $challengeToken,
        'method' => $method,
        'expires_in' => PC_CHALLENGE_TTL_SECONDS,
        'destination' => $maskedDestination,
        'requires_totp_setup' => $requiresTotpSetup,
        'totp_setup_key' => $totpSetupKey,
        'otpauth_uri' => $otpauthUri,
    ]);
} catch (PasswordChangeClientException $error) {
    if ($transactionStarted && $conn instanceof mysqli) {
        $conn->rollback();
    }
    if ($conn instanceof mysqli) {
        $conn->close();
    }
    pc_respond(pc_client_error_payload($error->getMessage(), $error->details()));
} catch (Throwable $error) {
    if ($transactionStarted && $conn instanceof mysqli) {
        $conn->rollback();
    }
    if ($conn instanceof mysqli) {
        $conn->close();
    }
    error_log('request_password_change.php failed: ' . $error->getMessage());
    pc_respond([
        'status' => 'error',
        'message' => 'Password change is temporarily unavailable. Please try again later.',
    ]);
}
