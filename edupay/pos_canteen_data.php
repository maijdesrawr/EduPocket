<?php
header('Content-Type: application/json');
require_once 'db_port_helper.php';

$servername = "127.0.0.1";
$username = "root";
$password = "R@wrah";
$database = "try";

try {
    $conn = connect_mysqli_with_fallback(
        $servername,
        $username,
        $password,
        $database
    );
} catch (mysqli_sql_exception $e) {
    echo json_encode([
        "status" => "error",
        "message" => "Database connection failed: " . $e->getMessage()
    ]);
    exit();
}

// Fetch all transactions
$query = "
    SELECT 
        t.id,
        s.Fname AS student_name,
        t.payment_title,
        t.amount,
        t.timestamp
    FROM transactions AS t
    LEFT JOIN students AS s 
        ON t.student_id = s.student_num
    ORDER BY t.timestamp DESC
";

$result = $conn->query($query);

if (!$result) {
    echo json_encode([
        "status" => "error",
        "message" => "Query failed: " . $conn->error
    ]);
    exit();
}

$transactions = [];
$totalBalance = 0.0;

while ($row = $result->fetch_assoc()) {
    $amount = floatval($row["amount"]);
    $totalBalance += $amount;

    $transactions[] = [
        "id" => $row["id"],
        "student_name" => $row["student_name"] ?: "N/A",
        "payment_title" => $row["payment_title"] ?: "Payment",
        "amount" => $amount,
        "timestamp" => $row["timestamp"]
    ];
}

echo json_encode([
    "status" => "success",
    "canteen_balance" => round($totalBalance, 2),
    "transactions" => $transactions
]);

$conn->close();
?>
