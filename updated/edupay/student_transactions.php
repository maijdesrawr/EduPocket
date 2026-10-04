<?php
require_once __DIR__ . '/cors_common.php';
ob_start();
ini_set('display_errors', '0');
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');

include 'db_connect.php';
require_once __DIR__ . '/app_session_common.php';
require_once __DIR__ . '/student_dashboard_common.php';

function respond_json(array $payload): void
{
    ob_clean();
    echo json_encode($payload);
    exit;
}

$student_id = trim($_GET['student_id'] ?? '');
$filter = sd_normalize_period($_GET['filter'] ?? 'monthly') ?? 'monthly';

if ($student_id === '') {
    respond_json(['status' => 'error', 'message' => 'Missing student_id']);
}

$appSession = as_require_session($conn);
as_assert_session_identity($appSession, 'student', $student_id, 'students');

$dateExpression = 'COALESCE(date_time, date_created, NOW())';
$filterClause = ' AND ' . sd_calendar_period_filter_sql($filter, $dateExpression);

$sql = "
    SELECT
        transaction_id,
        student_num,
        amount,
        transaction_type,
        description,
        canteen_id,
        cashier_id,
        COALESCE(date_time, date_created, NOW()) AS event_time
    FROM transactions
    WHERE student_num = ?
    $filterClause
    ORDER BY event_time DESC, transaction_id DESC
";

$stmt = $conn->prepare($sql);
if (!$stmt) {
    respond_json(['status' => 'error', 'message' => 'Failed to prepare transaction query']);
}

$stmt->bind_param('s', $student_id);
if (!$stmt->execute()) {
    respond_json(['status' => 'error', 'message' => 'Failed to load transactions']);
}

$result = $stmt->get_result();
$transactions = [];
$transactionIndexById = [];
$paymentTransactionIds = [];
$total_expense = 0.0;

while ($row = $result->fetch_assoc()) {
    $transactionId = intval($row['transaction_id'] ?? 0);
    $amount = floatval($row['amount'] ?? 0);
    $type = strtolower(trim($row['transaction_type'] ?? ''));

    if (sd_is_expense_transaction_type($type)) {
        $total_expense += $amount;
    }

    if ($type === 'payment') {
        if ($transactionId > 0) {
            $paymentTransactionIds[] = $transactionId;
        }
    }

    $eventTime = $row['event_time'] ?? '';
    $transactions[] = [
        'transaction_id' => $transactionId,
        'student_num' => $row['student_num'] ?? '',
        'amount' => $amount,
        'transaction_type' => $row['transaction_type'] ?? '',
        'transaction_label' => sd_transaction_label($type),
        'display_type' => sd_transaction_label($type),
        'description' => $row['description'] ?? '',
        'date' => $eventTime ? date('Y-m-d', strtotime($eventTime)) : '',
        'date_time' => $eventTime,
        'cashier_id' => $row['cashier_id'] ?? null,
        'canteen_id' => $row['canteen_id'] ?? null,
        'status' => 'Completed',
        'items' => [],
    ];

    if ($transactionId > 0) {
        $transactionIndexById[$transactionId] = count($transactions) - 1;
    }
}
$stmt->close();

$hasItemsTable = false;
$hasItemNameColumn = false;
$itemsTableCheck = $conn->query("SHOW TABLES LIKE 'transaction_items'");
if ($itemsTableCheck && $itemsTableCheck->num_rows > 0) {
    $hasItemsTable = true;
    $itemNameColumnCheck = $conn->query("SHOW COLUMNS FROM transaction_items LIKE 'item_name'");
    $hasItemNameColumn = $itemNameColumnCheck instanceof mysqli_result
        && $itemNameColumnCheck->num_rows > 0;
}

if ($hasItemsTable && count($paymentTransactionIds) > 0) {
    $paymentTransactionIds = array_values(array_unique(array_map('intval', $paymentTransactionIds)));
    if (count($paymentTransactionIds) > 0) {
        $inList = implode(',', $paymentTransactionIds);
        $itemNameExpression = $hasItemNameColumn
            ? "COALESCE(NULLIF(ti.item_name, ''), p.name, CONCAT('Product #', ti.product_id))"
            : "COALESCE(p.name, CONCAT('Product #', ti.product_id))";
        $itemsSql = "
            SELECT
                ti.transaction_id,
                ti.product_id,
                ti.quantity,
                ti.price,
                $itemNameExpression AS product_name
            FROM transaction_items ti
            LEFT JOIN products p ON p.product_id = ti.product_id
            WHERE ti.transaction_id IN ($inList)
            ORDER BY ti.id ASC
        ";

        $itemsResult = $conn->query($itemsSql);
        if ($itemsResult) {
            while ($item = $itemsResult->fetch_assoc()) {
                $tid = intval($item['transaction_id'] ?? 0);
                if (!array_key_exists($tid, $transactionIndexById)) {
                    continue;
                }

                $txIndex = $transactionIndexById[$tid];
                $quantity = intval($item['quantity'] ?? 0);
                $transactions[$txIndex]['items'][] = [
                    'product_id' => intval($item['product_id'] ?? 0),
                    'name' => $item['product_name'] ?? 'Item',
                    'qty' => $quantity,
                    'quantity' => $quantity,
                    'price' => floatval($item['price'] ?? 0),
                ];
            }
        }
    }
}

$balance_stmt = $conn->prepare('SELECT balance FROM students WHERE student_num = ? LIMIT 1');
if (!$balance_stmt) {
    respond_json(['status' => 'error', 'message' => 'Failed to prepare balance query']);
}

$balance_stmt->bind_param('s', $student_id);
if (!$balance_stmt->execute()) {
    respond_json(['status' => 'error', 'message' => 'Failed to load student balance']);
}

$balance_result = $balance_stmt->get_result();
$balance_row = $balance_result ? $balance_result->fetch_assoc() : null;
$student_balance = floatval($balance_row['balance'] ?? 0);
$balance_stmt->close();

respond_json([
    'status' => 'success',
    'total_balance' => number_format($student_balance, 2, '.', ''),
    'total_expense' => number_format($total_expense, 2, '.', ''),
    'total_expenses' => number_format($total_expense, 2, '.', ''),
    'filter' => ucfirst($filter),
    'transactions' => $transactions,
]);
?>
