<?php
require_once __DIR__ . '/cors_common.php';
ob_start();
ini_set('display_errors', '0');
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');
include "db_connect.php";

$canteen_id = $_GET['canteen_id'] ?? '';

if (empty($canteen_id)) {
    ob_clean();
    echo json_encode([
        'status' => 'error',
        'message' => 'canteen_id is required.'
    ]);
    exit;
}

$stmt = $conn->prepare("
    SELECT COUNT(*) AS total_orders
    FROM transactions
    WHERE canteen_id = ? AND transaction_type = 'payment'
");
$stmt->bind_param("s", $canteen_id);
$stmt->execute();
$result = $stmt->get_result();
$row = $result ? $result->fetch_assoc() : null;

$count = (int)($row['total_orders'] ?? 0);
$nextOrder = $count + 1;

ob_clean();
echo json_encode([
    'status' => 'success',
    'next_order_number' => $nextOrder,
    'order_code' => str_pad((string)$nextOrder, 5, '0', STR_PAD_LEFT),
]);

$stmt->close();
$conn->close();
?>
