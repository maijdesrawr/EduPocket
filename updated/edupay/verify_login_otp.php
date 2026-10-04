<?php

require_once __DIR__ . '/login_otp_common.php';

pc_bootstrap_json_endpoint();
pc_require_post();

$conn = null;
$transactionStarted = false;

try {
    lo_require_secure_transport();

    $challengeToken = pc_post_string('challenge_token');
    $code = pc_post_string('code');
    $deviceId = as_normalize_device_id(pc_post_string('device_id'));
    if ($challengeToken === '' || !preg_match('/^\d{6}$/', $code)) {
        pc_reject('Enter a valid 6-digit verification code.');
    }

    $config = pc_security_config();
    $tokenHash = pc_challenge_token_hash($challengeToken);
    $conn = pc_open_database();
    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Login verification could not be started.');
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
    $account = pc_fetch_account_for_update($conn, $role, $userId, $accountSource);
    $actualFingerprint = pc_account_fingerprint(
        $role,
        $accountSource,
        $userId,
        (string)$account['password_value'],
        $config
    );
    if (!hash_equals((string)$challenge['account_fingerprint'], $actualFingerprint)) {
        $statement = pc_prepare(
            $conn,
            "UPDATE login_otp_challenges SET status = 'cancelled' WHERE challenge_id = ?"
        );
        $challengeId = (int)$challenge['challenge_id'];
        $statement->bind_param('i', $challengeId);
        $statement->execute();
        $statement->close();
        $conn->commit();
        $transactionStarted = false;
        pc_reject('Your account security changed. Please log in again.');
    }

    $method = (string)$challenge['method'];
    $verified = false;
    $matchedTotpStep = null;
    if ($method === 'email') {
        if ((int)($challenge['otp_expired'] ?? 1) !== 1) {
            $expected = pc_email_otp_hash($tokenHash, $code, $config);
            $stored = (string)($challenge['otp_hash'] ?? '');
            $verified = $stored !== '' && hash_equals($stored, $expected);
        }
    } elseif ($method === 'totp') {
        $authenticator = pc_authenticator_for_update($conn, $role, $accountSource, $userId);
        if ($authenticator !== null) {
            $secret = pc_decrypt_totp_secret(
                (string)$authenticator['totp_secret_encrypted'],
                $role,
                $accountSource,
                $userId,
                $config
            );
            $lastUsed = $authenticator['last_used_step'] ?? null;
            $matchedTotpStep = pc_match_totp_step(
                $secret,
                $code,
                $lastUsed === null ? null : (int)$lastUsed
            );
            $verified = $matchedTotpStep !== null;
        }
    }

    if (!$verified) {
        $remaining = lo_record_failed_attempt(
            $conn,
            (int)$challenge['challenge_id'],
            (int)$challenge['failed_attempts']
        );
        $conn->commit();
        $transactionStarted = false;
        pc_reject(
            $remaining > 0
                ? 'Incorrect or expired verification code.'
                : 'Too many incorrect codes. Please log in again.',
            ['remaining_attempts' => $remaining]
        );
    }

    if ($method === 'totp') {
        pc_touch_authenticator(
            $conn,
            $role,
            $accountSource,
            $userId,
            (int)$matchedTotpStep
        );
    }
    $statement = pc_prepare(
        $conn,
        "UPDATE login_otp_challenges SET status = 'verified', verified_at = NOW(6), "
            . 'otp_hash = NULL WHERE challenge_id = ?'
    );
    $challengeId = (int)$challenge['challenge_id'];
    $statement->bind_param('i', $challengeId);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Login verification could not be completed.');
    }
    $statement->close();
    $payload = lo_login_payload($conn, $role, $accountSource, $userId);
    $issued = as_issue_session(
        $conn,
        $config,
        $role,
        $accountSource,
        $userId,
        $deviceId,
        (string)$account['password_value'],
        $method
    );
    $payload = array_merge($payload, as_public_session_payload($issued));
    if (!$conn->commit()) {
        throw new RuntimeException('Login verification could not be committed.');
    }
    $transactionStarted = false;
    pc_respond($payload);
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
    error_log('verify_login_otp.php failed: ' . $error->getMessage());
    pc_respond(pc_client_error_payload('Login verification could not be completed.'));
} finally {
    if ($conn instanceof mysqli) {
        $conn->close();
    }
}
