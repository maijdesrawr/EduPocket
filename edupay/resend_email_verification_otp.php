<?php

declare(strict_types=1);

require_once __DIR__ . '/email_verification_common.php';
require_once __DIR__ . '/app_session_common.php';

pc_bootstrap_json_endpoint();

$conn = null;
$transactionStarted = false;

try {
    pc_require_post();
    $oldChallengeToken = pc_post_string('challenge_token');
    if ($oldChallengeToken === '') {
        $oldChallengeToken = pc_post_string('token');
    }
    $oldTokenHash = ev_challenge_token_hash($oldChallengeToken);
    $config = pc_security_config();
    pc_email_config($config);

    $conn = pc_open_database();
    $appSession = as_require_session($conn, false);
    ev_require_schema($conn);
    $preview = ev_challenge_preview($conn, $oldTokenHash);
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
    $challenge = ev_challenge_for_update($conn, $oldTokenHash);
    if ($challenge === null
        || (int)$challenge['challenge_id'] !== (int)$preview['challenge_id']
        || (string)$challenge['role'] !== $role
        || (string)$challenge['account_source'] !== $accountSource
        || (string)$challenge['user_id'] !== $userId
    ) {
        throw new RuntimeException('Email-verification challenge binding changed unexpectedly.');
    }
    ev_assert_pending_challenge($challenge);

    if ((int)($challenge['challenge_expired'] ?? 1) === 1) {
        ev_set_challenge_status($conn, (int)$challenge['challenge_id'], 'expired');
        if (!$conn->commit()) {
            throw new RuntimeException('Expired email-verification challenge could not be committed.');
        }
        $transactionStarted = false;
        pc_reject('The email-verification request expired. Start a new request.');
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

    $resendCount = (int)($challenge['resend_count'] ?? 0);
    if ($resendCount >= EV_MAX_RESENDS) {
        pc_reject('The resend limit was reached. Start a new request.');
    }
    $secondsSinceLastSend = max(0, (int)($challenge['seconds_since_last_send'] ?? 0));
    if ($secondsSinceLastSend < EV_RESEND_COOLDOWN_SECONDS) {
        pc_reject(
            'Please wait before requesting another verification code.',
            ['retry_after' => EV_RESEND_COOLDOWN_SECONDS - $secondsSinceLastSend]
        );
    }

    $stage = (string)($challenge['stage'] ?? '');
    if (!in_array($stage, ['verify_old', 'verify_new'], true)) {
        throw new RuntimeException('Email-verification challenge stage is invalid.');
    }
    $destination = ev_decrypt_challenge_email(
        (string)$challenge['otp_destination_encrypted'],
        'destination',
        $role,
        $accountSource,
        $userId,
        $config
    );
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
        if ($existing !== null || $stage !== 'verify_new' || !hash_equals($destination, $proposedEmail)) {
            throw new RuntimeException('First email enrollment binding is invalid.');
        }
    } else {
        if ($existing === null
            || !hash_equals((string)$existing['email_fingerprint'], (string)$priorFingerprint)
        ) {
            ev_set_challenge_status($conn, (int)$challenge['challenge_id'], 'cancelled');
            if (!$conn->commit()) {
                throw new RuntimeException('Stale email replacement could not be committed.');
            }
            $transactionStarted = false;
            pc_reject('The verified email changed after this request started. Start a new request.');
        }
        $oldEmail = ev_decrypt_verified_email(
            (string)$existing['email_encrypted'],
            $role,
            $accountSource,
            $userId,
            $config
        );
        if (($stage === 'verify_old' && !hash_equals($destination, $oldEmail))
            || ($stage === 'verify_new' && !hash_equals($destination, $proposedEmail))
        ) {
            throw new RuntimeException('Email replacement destination binding is invalid.');
        }
    }

    $newTokenData = ev_new_challenge_token();
    $newChallengeToken = $newTokenData['token'];
    $newTokenHash = $newTokenData['hash'];
    $newOtp = pc_generate_email_otp();
    $newOtpHash = ev_otp_hash($newTokenHash, $newOtp, $config);
    $statement = pc_prepare(
        $conn,
        'UPDATE email_verification_challenges '
            . 'SET challenge_token_hash = ?, otp_hash = ?, '
            . 'otp_expires_at = DATE_ADD(NOW(6), INTERVAL 5 MINUTE), '
            . 'expires_at = DATE_ADD(NOW(6), INTERVAL 5 MINUTE), '
            . 'resend_count = resend_count + 1, last_sent_at = NOW(6) '
            . "WHERE challenge_id = ? AND status = 'pending'"
    );
    $challengeId = (int)$challenge['challenge_id'];
    $statement->bind_param('ssi', $newTokenHash, $newOtpHash, $challengeId);
    if (!$statement->execute() || $statement->affected_rows !== 1) {
        $statement->close();
        throw new RuntimeException('Verification code could not be renewed.');
    }
    $statement->close();
    as_record_activity(
        $conn,
        $appSession,
        'email_verification_otp_resent',
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
        $newOtp,
        [
            'purpose' => 'email_verification',
            'stage' => $stage,
            'role' => $role,
            'account_source' => $accountSource,
            'user_id' => $userId,
            'expires_in' => EV_OTP_TTL_SECONDS,
            'is_resend' => true,
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

    $destinationMasked = (string)$challenge['otp_destination_masked'];
    $attemptsRemaining = max(
        0,
        EV_MAX_ATTEMPTS - (int)($challenge['failed_attempts'] ?? 0)
    );
    $conn->close();
    $conn = null;
    pc_respond([
        'status' => 'success',
        'message' => 'A new 6-digit verification code was sent.',
        'challenge_token' => $newChallengeToken,
        'destination' => $destinationMasked,
        'expires_in' => EV_OTP_TTL_SECONDS,
        'attempts_remaining' => $attemptsRemaining,
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
    error_log('resend_email_verification_otp.php failed: ' . $error->getMessage());
    pc_respond([
        'status' => 'error',
        'message' => 'Email verification is temporarily unavailable. Please try again later.',
    ]);
}
