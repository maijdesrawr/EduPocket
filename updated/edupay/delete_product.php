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
    $canteenId = (string)$session['user_id'];

    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Product deletion could not be started.');
    }
    $transactionStarted = true;
    $statement = pc_prepare(
        $conn,
        'UPDATE products SET is_active = 0 '
            . 'WHERE product_id = ? AND canteen_id = ? AND is_active = 1'
    );
    $statement->bind_param('is', $productId, $canteenId);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Product deletion failed.');
    }
    $affected = $statement->affected_rows;
    $statement->close();
    if ($affected !== 1) {
        http_response_code(404);
        pc_reject('Product not found.');
    }
    as_record_activity(
        $conn,
        $session,
        'product_deleted',
        ['product_id' => $productId]
    );
    if (!$conn->commit()) {
        throw new RuntimeException('Product deletion could not be committed.');
    }
    $transactionStarted = false;
    $payload = [
        'status' => 'success',
        'message' => 'Product deleted successfully.',
        'product_id' => $productId,
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
            'product_delete_failed',
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
    error_log('delete_product.php failed: ' . $error->getMessage());
    http_response_code(500);
    $payload = pc_client_error_payload('The product could not be deleted. Please try again.');
} finally {
    if ($conn instanceof mysqli) {
        $conn->close();
    }
}

pc_respond(is_array($payload) ? $payload : pc_client_error_payload('The request failed.'));

