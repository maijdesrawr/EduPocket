<?php

declare(strict_types=1);

require_once __DIR__ . '/product_management_common.php';

pc_bootstrap_json_endpoint();

$conn = null;
$session = null;
$transactionStarted = false;
$payload = null;
try {
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
        http_response_code(405);
        pc_reject('POST is required.');
    }

    $conn = pc_open_database();
    $session = pm_require_canteen_session($conn);
    pm_assert_schema($conn);

    $name = pm_normalize_product_name(pc_post_string('name'));
    $price = pm_normalize_price(pc_post_string('price'));
    $stockQuantity = pm_post_stock_quantity();
    $category = pm_normalize_category(pc_post_string('category'));
    $canteenId = (string)$session['user_id'];

    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Product creation could not be started.');
    }
    $transactionStarted = true;
    $statement = pc_prepare(
        $conn,
        'INSERT INTO products (canteen_id, name, price, stock_qty, category, is_active) '
            . 'VALUES (?, ?, ?, ?, ?, 1)'
    );
    $statement->bind_param('sssis', $canteenId, $name, $price, $stockQuantity, $category);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Product creation failed.');
    }
    $productId = (int)$statement->insert_id;
    $statement->close();
    as_record_activity(
        $conn,
        $session,
        'product_created',
        [
            'product_id' => $productId,
            'name' => $name,
            'price' => $price,
            'stock_qty' => $stockQuantity,
            'category' => $category,
        ]
    );
    if (!$conn->commit()) {
        throw new RuntimeException('Product creation could not be committed.');
    }
    $transactionStarted = false;
    $payload = [
        'status' => 'success',
        'message' => 'Product added successfully.',
        'product' => pm_public_product([
            'product_id' => $productId,
            'name' => $name,
            'price' => $price,
            'stock_qty' => $stockQuantity,
            'category' => $category,
            'is_active' => 1,
        ]),

        'product_id' => $productId,
        'stock_qty' => $stockQuantity,
    ];
} catch (PasswordChangeClientException $error) {
    if ($transactionStarted && $conn instanceof mysqli) {
        $conn->rollback();
        $transactionStarted = false;
    }
    if ($conn instanceof mysqli && is_array($session)) {
        pm_record_failure($conn, $session, 'product_create_failed', $error->getMessage());
    }
    if (http_response_code() < 400) {
        http_response_code(422);
    }
    $payload = pc_client_error_payload($error->getMessage(), $error->details());
} catch (Throwable $error) {
    if ($transactionStarted && $conn instanceof mysqli) {
        $conn->rollback();
    }
    error_log('add_product.php failed: ' . $error->getMessage());
    http_response_code(500);
    $payload = pc_client_error_payload('The product could not be added. Please try again.');
} finally {
    if ($conn instanceof mysqli) {
        $conn->close();
    }
}

pc_respond(is_array($payload) ? $payload : pc_client_error_payload('The request failed.'));

