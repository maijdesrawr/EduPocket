<?php
header('Content-Type: application/json; charset=utf-8');
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

if (!$hasFailedAttempts || !$hasIsLocked) {
    echo json_encode([
        'status' => 'success',
        'failed_attempts' => 0,
        'is_locked' => false,
    ]);
    exit;
}

$stmt = $conn->prepare('SELECT failed_attempts, is_locked FROM students WHERE student_num = ? LIMIT 1');
if (!$stmt) {
    echo json_encode(['status' => 'error', 'message' => 'Prepare failed: ' . $conn->error]);
    exit;
}

$stmt->bind_param('s', $studentNum);
$stmt->execute();
$stmt->bind_result($failedAttempts, $isLocked);
if (!$stmt->fetch()) {
    echo json_encode(['status' => 'error', 'message' => 'Student not found']);
    $stmt->close();
    exit;
}
$stmt->close();

if ($isLocked) {
    echo json_encode([
        'status' => 'success',
        'failed_attempts' => (int) $failedAttempts,
        'is_locked' => true,
    ]);
    exit;
}

$failedAttempts = (int) $failedAttempts + 1;
$maxAttempts = 3;
$lockFlag = ($failedAttempts >= $maxAttempts) ? 1 : 0;

$updateStmt = $conn->prepare('UPDATE students SET failed_attempts = ?, is_locked = ? WHERE student_num = ?');
if (!$updateStmt) {
    echo json_encode(['status' => 'error', 'message' => 'Prepare failed: ' . $conn->error]);
    exit;
}

$updateStmt->bind_param('iis', $failedAttempts, $lockFlag, $studentNum);
if (!$updateStmt->execute()) {
    echo json_encode(['status' => 'error', 'message' => 'Execute failed: ' . $updateStmt->error]);
    $updateStmt->close();
    exit;
}
$updateStmt->close();

echo json_encode([
    'status' => 'success',
    'failed_attempts' => $failedAttempts,
    'is_locked' => (bool) $lockFlag,
]);
?>
