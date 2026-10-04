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

$cart_id = $_POST['cart_id'] ?? '';
$product_id = $_POST['product_id'] ?? '';
$quantity = $_POST['quantity'] ?? '';

if ($cart_id === '' || $product_id === '' || $quantity === '') {
    echo json_encode([
        'status' => 'error',
        'message' => 'cart_id, product_id, and quantity are required.'
    ]);
    exit;
}

if (!is_numeric($quantity) || (int)$quantity < 0) {
    echo json_encode([
        'status' => 'error',
        'message' => 'quantity must be 0 or greater.'
    ]);
    exit;
}

$cart_id = (int)$cart_id;
$product_id = (int)$product_id;
$quantity = (int)$quantity;

if ($quantity === 0) {
    $stmt = $conn->prepare("DELETE FROM pos_cart_items WHERE cart_id = ? AND product_id = ?");
    $stmt->bind_param("ii", $cart_id, $product_id);
    if (!$stmt->execute()) {
        echo json_encode([
            'status' => 'error',
            'message' => 'Failed to remove item: ' . $stmt->error
        ]);
    } else {
        echo json_encode([
            'status' => 'success',
            'message' => 'Item removed.'
        ]);
    }
    $stmt->close();
    $conn->close();
    exit;
}

$stmt = $conn->prepare("SELECT price FROM products WHERE product_id = ?");
$stmt->bind_param("i", $product_id);
$stmt->execute();
$result = $stmt->get_result();
if (!($row = $result->fetch_assoc())) {
    echo json_encode([
        'status' => 'error',
        'message' => 'Product not found.'
    ]);
    $stmt->close();
    $conn->close();
    exit;
}
$price = $row['price'];
$stmt->close();

$stmt = $conn->prepare(
    "INSERT INTO pos_cart_items (cart_id, product_id, quantity, price)
     VALUES (?, ?, ?, ?)
     ON DUPLICATE KEY UPDATE quantity = VALUES(quantity), price = VALUES(price)"
);
$stmt->bind_param("iiid", $cart_id, $product_id, $quantity, $price);

if ($stmt->execute()) {
    echo json_encode([
        'status' => 'success',
        'message' => 'Cart item saved.',
        'price' => $price
    ]);
} else {
    echo json_encode([
        'status' => 'error',
        'message' => 'Failed to save cart item: ' . $stmt->error
    ]);
}

$stmt->close();
$conn->close();
?>
