<?php
require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/app_session_common.php';
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);

function account_query(mysqli $conn, string $sql, array $params = []): mysqli_stmt {
    $stmt = $conn->prepare($sql);
    if ($params) $stmt->bind_param(str_repeat('s', count($params)), ...$params);
    $stmt->execute();
    return $stmt;
}
function account_target(string $category): array {
    $targets = ['student'=>['students','student_num'], 'parent'=>['parents','parent_id'], 'pos'=>['canteens','canteen_id'], 'cashier'=>['cashiers','cashier_id']];
    if (!isset($targets[$category])) throw new InvalidArgumentException('Invalid account category.');
    return $targets[$category];
}
function account_admin(mysqli $conn): array {
    $session = as_require_session($conn, false);
    if (($session['role'] ?? '') !== 'admin') throw new InvalidArgumentException('An administrator must sign in to manage accounts.');
    return $session;
}
function account_set_children(mysqli $conn, string $parentId, array $children): void {
    $children = array_values(array_unique(array_filter(array_map('trim', $children))));
    foreach ($children as $child) {
        $row = account_query($conn, 'SELECT parent_id FROM students WHERE student_num = ? FOR UPDATE', [$child])->get_result()->fetch_assoc();
        if (!$row) throw new InvalidArgumentException("Student $child was not found.");
        if (!empty($row['parent_id']) && $row['parent_id'] !== $parentId) throw new InvalidArgumentException("Student $child is already linked to another parent.");
        $other = account_query($conn, 'SELECT parent_id FROM parent_student_link WHERE student_num = ? AND parent_id <> ?', [$child,$parentId])->get_result()->fetch_assoc();
        if ($other) throw new InvalidArgumentException("Student $child is already linked to another parent.");
    }
    account_query($conn, 'UPDATE students SET parent_id = NULL WHERE parent_id = ?', [$parentId]);
    account_query($conn, 'DELETE FROM parent_student_link WHERE parent_id = ?', [$parentId]);
    foreach ($children as $child) {
        account_query($conn, 'UPDATE students SET parent_id = ? WHERE student_num = ?', [$parentId,$child]);
        account_query($conn, 'INSERT INTO parent_student_link (parent_id, student_num) VALUES (?, ?)', [$parentId,$child]);
    }
    account_query($conn, 'UPDATE parents SET linked_student_num = ? WHERE parent_id = ?', [$children[0] ?? null,$parentId]);
}
