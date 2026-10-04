<?php
require_once __DIR__ . '/cors_common.php';
ob_start();
ini_set('display_errors', '0');
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');

include 'db_connect.php';
require_once __DIR__ . '/product_management_common.php';


function respond_json(array $payload): void
{
    if (ob_get_length()) {
        ob_end_clean(); 
    }
    echo json_encode($payload);
    exit;
}

function prepare_or_throw(mysqli $conn, string $sql, string $errorMessage): mysqli_stmt
{
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        throw new Exception($errorMessage . ': ' . $conn->error);
    }
    return $stmt;
}

function column_exists(mysqli $conn, string $table, string $column): bool
{
    $safeTable = preg_replace('/[^a-zA-Z0-9_]/', '', $table);
    $safeColumn = preg_replace('/[^a-zA-Z0-9_]/', '', $column);
    if ($safeTable === '' || $safeColumn === '') {
        return false;
    }

    $result = $conn->query("SHOW COLUMNS FROM `$safeTable` LIKE '$safeColumn'");
    return $result instanceof mysqli_result && $result->num_rows > 0;
}

function pin_matches(string $enteredPin, ?string $storedPin): bool
{
    $storedPin = trim((string) $storedPin);
    if ($storedPin === '') {
        return false;
    }

    if (hash_equals($storedPin, $enteredPin)) {
        return true;
    }

    return password_verify($enteredPin, $storedPin);
}

function normalize_limit_period(?string $period): string
{
    $value = strtolower(trim((string)$period));
    if (in_array($value, ['daily', 'weekly', 'monthly'], true)) {
        return $value;
    }
    return 'daily';
}

function spending_limit_filter_sql(string $period): string
{
    switch (normalize_limit_period($period)) {
        case 'weekly':
            return "YEARWEEK(COALESCE(date_time, date_created, NOW()), 1) = YEARWEEK(CURDATE(), 1)";
        case 'monthly':
            return "MONTH(COALESCE(date_time, date_created, NOW())) = MONTH(CURDATE())"
                . " AND YEAR(COALESCE(date_time, date_created, NOW())) = YEAR(CURDATE())";
        case 'daily':
        default:
            return "DATE(COALESCE(date_time, date_created, NOW())) = CURDATE()";
    }
}

function assert_within_spending_limit(
    mysqli $conn,
    string $student_num,
    float $amount,
    float $limit,
    ?string $period
): void {
    if ($amount <= 0 || $limit <= 0) {
        return;
    }

    $normalizedPeriod = normalize_limit_period($period);
    $filterSql = spending_limit_filter_sql($normalizedPeriod);

    $spent_stmt = prepare_or_throw(
        $conn,
        "SELECT COALESCE(SUM(amount), 0) AS spent
         FROM transactions
         WHERE student_num = ?
           AND transaction_type = 'payment'
           AND $filterSql",
        'Failed to calculate spending limit usage'
    );
    $spent_stmt->bind_param('s', $student_num);
    $spent_stmt->execute();
    $spent_row = $spent_stmt->get_result()->fetch_assoc();
    $spent_stmt->close();

    $spent = floatval($spent_row['spent'] ?? 0);
    if (($spent + $amount) <= ($limit + 0.00001)) {
        return;
    }

    $remaining = max(0, $limit - $spent);
    throw new Exception(
        'Over your budget. '
        . ucfirst($normalizedPeriod)
        . ' spending limit is PHP '
        . number_format($limit, 2)
        . ' and you only have PHP '
        . number_format($remaining, 2)
        . ' left.'
    );
}

try {
    $appSession = as_require_session($conn, false);
} catch (PasswordChangeClientException $error) {
    respond_json(pc_client_error_payload($error->getMessage(), $error->details()));
} catch (Throwable $error) {
    error_log('confirm_payment.php session validation failed: ' . $error->getMessage());
    respond_json(['status' => 'error', 'message' => 'Your session could not be validated.']);
}

$student_num = trim($_POST['student_num'] ?? '');
$pin = trim($_POST['pin'] ?? '');
$amount = floatval($_POST['amount'] ?? 0);
$canteen_id = trim($_POST['canteen_id'] ?? '');
$cashier_id = isset($_POST['cashier_id']) ? trim($_POST['cashier_id']) : null;
$items_raw = $_POST['items'] ?? '';

if ($student_num === '' || $pin === '' || $canteen_id === '') {
    respond_json(['status' => 'error', 'message' => 'Missing required fields']);
}
if (!preg_match('/^\d{6}$/', $pin)) {
    respond_json(['status' => 'error', 'message' => 'PIN must be exactly 6 digits']);
}

$items_decoded = json_decode($items_raw, true);
if (!is_array($items_decoded) || count($items_decoded) === 0) {
    respond_json(['status' => 'error', 'message' => 'No purchased items provided']);
}

$requested_items = [];
foreach ($items_decoded as $item) {
    if (!is_array($item)) {
        continue;
    }

    $product_id = intval($item['product_id'] ?? 0);
    $quantity = intval($item['quantity'] ?? 0);

    if ($product_id <= 0 || $quantity <= 0) {
        continue;
    }

    if (!isset($requested_items[$product_id])) {
        $requested_items[$product_id] = 0;
    }
    $requested_items[$product_id] += $quantity;
}

if (count($requested_items) === 0) {
    respond_json(['status' => 'error', 'message' => 'No valid purchased items provided']);
}

ksort($requested_items, SORT_NUMERIC);

$conn->begin_transaction();

try {
    as_assert_session_identity($appSession, 'canteen', $canteen_id, 'canteens');
    $stock_col = $conn->query("SHOW COLUMNS FROM products LIKE 'stock_qty'");
    if (!$stock_col || $stock_col->num_rows === 0) {
        throw new Exception('Database migration required: products.stock_qty is missing.');
    }
    $canteen_balance_col = $conn->query("SHOW COLUMNS FROM canteens LIKE 'balance'");
    if (!$canteen_balance_col || $canteen_balance_col->num_rows === 0) {
        throw new Exception('Database migration required: canteens.balance is missing.');
    }

    $canteen_lookup_stmt = prepare_or_throw(
        $conn,
        'SELECT canteen_id FROM canteens WHERE canteen_id = ? LIMIT 1',
        'Failed to validate canteen id'
    );
    $canteen_lookup_stmt->bind_param('s', $canteen_id);
    if (!$canteen_lookup_stmt->execute()) {
        throw new Exception('Failed to validate canteen id');
    }

    $canteen_lookup_result = $canteen_lookup_stmt->get_result();
    if (!$canteen_lookup_result || $canteen_lookup_result->num_rows === 0) {
        $admin_canteen_stmt = prepare_or_throw(
            $conn,
            'SELECT canteen_id FROM admins WHERE admin_id = ? LIMIT 1',
            'Failed to resolve canteen id from admin'
        );
        $admin_canteen_stmt->bind_param('s', $canteen_id);
        if (!$admin_canteen_stmt->execute()) {
            throw new Exception('Failed to resolve canteen id from admin');
        }

        $admin_canteen_result = $admin_canteen_stmt->get_result();
        if ($admin_canteen_result && $admin_canteen_result->num_rows > 0) {
            $resolved = $admin_canteen_result->fetch_assoc();
            $canteen_id = trim($resolved['canteen_id'] ?? '');
        }
        $admin_canteen_stmt->close();
    }
    $canteen_lookup_stmt->close();

    if ($canteen_id === '') {
        throw new Exception('Invalid canteen id');
    }

    if (!empty($cashier_id)) {
        $cashier_lookup_stmt = prepare_or_throw(
            $conn,
            'SELECT admin_id FROM admins WHERE admin_id = ? LIMIT 1',
            'Failed to validate cashier id'
        );
        $cashier_lookup_stmt->bind_param('s', $cashier_id);
        if (!$cashier_lookup_stmt->execute()) {
            throw new Exception('Failed to validate cashier id');
        }

        $cashier_lookup_result = $cashier_lookup_stmt->get_result();
        if (!$cashier_lookup_result || $cashier_lookup_result->num_rows === 0) {
            $cashier_id = null;
        }
        $cashier_lookup_stmt->close();
    } else {
        $cashier_id = null;
    }

    $product_stmt = prepare_or_throw(
        $conn,
        'SELECT product_id, name, price, stock_qty FROM products WHERE product_id = ? AND canteen_id = ? AND is_active = 1 LIMIT 1 FOR UPDATE',
        'Failed to load product'
    );

    $validated_items = [];
    $computed_total = 0.0;

    foreach ($requested_items as $product_id => $quantity) {
        $product_id = intval($product_id);
        $quantity = intval($quantity);

        $product_stmt->bind_param('is', $product_id, $canteen_id);
        if (!$product_stmt->execute()) {
            throw new Exception('Failed to validate products');
        }

        $product_result = $product_stmt->get_result();
        if (!$product_result || $product_result->num_rows === 0) {
            throw new Exception('Product not found for this canteen (ID: ' . $product_id . ')');
        }

        $product_row = $product_result->fetch_assoc();
        $available_stock = intval($product_row['stock_qty'] ?? 0);
        if ($available_stock < $quantity) {
            throw new Exception('Insufficient stock for ' . ($product_row['name'] ?? ('product #' . $product_id)));
        }

        $unit_price = floatval($product_row['price'] ?? 0);
        if ($unit_price < 0) {
            throw new Exception('Invalid product price for product #' . $product_id);
        }

        $computed_total += ($unit_price * $quantity);
        $validated_items[] = [
            'product_id' => $product_id,
            'name' => $product_row['name'] ?? ('product #' . $product_id),
            'quantity' => $quantity,
            'unit_price' => $unit_price,
        ];
    }
    $product_stmt->close();

    if ($computed_total <= 0) {
        throw new Exception('Invalid order total');
    }

    if ($amount <= 0 || abs($amount - $computed_total) > 0.01) {
        $amount = $computed_total;
    }

    
    
    $description = pm_build_purchase_description($validated_items);

    $hasFailedAttempts = column_exists($conn, 'students', 'failed_attempts');
    $hasIsLocked = column_exists($conn, 'students', 'is_locked');
    $hasIsFrozen = column_exists($conn, 'students', 'is_frozen');
    $hasTransactionLimit = column_exists($conn, 'students', 'transaction_limit');
    $hasTransactionLimitPeriod = column_exists($conn, 'students', 'transaction_limit_period');
    $failedAttemptsSelect = $hasFailedAttempts ? 'failed_attempts' : '0 AS failed_attempts';
    $isLockedSelect = $hasIsLocked ? 'is_locked' : '0 AS is_locked';
    $isFrozenSelect = $hasIsFrozen ? 'is_frozen' : '0 AS is_frozen';
    $transactionLimitSelect = $hasTransactionLimit ? 'transaction_limit' : '0 AS transaction_limit';
    $transactionLimitPeriodSelect = $hasTransactionLimitPeriod
        ? "COALESCE(transaction_limit_period, 'daily') AS transaction_limit_period"
        : "'daily' AS transaction_limit_period";

$student_stmt = prepare_or_throw(
    $conn,
    "SELECT 
    balance,
    pin,
    $failedAttemptsSelect,
    $isLockedSelect,
    $isFrozenSelect,
    $transactionLimitSelect,
    $transactionLimitPeriodSelect
FROM students
WHERE student_num = ?
LIMIT 1
FOR UPDATE",
    'Failed to load student account'
);
$student_stmt->bind_param('s', $student_num);
$student_stmt->execute();
$student_row = $student_stmt->get_result()->fetch_assoc();
$student_stmt->close();

if (!$student_row) {
    respond_json(['status' => 'error', 'message' => 'Student not found']);
}

$failed_attempts = (int)$student_row['failed_attempts'];
$is_locked = (int)$student_row['is_locked'];

if ($is_locked === 1) {
    respond_json([
        'status' => 'locked',
        'message' => 'Profile is locked. Cannot transact until unlocked by admin.',
        'remaining_attempts' => 0,
    ]);
}

$is_frozen = (int)($student_row['is_frozen'] ?? 0);

if ($is_frozen === 1) {

    respond_json([
        'status' => 'frozen',
        'message' => 'Account is frozen by parent. Transactions are disabled.',
    ]);

}

$stored_pin = $student_row['pin'] ?? '';
if (!pin_matches($pin, $stored_pin)) {
    $failed_attempts++;
    $lock_profile = ($failed_attempts >= 3) ? 1 : 0;

    if ($hasFailedAttempts && $hasIsLocked) {
        $update_stmt = prepare_or_throw(
            $conn,
            'UPDATE students SET failed_attempts = ?, is_locked = ? WHERE student_num = ?',
            'Failed to update failed attempts'
        );
        $update_stmt->bind_param('iis', $failed_attempts, $lock_profile, $student_num);
        $update_stmt->execute();
        $update_stmt->close();

        $conn->commit();
        $conn->begin_transaction();

        if ($lock_profile) {
            respond_json([
                'status' => 'locked',
                'message' => 'Profile is locked due to too many failed PIN attempts.',
                'remaining_attempts' => 0,
                'failed_attempts' => $failed_attempts,
            ]);
        }

        respond_json([
            'status' => 'failed',
            'message' => 'Invalid PIN',
            'remaining_attempts' => max(0, 3 - $failed_attempts),
            'failed_attempts' => $failed_attempts,
        ]);
    } else {
        respond_json([
            'status' => 'failed',
            'message' => 'Invalid PIN',
            'remaining_attempts' => 0,
            'failed_attempts' => 0,
        ]);
    }
}

if ($hasFailedAttempts) {
    $reset_stmt = prepare_or_throw(
        $conn,
        'UPDATE students SET failed_attempts = 0 WHERE student_num = ?',
        'Failed to reset failed attempts'
    );
    $reset_stmt->bind_param('s', $student_num);
    $reset_stmt->execute();
    $reset_stmt->close();
}

    $current_balance = floatval($student_row['balance'] ?? 0);
    if ($current_balance < $amount) {
    throw new Exception('Insufficient balance');
    }

    $current_balance = floatval($student_row['balance'] ?? 0);
    if ($current_balance < $amount) {
        throw new Exception('Insufficient balance');
    }

    assert_within_spending_limit(
        $conn,
        $student_num,
        $amount,
        floatval($student_row['transaction_limit'] ?? 0),
        $student_row['transaction_limit_period'] ?? 'daily'
    );

    $new_balance = $current_balance - $amount;

    $balance_update_stmt = prepare_or_throw(
        $conn,
        'UPDATE students SET balance = ? WHERE student_num = ?',
        'Failed to prepare student balance update'
    );
    $balance_update_stmt->bind_param('ds', $new_balance, $student_num);
    if (!$balance_update_stmt->execute()) {
        throw new Exception('Failed to update student balance');
    }
    $balance_update_stmt->close();

    $canteen_balance_stmt = prepare_or_throw(
        $conn,
        'UPDATE canteens SET balance = balance + ? WHERE canteen_id = ?',
        'Failed to prepare canteen balance update'
    );
    $canteen_balance_stmt->bind_param('ds', $amount, $canteen_id);
    if (!$canteen_balance_stmt->execute() || $canteen_balance_stmt->affected_rows !== 1) {
        throw new Exception('Failed to update canteen balance');
    }
    $canteen_balance_stmt->close();

    $transaction_type = 'payment';
    $txn_stmt = prepare_or_throw(
        $conn,
        'INSERT INTO transactions '
            . '(student_num, amount, transaction_type, description, canteen_id, '
            . 'cashier_id, processor_role, processor_account_source, processor_id, '
            . 'date_time) '
            . "VALUES (?, ?, ?, ?, ?, ?, 'canteen', 'canteens', ?, NOW())",
        'Failed to prepare transaction insert'
    );
    $txn_stmt->bind_param(
        'sdsssss',
        $student_num,
        $amount,
        $transaction_type,
        $description,
        $canteen_id,
        $cashier_id,
        $canteen_id
    );
    if (!$txn_stmt->execute()) {
        throw new Exception('Failed to create transaction record: ' . $txn_stmt->error);
    }
    $transaction_id = intval($conn->insert_id);
    $txn_stmt->close();

    if ($transaction_id <= 0) {
        throw new Exception('Failed to resolve new transaction id');
    }

    $stock_update_stmt = prepare_or_throw(
        $conn,
        'UPDATE products SET stock_qty = stock_qty - ? WHERE product_id = ? AND canteen_id = ? AND stock_qty >= ?',
        'Failed to prepare stock update'
    );

    $has_transaction_items = false;
    $tx_items_table = $conn->query("SHOW TABLES LIKE 'transaction_items'");
    if ($tx_items_table && $tx_items_table->num_rows > 0) {
        $has_transaction_items = true;
    }

    $item_insert_stmt = null;
    if ($has_transaction_items) {
        $item_insert_stmt = prepare_or_throw(
            $conn,
            'INSERT INTO transaction_items (transaction_id, product_id, item_name, quantity, price) VALUES (?, ?, ?, ?, ?)',
            'Failed to prepare transaction item insert'
        );
    }

    foreach ($validated_items as $item) {
        $product_id = intval($item['product_id']);
        $quantity = intval($item['quantity']);
        $unit_price = floatval($item['unit_price']);
        $item_name = (string)($item['name'] ?? ('Product #' . $product_id));

        $stock_update_stmt->bind_param('iisi', $quantity, $product_id, $canteen_id, $quantity);
        if (!$stock_update_stmt->execute() || $stock_update_stmt->affected_rows !== 1) {
            throw new Exception('Failed to decrement stock for ' . ($item['name'] ?? ('product #' . $product_id)));
        }

        if ($item_insert_stmt) {
            $item_insert_stmt->bind_param(
                'iisid',
                $transaction_id,
                $product_id,
                $item_name,
                $quantity,
                $unit_price
            );
            if (!$item_insert_stmt->execute()) {
                throw new Exception('Failed to save transaction item for ' . ($item['name'] ?? ('product #' . $product_id)));
            }
        }
    }

    $stock_update_stmt->close();
    if ($item_insert_stmt) {
        $item_insert_stmt->close();
    }

    as_record_activity(
        $conn,
        $appSession,
        'payment_completed',
        [
            'transaction_id' => $transaction_id,
            'student_num' => $student_num,
            'amount' => number_format($amount, 2, '.', ''),
            'item_count' => count($validated_items),
        ],
        'server'
    );

    $conn->commit();

    respond_json([
        'status' => 'success',
        'new_balance' => number_format($new_balance, 2, '.', ''),
        'deducted_amount' => number_format($amount, 2, '.', ''),
        'transaction_id' => $transaction_id,
    ]);
} catch (Exception $e) {
    $conn->rollback();
    respond_json([
        'status' => 'error',
        'message' => $e->getMessage(),
    ]);
}
?>
