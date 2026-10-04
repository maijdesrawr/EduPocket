<?php

error_reporting(E_ALL);
ini_set('display_errors', '0');

// Flutter Web sends the app-session token in the Authorization header. That
// header triggers a browser CORS preflight, which must finish before any
// database/session work is performed.
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, OPTIONS");
header("Access-Control-Allow-Headers: Authorization, Content-Type");
header("Access-Control-Max-Age: 86400");
header("Content-Type: application/json; charset=utf-8");

if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

include "db_connect.php";
require_once __DIR__ . '/app_session_common.php';

function respond(string $status, string $message): void
{
    echo json_encode([
        "status" => $status,
        "message" => $message,
    ]);
    exit;
}

function post_string(string $key): string
{
    $value = $_POST[$key] ?? '';
    return is_string($value) ? trim($value) : '';
}

function credential_matches(string $entered, string $stored): bool
{
    return $stored !== ''
        && (password_verify($entered, $stored) || hash_equals($stored, $entered));
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    respond("error", "Invalid request method");
}

try {
    $appSession = as_require_session($conn, false);
} catch (PasswordChangeClientException $error) {
    respond('error', $error->getMessage());
} catch (Throwable $error) {
    error_log('change_password.php session validation failed: ' . $error->getMessage());
    respond('error', 'Your session could not be validated.');
}


$id = post_string('id');
$role = strtolower(post_string('role'));
$currentPassword = post_string('current_password');
$newPassword = post_string('password');
$newPin = post_string('pin');


if (empty($id) || empty($role) || empty($currentPassword) || empty($newPassword)) {
    respond("error", "Missing required fields");
}

if (!in_array($role, ['student', 'parent'], true)) {
    respond("error", "Invalid user role");
}

try {
    as_assert_session_identity($appSession, $role, $id);
} catch (PasswordChangeClientException $error) {
    respond('error', $error->getMessage());
}

$strongPassword = strlen($newPassword) >= 8
    && strlen($newPassword) <= 72
    && preg_match('/[A-Z]/', $newPassword)
    && preg_match('/[a-z]/', $newPassword)
    && preg_match('/[0-9]/', $newPassword)
    && preg_match('/[!@#$%^&*(),.?":{}|<>]/', $newPassword);

if (!$strongPassword) {
    respond(
        "error",
        "Password must have 8-72 characters, uppercase, lowercase, number, and special character"
    );
}

if (hash_equals($currentPassword, $newPassword)) {
    respond("error", "New password must be different from the temporary password");
}

if ($role === 'student') {
    if (!preg_match('/^\d{6}$/', $newPin) || preg_match('/^(\d)\1{5}$/', $newPin)) {
        respond(
            "error",
            "PIN must be exactly 6 digits and cannot contain repeating numbers"
        );
    }
}

if (!$conn->begin_transaction()) {
    error_log('change_password.php could not start a transaction');
    respond("error", "Unable to update credentials");
}

$lookupSql = $role === 'student'
    ? 'SELECT Password, password_changed FROM students WHERE student_num = ? FOR UPDATE'
    : 'SELECT Password, password_changed FROM parents WHERE parent_id = ? FOR UPDATE';
$lookup = $conn->prepare($lookupSql);

if (!$lookup) {
    error_log('change_password.php lookup prepare failed: ' . $conn->error);
    $conn->rollback();
    respond("error", "Unable to update credentials");
}

$lookup->bind_param('s', $id);
if (!$lookup->execute()) {
    error_log('change_password.php lookup failed: ' . $lookup->error);
    $lookup->close();
    $conn->rollback();
    respond("error", "Unable to update credentials");
}

$account = $lookup->get_result()->fetch_assoc();
$lookup->close();
$storedPassword = is_array($account) ? (string) ($account['Password'] ?? '') : '';
$passwordAlreadyChanged = is_array($account)
    ? (int) ($account['password_changed'] ?? 1) !== 0
    : true;

if ($passwordAlreadyChanged || !credential_matches($currentPassword, $storedPassword)) {
    $conn->rollback();
    $conn->close();
    respond("error", "Current credentials are invalid or password has already been changed");
}

try {
    as_assert_session_identity($appSession, $role, $id);
} catch (PasswordChangeClientException $error) {
    $conn->rollback();
    $conn->close();
    respond('error', $error->getMessage());
}


// Hash the new permanent password
$hashedPassword = password_hash($newPassword, PASSWORD_DEFAULT);
$hashedPin = $role === 'student'
    ? password_hash($newPin, PASSWORD_DEFAULT)
    : null;

if (!is_string($hashedPassword) || ($role === 'student' && !is_string($hashedPin))) {
    $conn->rollback();
    $conn->close();
    respond("error", "Unable to secure the new credentials");
}



switch ($role) {


    case "student":

        $stmt = $conn->prepare(
            "UPDATE students 
            SET Password = ?, pin = ?, password_changed = TRUE
            WHERE student_num = ? AND password_changed = FALSE"
        );

        if (!$stmt) {
            error_log('change_password.php prepare failed: ' . $conn->error);
            $conn->rollback();
            $conn->close();
            respond("error", "Unable to update credentials");
        }

        $stmt->bind_param(
            "sss",
            $hashedPassword,
            $hashedPin,
            $id
        );

        break;



    case "parent":

        $stmt = $conn->prepare(
            "UPDATE parents
             SET Password = ?, password_changed = TRUE
             WHERE parent_id = ? AND password_changed = FALSE"
        );

        if (!$stmt) {
            error_log('change_password.php prepare failed: ' . $conn->error);
            $conn->rollback();
            $conn->close();
            respond("error", "Unable to update credentials");
        }

        $stmt->bind_param(
            "ss",
            $hashedPassword,
            $id
        );

        break;



    default:
        respond("error", "Invalid user role");

}



if (!$stmt) {
    error_log('change_password.php prepare failed: ' . $conn->error);
    $conn->rollback();
    $conn->close();
    respond("error", "Unable to update credentials");
}

if ($stmt->execute()) {


    if ($stmt->affected_rows > 0) {
    } else {
        $conn->rollback();
        $conn->close();
        respond(
            "error",
            "Current credentials are invalid or password has already been changed"
        );
    }


} else {
    error_log('change_password.php update failed: ' . $stmt->error);
    $conn->rollback();
    $conn->close();
    respond("error", "Unable to update credentials");
}


$stmt->close();
as_record_activity(
    $conn,
    $appSession,
    'initial_password_changed',
    ['role' => $role, 'pin_created' => $role === 'student'],
    'server'
);
as_mark_session_revoked($conn, $appSession, 'password_changed');
if (!$conn->commit()) {
    error_log('change_password.php commit failed: ' . $conn->error);
    $conn->rollback();
    $conn->close();
    respond("error", "Unable to update credentials");
}
$conn->close();
respond("success", "Password changed successfully");
