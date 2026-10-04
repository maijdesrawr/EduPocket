<?php

ob_start();
ini_set('display_errors', '0');
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: POST, OPTIONS');
header('Access-Control-Allow-Headers: Authorization, Content-Type');

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

http_response_code(503);
require_once __DIR__ . '/db_connect.php';
http_response_code(200);
require_once __DIR__ . '/paymongo_config.php';
require_once __DIR__ . '/app_session_common.php';

function checkout_respond(array $payload, int $status = 200): void
{
    if (ob_get_length()) {
        ob_clean();
    }
    http_response_code($status);
    echo json_encode($payload);
    exit;
}

if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'POST') {
    checkout_respond(['status' => 'error', 'message' => 'POST is required.'], 405);
}

$parentId = trim((string)($_POST['parent_id'] ?? ''));
$studentNumber = trim((string)($_POST['child_id'] ?? ''));
$method = trim((string)($_POST['method'] ?? ''));
$amountInput = $_POST['amount'] ?? null;
$amount = filter_var($amountInput, FILTER_VALIDATE_FLOAT);

if ($parentId === '' || $studentNumber === '' || $amount === false
    || $amount < 1 || $amount > 100000
    || abs(($amount * 100) - round($amount * 100)) > 0.0001) {
    checkout_respond([
        'status' => 'error',
        'message' => 'Enter valid payment details and an amount from PHP 1.00 to PHP 100,000.00.',
    ], 400);
}
if (!in_array($method, ['GCash', 'Maya'], true)) {
    checkout_respond(['status' => 'error', 'message' => 'Invalid payment method.'], 400);
}

try {
    $appSession = as_require_session($conn, false);
    as_assert_session_identity($appSession, 'parent', $parentId);

    $link = $conn->prepare(
        'SELECT 1 FROM parents p '
            . 'LEFT JOIN parent_student_link psl '
            . 'ON psl.parent_id = p.parent_id AND psl.student_num = ? '
            . 'JOIN students s ON s.student_num = ? '
            . 'WHERE p.parent_id = ? '
            . 'AND (psl.id IS NOT NULL OR p.linked_student_num = ?) LIMIT 1'
    );
    if (!$link) {
        throw new RuntimeException('Payment validation could not be prepared.');
    }
    $link->bind_param('ssss', $studentNumber, $studentNumber, $parentId, $studentNumber);
    $link->execute();
    $isLinked = $link->get_result()->fetch_row() !== null;
    $link->close();
    if (!$isLinked) {
        checkout_respond([
            'status' => 'error',
            'message' => 'That student is not linked to this parent account.',
        ], 403);
    }

    $apiBaseUrl = trim((string)getenv('EDUPOCKET_PUBLIC_API_BASE_URL'));
    if ($apiBaseUrl === '') {
        $requestHost = trim((string)($_SERVER['HTTP_HOST'] ?? ''));
        if (!preg_match('/^(?:localhost|127\.0\.0\.1|\[[0-9a-f:]+\]|[a-z0-9.-]+)(?::[0-9]{1,5})?$/iD', $requestHost)) {
            throw new RuntimeException('The payment callback URL is not configured correctly.');
        }
        $isHttps = strtolower((string)($_SERVER['HTTPS'] ?? '')) !== ''
            && strtolower((string)($_SERVER['HTTPS'] ?? '')) !== 'off';
        $apiBaseUrl = ($isHttps ? 'https://' : 'http://') . $requestHost . '/edupay';
    }
    $apiBaseUrl = rtrim($apiBaseUrl, '/');
    $parsedApiBaseUrl = parse_url($apiBaseUrl);
    if (!is_array($parsedApiBaseUrl)
        || !in_array(strtolower((string)($parsedApiBaseUrl['scheme'] ?? '')), ['http', 'https'], true)
        || empty($parsedApiBaseUrl['host'])
        || isset($parsedApiBaseUrl['user'])
        || isset($parsedApiBaseUrl['pass'])
        || isset($parsedApiBaseUrl['query'])
        || isset($parsedApiBaseUrl['fragment'])) {
        throw new RuntimeException('The payment callback URL is not configured correctly.');
    }

    $callbackToken = 'EP-' . bin2hex(random_bytes(24));
    $callbackTokenHash = hash('sha256', $callbackToken);
    $amountCentavos = (int)round($amount * 100);
    $paymentMethodType = $method === 'GCash' ? 'gcash' : 'paymaya';

    $request = [
        'data' => [
            'attributes' => [
                'line_items' => [[
                    'currency' => 'PHP',
                    'amount' => $amountCentavos,
                    'name' => 'EduPocket Wallet Top-up',
                    'quantity' => 1,
                ]],
                'payment_method_types' => [$paymentMethodType],
                'description' => 'EduPocket ' . $method . ' wallet top-up',
                'metadata' => [
                    'parent_id' => $parentId,
                    'child_id' => $studentNumber,
                    'amount' => number_format((float)$amount, 2, '.', ''),
                    'method' => $method,
                    'callback_reference' => $callbackToken,
                ],
                'reference_number' => $callbackToken,
                'success_url' => $apiBaseUrl . '/payment_success.php?'
                    . http_build_query(['reference' => $callbackToken]),
                'cancel_url' => $apiBaseUrl . '/payment_cancel.php',
            ],
        ],
    ];

    $curl = curl_init();
    if ($curl === false) {
        throw new RuntimeException('Payment provider is unavailable.');
    }
    curl_setopt_array($curl, [
        CURLOPT_URL => 'https://api.paymongo.com/v1/checkout_sessions',
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => json_encode($request),
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_TIMEOUT => 25,
        CURLOPT_HTTPHEADER => [
            'Accept: application/json',
            'Content-Type: application/json',
            'Authorization: Basic ' . base64_encode(PAYMONGO_SECRET_KEY . ':'),
            'Idempotency-Key: ' . $callbackToken,
        ],
    ]);
    $response = curl_exec($curl);
    $httpStatus = (int)curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    $curlError = curl_error($curl);
    curl_close($curl);
    $decoded = is_string($response) ? json_decode($response, true) : null;

    $checkoutId = is_array($decoded) ? trim((string)($decoded['data']['id'] ?? '')) : '';
    $checkoutUrl = is_array($decoded)
        ? trim((string)($decoded['data']['attributes']['checkout_url'] ?? ''))
        : '';
    $checkoutUrlParts = parse_url($checkoutUrl);
    if ($httpStatus < 200 || $httpStatus >= 300
        || !preg_match('/^cs_[A-Za-z0-9_-]{8,96}$/', $checkoutId)
        || !filter_var($checkoutUrl, FILTER_VALIDATE_URL)
        || !is_array($checkoutUrlParts)
        || strtolower((string)($checkoutUrlParts['scheme'] ?? '')) !== 'https'
        || strtolower((string)($checkoutUrlParts['host'] ?? '')) !== 'checkout.paymongo.com') {
        error_log('PayMongo checkout creation failed: HTTP ' . $httpStatus . ' ' . $curlError);
        throw new RuntimeException('The secure payment page could not be created.');
    }

    $statement = $conn->prepare(
        'INSERT INTO pending_payments '
            . '(checkout_id, callback_token_hash, parent_id, student_num, amount, method, status) '
            . "VALUES (?, ?, ?, ?, ?, ?, 'pending')"
    );
    if (!$statement) {
        throw new RuntimeException('The payment request could not be saved.');
    }
    $statement->bind_param(
        'ssssds',
        $checkoutId,
        $callbackTokenHash,
        $parentId,
        $studentNumber,
        $amount,
        $method
    );
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('The payment request could not be saved.');
    }
    $statement->close();

    checkout_respond([
        'status' => 'success',
        'checkout_id' => $checkoutId,
        'checkout_url' => $checkoutUrl,
    ]);
} catch (Throwable $error) {
    error_log('create_paymongo_checkout.php failed: ' . $error->getMessage());
    checkout_respond([
        'status' => 'error',
        'message' => 'The payment could not be started. Please try again.',
    ], 500);
} finally {
    if ($conn instanceof mysqli) {
        $conn->close();
    }
}
