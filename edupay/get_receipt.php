<?php

declare(strict_types=1);

require_once __DIR__ . '/receipt_print_token_common.php';

pc_bootstrap_json_endpoint();

$conn = null;
$transactionStarted = false;
$payload = null;
try {
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'GET') {
        http_response_code(405);
        pc_reject('GET is required.');
    }
    $transactionId = filter_var(
        $_GET['transaction_id'] ?? null,
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    );
    if ($transactionId === false) {
        http_response_code(422);
        pc_reject('A valid transaction ID is required.');
    }

    $conn = pc_open_database();
    $session = as_require_session($conn);
    if (!$conn->begin_transaction()) {
        throw new RuntimeException('The receipt request could not be started.');
    }
    $transactionStarted = true;
    $receipt = rpt_fetch_receipt_for_identity(
        $conn,
        (int)$transactionId,
        (string)$session['role'],
        (string)$session['account_source'],
        (string)$session['user_id']
    );
    as_record_activity(
        $conn,
        $session,
        'receipt_viewed',
        ['transaction_id' => (int)$transactionId]
    );
    if (!$conn->commit()) {
        throw new RuntimeException('The receipt request could not be committed.');
    }
    $transactionStarted = false;
    $payload = ['status' => 'success', 'receipt' => $receipt];
} catch (PasswordChangeClientException $error) {
    if ($transactionStarted && $conn instanceof mysqli) {
        $conn->rollback();
        $transactionStarted = false;
    }
    if (http_response_code() < 400) {
        http_response_code(400);
    }
    $payload = pc_client_error_payload($error->getMessage(), $error->details());
} catch (InvalidArgumentException $error) {
    if ($transactionStarted && $conn instanceof mysqli) {
        $conn->rollback();
        $transactionStarted = false;
    }
    http_response_code(404);
    $payload = pc_client_error_payload('This receipt is unavailable.');
} catch (Throwable $error) {
    if ($transactionStarted && $conn instanceof mysqli) {
        $conn->rollback();
        $transactionStarted = false;
    }
    error_log('get_receipt.php failed: ' . $error->getMessage());
    http_response_code(404);
    $payload = pc_client_error_payload('The receipt could not be loaded.');
} finally {
    if ($conn instanceof mysqli) {
        $conn->close();
    }
}

pc_respond(is_array($payload) ? $payload : pc_client_error_payload('The request failed.'));
