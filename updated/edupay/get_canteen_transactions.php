<?php
require_once __DIR__ . '/cors_common.php';
ob_start();
ini_set('display_errors', '0');
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');

include 'db_connect.php';

$requested_id = trim($_GET['canteen_id'] ?? '');
if (empty($requested_id)) {
    ob_clean();
    echo json_encode([
        'status' => 'error',
        'message' => 'Missing canteen_id'
    ]);
    exit;
}

$resolved_canteen_id = $requested_id;
$canteen_stmt = $conn->prepare("SELECT canteen_id, Fname FROM canteens WHERE canteen_id = ? LIMIT 1");
$canteen_stmt->bind_param("s", $resolved_canteen_id);
$canteen_stmt->execute();
$canteen_result = $canteen_stmt->get_result();

if (!$canteen_result || $canteen_result->num_rows === 0) {
    $admin_stmt = $conn->prepare("
        SELECT c.canteen_id, c.Fname
        FROM admins a
        JOIN canteens c ON c.canteen_id = a.canteen_id
        WHERE a.admin_id = ?
        LIMIT 1
    ");
    $admin_stmt->bind_param("s", $requested_id);
    $admin_stmt->execute();
    $admin_result = $admin_stmt->get_result();

    if (!$admin_result || $admin_result->num_rows === 0) {
        ob_clean();
        echo json_encode([
            'status' => 'error',
            'message' => 'Canteen not found'
        ]);
        exit;
    }

    $canteen = $admin_result->fetch_assoc();
    $resolved_canteen_id = $canteen['canteen_id'];
    $admin_stmt->close();
} else {
    $canteen = $canteen_result->fetch_assoc();
}

$balance_stmt = $conn->prepare("
    SELECT COALESCE(SUM(amount), 0) AS total_balance
    FROM transactions
    WHERE transaction_type = 'payment'
      AND TRIM(COALESCE(canteen_id, '')) = ?
");
$balance_stmt->bind_param("s", $resolved_canteen_id);
$balance_stmt->execute();
$balance_result = $balance_stmt->get_result();
$balance_row = $balance_result ? $balance_result->fetch_assoc() : null;
$total_balance = floatval($balance_row['total_balance'] ?? 0);

$txn_stmt = $conn->prepare("
    SELECT
        t.transaction_id,
        t.student_num,
        s.Fname AS student_name,
        t.amount,
        COALESCE(t.description, 'Payment') AS description,
        COALESCE(t.date_time, t.date_created, NOW()) AS event_time
    FROM transactions t
    JOIN students s ON s.student_num = t.student_num
    WHERE t.transaction_type = 'payment'
      AND TRIM(COALESCE(t.canteen_id, '')) = ?
    ORDER BY COALESCE(t.date_time, t.date_created, NOW()) DESC
    LIMIT 50
");
$txn_stmt->bind_param("s", $resolved_canteen_id);
$txn_stmt->execute();
$txn_result = $txn_stmt->get_result();

$transactions = [];
while ($row = $txn_result->fetch_assoc()) {
    $transactions[] = [
        'id' => $row['transaction_id'],
        'recipientName' => $row['student_name'],
        'recipientNumber' => $row['student_num'],
        'amount' => floatval($row['amount']),
        'paymentTitle' => $row['description'],
        'timestamp' => $row['event_time'],
        'isCompleted' => true
    ];
}

ob_clean();
echo json_encode([
    'status' => 'success',
    'role' => 'canteen',
    'id' => $canteen['canteen_id'],
    'name' => $canteen['Fname'],
    'balance' => number_format($total_balance, 2, '.', ''),
    'transactions' => $transactions,
    'data' => $transactions
]);

$txn_stmt->close();
$balance_stmt->close();
$canteen_stmt->close();
$conn->close();
exit;
