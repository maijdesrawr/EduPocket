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
    $productId = pm_post_product_id();
    $name = pm_normalize_product_name(pc_post_string('name'));
    $price = pm_normalize_price(pc_post_string('price'));
    $stockQuantity = pm_post_stock_quantity();
    $category = pm_normalize_category(pc_post_string('category'));
    $canteenId = (string)$session['user_id'];

    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Product update could not be started.');
    }
    $transactionStarted = true;
    $lookup = pc_prepare(
        $conn,
        'SELECT product_id FROM products '
            . 'WHERE product_id = ? AND canteen_id = ? AND is_active = 1 LIMIT 1 FOR UPDATE'
    );
    $lookup->bind_param('is', $productId, $canteenId);
    $lookup->execute();
    $exists = $lookup->get_result()->fetch_assoc();
    $lookup->close();
    if (!is_array($exists)) {
        http_response_code(404);
        pc_reject('Product not found.');
    }

    $statement = pc_prepare(
        $conn,
        'UPDATE products SET name = ?, price = ?, stock_qty = ?, category = ? '
            . 'WHERE product_id = ? AND canteen_id = ? AND is_active = 1'
    );
    $statement->bind_param(
        'ssisis',
        $name,
        $price,
        $stockQuantity,
        $category,
        $productId,
        $canteenId
    );
    if (!$statement->execute() || $statement->affected_rows > 1) {
        $statement->close();
        throw new RuntimeException('Product update failed.');
    }
    $statement->close();
    as_record_activity(
        $conn,
        $session,
        'product_updated',
        [
            'product_id' => $productId,
            'name' => $name,
            'price' => $price,
            'stock_qty' => $stockQuantity,
            'category' => $category,
        ]
    );
    if (!$conn->commit()) {
        throw new RuntimeException('Product update could not be committed.');
    }
    $transactionStarted = false;
    $payload = [
        'status' => 'success',
        'message' => 'Product updated successfully.',
        'product' => pm_public_product([
            'product_id' => $productId,
            'name' => $name,
            'price' => $price,
            'stock_qty' => $stockQuantity,
            'category' => $category,
            'is_active' => 1,
        ]),
    ];
} catch (PasswordChangeClientException $error) {
    if ($transactionStarted && $conn instanceof mysqli) {
        $conn->rollback();
        $transactionStarted = false;
    }
    if ($conn instanceof mysqli && is_array($session)) {
        pm_record_failure(
            $conn,
            $session,
            'product_update_failed',
            $error->getMessage(),
            ['product_id' => isset($productId) ? $productId : null]
        );
    }
    if (http_response_code() < 400) {
        http_response_code(422);
    }
    $payload = pc_client_error_payload($error->getMessage(), $error->details());
} catch (Throwable $error) {
    if ($transactionStarted && $conn instanceof mysqli) {
        $conn->rollback();
    }
    error_log('update_product.php failed: ' . $error->getMessage());
    http_response_code(500);
    $payload = pc_client_error_payload('The product could not be updated. Please try again.');
} finally {
    if ($conn instanceof mysqli) {
        $conn->close();
    }
}

pc_respond(is_array($payload) ? $payload : pc_client_error_payload('The request failed.'));

