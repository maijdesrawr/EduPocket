<?php

declare(strict_types=1);

require_once __DIR__ . '/email_verification_common.php';
require_once __DIR__ . '/app_session_common.php';

pc_bootstrap_json_endpoint();

$conn = null;
$transactionStarted = false;

try {
    pc_require_post();
    $challengeToken = pc_post_string('challenge_token');
    if ($challengeToken === '') {
        $challengeToken = pc_post_string('token');
    }
    $code = pc_post_string('code');
    $challengeTokenHash = ev_challenge_token_hash($challengeToken);
    $config = pc_security_config();

    $conn = pc_open_database();
    $appSession = as_require_session($conn, false);
    ev_require_schema($conn);
    $preview = ev_challenge_preview($conn, $challengeTokenHash);
    if ($preview === null) {
        pc_reject('The email-verification request is invalid or has expired.');
    }
    $role = pc_normalize_role((string)$preview['role']);
    $accountSource = (string)$preview['account_source'];
    $userId = (string)$preview['user_id'];
    pc_validate_user_id($userId);
    as_assert_session_identity($appSession, $role, $userId, $accountSource);

    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Email-verification transaction could not start.');
    }
    $transactionStarted = true;

    $account = pc_fetch_account_for_update($conn, $role, $userId, $accountSource);
    $canonicalUserId = (string)$account['user_id'];
    if (!hash_equals($userId, $canonicalUserId)) {
        throw new RuntimeException('Email-verification account ID binding changed unexpectedly.');
    }
    $userId = $canonicalUserId;
    $challenge = ev_challenge_for_update($conn, $challengeTokenHash);
    if ($challenge === null
        || (int)$challenge['challenge_id'] !== (int)$preview['challenge_id']
        || (string)$challenge['role'] !== $role
        || (string)$challenge['account_source'] !== $accountSource
        || (string)$challenge['user_id'] !== $userId
    ) {
        throw new RuntimeException('Email-verification challenge binding changed unexpectedly.');
    }
    ev_assert_pending_challenge($challenge);

    if ((int)($challenge['challenge_expired'] ?? 1) === 1
        || (int)($challenge['otp_expired'] ?? 1) === 1
    ) {
        ev_set_challenge_status($conn, (int)$challenge['challenge_id'], 'expired');
        if (!$conn->commit()) {
            throw new RuntimeException('Expired email-verification challenge could not be committed.');
        }
        $transactionStarted = false;
        pc_reject('The verification code expired. Start a new request.');
    }

    $currentFingerprint = pc_account_fingerprint(
        $role,
        $accountSource,
        $userId,
        (string)$account['password_value'],
        $config
    );
    if (!hash_equals((string)$challenge['account_fingerprint'], $currentFingerprint)) {
        ev_set_challenge_status($conn, (int)$challenge['challenge_id'], 'cancelled');
        if (!$conn->commit()) {
            throw new RuntimeException('Stale email-verification challenge could not be committed.');
        }
        $transactionStarted = false;
        pc_reject('Your password changed after this request started. Start a new request.');
    }

    $storedOtpHash = (string)($challenge['otp_hash'] ?? '');
    $candidateOtpHash = preg_match('/^\d{6}$/', $code) === 1
        ? ev_otp_hash($challengeTokenHash, $code, $config)
        : '';
    if ($storedOtpHash === ''
        || $candidateOtpHash === ''
        || !hash_equals($storedOtpHash, $candidateOtpHash)
    ) {
        $attemptsRemaining = ev_increment_failed_attempt(
            $conn,
            (int)$challenge['challenge_id'],
            (int)$challenge['failed_attempts']
        );
        if (!$conn->commit()) {
            throw new RuntimeException('Failed email-verification attempt could not be committed.');
        }
        $transactionStarted = false;
        pc_reject(
            $attemptsRemaining > 0
                ? 'Incorrect verification code. Please try again.'
                : 'Too many incorrect verification attempts. Start a new request.',
            ['attempts_remaining' => $attemptsRemaining]
        );
    }

    $stage = (string)($challenge['stage'] ?? '');
    if (!in_array($stage, ['verify_old', 'verify_new'], true)) {
        throw new RuntimeException('Email-verification challenge stage is invalid.');
    }
    $proposedEmail = ev_decrypt_challenge_email(
        (string)$challenge['proposed_email_encrypted'],
        'proposed',
        $role,
        $accountSource,
        $userId,
        $config
    );
    if (!hash_equals(
        (string)$challenge['proposed_email_fingerprint'],
        ev_email_fingerprint($proposedEmail, $config)
    )) {
        throw new RuntimeException('Proposed email integrity check failed.');
    }

    $existing = ev_verified_email_record($conn, $role, $accountSource, $userId, true);
    $priorFingerprint = $challenge['prior_email_fingerprint'] ?? null;
    if ($priorFingerprint === null || $priorFingerprint === '') {
        if ($existing !== null) {
            ev_set_challenge_status($conn, (int)$challenge['challenge_id'], 'cancelled');
            if (!$conn->commit()) {
                throw new RuntimeException('Conflicting email enrollment could not be committed.');
            }
            $transactionStarted = false;
            pc_reject('A verified email was added after this request started. Start a new request.');
        }
    } elseif ($existing === null
        || !hash_equals((string)$existing['email_fingerprint'], (string)$priorFingerprint)
    ) {
        ev_set_challenge_status($conn, (int)$challenge['challenge_id'], 'cancelled');
        if (!$conn->commit()) {
            throw new RuntimeException('Stale email replacement could not be committed.');
        }
        $transactionStarted = false;
        pc_reject('The verified email changed after this request started. Start a new request.');
    }

    if ($stage === 'verify_old') {
        pc_email_config($config);
        if ($existing === null) {
            throw new RuntimeException('Current verified email is missing.');
        }
        $oldEmail = ev_decrypt_verified_email(
            (string)$existing['email_encrypted'],
            $role,
            $accountSource,
            $userId,
            $config
        );
        $otpDestination = ev_decrypt_challenge_email(
            (string)$challenge['otp_destination_encrypted'],
            'destination',
            $role,
            $accountSource,
            $userId,
            $config
        );
        if (!hash_equals($oldEmail, $otpDestination)) {
            throw new RuntimeException('Current email challenge binding is invalid.');
        }

        $newTokenData = ev_new_challenge_token();
        $newChallengeToken = $newTokenData['token'];
        $newTokenHash = $newTokenData['hash'];
        $newOtp = pc_generate_email_otp();
        $newOtpHash = ev_otp_hash($newTokenHash, $newOtp, $config);
        $newDestinationEncrypted = ev_encrypt_challenge_email(
            $proposedEmail,
            'destination',
            $role,
            $accountSource,
            $userId,
            $config
        );
        $newDestinationMasked = pc_mask_email($proposedEmail);
        $statement = pc_prepare(
            $conn,
            'UPDATE email_verification_challenges '
                . "SET challenge_token_hash = ?, stage = 'verify_new', "
                . 'otp_destination_encrypted = ?, otp_destination_masked = ?, otp_hash = ?, '
                . 'otp_expires_at = DATE_ADD(NOW(6), INTERVAL 5 MINUTE), '
                . 'expires_at = DATE_ADD(NOW(6), INTERVAL 5 MINUTE), '
                . 'failed_attempts = 0, resend_count = 0, last_sent_at = NOW(6) '
                . "WHERE challenge_id = ? AND status = 'pending'"
        );
        $challengeId = (int)$challenge['challenge_id'];
        $statement->bind_param(
            'ssssi',
            $newTokenHash,
            $newDestinationEncrypted,
            $newDestinationMasked,
            $newOtpHash,
            $challengeId
        );
        if (!$statement->execute() || $statement->affected_rows !== 1) {
            $statement->close();
            throw new RuntimeException('Email replacement could not advance to the new address.');
        }
        $statement->close();
        as_record_activity(
            $conn,
            $appSession,
            'email_change_current_verified',
            null,
            'server',
            'info',
            $config
        );
        if (!$conn->commit()) {
            throw new RuntimeException('Email replacement transaction could not be committed.');
        }
        $transactionStarted = false;

        $sent = pc_send_email_otp(
            $config,
            $proposedEmail,
            $newOtp,
            [
                'purpose' => 'email_verification',
                'stage' => 'verify_new',
                'role' => $role,
                'account_source' => $accountSource,
                'user_id' => $userId,
                'expires_in' => EV_OTP_TTL_SECONDS,
            ]
        );
        if (!$sent) {
            if ($conn->begin_transaction()) {
                ev_cancel_challenge_by_hash($conn, $newTokenHash);
                $conn->commit();
            }
            $conn->close();
            $conn = null;
            pc_reject('The verification email could not be sent. Start a new request.');
        }
        $conn->close();
        $conn = null;
        pc_respond([
            'status' => 'success',
            'message' => 'Current email confirmed. A code was sent to the new email address.',
            'verification_complete' => false,
            'next_step' => 'verify_new_email',
            'challenge_token' => $newChallengeToken,
            'destination' => $newDestinationMasked,
            'expires_in' => EV_OTP_TTL_SECONDS,
            'attempts_remaining' => EV_MAX_ATTEMPTS,
            'resend_after' => EV_RESEND_COOLDOWN_SECONDS,
        ]);
    }

    $otpDestination = ev_decrypt_challenge_email(
        (string)$challenge['otp_destination_encrypted'],
        'destination',
        $role,
        $accountSource,
        $userId,
        $config
    );
    if (!hash_equals($proposedEmail, $otpDestination)) {
        throw new RuntimeException('New email challenge binding is invalid.');
    }
    $emailMasked = ev_save_verified_email(
        $conn,
        $role,
        $accountSource,
        $userId,
        $proposedEmail,
        $config
    );
    ev_set_challenge_status($conn, (int)$challenge['challenge_id'], 'verified');
    ev_cancel_pending_challenges($conn, $role, $accountSource, $userId);
    pc_cancel_pending_challenges($conn, $role, $accountSource, $userId);
    as_record_activity(
        $conn,
        $appSession,
        ($priorFingerprint === null || $priorFingerprint === '')
            ? 'email_verified'
            : 'email_changed',
        null,
        'server',
        'success',
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
        'message' => 'Email address verified successfully.',
        'verification_complete' => true,
        'email_masked' => $emailMasked,
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
    error_log('verify_email_verification.php failed: ' . $error->getMessage());
    pc_respond([
        'status' => 'error',
        'message' => 'Email verification is temporarily unavailable. Please try again later.',
    ]);
}
