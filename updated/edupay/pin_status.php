<?php

declare(strict_types=1);

require_once __DIR__ . '/pin_management_common.php';
require_once __DIR__ . '/app_session_common.php';

pc_bootstrap_json_endpoint();

$conn = null;
$transactionStarted = false;

try {
    pc_require_post();
    pm_require_secure_transport();

    $role = pc_normalize_role(pc_post_string('role'));
    $userId = pc_post_string('user_id');
    if ($userId === '') {
        $userId = pc_post_string('id');
    }
    $currentPassword = pc_post_string('current_password', false);
    pc_validate_user_id($userId);
    if ($currentPassword === '') {
        pc_reject('Current password is required.');
    }

    $conn = pc_open_database();
    $appSession = as_require_session($conn);
    as_assert_session_identity($appSession, $role, $userId);
    if (!$conn->begin_transaction()) {
        throw new RuntimeException('PIN status transaction could not start.');
    }
    $transactionStarted = true;

    $account = pc_fetch_account_for_update(
        $conn,
        $role,
        $userId,
        (string)$appSession['account_source']
    );
    $userId = (string)$account['user_id'];
    $accountSource = (string)$account['account_source'];
    as_assert_session_identity($appSession, $role, $userId, $accountSource);
    pc_assert_current_password($currentPassword, (string)$account['password_value']);
    $hasPin = pm_fetch_pin_for_update($conn, $role, $accountSource, $userId) !== '';

    if (!$conn->commit()) {
        throw new RuntimeException('PIN status transaction could not be committed.');
    }
    $transactionStarted = false;
    $conn->close();
    $conn = null;

    pc_respond([
        'status' => 'success',
        'has_pin' => $hasPin,
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
    error_log('pin_status.php failed: ' . $error->getMessage());
    pc_respond([
        'status' => 'error',
        'message' => 'PIN status is temporarily unavailable. Please try again later.',
    ]);
}
