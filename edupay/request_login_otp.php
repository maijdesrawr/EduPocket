<?php

require_once __DIR__ . '/login_otp_common.php';

pc_bootstrap_json_endpoint();
pc_require_post();

$conn = null;
$transactionStarted = false;

try {
    lo_require_secure_transport();

    $challengeToken = pc_post_string('challenge_token');
    $method = pc_normalize_method(pc_post_string('method'));
    $deviceId = as_normalize_device_id(pc_post_string('device_id'));
    if ($challengeToken === '') {
        pc_reject('The login verification request is missing. Please log in again.');
    }

    $config = pc_security_config();
    $tokenHash = pc_challenge_token_hash($challengeToken);
    $conn = pc_open_database();
    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Login verification could not be updated.');
    }
    $transactionStarted = true;

    $challenge = lo_challenge_for_update($conn, $tokenHash);
    if ($challenge === null) {
        pc_reject('The login verification request is invalid or expired.');
    }
    lo_assert_pending_challenge($challenge);
    $challengeDeviceHash = (string)($challenge['device_id_hash'] ?? '');
    if ($challengeDeviceHash === ''
        || !hash_equals($challengeDeviceHash, as_device_id_hash($deviceId))
    ) {
        pc_reject('This login verification request belongs to a different device. Please log in again.');
    }

    $role = (string)$challenge['role'];
    $accountSource = (string)$challenge['account_source'];
    $userId = (string)$challenge['user_id'];
    $methods = lo_available_methods($conn, $role, $accountSource, $userId);
    if (!in_array($method, $methods, true)) {
        pc_reject('That verification method is not available for this account.');
    }

    $otp = null;
    $otpHash = null;
    $destination = null;
    $destinationMasked = null;
    $resendCount = (int)($challenge['resend_count'] ?? 0);
    if ($method === 'email') {
        if ($resendCount >= LO_MAX_RESENDS) {
            pc_reject('The email-code resend limit was reached. Please log in again.');
        }
        $lastSent = strtotime((string)($challenge['last_sent_at'] ?? ''));
        if ($lastSent !== false) {
            $remaining = LO_RESEND_COOLDOWN_SECONDS - (time() - $lastSent);
            if ($remaining > 0) {
                pc_reject('Please wait before requesting another email code.', [
                    'retry_after' => $remaining,
                ]);
            }
        }
        $email = lo_email_destination($conn, $config, $role, $accountSource, $userId);
        $destination = (string)$email['address'];
        $destinationMasked = (string)$email['masked'];
        $otp = pc_generate_email_otp();
        $otpHash = pc_email_otp_hash($tokenHash, $otp, $config);
        $resendCount++;
    }

    $statement = pc_prepare(
        $conn,
        'UPDATE login_otp_challenges SET method = ?, otp_hash = ?, '
            . 'otp_expires_at = CASE WHEN ? IS NULL THEN NULL '
            . 'ELSE DATE_ADD(NOW(6), INTERVAL 5 MINUTE) END, '
            . 'destination_masked = ?, resend_count = ?, '
            . 'last_sent_at = CASE WHEN ? IS NULL THEN last_sent_at ELSE NOW(6) END, '
            . 'expires_at = DATE_ADD(NOW(6), INTERVAL 5 MINUTE) '
            . 'WHERE challenge_id = ?'
    );
    $challengeId = (int)$challenge['challenge_id'];
    $statement->bind_param(
        'ssssisi',
        $method,
        $otpHash,
        $otpHash,
        $destinationMasked,
        $resendCount,
        $otpHash,
        $challengeId
    );
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Verification method could not be updated.');
    }
    $statement->close();
    if (!$conn->commit()) {
        throw new RuntimeException('Verification method could not be committed.');
    }
    $transactionStarted = false;

    if ($method === 'email' && !lo_send_email_code(
        $config,
        (string)$destination,
        (string)$otp,
        $role,
        $accountSource,
        $userId
    )) {
        pc_reject('The login code could not be sent. Please try again.');
    }

    pc_respond([
        'status' => 'success',
        'message' => $method === 'email'
            ? 'A new 6-digit code was sent to your verified email.'
            : 'Enter the current 6-digit code from Google Authenticator.',
        'method' => $method,
        'available_methods' => $methods,
        'destination_masked' => $destinationMasked,
        'expires_in' => LO_CHALLENGE_TTL_SECONDS,
        'resend_after' => $method === 'email' ? LO_RESEND_COOLDOWN_SECONDS : 0,
    ]);
} catch (PasswordChangeClientException $error) {
    if ($transactionStarted && $conn instanceof mysqli) {
        $conn->rollback();
    }
    if ($conn instanceof mysqli) {
        $conn->close();
        $conn = null;
    }
    pc_respond(pc_client_error_payload($error->getMessage(), $error->details()));
} catch (Throwable $error) {
    if ($transactionStarted && $conn instanceof mysqli) {
        $conn->rollback();
    }
    error_log('request_login_otp.php failed: ' . $error->getMessage());
    pc_respond(pc_client_error_payload('The login code could not be requested. Please try again.'));
} finally {
    if ($conn instanceof mysqli) {
        $conn->close();
    }
}
