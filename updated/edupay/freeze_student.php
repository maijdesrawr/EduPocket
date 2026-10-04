<?php

header("Content-Type: application/json");
include "db_connect.php";


$student_num = $_POST['student_num'] ?? '';
$parent_id = $_POST['parent_id'] ?? '';
$action = $_POST['action'] ?? '';


if(empty($parent_id) || empty($student_num) || empty($action)){
    echo json_encode([
        "status"=>"error",
        "message"=>"Missing data"
    ]);
    exit;
}

$check = $conn->prepare(
    "SELECT 1 FROM parent_student_link WHERE parent_id = ? AND student_num = ? LIMIT 1"
);
$check->bind_param("ss", $parent_id, $student_num);
$check->execute();
if ($check->get_result()->num_rows === 0) {
    http_response_code(403);
    echo json_encode([
        "status" => "error",
        "message" => "Student is not linked to this parent"
    ]);
    exit;
}


if($action == "freeze"){
    $freeze = 1;
}
else if($action == "unfreeze"){
    $freeze = 0;
}
else{
    echo json_encode([
        "status"=>"error",
        "message"=>"Invalid action"
    ]);
    exit;
}



$sql = "
UPDATE students
SET is_frozen = ?
WHERE student_num = ?
";


$stmt = $conn->prepare($sql);

$stmt->bind_param(
    "is",
    $freeze,
    $student_num
);



if($stmt->execute()){

    echo json_encode([
        "status"=>"success",
        "message"=>"Account updated",
        "is_frozen"=>$freeze
    ]);

}
else{

    echo json_encode([
        "status"=>"error",
        "message"=>"Update failed"
    ]);

}

?>
