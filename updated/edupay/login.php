<?php

require_once __DIR__ . '/login_otp_common.php';

pc_bootstrap_json_endpoint();
pc_require_post();

$conn = null;
$transactionStarted = false;

try {
    lo_require_secure_transport();

    $loginId = lo_normalize_login_id(pc_post_string('id'));
    $password = pc_post_string('password', false);
    $deviceId = as_normalize_device_id(pc_post_string('device_id'));
    if ($loginId === '' || $password === '') {
        pc_reject('Enter both your user ID and password.');
    }

    $conn = pc_open_database();
    $config = pc_security_config();
    if (!pc_table_exists($conn, 'login_otp_challenges')) {
        throw new RuntimeException('The login OTP database migration has not been applied.');
    }
    as_assert_tables($conn);

    $account = lo_find_login_account($conn, $loginId);
    if ($account === null) {
        password_verify($password, LO_DUMMY_PASSWORD_HASH);
        pc_reject('Invalid ID or password.');
    }

    $storedCredential = (string)($account['password_value'] ?? '');
    if (!pc_password_matches($password, $storedCredential)) {
        if (!pc_is_password_hash($storedCredential)) {
            password_verify($password, LO_DUMMY_PASSWORD_HASH);
        }
        pc_reject('Invalid ID or password.');
    }

    $role = pc_normalize_role((string)$account['app_role']);
    $accountSource = (string)$account['account_source'];
    $userId = (string)$account['id'];
    $methods = lo_available_methods($conn, $role, $accountSource, $userId);

    if ($methods === []) {
        if (!$conn->begin_transaction()) {
            throw new RuntimeException('A secure app session could not be started.');
        }
        $transactionStarted = true;
        $lockedAccount = pc_fetch_account_for_update($conn, $role, $userId, $accountSource);
        if (!pc_password_matches($password, (string)$lockedAccount['password_value'])) {
            pc_reject('Invalid ID or password.');
        }
        $issued = as_issue_session(
            $conn,
            $config,
            $role,
            $accountSource,
            $userId,
            $deviceId,
            (string)$lockedAccount['password_value'],
            'password'
        );
        if (!$conn->commit()) {
            throw new RuntimeException('The secure app session could not be committed.');
        }
        $transactionStarted = false;
        pc_respond(array_merge([
            'status' => 'success',
            'role' => $role,
            'account_source' => $accountSource,
            'id' => $userId,
            'name' => (string)$account['name'],
            'password_changed' => (bool)($account['password_changed'] ?? true),
            'otp_enrollment_available' => false,
        ], as_public_session_payload($issued)));
    }

    $method = in_array('totp', $methods, true) ? 'totp' : 'email';
    ['token' => $challengeToken, 'hash' => $challengeTokenHash] = pc_new_challenge_token();
    $accountFingerprint = pc_account_fingerprint(
        $role,
        $accountSource,
        $userId,
        $storedCredential,
        $config
    );
    $requestIpHash = lo_remote_ip_hash($config);
    $deviceIdHash = as_device_id_hash($deviceId);

    $emailOtp = null;
    $emailDestination = null;
    $destinationMasked = null;
    $otpHash = null;
    if ($method === 'email') {
        $destination = lo_email_destination(
            $conn,
            $config,
            $role,
            $accountSource,
            $userId
        );
        $emailDestination = (string)$destination['address'];
        $destinationMasked = (string)$destination['masked'];
        $emailOtp = pc_generate_email_otp();
        $otpHash = pc_email_otp_hash($challengeTokenHash, $emailOtp, $config);
    }

    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Login verification could not be started.');
    }
    $transactionStarted = true;
    lo_enforce_challenge_rate_limits(
        $conn,
        $role,
        $accountSource,
        $userId,
        $method,
        $requestIpHash
    );
    lo_cancel_pending_challenges($conn, $role, $accountSource, $userId);

    $statement = pc_prepare(
        $conn,
        'INSERT INTO login_otp_challenges '
            . '(challenge_token_hash, role, account_source, user_id, method, '
            . 'account_fingerprint, device_id_hash, request_ip_hash, otp_hash, otp_expires_at, destination_masked, '
            . 'last_sent_at, expires_at) '
            . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, '
            . "CASE WHEN ? IS NULL THEN NULL ELSE DATE_ADD(NOW(6), INTERVAL 5 MINUTE) END, ?, "
            . "CASE WHEN ? IS NULL THEN NULL ELSE NOW(6) END, "
            . 'DATE_ADD(NOW(6), INTERVAL 5 MINUTE))'
    );
    $statement->bind_param(
        'ssssssssssss',
        $challengeTokenHash,
        $role,
        $accountSource,
        $userId,
        $method,
        $accountFingerprint,
        $deviceIdHash,
        $requestIpHash,
        $otpHash,
        $otpHash,
        $destinationMasked,
        $otpHash
    );
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Login verification challenge could not be created.');
    }
    $statement->close();
    if (!$conn->commit()) {
        throw new RuntimeException('Login verification challenge could not be committed.');
    }
    $transactionStarted = false;

    if ($method === 'email' && !lo_send_email_code(
        $config,
        (string)$emailDestination,
        (string)$emailOtp,
        $role,
        $accountSource,
        $userId
    )) {
        $cancel = pc_prepare(
            $conn,
            "UPDATE login_otp_challenges SET status = 'cancelled' WHERE challenge_token_hash = ?"
        );
        $cancel->bind_param('s', $challengeTokenHash);
        $cancel->execute();
        $cancel->close();
        pc_reject('The login code could not be sent. Please try again.');
    }

    pc_respond([
        'status' => 'otp_required',
        'message' => $method === 'totp'
            ? 'Enter the 6-digit code from Google Authenticator.'
            : 'Enter the 6-digit code sent to your verified email.',
        'challenge_token' => $challengeToken,
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
    error_log('login.php failed: ' . $error->getMessage());
    pc_respond(pc_client_error_payload('Login could not be completed. Please try again.'));
} finally {
    if ($conn instanceof mysqli) {
        $conn->close();
    }
}
