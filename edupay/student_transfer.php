<?php

declare(strict_types=1);

require_once __DIR__ . '/student_transfer_common.php';

pc_bootstrap_json_endpoint();

$conn = null;
$session = null;
$senderId = '';
$recipientId = '';
$amount = '';
$clientRequestId = '';

function st_endpoint_record_rejection(
    mysqli $conn,
    array $appSession,
    string $reason,
    string $senderId,
    string $recipientId,
    string $amount,
    string $clientRequestId
): void {
    try {
        as_record_activity(
            $conn,
            $appSession,
            'student_transfer_failed',
            [
                'reason' => $reason,
                'attempted_sender_id' => $senderId,
                'recipient_student_num' => $recipientId,
                'amount' => $amount,
                'client_request_id' => $clientRequestId,
            ],
            'server',
            'failure'
        );
    } catch (Throwable $auditError) {
        error_log('student_transfer.php rejection audit failed: ' . $auditError->getMessage());
    }
}

try {
    pc_require_post();
    pm_require_secure_transport();

    $conn = pc_open_database();
    $session = as_require_session($conn, false);
    as_assert_session_role($session, ['student']);

    $senderId = pc_post_string('sender_id');
    $recipientId = pc_post_string('recipient_id');
    $amount = pc_post_string('amount');
    $pin = pc_post_string('pin');
    $clientRequestId = pc_post_string('client_request_id');

    $result = st_execute_transfer(
        $conn,
        $session,
        $senderId,
        $recipientId,
        $amount,
        $pin,
        $clientRequestId
    );

    $conn->close();
    $conn = null;
    pc_respond(array_merge(
        [
            'status' => 'success',
            'message' => ($result['idempotent'] ?? false)
                ? 'This transfer was already completed.'
                : 'Fund transfer completed successfully.',
        ],
        $result
    ));
} catch (StudentTransferClientException $error) {
    if ($conn instanceof mysqli && is_array($session) && !$error->wasAudited()) {
        st_endpoint_record_rejection(
            $conn,
            $session,
            (string)($error->details()['code'] ?? 'rejected'),
            $senderId,
            $recipientId,
            $amount,
            $clientRequestId
        );
    }
    if (!headers_sent()) {
        http_response_code($error->httpStatus());
    }
    if ($conn instanceof mysqli) {
        $conn->close();
        $conn = null;
    }
    pc_respond(pc_client_error_payload($error->getMessage(), $error->details()));
} catch (PasswordChangeClientException $error) {
    if ($conn instanceof mysqli && is_array($session)) {
        st_endpoint_record_rejection(
            $conn,
            $session,
            (string)($error->details()['code'] ?? 'authorization_rejected'),
            $senderId,
            $recipientId,
            $amount,
            $clientRequestId
        );
    }
    if ($conn instanceof mysqli) {
        $conn->close();
        $conn = null;
    }
    pc_respond(pc_client_error_payload($error->getMessage(), $error->details()));
} catch (Throwable $error) {
    error_log('student_transfer.php failed: ' . $error->getMessage());
    if ($conn instanceof mysqli) {
        $conn->close();
        $conn = null;
    }
    if (!headers_sent()) {
        http_response_code(500);
    }
    pc_respond([
        'status' => 'error',
        'code' => 'transfer_unavailable',
        'message' => 'Fund transfer is temporarily unavailable. Please try again later.',
    ]);
}
