<?php

declare(strict_types=1);

require_once __DIR__ . '/app_session_common.php';

const PM_MAX_STOCK_QUANTITY = 1000000;

/** @return array<string, mixed> */
function pm_require_canteen_session(mysqli $conn): array
{
    $session = as_require_session($conn);
    as_assert_session_role($session, ['canteen']);
    as_assert_session_identity(
        $session,
        'canteen',
        (string)$session['user_id'],
        'canteens'
    );
    return $session;
}

function pm_assert_schema(mysqli $conn): void
{
    foreach (['stock_qty', 'category', 'is_active'] as $column) {
        if (!pc_column_exists($conn, 'products', $column)) {
            throw new RuntimeException(
                'The product-management database migration has not been applied.'
            );
        }
    }
}

function pm_text_length(string $value): int
{
    return function_exists('mb_strlen') ? mb_strlen($value, 'UTF-8') : strlen($value);
}

function pm_normalize_text(string $value, string $label, int $maximumLength): string
{
    $value = trim($value);
    if ($value === '' || preg_match('//u', $value) !== 1) {
        pc_reject("{$label} is required.");
    }
    if (preg_match('/[\x00-\x1F\x7F]/u', $value) === 1) {
        pc_reject("{$label} contains invalid characters.");
    }
    $normalized = preg_replace('/\s+/u', ' ', $value);
    $normalized = is_string($normalized) ? trim($normalized) : '';
    if ($normalized === '' || pm_text_length($normalized) > $maximumLength) {
        pc_reject("{$label} must be at most {$maximumLength} characters.");
    }
    return $normalized;
}

function pm_normalize_product_name(string $value): string
{
    return pm_normalize_text($value, 'Product name', 100);
}

function pm_normalize_category(string $value): string
{
    $category = pm_normalize_text($value, 'Category', 50);
    if (strcasecmp($category, 'All') === 0) {
        pc_reject('All is reserved for showing every category. Choose another category name.');
    }
    return $category;
}

function pm_normalize_search(string $value): string
{
    $value = trim($value);
    return $value === '' ? '' : pm_normalize_text($value, 'Search', 100);
}

function pm_normalize_category_filter(string $value): string
{
    $value = trim($value);
    if ($value === '' || strcasecmp($value, 'All') === 0) {
        return '';
    }
    return pm_normalize_text($value, 'Category', 50);
}

function pm_normalize_price(string $value): string
{
    $value = trim($value);
    if (preg_match('/^\d{1,8}(?:\.\d{1,2})?$/D', $value) !== 1) {
        pc_reject('Price must be a positive amount with no more than 2 decimal places.');
    }
    [$whole, $fraction] = array_pad(explode('.', $value, 2), 2, '');
    $whole = ltrim($whole, '0');
    if ($whole === '') {
        $whole = '0';
    }
    $fraction = str_pad($fraction, 2, '0');
    $canonical = $whole . '.' . $fraction;
    if ($canonical === '0.00') {
        pc_reject('Price must be greater than 0.');
    }
    return $canonical;
}

function pm_normalize_stock_quantity(string $value): int
{
    $value = trim($value);
    if ($value === '' || ctype_digit($value) === false) {
        pc_reject('Quantity must be a positive whole number.');
    }
    $quantity = (int)$value;
    if ($quantity < 1 || $quantity > PM_MAX_STOCK_QUANTITY) {
        pc_reject(
            'Quantity must be between 1 and ' . number_format(PM_MAX_STOCK_QUANTITY) . '.'
        );
    }
    return $quantity;
}

function pm_post_stock_quantity(): int
{
    $value = pc_post_string('stock_qty');
    if ($value === '') {
        $value = pc_post_string('quantity');
    }
    return pm_normalize_stock_quantity($value);
}

function pm_post_product_id(): int
{
    $value = pc_post_string('product_id');
    if ($value === '' || ctype_digit($value) === false || (int)$value < 1) {
        pc_reject('A valid product ID is required.');
    }
    return (int)$value;
}

/** @param array<string, mixed> $row
 *  @return array<string, mixed>
 */
function pm_public_product(array $row): array
{
    return [
        'product_id' => (int)$row['product_id'],
        'name' => (string)$row['name'],
        'price' => number_format((float)$row['price'], 2, '.', ''),
        'stock_qty' => (int)$row['stock_qty'],
        'category' => (string)$row['category'],
        'is_active' => (int)($row['is_active'] ?? 1) === 1,
    ];
}

function pm_build_purchase_description(array $items): string
{
    if ($items === []) {
        throw new RuntimeException('A purchase description requires at least one product.');
    }

    usort(
        $items,
        static function (array $left, array $right): int {
            $byProduct = ((int)($left['product_id'] ?? 0))
                <=> ((int)($right['product_id'] ?? 0));
            if ($byProduct !== 0) {
                return $byProduct;
            }
            return strcmp((string)($left['name'] ?? ''), (string)($right['name'] ?? ''));
        }
    );

    $parts = [];
    foreach ($items as $item) {
        $productId = (int)($item['product_id'] ?? 0);
        $quantity = (int)($item['quantity'] ?? 0);
        $name = trim((string)($item['name'] ?? ''));
        if ($productId < 1 || $quantity < 1 || $name === '') {
            throw new RuntimeException('A validated purchase product is invalid.');
        }
        $parts[] = $name . ' ' . $quantity . 'x';
    }

    $description = implode(', ', $parts);
    if (pm_text_length($description) > 255) {
        throw new RuntimeException(
            'The selected product names are too long for one transaction. Please use a smaller cart.'
        );
    }
    return $description;
}

/** @param array<string, mixed> $session */
function pm_record_failure(
    mysqli $conn,
    array $session,
    string $eventName,
    string $reason,
    array $metadata = []
): void {
    try {
        as_record_activity(
            $conn,
            $session,
            $eventName,
            array_merge(['reason' => $reason], $metadata),
            'server',
            'failure'
        );
    } catch (Throwable $auditError) {
        error_log('Product-management failure audit failed: ' . $auditError->getMessage());
    }
}
