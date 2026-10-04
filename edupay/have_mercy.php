<?php
include 'db_connect.php';

$students = [];
$student_query = $conn->query("SELECT student_num, Fname, parent_id, balance FROM students");
while ($row = $student_query->fetch_assoc()) {
    $students[] = $row;
}

$parents = [];
$parent_query = $conn->query("SELECT parent_id, Fname, linked_student_num AS student_num FROM parents");
while ($row = $parent_query->fetch_assoc()) {
    $parents[] = $row;
}

$pos = [];
$pos_query = $conn->query("SELECT canteen_id, Fname, location FROM canteens");
while ($row = $pos_query->fetch_assoc()) {
    $pos[] = $row;
}

echo json_encode([
    'status' => 'success',
    'students' => $students,
    'parents' => $parents,
    'pos' => $pos
]);
?>
