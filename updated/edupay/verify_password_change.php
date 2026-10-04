<?php

declare(strict_types=1);

require_once __DIR__ . '/password_change_common.php';
require_once __DIR__ . '/app_session_common.php';

pc_bootstrap_json_endpoint();

$conn = null;
$transactionStarted = false;

try {
    pc_require_post();

    $challengeToken = pc_post_string('challenge_token');
    $code = pc_post_string('code');
    $challengeTokenHash = pc_challenge_token_hash($challengeToken);
    $config = pc_security_config();

    $conn = pc_open_database();
    $appSession = as_require_session($conn, false);
    $preview = pc_challenge_preview($conn, $challengeTokenHash);
    if ($preview === null) {
        pc_reject('The password-change request is invalid or has expired.');
    }

    $role = pc_normalize_role((string)$preview['role']);
    $accountSource = (string)$preview['account_source'];
    $userId = (string)$preview['user_id'];
    pc_validate_user_id($userId);
    as_assert_session_identity($appSession, $role, $userId, $accountSource);

    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Password-change transaction could not start.');
    }
    $transactionStarted = true;

    $account = pc_fetch_account_for_update(
        $conn,
        $role,
        $userId,
        $accountSource
    );
    $canonicalUserId = (string)$account['user_id'];
    if (!hash_equals($userId, $canonicalUserId)) {
        throw new RuntimeException('Password-change account ID binding changed unexpectedly.');
    }
    $userId = $canonicalUserId;
    as_assert_session_identity($appSession, $role, $userId, $accountSource);
    $challenge = pc_challenge_for_update($conn, $challengeTokenHash);
    if ($challenge === null
        || (int)$challenge['challenge_id'] !== (int)$preview['challenge_id']
        || (string)$challenge['role'] !== $role
        || (string)$challenge['account_source'] !== $accountSource
        || (string)$challenge['user_id'] !== $userId
    ) {
        throw new RuntimeException('Challenge binding changed unexpectedly.');
    }

    pc_assert_pending_challenge($challenge);
    if ((int)($challenge['challenge_expired'] ?? 1) === 1) {
        pc_expire_challenge($conn, (int)$challenge['challenge_id']);
        if (!$conn->commit()) {
            throw new RuntimeException('Expired challenge could not be committed.');
        }
        $transactionStarted = false;
        pc_reject('The verification code expired. Start a new password-change request.');
    }

    $currentCredential = $account['password_value'];
    $currentFingerprint = pc_account_fingerprint(
        $role,
        $accountSource,
        $userId,
        $currentCredential,
        $config
    );
    if (!hash_equals((string)$challenge['account_fingerprint'], $currentFingerprint)) {
        pc_mark_challenge_cancelled($conn, $challengeTokenHash);
        if (!$conn->commit()) {
            throw new RuntimeException('Stale challenge could not be committed.');
        }
        $transactionStarted = false;
        pc_reject(
            'Your account password changed after this request started. Start a new password-change request.'
        );
    }

    $method = pc_normalize_method((string)$challenge['method']);
    $matchedTotpStep = null;
    $verificationMatches = false;

    if ($method === 'email') {
        if ((int)($challenge['otp_expired'] ?? 1) === 1) {
            pc_expire_challenge($conn, (int)$challenge['challenge_id']);
            if (!$conn->commit()) {
                throw new RuntimeException('Expired OTP could not be committed.');
            }
            $transactionStarted = false;
            pc_reject('The verification code expired. Start a new password-change request.');
        }
        $storedOtpHash = (string)($challenge['otp_hash'] ?? '');
        $candidateOtpHash = preg_match('/^\d{6}$/', $code) === 1
            ? pc_email_otp_hash($challengeTokenHash, $code, $config)
            : '';
        $verificationMatches = $storedOtpHash !== ''
            && $candidateOtpHash !== ''
            && hash_equals($storedOtpHash, $candidateOtpHash);
    } else {
        if ((int)($challenge['requires_totp_setup'] ?? 0) === 1) {
            $existingAuthenticator = pc_authenticator_for_update(
                $conn,
                $role,
                $accountSource,
                $userId
            );
            if ($existingAuthenticator !== null) {
                pc_mark_challenge_cancelled($conn, $challengeTokenHash);
                if (!$conn->commit()) {
                    throw new RuntimeException('Stale authenticator setup could not be committed.');
                }
                $transactionStarted = false;
                pc_reject(
                    'An authenticator was linked after this request started. Start a new password-change request.'
                );
            }
        }
        $totp = pc_totp_material_for_challenge($conn, $challenge, $config);
        $matchedTotpStep = pc_match_totp_step(
            $totp['secret'],
            $code,
            $totp['last_used_step']
        );
        $verificationMatches = $matchedTotpStep !== null;
    }

    if (!$verificationMatches) {
        $attemptsRemaining = pc_increment_failed_attempt(
            $conn,
            (int)$challenge['challenge_id'],
            (int)$challenge['failed_attempts']
        );
        if (!$conn->commit()) {
            throw new RuntimeException('Failed attempt could not be committed.');
        }
        $transactionStarted = false;
        pc_reject(
            $attemptsRemaining > 0
                ? 'Incorrect or already-used verification code. Please try again.'
                : 'Too many incorrect verification attempts. Start a new password-change request.',
            ['attempts_remaining' => $attemptsRemaining]
        );
    }

    $newPasswordHash = (string)($challenge['new_password_hash'] ?? '');
    if (!pc_is_password_hash($newPasswordHash)) {
        throw new RuntimeException('Challenge password hash is invalid.');
    }

    $oldHistoryHash = pc_is_password_hash($currentCredential)
        ? $currentCredential
        : pc_hash_password($currentCredential);
    pc_record_password_history(
        $conn,
        $role,
        $accountSource,
        $userId,
        $oldHistoryHash
    );
    pc_record_password_history(
        $conn,
        $role,
        $accountSource,
        $userId,
        $newPasswordHash
    );
    pc_update_account_password(
        $conn,
        $role,
        $accountSource,
        $userId,
        $newPasswordHash
    );

    if ($method === 'totp') {
        if (!is_int($matchedTotpStep)) {
            throw new RuntimeException('Matched authenticator step is missing.');
        }
        if ((int)($challenge['requires_totp_setup'] ?? 0) === 1) {
            $pendingSecret = (string)($challenge['pending_totp_secret_encrypted'] ?? '');
            if ($pendingSecret === '') {
                throw new RuntimeException('Pending authenticator enrollment is missing.');
            }
            pc_save_authenticator(
                $conn,
                $role,
                $accountSource,
                $userId,
                $pendingSecret,
                $matchedTotpStep
            );
        } else {
            pc_touch_authenticator(
                $conn,
                $role,
                $accountSource,
                $userId,
                $matchedTotpStep
            );
        }
    }

    pc_mark_challenge_verified($conn, (int)$challenge['challenge_id']);
    pc_cancel_pending_challenges($conn, $role, $accountSource, $userId);
    as_record_activity(
        $conn,
        $appSession,
        'password_changed',
        ['verification_method' => $method],
        'server',
        'success',
        $config
    );
    as_mark_session_revoked($conn, $appSession, 'password_changed', $config);

    if (!$conn->commit()) {
        throw new RuntimeException('Password-change transaction could not be committed.');
    }
    $transactionStarted = false;
    $conn->close();
    $conn = null;

    pc_respond([
        'status' => 'success',
        'message' => 'Password changed successfully. Please sign in with your new password.',
        'method' => $method,
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
    error_log('verify_password_change.php failed: ' . $error->getMessage());
    pc_respond([
        'status' => 'error',
        'message' => 'Password change is temporarily unavailable. Please try again later.',
    ]);
}
