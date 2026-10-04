<?php
header('Content-Type: application/json');
include 'db_connect.php';

$student_num = $_POST['student_num'] ?? '';
$amount = $_POST['amount'] ?? '';
$transaction_type = $_POST['transaction_type'] ?? 'Top-Up';
$description = $_POST['description'] ?? 'Wallet Top-Up';

if (empty($student_num) || empty($amount)) {
    echo json_encode(['status' => 'error', 'message' => 'Missing required fields']);
    exit;
}

$stmt = $conn->prepare("
    INSERT INTO transactions (student_num, amount, transaction_type, description, date_time)
    VALUES (?, ?, ?, ?, NOW())
");
$stmt->bind_param("sdss", $student_num, $amount, $transaction_type, $description);

if ($stmt->execute()) {
    echo json_encode(['status' => 'success', 'message' => 'Transaction recorded successfully']);
} else {
    echo json_encode(['status' => 'error', 'message' => 'Failed to record transaction']);
}

$stmt->close();
$conn->close();
?>
