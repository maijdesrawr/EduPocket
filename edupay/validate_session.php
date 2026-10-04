<?php

require_once __DIR__ . '/app_session_common.php';

pc_bootstrap_json_endpoint();
pc_require_post();

$conn = null;
try {
    $conn = pc_open_database();
    $session = as_require_session($conn);
    pc_respond([
        'status' => 'success',
        'role' => $session['role'],
        'account_source' => $session['account_source'],
        'id' => $session['user_id'],
        'session_expires_at' => $session['session_expires_at'],
        'session_expires_in' => $session['session_expires_in'],
        'expires_in' => $session['expires_in'],
        'session_idle_timeout_seconds' => $session['session_idle_timeout_seconds'],
        'session_idle_expires_at' => $session['session_idle_expires_at'],
        'session_idle_expires_in' => $session['session_idle_expires_in'],
    ]);
} catch (PasswordChangeClientException $error) {
    pc_respond(pc_client_error_payload($error->getMessage(), $error->details()));
} catch (Throwable $error) {
    error_log('validate_session.php failed: ' . $error->getMessage());
    pc_respond(pc_client_error_payload('Your session could not be validated.'));
} finally {
    if ($conn instanceof mysqli) {
        $conn->close();
    }
}
