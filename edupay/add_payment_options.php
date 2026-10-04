<?php
header('Content-Type: application/json; charset=utf-8');
include 'db_connect.php'; 

$description = trim($_POST['description'] ?? '');
$cashier_id = trim($_POST['cashier_id'] ?? '');

if ($description === '') {
    echo json_encode(['status' => 'error', 'message' => 'Description is required']);
    exit;
}

if ($cashier_id === '') {
    echo json_encode(['status' => 'error', 'message' => 'Cashier ID is required']);
    exit;
}

$sql = "INSERT INTO bill_payments (description, cashier_id) VALUES (?, ?)";
$stmt = $conn->prepare($sql);

if (!$stmt) {
    echo json_encode(['status' => 'error', 'message' => $conn->error]);
    exit;
}

$stmt->bind_param('ss', $description, $cashier_id);

if ($stmt->execute()) {
    echo json_encode([
        'status' => 'success',
        'message' => 'Payment added successfully',
        'payment' => [
            'id' => $stmt->insert_id,
            'description' => $description,
            'cashier_id' => $cashier_id
        ]
    ]);
} else {
    echo json_encode(['status' => 'error', 'message' => $stmt->error]);
}

$stmt->close();
$conn->close();
?>
