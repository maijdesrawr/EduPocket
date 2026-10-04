<?php

declare(strict_types=1);

require_once __DIR__ . '/email_verification_common.php';
require_once __DIR__ . '/app_session_common.php';

pc_bootstrap_json_endpoint();

$conn = null;
$transactionStarted = false;

try {
    pc_require_post();
    $role = pc_normalize_role(pc_post_string('role'));
    $userId = pc_post_string('id');
    $currentPassword = pc_post_string('current_password', false);
    $proposedEmail = ev_normalize_email(pc_post_string('email'));
    pc_validate_user_id($userId);
    if ($currentPassword === '') {
        pc_reject('Current password is required.');
    }

    $config = pc_security_config();
    pc_email_config($config);
    $conn = pc_open_database();
    $appSession = as_require_session($conn, false);
    as_assert_session_identity($appSession, $role, $userId);
    ev_require_schema($conn);

    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Email-verification cleanup transaction could not start.');
    }
    $transactionStarted = true;
    ev_purge_stale_security_state($conn);
    if (!$conn->commit()) {
        throw new RuntimeException('Email-verification cleanup transaction could not be committed.');
    }
    $transactionStarted = false;

    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Email-verification rate-limit transaction could not start.');
    }
    $transactionStarted = true;
    $preAuthLimit = ev_consume_pre_auth_attempt($conn, $role, $userId, $config);
    if (!$conn->commit()) {
        throw new RuntimeException('Email-verification rate-limit transaction could not be committed.');
    }
    $transactionStarted = false;
    $preAuthRetryAfter = max(
        (int)$preAuthLimit['account_retry_after'],
        (int)$preAuthLimit['ip_retry_after']
    );
    if ($preAuthRetryAfter > 0) {
        pc_reject(
            'Too many email-verification attempts. Please try again later.',
            ['retry_after' => $preAuthRetryAfter]
        );
    }

    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Email-verification transaction could not start.');
    }
    $transactionStarted = true;

    $account = ev_authenticate_account_for_enrollment(
        $conn,
        $role,
        $userId,
        $currentPassword,
        (string)$appSession['account_source']
    );
    $userId = (string)$account['user_id'];
    $accountSource = (string)$account['account_source'];
    as_assert_session_identity($appSession, $role, $userId, $accountSource);
    $currentCredential = (string)$account['password_value'];

    $existing = ev_verified_email_record($conn, $role, $accountSource, $userId, true);
    $priorFingerprint = null;
    $stage = 'verify_new';
    $destination = $proposedEmail;
    if ($existing !== null) {
        $currentEmail = ev_decrypt_verified_email(
            (string)$existing['email_encrypted'],
            $role,
            $accountSource,
            $userId,
            $config
        );
        $priorFingerprint = ev_email_fingerprint($currentEmail, $config);
        if (!hash_equals((string)$existing['email_fingerprint'], $priorFingerprint)) {
            throw new RuntimeException('Verified email integrity check failed.');
        }
        if (hash_equals($currentEmail, $proposedEmail)) {
            as_record_activity(
                $conn,
                $appSession,
                'email_already_verified',
                null,
                'server',
                'info',
                $config
            );
            if (!$conn->commit()) {
                throw new RuntimeException('Email-verification transaction could not be committed.');
            }
            $transactionStarted = false;
            $conn->close();
            $conn = null;
            pc_respond([
                'status' => 'success',
                'message' => 'This email address is already verified for the account.',
                'verified' => true,
                'already_verified' => true,
                'verification_complete' => true,
                'email_masked' => (string)$existing['email_masked'],
            ]);
        }
        $stage = 'verify_old';
        $destination = $currentEmail;
    }
    ev_enforce_request_rate_limits($conn, $role, $accountSource, $userId, $config);

    $accountFingerprint = pc_account_fingerprint(
        $role,
        $accountSource,
        $userId,
        $currentCredential,
        $config
    );
    $tokenData = ev_new_challenge_token();
    $challengeToken = $tokenData['token'];
    $challengeTokenHash = $tokenData['hash'];
    $otp = pc_generate_email_otp();
    $otpHash = ev_otp_hash($challengeTokenHash, $otp, $config);
    $proposedEncrypted = ev_encrypt_challenge_email(
        $proposedEmail,
        'proposed',
        $role,
        $accountSource,
        $userId,
        $config
    );
    $destinationEncrypted = ev_encrypt_challenge_email(
        $destination,
        'destination',
        $role,
        $accountSource,
        $userId,
        $config
    );
    $proposedMasked = pc_mask_email($proposedEmail);
    $destinationMasked = pc_mask_email($destination);
    $proposedFingerprint = ev_email_fingerprint($proposedEmail, $config);
    $requestIpHash = (string)$preAuthLimit['ip_hash'];

    ev_cancel_pending_challenges($conn, $role, $accountSource, $userId);
    $statement = pc_prepare(
        $conn,
        'INSERT INTO email_verification_challenges '
            . '(challenge_token_hash, role, account_source, user_id, account_fingerprint, '
            . 'stage, proposed_email_encrypted, proposed_email_masked, '
            . 'proposed_email_fingerprint, prior_email_fingerprint, '
            . 'otp_destination_encrypted, otp_destination_masked, otp_hash, '
            . 'otp_expires_at, failed_attempts, resend_count, last_sent_at, expires_at, '
            . 'request_ip_hash, status) '
            . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
            . 'DATE_ADD(NOW(6), INTERVAL 5 MINUTE), 0, 0, NOW(6), '
            . "DATE_ADD(NOW(6), INTERVAL 5 MINUTE), ?, 'pending')"
    );
    $statement->bind_param(
        'ssssssssssssss',
        $challengeTokenHash,
        $role,
        $accountSource,
        $userId,
        $accountFingerprint,
        $stage,
        $proposedEncrypted,
        $proposedMasked,
        $proposedFingerprint,
        $priorFingerprint,
        $destinationEncrypted,
        $destinationMasked,
        $otpHash,
        $requestIpHash
    );
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Email-verification challenge could not be created.');
    }
    $statement->close();
    as_record_activity(
        $conn,
        $appSession,
        'email_verification_requested',
        ['stage' => $stage],
        'server',
        'info',
        $config
    );

    if (!$conn->commit()) {
        throw new RuntimeException('Email-verification transaction could not be committed.');
    }
    $transactionStarted = false;

    $sent = pc_send_email_otp(
        $config,
        $destination,
        $otp,
        [
            'purpose' => 'email_verification',
            'stage' => $stage,
            'role' => $role,
            'account_source' => $accountSource,
            'user_id' => $userId,
            'expires_in' => EV_OTP_TTL_SECONDS,
        ]
    );
    if (!$sent) {
        if ($conn->begin_transaction()) {
            ev_cancel_challenge_by_hash($conn, $challengeTokenHash);
            $conn->commit();
        }
        $conn->close();
        $conn = null;
        pc_reject('The verification email could not be sent. Please try again later.');
    }

    $conn->close();
    $conn = null;
    pc_respond([
        'status' => 'success',
        'message' => $stage === 'verify_old'
            ? 'A 6-digit code was sent to your current verified email.'
            : 'A 6-digit verification code was sent to your email.',
        'challenge_token' => $challengeToken,
        'destination' => $destinationMasked,
        'expires_in' => EV_OTP_TTL_SECONDS,
        'attempts_remaining' => EV_MAX_ATTEMPTS,
        'resend_after' => EV_RESEND_COOLDOWN_SECONDS,
        'verification_complete' => false,
        'next_step' => $stage === 'verify_old' ? 'verify_current_email' : 'verify_new_email',
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
    error_log('request_email_verification.php failed: ' . $error->getMessage());
    pc_respond([
        'status' => 'error',
        'message' => 'Email verification is temporarily unavailable. Please try again later.',
    ]);
}
