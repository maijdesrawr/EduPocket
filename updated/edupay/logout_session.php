<?php

require_once __DIR__ . '/app_session_common.php';

pc_bootstrap_json_endpoint();
pc_require_post();

$conn = null;
$transactionStarted = false;
try {
    $requestedReason = strtolower(pc_post_string('reason'));
    $logoutReason = in_array(
        $requestedReason,
        ['logout', 'inactivity_timeout', 'login_page_opened'],
        true
    ) ? $requestedReason : 'logout';

    $conn = pc_open_database();
    $session = as_require_session($conn, false);
    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Logout could not be started.');
    }
    $transactionStarted = true;
    as_mark_session_revoked($conn, $session, $logoutReason);
    if (!$conn->commit()) {
        throw new RuntimeException('Logout could not be committed.');
    }
    $transactionStarted = false;
    pc_respond([
        'status' => 'success',
        'message' => 'You have been logged out.',
    ]);
} catch (PasswordChangeClientException $error) {
    if ($transactionStarted && $conn instanceof mysqli) {
        $conn->rollback();
    }
    pc_respond(pc_client_error_payload($error->getMessage(), $error->details()));
} catch (Throwable $error) {
    if ($transactionStarted && $conn instanceof mysqli) {
        $conn->rollback();
    }
    error_log('logout_session.php failed: ' . $error->getMessage());
    pc_respond(pc_client_error_payload('Logout could not be completed.'));
} finally {
    if ($conn instanceof mysqli) {
        $conn->close();
    }
}
