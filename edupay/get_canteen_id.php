<?php
header('Content-Type: application/json');
require_once 'db_port_helper.php';

$servername = "127.0.0.1";
$username = "root";
$password = "R@wrah";
$dbname = "try";

try {
    $conn = connect_mysqli_with_fallback(
        $servername,
        $username,
        $password,
        $dbname
    );
} catch (mysqli_sql_exception $e) {
    echo json_encode([
        'status' => 'error',
        'message' => 'Database connection failed: ' . $e->getMessage()
    ]);
    exit;
}

$canteen_id = $_GET['canteen_id'] ?? '';

if (empty($canteen_id)) {
    echo json_encode([
        'status' => 'error',
        'message' => 'canteen_id is required.'
    ]);
    exit;
}

$stmt = $conn->prepare("SELECT product_id, name, price, is_active FROM products WHERE canteen_id = ?");
$stmt->bind_param("s", $canteen_id);
$stmt->execute();

$result = $stmt->get_result();
$products = [];

while ($row = $result->fetch_assoc()) {
    $products[] = [
        'product_id' => $row['product_id'],
        'name' => $row['name'],
        'price' => $row['price'],
        'is_active' => $row['is_active'] ? true : false
    ];
}

$stmt->close();
$conn->close();

echo json_encode([
    'status' => 'success',
    'products' => $products
]);
?>
