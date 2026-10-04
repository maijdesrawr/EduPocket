<?php

declare(strict_types=1);

require_once __DIR__ . '/receipt_print_token_common.php';

pc_bootstrap_json_endpoint();

$conn = null;
$payload = null;
try {
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
        http_response_code(405);
        pc_reject('POST is required.');
    }
    $transactionId = filter_var(
        $_POST['transaction_id'] ?? null,
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1]]
    );
    if ($transactionId === false) {
        http_response_code(422);
        pc_reject('A valid transaction ID is required.');
    }

    $conn = pc_open_database();
    $issued = rpt_issue_for_authenticated_request($conn, (int)$transactionId);
    $payload = [
        'status' => 'success',
        'print_token' => $issued['print_token'],
        'expires_in' => $issued['expires_in'],
    ];
} catch (PasswordChangeClientException $error) {
    if (http_response_code() < 400) {
        http_response_code(400);
    }
    $payload = pc_client_error_payload($error->getMessage(), $error->details());
} catch (InvalidArgumentException $error) {
    http_response_code(404);
    $payload = pc_client_error_payload('This receipt is unavailable.');
} catch (Throwable $error) {
    error_log('issue_receipt_print_token.php failed: ' . $error->getMessage());
    http_response_code(500);
    $payload = pc_client_error_payload('The printable receipt link could not be created.');
} finally {
    if ($conn instanceof mysqli) {
        $conn->close();
    }
}

pc_respond(is_array($payload) ? $payload : pc_client_error_payload('The request failed.'));
