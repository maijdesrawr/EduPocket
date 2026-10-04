<?php
require_once __DIR__ . '/cors_common.php';
ob_start();
ini_set('display_errors', '0');
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');
require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/app_session_common.php';

function notification_json(array $payload): void
{
    if (ob_get_length()) ob_clean();
    echo json_encode($payload);
    exit;
}

try {
    $appSession = as_require_session($conn, false);
} catch (PasswordChangeClientException $error) {
    notification_json(pc_client_error_payload($error->getMessage(), $error->details()));
} catch (Throwable $error) {
    error_log('get_account_notifications.php session validation failed: ' . $error->getMessage());
    notification_json(['status' => 'error', 'message' => 'Your session could not be validated.']);
}

$role = strtolower(trim((string)($_GET['role'] ?? '')));
$accountSource = strtolower(trim((string)($_GET['account_source'] ?? '')));
$userId = trim((string)($_GET['user_id'] ?? ''));
$afterId = max(0, (int)($_GET['after_id'] ?? 0));
$allowedSources = [
    'student' => ['students'],
    'canteen' => ['canteens'],
    'cashier' => ['cashiers', 'admins'],
];

if (!in_array($accountSource, $allowedSources[$role] ?? [], true) || $userId === '') {
    notification_json(['status' => 'error', 'message' => 'Invalid notification account.']);
}

try {
    as_assert_session_identity($appSession, $role, $userId, $accountSource);
} catch (PasswordChangeClientException $error) {
    notification_json(pc_client_error_payload($error->getMessage(), $error->details()));
}

$identityColumn = match ($role) {
    'student' => 'student_num',
    'canteen' => 'canteen_id',
    'cashier' => 'cashier_id',
};
$latestStatement = $conn->prepare(
    "SELECT COALESCE(MAX(transaction_id), 0) AS latest_id FROM transactions WHERE $identityColumn = ?"
);
if (!$latestStatement) {
    notification_json(['status' => 'error', 'message' => 'Notifications could not be loaded.']);
}
$latestStatement->bind_param('s', $userId);
$latestStatement->execute();
$latestRow = $latestStatement->get_result()->fetch_assoc();
$latestId = (int)($latestRow['latest_id'] ?? 0);
$latestStatement->close();


if ($afterId === 0) {
    notification_json(['status' => 'success', 'notifications' => [], 'latest_id' => $latestId]);
}

$statement = $conn->prepare(
    'SELECT transaction_id, student_num, amount, transaction_type, description, '
        . 'canteen_id, cashier_id, COALESCE(date_time, NOW()) AS occurred_at '
        . "FROM transactions WHERE $identityColumn = ? AND transaction_id > ? "
        . 'ORDER BY transaction_id ASC LIMIT 20'
);
if (!$statement) {
    notification_json(['status' => 'error', 'message' => 'Notifications could not be loaded.']);
}
$statement->bind_param('si', $userId, $afterId);
$statement->execute();
$result = $statement->get_result();
$notifications = [];
$deliveryLatestId = $afterId;
while ($row = $result->fetch_assoc()) {
    $transactionId = (int)$row['transaction_id'];
    $deliveryLatestId = $transactionId;
    $amount = number_format((float)$row['amount'], 2, '.', ',');
    $isTopUp = strtolower(trim((string)$row['transaction_type'])) === 'top-up';
    $studentNumber = trim((string)$row['student_num']);

    if ($role === 'student') {
        $title = $isTopUp ? 'Wallet top-up received' : 'Payment completed';
        $body = $isTopUp
            ? 'PHP ' . $amount . ' was added to your EduPocket balance.'
            : 'PHP ' . $amount . ' was paid from your EduPocket balance.';
    } else {
        $title = $isTopUp ? 'Student top-up completed' : 'Payment received';
        $body = $isTopUp
            ? 'PHP ' . $amount . ' was deducted for student ' . $studentNumber . '.'
            : 'PHP ' . $amount . ' was received from student ' . $studentNumber . '.';
    }

    $notifications[] = [
        'notification_id' => $transactionId,
        'transaction_id' => $transactionId,
        'title' => $title,
        'body' => $body,
        'created_at' => (string)$row['occurred_at'],
    ];
}
$statement->close();

notification_json([
    'status' => 'success',
    'notifications' => $notifications,
    'latest_id' => $deliveryLatestId,
]);
