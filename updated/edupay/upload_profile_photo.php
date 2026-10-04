<?php
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

$role = strtolower(trim($_POST['role'] ?? ''));
$id = trim($_POST['id'] ?? '');

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

if (!isset($_FILES['photo'])) {
    respond_json([
        'status' => 'error',
        'message' => 'Missing uploaded file',
    ]);
}

$file = $_FILES['photo'];
if (($file['error'] ?? UPLOAD_ERR_NO_FILE) !== UPLOAD_ERR_OK) {
    respond_json([
        'status' => 'error',
        'message' => 'Failed to upload file',
    ]);
}

$tmpPath = $file['tmp_name'] ?? '';
$size = intval($file['size'] ?? 0);
if ($tmpPath === '' || $size <= 0) {
    respond_json([
        'status' => 'error',
        'message' => 'Invalid uploaded file',
    ]);
}

if ($size > 4 * 1024 * 1024) {
    respond_json([
        'status' => 'error',
        'message' => 'Image must be 4MB or smaller',
    ]);
}

$finfo = new finfo(FILEINFO_MIME_TYPE);
$mime = $finfo->file($tmpPath);
$allowedMimes = [
    'image/jpeg' => 'jpg',
    'image/png' => 'png',
    'image/webp' => 'webp',
];
$ext = $allowedMimes[$mime] ?? null;
if ($ext === null) {
    respond_json([
        'status' => 'error',
        'message' => 'Only JPG, PNG, and WEBP are allowed',
    ]);
}

$table = $target['table'];
$idField = $target['id_field'];
$nameField = $target['name_field'];

if (!ensure_profile_photo_column($conn, $table)) {
    respond_json([
        'status' => 'error',
        'message' => 'Failed to prepare profile schema',
    ]);
}

// Ensure user exists and fetch current photo for cleanup.
$lookupSql = "SELECT `$idField` AS id, `$nameField` AS name, profile_photo "
    . "FROM `$table` WHERE `$idField` = ? LIMIT 1";
$lookupStmt = $conn->prepare($lookupSql);
if (!$lookupStmt) {
    respond_json([
        'status' => 'error',
        'message' => 'Failed to prepare user lookup',
    ]);
}

$lookupStmt->bind_param('s', $id);
if (!$lookupStmt->execute()) {
    $lookupStmt->close();
    respond_json([
        'status' => 'error',
        'message' => 'Failed to validate user',
    ]);
}

$lookupResult = $lookupStmt->get_result();
$userRow = $lookupResult ? $lookupResult->fetch_assoc() : null;
$lookupStmt->close();

if (!$userRow) {
    respond_json([
        'status' => 'error',
        'message' => 'User not found',
    ]);
}

$uploadDir = __DIR__ . DIRECTORY_SEPARATOR . 'uploads' . DIRECTORY_SEPARATOR . 'profile';
if (!is_dir($uploadDir) && !mkdir($uploadDir, 0775, true)) {
    respond_json([
        'status' => 'error',
        'message' => 'Failed to create upload directory',
    ]);
}

$safeId = preg_replace('/[^a-zA-Z0-9_-]/', '_', $id);
$random = bin2hex(random_bytes(5));
$filename = $role . '_' . $safeId . '_' . date('YmdHis') . '_' . $random . '.' . $ext;
$destination = $uploadDir . DIRECTORY_SEPARATOR . $filename;

if (!move_uploaded_file($tmpPath, $destination)) {
    respond_json([
        'status' => 'error',
        'message' => 'Failed to save uploaded file',
    ]);
}

$relativePath = 'uploads/profile/' . $filename;
$updateSql = "UPDATE `$table` SET profile_photo = ? WHERE `$idField` = ? LIMIT 1";
$updateStmt = $conn->prepare($updateSql);
if (!$updateStmt) {
    @unlink($destination);
    respond_json([
        'status' => 'error',
        'message' => 'Failed to prepare profile update',
    ]);
}

$updateStmt->bind_param('ss', $relativePath, $id);
if (!$updateStmt->execute()) {
    $updateStmt->close();
    @unlink($destination);
    respond_json([
        'status' => 'error',
        'message' => 'Failed to update profile photo',
    ]);
}
$updateStmt->close();

$oldPath = normalize_profile_photo_path($userRow['profile_photo'] ?? null);
if ($oldPath !== null && strpos($oldPath, 'uploads/profile/') === 0) {
    $oldFile = __DIR__ . DIRECTORY_SEPARATOR . str_replace('/', DIRECTORY_SEPARATOR, $oldPath);
    if (is_file($oldFile)) {
        @unlink($oldFile);
    }
}

respond_json([
    'status' => 'success',
    'message' => 'Profile photo updated',
    'profile' => [
        'role' => $role,
        'id' => (string)($userRow['id'] ?? $id),
        'name' => (string)($userRow['name'] ?? ''),
        'photo_path' => $relativePath,
        'photo_url' => profile_photo_url($relativePath),
    ],
]);

