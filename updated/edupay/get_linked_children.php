<?php
header('Content-Type: application/json');
include 'db_connect.php';

$parent_id = $_GET['parent_id'] ?? $_POST['parent_id'] ?? '';

if (empty($parent_id)) {
    echo json_encode(['status' => 'error', 'message' => 'Missing parent_id']);
    exit;
}

try {
    $query = "
        SELECT s.student_num, s.Fname, s.balance, s.transaction_limit
        FROM students s
        INNER JOIN parent_student_link psl ON s.student_num = psl.student_num
        WHERE psl.parent_id = ?
    ";

    $stmt = $conn->prepare($query);
    $stmt->bind_param('s', $parent_id);
    $stmt->execute();
    $result = $stmt->get_result();

    $children = [];
    while ($row = $result->fetch_assoc()) {
        $children[] = $row;
    }

    if (count($children) > 0) {
        echo json_encode([
            'status' => 'success',
            'children' => $children
        ]);
    } else {
        echo json_encode([
            'status' => 'error',
            'message' => 'No children found for this parent.'
        ]);
    }

    $stmt->close();
    $conn->close();
} catch (Exception $e) {
    echo json_encode(['status' => 'error', 'message' => $e->getMessage()]);
}
?>
