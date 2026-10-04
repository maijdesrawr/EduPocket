<?php
ob_start();
ini_set('display_errors', '0');
error_reporting(0);
header('Access-Control-Allow-Origin: *');
header('Content-Type: application/json; charset=utf-8');

include 'db_connect.php';

function respond_json(array $payload): void
{
    ob_clean();
    echo json_encode($payload);
    exit;
}

$student_num = trim($_GET['student_id'] ?? $_POST['student_id'] ?? '');
if ($student_num === '') {
    respond_json(['status' => 'error', 'message' => 'Missing student_id parameter']);
}

$topup_stmt = $conn->prepare(
    "SELECT t.topup_id, t.parent_id, t.amount, t.method, t.status, t.date_time
     FROM topups t
     WHERE t.student_num = ?
     ORDER BY t.date_time DESC"
);
if (!$topup_stmt) {
    respond_json(['status' => 'error', 'message' => 'Failed to prepare topup query']);
}

$topup_stmt->bind_param('s', $student_num);
if (!$topup_stmt->execute()) {
    respond_json(['status' => 'error', 'message' => 'Failed to load topups']);
}

$topup_result = $topup_stmt->get_result();
$topups = [];
while ($row = $topup_result->fetch_assoc()) {
    $topups[] = [
        'topup_id' => (int)($row['topup_id'] ?? 0),
        'parent_id' => $row['parent_id'] ?? null,
        'amount' => number_format(floatval($row['amount'] ?? 0), 2, '.', ''),
        'method' => $row['method'] ?? '',
        'status' => $row['status'] ?? '',
        'date_time' => $row['date_time'] ?? '',
        'is_cashier_topup' => ($row['method'] === 'Over-the-counter' && $row['parent_id'] === null)
    ];
}
$topup_stmt->close();

$balance_stmt = $conn->prepare('SELECT balance FROM students WHERE student_num = ? LIMIT 1');
if (!$balance_stmt) {
    respond_json(['status' => 'error', 'message' => 'Failed to prepare balance query']);
}

$balance_stmt->bind_param('s', $student_num);
if (!$balance_stmt->execute()) {
    respond_json(['status' => 'error', 'message' => 'Failed to load balance']);
}

$balance_result = $balance_stmt->get_result();
$balance_row = $balance_result ? $balance_result->fetch_assoc() : null;
$total_balance = floatval($balance_row['balance'] ?? 0);
$balance_stmt->close();

$conn->close();

respond_json([
    'status' => 'success',
    'total_balance' => number_format($total_balance, 2, '.', ''),
    'topups_count' => count($topups),
    'topups' => $topups,
]);
?>
