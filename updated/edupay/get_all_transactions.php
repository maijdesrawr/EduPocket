<?php
require_once __DIR__ . '/cors_common.php';
error_reporting(0);
ini_set('display_errors', 0);

header('Content-Type: application/json');
include 'db_connect.php';

$sql = "SELECT 
            t.transaction_id AS id,
            s.Fname AS name,
            t.description AS note,
            t.amount,
            t.transaction_type,
            t.date_time AS date
        FROM transactions t
        JOIN students s ON t.student_num = s.student_num
        ORDER BY t.date_time DESC";

$result = $conn->query($sql);

$transactions = [];

if ($result && $result->num_rows > 0) {
    while ($row = $result->fetch_assoc()) {
        $transactions[] = [
            "id" => (int)($row['id'] ?? 0),
            "transaction_id" => (int)($row['id'] ?? 0),
            "name" => $row['name'] ?? '',
            "note" => $row['note'] ?? '',
            "amount" => $row['amount'] ?? '0',
            "date" => $row['date'] ?? '',
            "type" => $row['transaction_type'] ?? ''
        ];
    }
}

echo json_encode([
    "status" => "success",
    "transactions" => $transactions
]);

$conn->close();
