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

$studentId = trim($_GET['student_id'] ?? '');
if ($studentId === '') {
    echo json_encode([
        'status' => 'error',
        'message' => 'Missing student_id parameter.',
    ]);
    exit;
}

$hasFailedAttempts = column_exists($conn, 'students', 'failed_attempts');
$hasIsLocked = column_exists($conn, 'students', 'is_locked');
$failedAttemptsSelect = $hasFailedAttempts ? 'failed_attempts' : '0 AS failed_attempts';
$isLockedSelect = $hasIsLocked ? 'is_locked' : '0 AS is_locked';

$stmt = $conn->prepare(
    "SELECT student_num AS id, Fname AS name, balance, $failedAttemptsSelect, $isLockedSelect
     FROM students
     WHERE student_num = ?
     LIMIT 1"
);

if (!$stmt) {
    echo json_encode([
        'status' => 'error',
        'message' => 'Failed to prepare student query.',
    ]);
    exit;
}

$stmt->bind_param('s', $studentId);
$stmt->execute();
$result = $stmt->get_result();

if ($result && $result->num_rows > 0) {
    $row = $result->fetch_assoc();
    echo json_encode([
        'status' => 'success',
        'role' => 'student',
        'id' => $row['id'],
        'name' => $row['name'],
        'balance' => $row['balance'],
        'failed_attempts' => (int) ($row['failed_attempts'] ?? 0),
        'is_locked' => (bool) ($row['is_locked'] ?? 0),
    ]);
} else {
    echo json_encode([
        'status' => 'error',
        'message' => 'Student not found.',
    ]);
}

$stmt->close();
$conn->close();
?>
