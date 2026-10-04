<?php
header('Content-Type: application/json; charset=utf-8');
include 'db_connect.php';

function respond(array $payload): void
{
    echo json_encode($payload, JSON_UNESCAPED_UNICODE);
    exit;
}

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

$parent_id = trim($_POST['parent_id'] ?? '');
$student_num = trim($_POST['student_num'] ?? '');
$amount = floatval($_POST['amount'] ?? 0);
$limit_period = strtolower(trim($_POST['limit_period'] ?? 'daily'));

if ($parent_id === '' || $student_num === '') {
    respond(['status' => 'error', 'message' => 'Missing parent or child id']);
}

if (!in_array($limit_period, ['daily', 'weekly', 'monthly'], true)) {
    respond(['status' => 'error', 'message' => 'Invalid spending limit period']);
}

if ($amount <= 0 || $amount > 100000) {
    respond(['status' => 'error', 'message' => 'Amount must be between 1 and 100,000']);
}

if (!column_exists($conn, 'students', 'transaction_limit') ||
    !column_exists($conn, 'students', 'transaction_limit_period')) {
    respond([
        'status' => 'error',
        'message' => 'Database migration required for spending limits'
    ]);
}

$link_stmt = $conn->prepare("
    SELECT 1
    FROM parent_student_link
    WHERE parent_id = ? AND student_num = ?
    LIMIT 1
");
if (!$link_stmt) {
    respond(['status' => 'error', 'message' => 'Failed to validate linked child']);
}

$link_stmt->bind_param('ss', $parent_id, $student_num);
$link_stmt->execute();
$link_result = $link_stmt->get_result();
if (!$link_result || $link_result->num_rows === 0) {
    $link_stmt->close();
    respond(['status' => 'error', 'message' => 'Selected child is not linked to this parent']);
}
$link_stmt->close();

$update_stmt = $conn->prepare("
    UPDATE students
    SET transaction_limit = ?, transaction_limit_period = ?
    WHERE student_num = ?
");
if (!$update_stmt) {
    respond(['status' => 'error', 'message' => 'Failed to prepare spending limit update']);
}

$update_stmt->bind_param('dss', $amount, $limit_period, $student_num);
if (!$update_stmt->execute()) {
    $update_stmt->close();
    respond(['status' => 'error', 'message' => 'Failed to save spending limit']);
}
$update_stmt->close();

respond([
    'status' => 'success',
    'message' => 'Spending limit saved successfully',
    'transaction_limit' => number_format($amount, 2, '.', ''),
    'transaction_limit_period' => $limit_period
]);
?>
