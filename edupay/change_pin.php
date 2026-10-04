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
    $currentPin = pc_post_string('current_pin');
    $newPin = pc_post_string('new_pin');

    pc_validate_user_id($userId);
    if ($currentPassword === '') {
        pc_reject('Current password is required.');
    }
    pm_validate_pin($newPin, 'New PIN', true);

    $conn = pc_open_database();
    if (!$conn->begin_transaction()) {
        throw new RuntimeException('PIN-change transaction could not start.');
    }
    $transactionStarted = true;

    $appSession = as_require_session($conn);
    as_assert_session_identity($appSession, $role, $userId);
    $account = pc_fetch_account_for_update(
        $conn,
        $role,
        $userId,
        (string)$appSession['account_source']
    );
    $userId = (string)$account['user_id'];
    $accountSource = (string)$account['account_source'];
    pc_assert_current_password($currentPassword, (string)$account['password_value']);

    $storedPin = pm_fetch_pin_for_update($conn, $role, $accountSource, $userId);
    $hadPin = $storedPin !== '';
    if ($hadPin) {
        pm_validate_pin($currentPin, 'Current PIN');
        if (!pm_pin_matches($currentPin, $storedPin)) {
            pc_reject('Current PIN is incorrect.');
        }
        if (hash_equals($currentPin, $newPin)) {
            pc_reject('New PIN must be different from your current PIN.');
        }
    }

    pm_update_account_pin(
        $conn,
        $role,
        $accountSource,
        $userId,
        pm_hash_pin($newPin)
    );
    as_record_activity(
        $conn,
        $appSession,
        $hadPin ? 'pin_changed' : 'pin_created',
        ['had_existing_pin' => $hadPin],
        'server'
    );

    if (!$conn->commit()) {
        throw new RuntimeException('PIN change could not be committed.');
    }
    $transactionStarted = false;
    $conn->close();
    $conn = null;

    pc_respond([
        'status' => 'success',
        'has_pin' => true,
        'message' => $hadPin
            ? 'Your 6-digit PIN was changed successfully.'
            : 'Your 6-digit PIN was created successfully.',
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
    error_log('change_pin.php failed: ' . $error->getMessage());
    pc_respond([
        'status' => 'error',
        'message' => 'PIN change is temporarily unavailable. Please try again later.',
    ]);
}
