<?php

declare(strict_types=1);

require_once __DIR__ . '/cors_common.php';

require_once __DIR__ . '/product_management_common.php';

pc_bootstrap_json_endpoint();

$conn = null;
$session = null;
$payload = null;
try {
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'GET') {
        http_response_code(405);
        pc_reject('GET is required.');
    }

    $conn = pc_open_database();
    $session = pm_require_canteen_session($conn);
    pm_assert_schema($conn);
    $canteenId = (string)$session['user_id'];
    $searchInput = $_GET['search'] ?? ($_GET['q'] ?? '');
    $categoryInput = $_GET['category'] ?? '';
    $search = pm_normalize_search(is_string($searchInput) ? $searchInput : '');
    $category = pm_normalize_category_filter(
        is_string($categoryInput) ? $categoryInput : ''
    );

    $statement = pc_prepare(
        $conn,
        'SELECT product_id, name, price, stock_qty, category, is_active '
            . 'FROM products WHERE canteen_id = ? AND is_active = 1 '
            . "AND (? = '' OR INSTR(LOWER(name), LOWER(?)) > 0) "
            . "AND (? = '' OR category = ?) "
            . 'ORDER BY category ASC, name ASC, product_id ASC'
    );
    $statement->bind_param('sssss', $canteenId, $search, $search, $category, $category);
    $statement->execute();
    $result = $statement->get_result();
    $products = [];
    while ($row = $result->fetch_assoc()) {
        $products[] = pm_public_product($row);
    }
    $statement->close();

    $categoryStatement = pc_prepare(
        $conn,
        'SELECT DISTINCT category FROM products '
            . 'WHERE canteen_id = ? AND is_active = 1 ORDER BY category ASC'
    );
    $categoryStatement->bind_param('s', $canteenId);
    $categoryStatement->execute();
    $categoryResult = $categoryStatement->get_result();
    $categories = [];
    while ($row = $categoryResult->fetch_assoc()) {
        $value = trim((string)($row['category'] ?? ''));
        if ($value !== '') {
            $categories[] = $value;
        }
    }
    $categoryStatement->close();

    as_record_activity(
        $conn,
        $session,
        'products_viewed',
        [
            'search_applied' => $search !== '',
            'category' => $category === '' ? 'All' : $category,
            'result_count' => count($products),
        ]
    );
    $payload = [
        'status' => 'success',
        'products' => $products,
        'categories' => $categories,
    ];
} catch (PasswordChangeClientException $error) {
    if ($conn instanceof mysqli && is_array($session)) {
        pm_record_failure($conn, $session, 'products_view_failed', $error->getMessage());
    }
    if (http_response_code() < 400) {
        http_response_code(422);
    }
    $payload = pc_client_error_payload($error->getMessage(), $error->details());
} catch (Throwable $error) {
    error_log('get_products.php failed: ' . $error->getMessage());
    http_response_code(500);
    $payload = pc_client_error_payload('Products could not be loaded. Please try again.');
} finally {
    if ($conn instanceof mysqli) {
        $conn->close();
    }
}

pc_respond(is_array($payload) ? $payload : pc_client_error_payload('The request failed.'));
