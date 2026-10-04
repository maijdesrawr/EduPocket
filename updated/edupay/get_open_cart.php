<?php
header('Content-Type: application/json');
require_once 'db_port_helper.php';

$servername = "127.0.0.1";
$username = "root";
$password = "";
$dbname = "centraldb";

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
$cashier_id = $_GET['cashier_id'] ?? '';

if (empty($canteen_id) || empty($cashier_id)) {
    echo json_encode([
        'status' => 'error',
        'message' => 'canteen_id and cashier_id are required.'
    ]);
    exit;
}

$cart_id = null;
$stmt = $conn->prepare(
    "SELECT cart_id FROM pos_carts 
     WHERE canteen_id = ? AND cashier_id = ? AND status = 'open' 
     ORDER BY cart_id DESC LIMIT 1"
);
$stmt->bind_param("ss", $canteen_id, $cashier_id);
$stmt->execute();
$result = $stmt->get_result();
if ($row = $result->fetch_assoc()) {
    $cart_id = (int)$row['cart_id'];
}
$stmt->close();

if ($cart_id === null) {
    $stmt = $conn->prepare(
        "INSERT INTO pos_carts (canteen_id, cashier_id, status) VALUES (?, ?, 'open')"
    );
    $stmt->bind_param("ss", $canteen_id, $cashier_id);
    if (!$stmt->execute()) {
        echo json_encode([
            'status' => 'error',
            'message' => 'Failed to create cart: ' . $stmt->error
        ]);
        $stmt->close();
        $conn->close();
        exit;
    }
    $cart_id = $stmt->insert_id;
    $stmt->close();
}

$items = [];
$stmt = $conn->prepare(
    "SELECT i.product_id, p.name, i.quantity, i.price
     FROM pos_cart_items i
     JOIN products p ON p.product_id = i.product_id
     WHERE i.cart_id = ?"
);
$stmt->bind_param("i", $cart_id);
$stmt->execute();
$result = $stmt->get_result();
while ($row = $result->fetch_assoc()) {
    $items[] = [
        'product_id' => $row['product_id'],
        'name' => $row['name'],
        'quantity' => (int)$row['quantity'],
        'price' => $row['price']
    ];
}
$stmt->close();
$conn->close();

echo json_encode([
    'status' => 'success',
    'cart_id' => $cart_id,
    'items' => $items
]);
?>
