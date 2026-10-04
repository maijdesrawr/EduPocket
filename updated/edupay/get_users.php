<?php
require_once __DIR__ . '/cors_common.php';
header('Content-Type: application/json');
include 'db_connect.php';
require_once 'profile_common.php';

function table_exists(mysqli $conn, string $table): bool
{
    $safeTable = preg_replace('/[^a-zA-Z0-9_]/', '', $table);
    if ($safeTable === '') {
        return false;
    }

    $result = $conn->query("SHOW TABLES LIKE '$safeTable'");
    return $result instanceof mysqli_result && $result->num_rows > 0;
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

$category = $_GET['category'] ?? '';

try {
    $data = [];

    if ($category === 'student') {
        ensure_profile_photo_column($conn, 'students');
        $hasFailedAttempts = column_exists($conn, 'students', 'failed_attempts');
        $hasIsLocked = column_exists($conn, 'students', 'is_locked');
        $failedAttemptsSelect = $hasFailedAttempts ? 's.failed_attempts' : '0 AS failed_attempts';
        $isLockedSelect = $hasIsLocked ? 's.is_locked' : '0 AS is_locked';

        $query = $conn->query("
            SELECT 
                s.student_num, 
                s.Fname AS name,      
                s.balance, s.parent_id, 
                p.Fname AS parent_name, 
                s.profile_photo,
                $failedAttemptsSelect,
                $isLockedSelect
            FROM students s
            LEFT JOIN parents p ON s.parent_id = p.parent_id
        ");
    } elseif ($category === 'parent') {
        ensure_profile_photo_column($conn, 'parents');
        $query = $conn->query("
            SELECT 
                p.parent_id, 
                p.Fname AS name,      
                (SELECT GROUP_CONCAT(DISTINCT s2.Fname ORDER BY s2.student_num SEPARATOR ', ') FROM students s2 WHERE s2.parent_id = p.parent_id OR EXISTS (SELECT 1 FROM parent_student_link l WHERE l.parent_id = p.parent_id AND l.student_num = s2.student_num)) AS student_name,
                (SELECT GROUP_CONCAT(DISTINCT s2.student_num ORDER BY s2.student_num SEPARATOR ', ') FROM students s2 WHERE s2.parent_id = p.parent_id OR EXISTS (SELECT 1 FROM parent_student_link l WHERE l.parent_id = p.parent_id AND l.student_num = s2.student_num)) AS student_nums, 
                p.profile_photo
            FROM parents p

        ");
    } elseif ($category === 'pos') {
        ensure_profile_photo_column($conn, 'canteens');
        $query = $conn->query("
            SELECT 
                canteen_id, 
                Fname AS name,         
                location, 
                profile_photo
            FROM canteens
        ");
    } elseif ($category === 'cashier') {
        if (table_exists($conn, 'cashiers')) {
            ensure_profile_photo_column($conn, 'cashiers');
            $query = $conn->query("
                SELECT 
                    cashier_id, 
                    Fname AS name,
                    username,
                    profile_photo
                FROM cashiers
            ");
        } elseif (table_exists($conn, 'admins') && column_exists($conn, 'admins', 'role')) {
            ensure_profile_photo_column($conn, 'admins');
            $query = $conn->query("
                SELECT
                    admin_id AS cashier_id,
                    Fname AS name,
                    username,
                    profile_photo
                FROM admins
                WHERE LOWER(COALESCE(role, '')) = 'cashier'
            ");
        } else {
            $query = false;
            $data = [];
        }
    } else {
        throw new Exception("Invalid category");
    }

    if ($category === 'cashier' && $query === false && !table_exists($conn, 'cashiers')) {
        echo json_encode([
            'status' => 'success',
            'data' => []
        ]);
        exit;
    }

    if (!$query) {
        throw new Exception('Failed to fetch users');
    }

    while ($row = $query->fetch_assoc()) {
        $photoPath = normalize_profile_photo_path($row['profile_photo'] ?? null);
        $row['photo_url'] = profile_photo_url($photoPath);
        $data[] = $row;
    }

    echo json_encode([
        'status' => 'success',
        'data' => $data
    ]);
} catch (Exception $e) {
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}
?>
