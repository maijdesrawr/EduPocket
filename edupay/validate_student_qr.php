<?php
ob_start();
ini_set('display_errors', '0');
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');

include 'db_connect.php';

function respond_json(array $payload): void
{
    ob_clean();
    echo json_encode($payload);
    exit;
}

if (!array_key_exists('student_num', $_POST)) {
    respond_json([
        'status' => 'error',
        'exists' => false,
        'message' => 'Missing student_num',
    ]);
}

$student_num = (string)($_POST['student_num'] ?? '');
if ($student_num === '') {
    respond_json([
        'status' => 'error',
        'exists' => false,
        'message' => 'Missing student_num',
    ]);
}

$stmt = $conn->prepare('SELECT COUNT(*) AS match_count, MIN(student_num) AS student_num, MIN(Fname) AS Fname FROM students WHERE BINARY student_num = ?');
if (!$stmt) {
    respond_json([
        'status' => 'error',
        'exists' => false,
        'message' => 'Failed to prepare query',
    ]);
}

$stmt->bind_param('s', $student_num);
if (!$stmt->execute()) {
    $stmt->close();
    respond_json([
        'status' => 'error',
        'exists' => false,
        'message' => 'Failed to execute query',
    ]);
}

$result = $stmt->get_result();
$row = $result ? $result->fetch_assoc() : null;
$stmt->close();

$match_count = intval($row['match_count'] ?? 0);
if ($match_count !== 1) {
    respond_json([
        'status' => 'success',
        'exists' => false,
        'message' => 'Student number not found',
    ]);
}

respond_json([
    'status' => 'success',
    'exists' => true,
    'student' => [
        'student_num' => (string)($row['student_num'] ?? ''),
        'name' => (string)($row['Fname'] ?? ''),
    ],
]);
