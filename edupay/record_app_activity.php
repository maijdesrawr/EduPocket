<?php

require_once __DIR__ . '/app_session_common.php';

pc_bootstrap_json_endpoint();
pc_require_post();

$conn = null;
try {
    $eventType = pc_post_string('event_type');
    $details = $_POST['details'] ?? null;
    if (!is_string($details) && !is_array($details) && $details !== null) {
        pc_reject('Activity details must be valid JSON.');
    }

    $conn = pc_open_database();
    $session = as_require_session($conn);
    $eventId = as_record_activity(
        $conn,
        $session,
        $eventType,
        $details,
        'client',
        'success'
    );
    pc_respond([
        'status' => 'success',
        'event_id' => $eventId,
    ]);
} catch (PasswordChangeClientException $error) {
    pc_respond(pc_client_error_payload($error->getMessage(), $error->details()));
} catch (Throwable $error) {
    error_log('record_app_activity.php failed: ' . $error->getMessage());
    pc_respond(pc_client_error_payload('App activity could not be recorded.'));
} finally {
    if ($conn instanceof mysqli) {
        $conn->close();
    }
}

