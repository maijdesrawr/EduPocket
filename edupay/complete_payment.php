<?php

ob_start();
ini_set('display_errors', '0');
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');

http_response_code(503);
require_once __DIR__ . '/db_connect.php';
http_response_code(200);
require_once __DIR__ . '/paymongo_payment_common.php';

function complete_payment_respond(array $payload, int $status = 200): void
{
    if (ob_get_length()) {
        ob_clean();
    }
    http_response_code($status);
    echo json_encode($payload);
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    complete_payment_respond(['status' => 'error', 'message' => 'POST is required.'], 405);
}

try {
    $checkoutId = pm_checkout_id((string)($_POST['checkout_id'] ?? ''));
    $result = pm_verify_and_fulfill($conn, $checkoutId);
    complete_payment_respond([
        'status' => 'success',
        'message' => 'Payment verified and wallet updated.',
        'transaction_id' => $result['transaction_id'],
        'student_num' => $result['student_num'],
        'amount' => $result['amount'],
        'already_completed' => $result['already_completed'],
    ]);
} catch (InvalidArgumentException $error) {
    complete_payment_respond(['status' => 'error', 'message' => $error->getMessage()], 400);
} catch (Throwable $error) {
    error_log('complete_payment.php failed: ' . $error->getMessage());
    complete_payment_respond([
        'status' => 'error',
        'message' => 'PayMongo has not confirmed this payment.',
    ], 409);
} finally {
    if ($conn instanceof mysqli) {
        $conn->close();
    }
}
