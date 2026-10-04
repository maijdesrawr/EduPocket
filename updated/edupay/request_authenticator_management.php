<?php

declare(strict_types=1);

require_once __DIR__ . '/authenticator_management_common.php';
require_once __DIR__ . '/app_session_common.php';

pc_bootstrap_json_endpoint();

$conn = null;
$transactionStarted = false;

try {
    pc_require_post();
    am_require_secure_transport();

    $role = pc_normalize_role(pc_post_string('role'));
    $userId = pc_post_string('user_id');
    $action = am_normalize_action(pc_post_string('action'));
    $currentPassword = pc_post_string('current_password', false);
    pc_validate_user_id($userId);

    $config = pc_security_config();
    $conn = pc_open_database();
    $appSession = as_require_session($conn);
    as_assert_session_identity($appSession, $role, $userId);
    am_require_schema($conn);

    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Authenticator cleanup transaction could not start.');
    }
    $transactionStarted = true;
    am_purge_stale_security_state($conn);
    if (!$conn->commit()) {
        throw new RuntimeException('Authenticator cleanup transaction could not be committed.');
    }
    $transactionStarted = false;

    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Authenticator rate-limit transaction could not start.');
    }
    $transactionStarted = true;
    $preAuthLimit = am_consume_pre_auth_attempt($conn, $role, $userId, $config);
    if (!$conn->commit()) {
        throw new RuntimeException('Authenticator rate-limit transaction could not be committed.');
    }
    $transactionStarted = false;
    $retryAfter = max(
        (int)$preAuthLimit['account_retry_after'],
        (int)$preAuthLimit['ip_retry_after']
    );
    if ($retryAfter > 0) {
        pc_reject(
            'Too many authenticator-management attempts. Please try again later.',
            ['retry_after' => $retryAfter]
        );
    }

    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Authenticator request transaction could not start.');
    }
    $transactionStarted = true;

    $account = am_authenticate_account_for_management(
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
    $authenticator = am_authenticator_for_update($conn, $role, $accountSource, $userId);

    if ($action === 'enroll' && $authenticator !== null) {
        pc_reject('An authenticator app is already linked to this account.');
    }
    if ($action === 'remove' && $authenticator === null) {
        pc_reject('No authenticator app is linked to this account.');
    }

    $pendingSecretEncrypted = null;
    $expectedAuthenticatorFingerprint = null;
    $setupKey = null;
    $otpauthUri = null;
    if ($action === 'enroll') {
        $setupKey = pc_base32_encode(random_bytes(20));
        $pendingSecretEncrypted = pc_encrypt_totp_secret(
            $setupKey,
            $role,
            $accountSource,
            $userId,
            $config
        );
        $otpauthUri = pc_otpauth_uri($setupKey, $role, $userId, $config);
    } else {
        $encryptedSecret = (string)$authenticator['totp_secret_encrypted'];
        $secret = pc_decrypt_totp_secret(
            $encryptedSecret,
            $role,
            $accountSource,
            $userId,
            $config
        );
        unset($secret);
        $expectedAuthenticatorFingerprint = am_authenticator_fingerprint(
            $role,
            $accountSource,
            $userId,
            $encryptedSecret,
            $config
        );
    }

    $accountFingerprint = pc_account_fingerprint(
        $role,
        $accountSource,
        $userId,
        $currentCredential,
        $config
    );
    $tokenData = pc_new_challenge_token();
    $challengeToken = $tokenData['token'];
    $challengeTokenHash = $tokenData['hash'];
    $requestIpHash = (string)$preAuthLimit['ip_hash'];

    am_cancel_pending_challenges($conn, $role, $accountSource, $userId);
    $statement = pc_prepare(
        $conn,
        'INSERT INTO authenticator_management_challenges '
            . '(challenge_token_hash, role, account_source, user_id, action, '
            . 'account_fingerprint, pending_totp_secret_encrypted, '
            . 'expected_authenticator_fingerprint, failed_attempts, expires_at, '
            . 'request_ip_hash, status) '
            . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, '
            . "DATE_ADD(NOW(6), INTERVAL 5 MINUTE), ?, 'pending')"
    );
    $statement->bind_param(
        'sssssssss',
        $challengeTokenHash,
        $role,
        $accountSource,
        $userId,
        $action,
        $accountFingerprint,
        $pendingSecretEncrypted,
        $expectedAuthenticatorFingerprint,
        $requestIpHash
    );
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Authenticator-management challenge could not be created.');
    }
    $statement->close();
    as_record_activity(
        $conn,
        $appSession,
        'authenticator_change_requested',
        ['action' => $action],
        'server',
        'info',
        $config
    );

    if (!$conn->commit()) {
        throw new RuntimeException('Authenticator request transaction could not be committed.');
    }
    $transactionStarted = false;
    $conn->close();
    $conn = null;

    $payload = [
        'status' => 'success',
        'action' => $action,
        'challenge_token' => $challengeToken,
        'expires_in' => AM_CHALLENGE_TTL_SECONDS,
        'attempts_remaining' => AM_MAX_ATTEMPTS,
    ];
    if ($action === 'enroll') {
        $payload['setup_key'] = $setupKey;
        $payload['otpauth_uri'] = $otpauthUri;
    }
    pc_respond($payload);
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
    error_log('request_authenticator_management.php failed: ' . $error->getMessage());
    pc_respond([
        'status' => 'error',
        'message' => 'Authenticator management is temporarily unavailable. Please try again later.',
    ]);
}
