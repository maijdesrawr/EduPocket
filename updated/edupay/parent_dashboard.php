<?php
header('Content-Type: application/json; charset=utf-8');
include 'db_connect.php';

date_default_timezone_set('Asia/Manila');

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

$parent_id = $_GET['parent_id'] ?? '';

if (empty($parent_id)) {
    echo json_encode(['status' => 'error', 'message' => 'Missing parent_id']);
    exit;
}

$hasTransactionLimit = column_exists($conn, 'students', 'transaction_limit');
$hasTransactionLimitPeriod = column_exists($conn, 'students', 'transaction_limit_period');

$limitAmountSelect = $hasTransactionLimit
    ? "COALESCE(s.transaction_limit, 0) AS transaction_limit"
    : "0 AS transaction_limit";
$limitPeriodSelect = $hasTransactionLimitPeriod
    ? "COALESCE(s.transaction_limit_period, 'daily') AS transaction_limit_period"
    : "'daily' AS transaction_limit_period";

$children_query = $conn->prepare("
    SELECT DISTINCT
        s.student_num AS child_id,
        s.Fname AS child_name,
        s.balance,
        MAX(COALESCE(s.is_frozen, 0)) AS is_frozen,
        $limitAmountSelect,
        $limitPeriodSelect,
        COALESCE(
            SUM(CASE WHEN t.transaction_type = 'payment' THEN t.amount ELSE 0 END),
            0
        ) AS expense
    FROM parent_student_link l
    INNER JOIN students s ON l.student_num = s.student_num
    LEFT JOIN transactions t ON s.student_num = t.student_num
    WHERE l.parent_id = ?
    GROUP BY s.student_num, s.Fname, s.balance
");
$children_query->bind_param('s', $parent_id);
$children_query->execute();
$children_result = $children_query->get_result();

$children = [];
$total_balance = 0;
$total_expense = 0;

while ($row = $children_result->fetch_assoc()) {
    $row['balance'] = (float)($row['balance'] ?? 0);
    $row['expense'] = (float)($row['expense'] ?? 0);
    $row['transaction_limit'] = (float)($row['transaction_limit'] ?? 0);
    $row['transaction_limit_period'] = strtolower(trim((string)($row['transaction_limit_period'] ?? 'daily')));

    $total_balance += $row['balance'];
    $total_expense += $row['expense'];
    $children[] = $row;
}

$activity_query = $conn->prepare("
    SELECT
        t.transaction_id,
        s.student_num AS child_id,
        COALESCE(NULLIF(TRIM(s.Fname), ''), s.student_num) AS name,
        t.transaction_type,
        t.amount,
        COALESCE(t.date_time, t.date_created, NOW()) AS event_time,
        CASE
            WHEN t.transaction_type = 'top-up' THEN 'Wallet Top-Up'
            ELSE COALESCE(NULLIF(TRIM(t.description), ''), 'Payment')
        END AS note
    FROM transactions t
    INNER JOIN students s ON t.student_num = s.student_num
    INNER JOIN parent_student_link l ON s.student_num = l.student_num
    WHERE l.parent_id = ?
    ORDER BY COALESCE(t.date_time, t.date_created, NOW()) DESC, t.transaction_id DESC
");
$activity_query->bind_param('s', $parent_id);
$activity_query->execute();
$activity_result = $activity_query->get_result();

$activities = [];
while ($row = $activity_result->fetch_assoc()) {
    $timestamp = $row['event_time'] ?? '';
    $activities[] = [
        'transaction_id' => (int)$row['transaction_id'],
        'child_id' => $row['child_id'] ?? '',
        'name' => $row['name'] ?? '',
        'transaction_type' => $row['transaction_type'] ?? '',
        'amount' => (float)($row['amount'] ?? 0),
        'note' => $row['note'] ?? '',
        'timestamp' => $timestamp,
        'date' => $timestamp
    ];
}

echo json_encode([
    'status' => 'success',
    'total_balance' => $total_balance,
    'total_expense' => $total_expense,
    'children' => $children,
    'activities' => $activities
], JSON_UNESCAPED_UNICODE);

$children_query->close();
$activity_query->close();
$conn->close();
?>
