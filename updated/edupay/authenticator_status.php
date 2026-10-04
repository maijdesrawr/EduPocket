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
        throw new RuntimeException('Authenticator status transaction could not start.');
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
    $authenticator = am_authenticator_for_update($conn, $role, $accountSource, $userId);
    $enrolled = $authenticator !== null;
    $enrolledAt = null;
    $lastVerifiedAt = null;
    if ($authenticator !== null) {
        $secret = pc_decrypt_totp_secret(
            (string)$authenticator['totp_secret_encrypted'],
            $role,
            $accountSource,
            $userId,
            $config
        );
        unset($secret);
        $enrolledAt = (string)($authenticator['enrolled_at'] ?? '');
        $lastVerified = $authenticator['last_verified_at'] ?? null;
        $lastVerifiedAt = $lastVerified === null ? null : (string)$lastVerified;
    }

    if (!$conn->commit()) {
        throw new RuntimeException('Authenticator status transaction could not be committed.');
    }
    $transactionStarted = false;
    $conn->close();
    $conn = null;

    pc_respond([
        'status' => 'success',
        'enrolled' => $enrolled,
        'enrolled_at' => $enrolled ? $enrolledAt : null,
        'last_verified_at' => $enrolled ? $lastVerifiedAt : null,
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
    error_log('authenticator_status.php failed: ' . $error->getMessage());
    pc_respond([
        'status' => 'error',
        'message' => 'Authenticator status is temporarily unavailable. Please try again later.',
    ]);
}
