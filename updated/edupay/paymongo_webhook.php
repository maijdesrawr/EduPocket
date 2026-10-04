<?php

ob_start();
ini_set('display_errors', '0');
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');

require_once __DIR__ . '/paymongo_payment_common.php';

function webhook_respond(array $payload, int $status = 200): void
{
    if (ob_get_length()) {
        ob_clean();
    }
    http_response_code($status);
    echo json_encode($payload);
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    webhook_respond(['status' => 'error', 'message' => 'POST is required.'], 405);
}

try {
    $raw = file_get_contents('php://input');
    if (!is_string($raw) || $raw === '') {
        webhook_respond(['status' => 'error', 'message' => 'Invalid JSON payload.'], 400);
    }
    $signatureHeader = (string)($_SERVER['HTTP_PAYMONGO_SIGNATURE'] ?? '');
    if (!pm_verify_webhook_signature($raw, $signatureHeader)) {
        webhook_respond(['status' => 'error', 'message' => 'Invalid webhook signature.'], 401);
    }

    $payload = json_decode($raw, true);
    if (!is_array($payload)) {
        webhook_respond(['status' => 'error', 'message' => 'Invalid JSON payload.'], 400);
    }

    $eventType = (string)(
        $payload['data']['attributes']['type']
        ?? $payload['data']['type']
        ?? $payload['type']
        ?? ''
    );
    if ($eventType !== 'checkout_session.payment.paid') {
        webhook_respond(['status' => 'ignored']);
    }

    $resource = $payload['data']['attributes']['data']
        ?? $payload['data']['data']
        ?? $payload['data']['resource']
        ?? null;
    $checkoutId = is_array($resource) ? (string)($resource['id'] ?? '') : '';
    $checkoutId = pm_checkout_id($checkoutId);

    http_response_code(503);
    require_once __DIR__ . '/db_connect.php';
    $result = pm_verify_and_fulfill($conn, $checkoutId);
    webhook_respond([
        'status' => 'received',
        'transaction_id' => $result['transaction_id'],
        'already_completed' => $result['already_completed'],
    ]);
} catch (InvalidArgumentException $error) {
    webhook_respond(['status' => 'error', 'message' => 'Invalid checkout event.'], 400);
} catch (Throwable $error) {
    error_log('paymongo_webhook.php failed: ' . $error->getMessage());
    webhook_respond(['status' => 'error', 'message' => 'Payment is not confirmed.'], 503);
} finally {
    if ($conn instanceof mysqli) {
        $conn->close();
    }
}
