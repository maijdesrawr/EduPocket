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

$parent_id = trim($_GET['parent_id'] ?? $_POST['parent_id'] ?? '');
if ($parent_id === '') {
    respond_json(['status' => 'error', 'message' => 'Missing parent_id parameter']);
}

$topup_stmt = $conn->prepare("
    SELECT 
        t.topup_id,
        t.student_num,
        t.amount,
        t.method,
        t.status,
        t.date_time,
        s.Fname AS child_name
    FROM topups t
    INNER JOIN students s ON t.student_num = s.student_num
    WHERE t.parent_id = ?
    ORDER BY t.date_time DESC
");

if (!$topup_stmt) {
    respond_json(['status' => 'error', 'message' => 'Failed to prepare topup query']);
}

$topup_stmt->bind_param('s', $parent_id);
if (!$topup_stmt->execute()) {
    respond_json(['status' => 'error', 'message' => 'Failed to load topups']);
}

$topup_result = $topup_stmt->get_result();
$topups = [];
$total_topup_amount = 0;

while ($row = $topup_result->fetch_assoc()) {
    $amount = floatval($row['amount'] ?? 0);
    $total_topup_amount += $amount;
    
    $topups[] = [
        'topup_id' => (int)($row['topup_id'] ?? 0),
        'student_num' => $row['student_num'] ?? '',
        'child_name' => $row['child_name'] ?? 'Unknown',
        'amount' => number_format($amount, 2, '.', ''),
        'method' => $row['method'] ?? '',
        'status' => $row['status'] ?? '',
        'date_time' => $row['date_time'] ?? '',
        'is_cashier_topup' => ($row['method'] === 'Over-the-counter')
    ];
}
$topup_stmt->close();

$balance_stmt = $conn->prepare("
    SELECT 
        s.student_num,
        s.Fname,
        s.balance,
        COALESCE(SUM(CASE WHEN t.transaction_type = 'payment' THEN t.amount ELSE 0 END), 0) AS total_spent
    FROM parent_student_link psl
    INNER JOIN students s ON psl.student_num = s.student_num
    LEFT JOIN transactions t ON s.student_num = t.student_num AND t.transaction_type = 'payment'
    WHERE psl.parent_id = ?
    GROUP BY s.student_num
");

if (!$balance_stmt) {
    respond_json(['status' => 'error', 'message' => 'Failed to prepare balance query']);
}

$balance_stmt->bind_param('s', $parent_id);
if (!$balance_stmt->execute()) {
    respond_json(['status' => 'error', 'message' => 'Failed to load balance info']);
}

$balance_result = $balance_stmt->get_result();
$children = [];
$total_balance = 0;

while ($row = $balance_result->fetch_assoc()) {
    $balance = floatval($row['balance'] ?? 0);
    $total_balance += $balance;
    
    $children[] = [
        'student_num' => $row['student_num'] ?? '',
        'name' => $row['Fname'] ?? 'Unknown',
        'balance' => number_format($balance, 2, '.', ''),
        'total_spent' => number_format(floatval($row['total_spent'] ?? 0), 2, '.', '')
    ];
}
$balance_stmt->close();
$conn->close();

respond_json([
    'status' => 'success',
    'parent_id' => $parent_id,
    'total_balance' => number_format($total_balance, 2, '.', ''),
    'total_topup_amount' => number_format($total_topup_amount, 2, '.', ''),
    'topups_count' => count($topups),
    'children_count' => count($children),
    'children' => $children,
    'topups' => $topups,
]);
?>
