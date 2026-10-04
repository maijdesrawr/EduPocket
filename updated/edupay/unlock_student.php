<?php
header('Content-Type: application/json');
include 'db_connect.php';

function column_exists(mysqli $conn, string $table, string $column): bool
{
    $safeTable = preg_replace('/[^a-zA-Z0-9_]/', '', $table);
    $safeColumn = preg_replace('/[^a-zA-Z0-9_]/', '', $column);
    if ($safeTable === '' || $safeColumn === '') {
        return false;
    }

    $result = $conn->query("SHOW COLUMNS FROM `$safeTable` LIKE '$safeColumn'");
    return $result instanceof mysqli_result && $result->num_rows > 0;
}

$studentNum = trim($_POST['student_num'] ?? '');
if ($studentNum === '') {
    echo json_encode(['status' => 'error', 'message' => 'Missing student number']);
    exit;
}

$hasFailedAttempts = column_exists($conn, 'students', 'failed_attempts');
$hasIsLocked = column_exists($conn, 'students', 'is_locked');

if (!$hasFailedAttempts && !$hasIsLocked) {
    echo json_encode([
        'status' => 'success',
        'message' => "Student $studentNum does not use lock tracking.",
    ]);
    exit;
}

$setParts = [];
if ($hasFailedAttempts) {
    $setParts[] = 'failed_attempts = 0';
}
if ($hasIsLocked) {
    $setParts[] = 'is_locked = 0';
}

$sql = 'UPDATE students SET ' . implode(', ', $setParts) . ' WHERE student_num = ?';
$stmt = $conn->prepare($sql);
if (!$stmt) {
    echo json_encode(['status' => 'error', 'message' => $conn->error]);
    exit;
}

$stmt->bind_param('s', $studentNum);
$stmt->execute();
$stmt->close();

echo json_encode([
    'status' => 'success',
    'message' => "Student $studentNum has been unlocked.",
]);
?>
