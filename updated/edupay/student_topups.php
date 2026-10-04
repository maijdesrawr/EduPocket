<?php
require_once __DIR__ . '/cors_common.php';
ob_start();
ini_set('display_errors', '0');
error_reporting(0);
header('Access-Control-Allow-Origin: *');
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

$student_num = trim($_GET['student_id'] ?? '');
if ($student_num === '') {
    respond_json(['status' => 'error', 'message' => 'Missing student_id parameter']);
}

$filterInput = trim((string)($_GET['filter'] ?? ''));
$filter = $filterInput === '' ? null : sd_normalize_period($filterInput);
if ($filterInput !== '' && $filter === null) {
    respond_json([
        'status' => 'error',
        'message' => 'Invalid filter. Use Daily, Weekly, Monthly, or Yearly.',
    ]);
}

$appSession = as_require_session($conn);
as_assert_session_identity($appSession, 'student', $student_num, 'students');

$topup_stmt = $conn->prepare(
    "SELECT transaction_id, amount, description,
        COALESCE(date_time, date_created) AS event_time
    FROM transactions
    WHERE student_num = ?
    AND transaction_type = 'top-up'
    ORDER BY COALESCE(date_time, date_created) DESC, transaction_id DESC"
);
if (!$topup_stmt) {
    respond_json(['status' => 'error', 'message' => 'Failed to prepare topup query']);
}

$topup_stmt->bind_param('s', $student_num);
if (!$topup_stmt->execute()) {
    respond_json(['status' => 'error', 'message' => 'Failed to load topups']);
}

$topup_result = $topup_stmt->get_result();
$topups = [];
while ($row = $topup_result->fetch_assoc()) {
    $topups[] = [
        'transaction_id' => (int)($row['transaction_id'] ?? 0),
        'amount' => number_format(floatval($row['amount'] ?? 0), 2, '.', ''),
        'method' => $row['description'] ?? 'Wallet Top-up',
        'status' => 'Completed',
        'date_time' => $row['event_time'] ?? '',
    ];
}
$topup_stmt->close();

$balance_stmt = $conn->prepare('SELECT balance FROM students WHERE student_num = ? LIMIT 1');
if (!$balance_stmt) {
    respond_json(['status' => 'error', 'message' => 'Failed to prepare balance query']);
}

$balance_stmt->bind_param('s', $student_num);
if (!$balance_stmt->execute()) {
    respond_json(['status' => 'error', 'message' => 'Failed to load balance']);
}

$balance_result = $balance_stmt->get_result();
$balance_row = $balance_result ? $balance_result->fetch_assoc() : null;
$total_balance = floatval($balance_row['balance'] ?? 0);
$balance_stmt->close();

$expenseDateExpression = 'COALESCE(date_time, date_created, NOW())';
$expensePeriodFilter = $filter === null
    ? ''
    : ' AND ' . sd_calendar_period_filter_sql($filter, $expenseDateExpression);
$expense_stmt = $conn->prepare(
    "SELECT IFNULL(SUM(amount), 0) AS total_expense "
        . "FROM transactions "
        . "WHERE student_num = ? "
        . "AND transaction_type IN ('payment', 'transfer-out') "
        . $expensePeriodFilter
);
if (!$expense_stmt) {
    respond_json(['status' => 'error', 'message' => 'Failed to prepare expense query']);
}

$expense_stmt->bind_param('s', $student_num);
if (!$expense_stmt->execute()) {
    respond_json(['status' => 'error', 'message' => 'Failed to load expenses']);
}

$expense_result = $expense_stmt->get_result();
$expense_row = $expense_result ? $expense_result->fetch_assoc() : null;
$total_expense = floatval($expense_row['total_expense'] ?? 0);
$expense_stmt->close();

$conn->close();

respond_json([
    'status' => 'success',
    'total_balance' => number_format($total_balance, 2, '.', ''),
    'total_expense' => number_format($total_expense, 2, '.', ''),
    'total_expenses' => number_format($total_expense, 2, '.', ''),
    'filter' => $filter === null ? 'All' : ucfirst($filter),
    'topups' => $topups,
]);
?>
