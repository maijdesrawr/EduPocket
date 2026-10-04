<?php
require_once __DIR__ . '/cors_common.php';
header('Content-Type: application/json');
include 'db_connect.php'; 
require_once __DIR__ . '/app_session_common.php';
require_once __DIR__ . '/student_dashboard_common.php';

$student_num = $_GET['student_num'] ?? '';
$normalizedFilter = sd_normalize_period($_GET['filter'] ?? 'monthly');
$filter = $normalizedFilter === null ? null : ucfirst($normalizedFilter);

if (!$student_num) {
    echo json_encode(['status' => 'error', 'message' => 'Student ID missing']);
    exit;
}

$appSession = as_require_session($conn);
as_assert_session_identity($appSession, 'student', trim((string)$student_num), 'students');

if ($filter === null) {
    echo json_encode([
        'status' => 'error',
        'message' => 'Invalid filter. Use Daily, Weekly, Monthly, or Yearly.',
    ]);
    exit;
}

switch ($filter) {
case 'Daily':
    $sql = "
        SELECT DATE(date_time) AS label,
               SUM(CASE WHEN transaction_type='top-up' THEN amount ELSE 0 END) AS topup,
               SUM(CASE WHEN transaction_type IN ('payment', 'transfer-out') THEN amount ELSE 0 END) AS expense
        FROM transactions
        WHERE student_num = ?
        AND date_time >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
        GROUP BY DATE(date_time)
        ORDER BY DATE(date_time)
    ";
    break;

case 'Weekly':
    $sql = "
        SELECT 
            DATE_FORMAT(week_start, '%b %d') AS label,
            SUM(topup) AS topup,
            SUM(expense) AS expense
        FROM (
            SELECT 
                DATE_SUB(date_time, INTERVAL WEEKDAY(date_time) DAY) AS week_start,
                CASE WHEN transaction_type='top-up' THEN amount ELSE 0 END AS topup,
                CASE WHEN transaction_type IN ('payment', 'transfer-out') THEN amount ELSE 0 END AS expense
            FROM transactions
            WHERE student_num = ?
              AND date_time >= DATE_SUB(CURDATE(), INTERVAL 8 WEEK)
        ) AS sub
        GROUP BY week_start
        ORDER BY week_start
    ";
    break;

case 'Monthly':
    $sql = "
        SELECT 
            DATE_FORMAT(month_start, '%b %Y') AS label,
            SUM(CASE WHEN transaction_type='top-up' THEN amount ELSE 0 END) AS topup,
            SUM(CASE WHEN transaction_type IN ('payment', 'transfer-out') THEN amount ELSE 0 END) AS expense
        FROM (
            SELECT *,
                   DATE_FORMAT(date_time, '%Y-%m-01') AS month_start
            FROM transactions
            WHERE student_num = ?
            AND date_time >= DATE_SUB(CURDATE(), INTERVAL 12 MONTH)
        ) AS t
        GROUP BY month_start
        ORDER BY month_start
    ";
    break;

    case 'Yearly':
        $sql = "
            SELECT YEAR(date_time) AS label,
                   SUM(CASE WHEN transaction_type='top-up' THEN amount ELSE 0 END) AS topup,
                   SUM(CASE WHEN transaction_type IN ('payment', 'transfer-out') THEN amount ELSE 0 END) AS expense
            FROM transactions
            WHERE student_num = ?
            GROUP BY YEAR(date_time)
            ORDER BY YEAR(date_time)
        ";
        break;

    default:
        echo json_encode(['status' => 'error', 'message' => 'Invalid filter']);
        exit;
}

try {
    $stmt = $conn->prepare($sql);
if (!$stmt) {
    echo json_encode([
        'status' => 'error',
        'message' => 'Database prepare failed: ' . $conn->error
    ]);
    exit;
}

$stmt->bind_param("s", $student_num);

if (!$stmt->execute()) {
    echo json_encode([
        'status' => 'error',
        'message' => 'Database execute failed: ' . $stmt->error
    ]);
    exit;
}

$result = $stmt->get_result();

    $data = [];
    $totalTopup = 0.0;
    $totalExpense = 0.0;
    while ($row = $result->fetch_assoc()) {
        $topup = (float)$row['topup'];
        $expense = (float)$row['expense'];
        $totalTopup += $topup;
        $totalExpense += $expense;
        $data[] = [
            'label' => $row['label'],
            'topup' => $topup,
            'expense' => $expense,
        ];
    }

    echo json_encode([
        'status' => 'success',
        'filter' => $filter,
        'total_topup' => number_format($totalTopup, 2, '.', ''),
        'total_expense' => number_format($totalExpense, 2, '.', ''),
        'total_expenses' => number_format($totalExpense, 2, '.', ''),
        'data' => $data,
    ]);
    $stmt->close();
    $conn->close();
} catch (mysqli_sql_exception $e) {
    echo json_encode([
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}
?>
