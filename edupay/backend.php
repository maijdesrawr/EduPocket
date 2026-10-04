<?php
header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: POST, GET, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");
header("Content-Type: application/json");
require_once 'db_port_helper.php';

$servername = "127.0.0.1"; 
$username   = "root";        
$password   = "R@wrah";     
$dbname     = "try";    

try {
    $conn = connect_mysqli_with_fallback(
        $servername,
        $username,
        $password,
        $dbname
    );
} catch (mysqli_sql_exception $e) {
    echo json_encode([
        "status" => "error",
        "message" => "Database connection failed: " . $e->getMessage()
    ]);
    exit();
}

$data = json_decode(file_get_contents('php://input'), true);
$student_num = $data['student_num'] ?? '';


if (empty($student_num)) {
    echo json_encode([
        "status" => "error",
        "message" => "Student number is required",
        "debug" => $_POST
    ]);
    exit();
}

$sql = "SELECT FullName, Balance, Year_Level FROM records WHERE StudentNum = ?";
$stmt = $conn->prepare($sql);

if (!$stmt) {
    echo json_encode([
        "status" => "error",
        "message" => "Query preparation failed: " . $conn->error
    ]);
    exit();
}

$stmt->bind_param("s", $student_num); 
$stmt->execute();
$result = $stmt->get_result();

if ($result && $result->num_rows > 0) {
    $row = $result->fetch_assoc();
    echo json_encode([
        "status" => "success",
        "message" => "Welcome " . $row['FullName'] . " to your account",
        "details" => [
            "full_name" => $row['FullName'],
            "balance" => $row['Balance'],
            "year_level" => $row['Year_Level']
        ]
    ]);
} else {
    echo json_encode([
        "status" => "error",
        "message" => "You entered the wrong student number"
    ]);
}

$stmt->close();
$conn->close();

?>
