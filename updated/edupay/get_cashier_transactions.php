<?php
require_once __DIR__ . '/cors_common.php';
ob_start();
ini_set('display_errors', '0');
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');

require_once 'db_connect.php';

$cashierId = trim($_GET['cashier_id'] ?? '');
if ($cashierId === '') {
    ob_clean();
    http_response_code(400);
    echo json_encode([
        'status' => 'error',
        'message' => 'cashier_id is required',
    ]);
    exit;
}

$stmt = $conn->prepare(<<<'SQL'
    SELECT
        t.transaction_id AS id,
        COALESCE(s.Fname, 'Unknown student') AS recipientName,
        t.student_num AS recipientNumber,
        COALESCE(
            NULLIF(t.description, ''),
            CASE
                WHEN t.transaction_type = 'top-up' THEN 'Student Top-up'
                ELSE 'Payment'
            END
        ) AS paymentTitle,
        CASE WHEN t.transaction_type = 'top-up' THEN -t.amount ELSE t.amount END AS amount,
        COALESCE(t.date_time, t.date_created) AS timestamp,
        1 AS isCompleted
    FROM transactions t
    LEFT JOIN students s ON s.student_num = t.student_num
    WHERE TRIM(COALESCE(t.cashier_id, '')) = ?
      AND t.transaction_type IN ('payment', 'top-up')
    ORDER BY COALESCE(t.date_time, t.date_created) DESC
SQL);

if (!$stmt) {
    ob_clean();
    http_response_code(500);
    echo json_encode([
        'status' => 'error',
        'message' => 'Unable to load transaction history.',
    ]);
    exit;
}

$stmt->bind_param('s', $cashierId);
$stmt->execute();
$result = $stmt->get_result();
$transactions = [];

while ($row = $result->fetch_assoc()) {
    $transactions[] = [
        'id' => (int) $row['id'],
        'recipientName' => $row['recipientName'],
        'recipientNumber' => $row['recipientNumber'],
        'paymentTitle' => $row['paymentTitle'],
        'amount' => (float) $row['amount'],
        'timestamp' => $row['timestamp'],
        'isCompleted' => true,
    ];
}

$stmt->close();
$conn->close();

ob_clean();
echo json_encode([
    'status' => 'success',
    'transactions' => $transactions,
]);
exit;
