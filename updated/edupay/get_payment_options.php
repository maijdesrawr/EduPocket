<?php
require_once __DIR__ . '/cors_common.php';
header('Content-Type: application/json');
include 'db_connect.php';

$cashier_id = $_GET['cashier_id'] ?? $_POST['cashier_id'] ?? '';

if (empty($cashier_id)) {
    echo json_encode([
        'status' => 'error',
        'message' => 'Missing cashier_id'
    ]);
    exit;
}

$stmt = $conn->prepare("
    SELECT id, description 
    FROM bill_payments 
    WHERE id != 1 AND cashier_id = ? 
    ORDER BY created_at DESC
");
$stmt->bind_param("s", $cashier_id);
$stmt->execute();
$result = $stmt->get_result();

$payments = [];
while ($row = $result->fetch_assoc()) {
    $payments[] = $row;
}

echo json_encode(['status' => 'success', 'payments' => $payments]);
?>
