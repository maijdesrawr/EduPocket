<?php
require_once __DIR__ . '/cors_common.php';
header('Content-Type: application/json');
require_once 'db_connect.php';

$cashier_id = $_GET['cashier_id'] ?? '';
if (!$cashier_id) {
    echo json_encode(["status" => "error", "message" => "Missing cashier_id"]);
    exit;
}

$balance = 0.0;
$balanceStmt = $conn->prepare("SELECT balance FROM cashiers WHERE cashier_id = ? LIMIT 1");
if ($balanceStmt) {
    $balanceStmt->bind_param("s", $cashier_id);
    if ($balanceStmt->execute()) {
        $balanceResult = $balanceStmt->get_result();
        $balanceRow = $balanceResult ? $balanceResult->fetch_assoc() : null;
        $balance = (float) ($balanceRow['balance'] ?? 0);
    }
    $balanceStmt->close();
}

$sqlTxn = "
SELECT 
    t.transaction_id,
    s.Fname AS student_name,
    t.amount,
    COALESCE(NULLIF(t.description, ''), CASE WHEN t.transaction_type = 'top-up' THEN 'Student Top-up' ELSE 'Payment' END) AS description,
    t.transaction_type,
    t.date_time
FROM transactions t
LEFT JOIN students s ON t.student_num = s.student_num
WHERE t.cashier_id = ?
AND t.transaction_type IN ('payment', 'top-up')
ORDER BY t.date_time DESC
LIMIT 10
";

$stmt = $conn->prepare($sqlTxn);
$transactions = [];
$transactionBalance = 0.0;

if (!$stmt) {
    echo json_encode([
        "status" => "error",
        "message" => "Failed to prepare dashboard query",
    ]);
    $conn->close();
    exit;
}

$stmt->bind_param("s", $cashier_id);
$stmt->execute();
$result = $stmt->get_result();

while ($row = $result->fetch_assoc()) {
    $amount = (float)$row['amount'] * ($row['transaction_type'] === 'top-up' ? -1 : 1);
    $transactions[] = [
        "id" => $row['transaction_id'],
        "recipientName" => $row['student_name'] ?? "Unknown",
        "recipientNumber" => "",
        "paymentTitle" => $row['description'],
        "amount" => $amount,
        "timestamp" => $row['date_time'],
        "isCompleted" => true
    ];
    $transactionBalance += $amount;
}

$stmt->close();



echo json_encode([
    "status" => "success",
    "balance" => number_format($balance, 2, '.', ''),
    "transactions" => $transactions
]);

$conn->close();
?>
