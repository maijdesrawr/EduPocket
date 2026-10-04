<?php
header('Content-Type: application/json');
include 'db_connect.php';

date_default_timezone_set('Asia/Manila');

$parent_id = $_GET['parent_id'] ?? '';
$child_id  = $_GET['child_id'] ?? ''; 

if (empty($parent_id)) {
    echo json_encode(['status' => 'error', 'message' => 'Missing parent_id']);
    exit;
}

$childQuery = $conn->prepare("
    SELECT s.student_num, s.Fname AS child_name
    FROM students s
    INNER JOIN parent_student_link psl ON s.student_num = psl.student_num
    WHERE psl.parent_id = ?
");
$childQuery->bind_param("s", $parent_id);
$childQuery->execute();
$childResult = $childQuery->get_result();

if ($childResult->num_rows === 0) {
    echo json_encode(['status' => 'error', 'message' => 'No linked student found.']);
    exit;
}

$children = [];
while ($row = $childResult->fetch_assoc()) {
    $children[] = $row;
}

if (!empty($child_id)) {
    $selectedChild = array_filter($children, fn($c) => $c['student_num'] == $child_id);
    $selectedChild = reset($selectedChild);
} else {
    $selectedChild = $children[0];
}

if (!$selectedChild) { echo json_encode(['status'=>'error','message'=>'Student is not linked to this parent.']); exit; }
$student_num = $selectedChild['student_num'];
$child_name = $selectedChild['child_name'];

$txQuery = $conn->prepare("
    SELECT transaction_id, amount, description AS note, date_time AS date, transaction_type
    FROM transactions
    WHERE student_num = ?
    ORDER BY date_time DESC, transaction_id DESC
");
$txQuery->bind_param("s", $student_num);
$txQuery->execute();
$txResult = $txQuery->get_result();

$transactions = [];
while ($row = $txResult->fetch_assoc()) {
    $transactions[] = [
        'transaction_id' => (int)$row['transaction_id'],
        'name' => $child_name,
        'amount' => (string)($row['amount'] ?? '0'),
        'date' => (string)($row['date'] ?? ''),
        'timestamp' => (string)($row['date'] ?? ''),
        'note' => $row['note'] ?? ucfirst($row['transaction_type']),
        'is_topup' => strtolower($row['transaction_type']) === 'top-up', 
    ];
}

echo json_encode([
    'status' => 'success',
    'children' => $children,
    'transactions' => $transactions
]);

$conn->close();
?>
