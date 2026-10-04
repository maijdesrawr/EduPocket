<?php
error_reporting(E_ALL);
ini_set('display_errors', 1);

header("Access-Control-Allow-Origin: *");
header("Content-Type: application/json; charset=utf-8");

include 'db_connect.php';

function table_exists(mysqli $conn, string $table): bool
{
    $safeTable = preg_replace('/[^a-zA-Z0-9_]/', '', $table);
    if ($safeTable === '') {
        return false;
    }

    $result = $conn->query("SHOW TABLES LIKE '$safeTable'");
    return $result instanceof mysqli_result && $result->num_rows > 0;
}

function scalar_result(mysqli $conn, string $sql, string $field): float
{
    $result = $conn->query($sql);
    if (!$result) {
        return 0;
    }

    $row = $result->fetch_assoc();
    return floatval($row[$field] ?? 0);
}

if (!$conn) {
    echo json_encode(["error" => "Database connection failed"]);
    exit;
}

$user_breakdown = [];
foreach (['admins', 'students', 'canteens', 'cashiers', 'parents'] as $user_table) {
    $user_breakdown[$user_table] = table_exists($conn, $user_table)
        ? (int)scalar_result($conn, "SELECT COUNT(*) AS user_count FROM $user_table", 'user_count')
        : 0;
}
$total_users = array_sum($user_breakdown);

$studentBalance = table_exists($conn, 'students')
    ? scalar_result($conn, "SELECT COALESCE(SUM(balance), 0) AS total_balance FROM students", 'total_balance')
    : 0;
$canteenBalance = table_exists($conn, 'canteens')
    ? scalar_result($conn, "SELECT COALESCE(SUM(balance), 0) AS total_balance FROM canteens", 'total_balance')
    : 0;
$total_balance = $studentBalance + $canteenBalance;

$activities = [];
if (table_exists($conn, 'transactions') && table_exists($conn, 'students')) {
    $itemSummarySelect = "NULL";
    if (table_exists($conn, 'transaction_items') && table_exists($conn, 'products')) {
        $itemSummarySelect = "
            (
                SELECT GROUP_CONCAT(
                    CONCAT(p.name, ' x', ti.quantity)
                    ORDER BY ti.id ASC
                    SEPARATOR ', '
                )
                FROM transaction_items ti
                JOIN products p ON p.product_id = ti.product_id
                WHERE ti.transaction_id = t.transaction_id
            )
        ";
    }

    $activity_sql = "
        SELECT
            t.transaction_id,
            COALESCE(NULLIF(TRIM(s.Fname), ''), t.student_num, 'Unknown User') AS title,
            t.transaction_type,
            t.amount,
            COALESCE(
                NULLIF(TRIM($itemSummarySelect), ''),
                NULLIF(TRIM(t.description), ''),
                CASE
                    WHEN t.transaction_type = 'top-up' THEN 'Parent Top-up'
                    ELSE 'Payment'
                END
            ) AS description,
            COALESCE(t.date_time, t.date_created, NOW()) AS event_time
        FROM transactions t
        LEFT JOIN students s ON s.student_num = t.student_num
        ORDER BY COALESCE(t.date_time, t.date_created, NOW()) DESC, t.transaction_id DESC
        LIMIT 10
    ";

    $activity_query = $conn->query($activity_sql);
    if ($activity_query) {
        while ($row = $activity_query->fetch_assoc()) {
            $activities[] = [
                'transaction_id' => (int)$row['transaction_id'],
                'title' => $row['title'] ?? 'Unknown User',
                'transaction_type' => $row['transaction_type'] ?? '',
                'description' => $row['description'] ?? '',
                'amount' => floatval($row['amount'] ?? 0),
                'timestamp' => $row['event_time'] ?? '',
                'status' => 'Completed'
            ];
        }
    }
}

echo json_encode([
    'total_users' => $total_users,
    'user_breakdown' => $user_breakdown,
    'total_balance' => $total_balance,
    'activities' => $activities
]);
?>
