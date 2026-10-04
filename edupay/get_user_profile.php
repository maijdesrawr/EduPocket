<?php
require_once __DIR__ . '/cors_common.php';
ob_start();
ini_set('display_errors', '0');
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');

include 'db_connect.php';
include 'profile_common.php';

function respond_json(array $payload): void
{
    ob_clean();
    echo json_encode($payload);
    exit;
}

$role = strtolower(trim($_GET['role'] ?? $_POST['role'] ?? ''));
$id = trim($_GET['id'] ?? $_POST['id'] ?? '');

if ($role === '' || $id === '') {
    respond_json([
        'status' => 'error',
        'message' => 'Missing role or id',
    ]);
}

$target = resolve_profile_target($role);
if ($target === null) {
    respond_json([
        'status' => 'error',
        'message' => 'Invalid role',
    ]);
}

$table = $target['table'];
$id_field = $target['id_field'];
$name_field = $target['name_field'];

if (!ensure_profile_photo_column($conn, $table)) {
    respond_json([
        'status' => 'error',
        'message' => 'Failed to prepare profile schema',
    ]);
}

$sql = "SELECT `$id_field` AS id, `$name_field` AS name, profile_photo "
    . "FROM `$table` WHERE `$id_field` = ? LIMIT 1";
$stmt = $conn->prepare($sql);
if (!$stmt) {
    respond_json([
        'status' => 'error',
        'message' => 'Failed to prepare profile query',
    ]);
}

$stmt->bind_param('s', $id);
if (!$stmt->execute()) {
    $stmt->close();
    respond_json([
        'status' => 'error',
        'message' => 'Failed to load profile',
    ]);
}

$result = $stmt->get_result();
$row = $result ? $result->fetch_assoc() : null;
$stmt->close();

if (!$row) {
    respond_json([
        'status' => 'error',
        'message' => 'User not found',
    ]);
}

$photoPath = normalize_profile_photo_path($row['profile_photo'] ?? null);
respond_json([
    'status' => 'success',
    'profile' => [
        'role' => $role,
        'id' => (string)($row['id'] ?? ''),
        'name' => (string)($row['name'] ?? ''),
        'photo_path' => $photoPath,
        'photo_url' => profile_photo_url($photoPath),
    ],
]);
