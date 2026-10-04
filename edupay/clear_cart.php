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

$cart_id = $_POST['cart_id'] ?? '';
$checkout = $_POST['checkout'] ?? '0';

if ($cart_id === '') {
    echo json_encode([
        'status' => 'error',
        'message' => 'cart_id is required.'
    ]);
    exit;
}

$cart_id = (int)$cart_id;
$checkout = ($checkout === '1' || $checkout === 1 || $checkout === true);

$stmt = $conn->prepare("DELETE FROM pos_cart_items WHERE cart_id = ?");
$stmt->bind_param("i", $cart_id);
if (!$stmt->execute()) {
    echo json_encode([
        'status' => 'error',
        'message' => 'Failed to clear cart items: ' . $stmt->error
    ]);
    $stmt->close();
    $conn->close();
    exit;
}
$stmt->close();

if ($checkout) {
    $stmt = $conn->prepare("UPDATE pos_carts SET status = 'checked_out' WHERE cart_id = ?");
    $stmt->bind_param("i", $cart_id);
    if (!$stmt->execute()) {
        echo json_encode([
            'status' => 'error',
            'message' => 'Failed to update cart status: ' . $stmt->error
        ]);
        $stmt->close();
        $conn->close();
        exit;
    }
    $stmt->close();
}

$conn->close();

echo json_encode([
    'status' => 'success',
    'message' => $checkout ? 'Cart checked out and cleared.' : 'Cart cleared.'
]);
?>
