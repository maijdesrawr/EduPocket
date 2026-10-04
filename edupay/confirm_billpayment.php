<?php
header('Content-Type: application/json');
include 'db_connect.php'; 

function column_exists(mysqli $conn, string $table, string $column): bool {
    $safeTable = preg_replace('/[^a-zA-Z0-9_]/', '', $table);
    $safeColumn = preg_replace('/[^a-zA-Z0-9_]/', '', $column);
    if ($safeTable === '' || $safeColumn === '') {
        return false;
    }

    $result = $conn->query("SHOW COLUMNS FROM `$safeTable` LIKE '$safeColumn'");
    return $result instanceof mysqli_result && $result->num_rows > 0;
}

function table_exists(mysqli $conn, string $table): bool {
    $safeTable = preg_replace('/[^a-zA-Z0-9_]/', '', $table);
    if ($safeTable === '') {
        return false;
    }

    $result = $conn->query("SHOW TABLES LIKE '$safeTable'");
    return $result instanceof mysqli_result && $result->num_rows > 0;
}

function pin_matches(string $enteredPin, ?string $storedPin): bool {
    $storedPin = trim((string) $storedPin);
    if ($storedPin === '') {
        return false;
    }

    if (hash_equals($storedPin, $enteredPin)) {
        return true;
    }

    return password_verify($enteredPin, $storedPin);
}

function normalize_limit_period(?string $period): string {
    $value = strtolower(trim((string)$period));
    if (in_array($value, ['daily', 'weekly', 'monthly'], true)) {
        return $value;
    }
    return 'daily';
}

function spending_limit_filter_sql(string $period): string {
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

function spent_in_limit_period(mysqli $conn, string $student_id, string $period): float {
    $filterSql = spending_limit_filter_sql($period);
    $stmt = $conn->prepare(
        "SELECT COALESCE(SUM(amount), 0) AS spent
         FROM transactions
         WHERE student_num = ?
           AND transaction_type = 'payment'
           AND $filterSql"
    );

    if (!$stmt) {
        throw new Exception('Failed to calculate spending limit usage');
    }

    $stmt->bind_param('s', $student_id);
    $stmt->execute();
    $result = $stmt->get_result();
    $row = $result ? $result->fetch_assoc() : null;
    $stmt->close();

    return floatval($row['spent'] ?? 0);
}

$response = [];

$student_id = $_POST['student_id'] ?? '';
$cashier_id = $_POST['cashier_id'] ?? '';
$amount = $_POST['amount'] ?? '';
$pin = $_POST['pin'] ?? '';
$bill_payment_id = $_POST['bill_payment_id'] ?? 1;
$selected_description = trim($_POST['description'] ?? '');

if (empty($student_id) || empty($cashier_id) || empty($amount) || empty($pin)) {
    echo json_encode([
        "status" => "error",
        "message" => "Missing required fields"
    ]);
    exit;
}

if (!is_numeric($amount) || $amount <= 0) {
    echo json_encode([
        "status" => "error",
        "message" => "Invalid amount"
    ]);
    exit;
}

$hasTransactionLimit = column_exists($conn, 'students', 'transaction_limit');
$hasTransactionLimitPeriod = column_exists($conn, 'students', 'transaction_limit_period');
$limitSelect = $hasTransactionLimit ? 'transaction_limit' : '0 AS transaction_limit';
$limitPeriodSelect = $hasTransactionLimitPeriod
    ? "COALESCE(transaction_limit_period, 'daily') AS transaction_limit_period"
    : "'daily' AS transaction_limit_period";

$stmt = $conn->prepare("SELECT balance, pin, $limitSelect, $limitPeriodSelect FROM students WHERE student_num = ?");
$stmt->bind_param("s", $student_id);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    echo json_encode([
        "status" => "error",
        "message" => "Student not found"
    ]);
    exit;
}

$row = $result->fetch_assoc();
$current_balance = floatval($row['balance']);
$stored_pin = $row['pin'];

if (!pin_matches($pin, $stored_pin)) {
    echo json_encode([
        "status" => "error",
        "message" => "Invalid PIN"
    ]);
    exit;
}

if ($current_balance < $amount) {
    echo json_encode([
        "status" => "error",
        "message" => "Insufficient balance"
    ]);
    exit;
}

$limitAmount = floatval($row['transaction_limit'] ?? 0);
$limitPeriod = normalize_limit_period($row['transaction_limit_period'] ?? 'daily');
if ($limitAmount > 0) {
    $spent = spent_in_limit_period($conn, $student_id, $limitPeriod);
    if (($spent + floatval($amount)) > ($limitAmount + 0.00001)) {
        $remaining = max(0, $limitAmount - $spent);
        echo json_encode([
            "status" => "error",
            "message" => "Over your budget. " . ucfirst($limitPeriod)
                . " spending limit is PHP " . number_format($limitAmount, 2)
                . " and you only have PHP " . number_format($remaining, 2) . " left."
        ]);
        exit;
    }
}

$conn->begin_transaction();

try {
    $new_balance = $current_balance - $amount;

    $update = $conn->prepare("UPDATE students SET balance = ? WHERE student_num = ?");
    $update->bind_param("ds", $new_balance, $student_id);
    $update->execute();

    if ((int)$bill_payment_id === 1) {
        $description = "Cashier Payment";
    } elseif ($selected_description !== '') {
        $description = $selected_description;
    } elseif ((int)$bill_payment_id > 0 && table_exists($conn, 'bill_payments')) {
        $paymentStmt = $conn->prepare("SELECT description FROM bill_payments WHERE id = ? LIMIT 1");
        if ($paymentStmt) {
            $paymentStmt->bind_param("i", $bill_payment_id);
            $paymentStmt->execute();
            $paymentResult = $paymentStmt->get_result();
            $paymentRow = $paymentResult ? $paymentResult->fetch_assoc() : null;
            $paymentStmt->close();
            $description = trim((string)($paymentRow['description'] ?? ''));
        }
        if ($description === '') {
            $description = "Cashier Payment";
        }
    } else {
        $description = "Cashier Payment";
    }

    $insert = $conn->prepare(
        "INSERT INTO transactions 
        (student_num, amount, transaction_type, description, cashier_id, bill_payment_id)
        VALUES (?, ?, 'payment', ?, ?, ?)"
    );
    $insert->bind_param("sdssi", $student_id, $amount, $description, $cashier_id, $bill_payment_id);
    $insert->execute();

    $conn->commit();

    echo json_encode([
        "status" => "success",
        "data" => [
            "new_balance" => number_format($new_balance, 2)
        ]
    ]);

} catch (Exception $e) {
    $conn->rollback();
    echo json_encode([
        "status" => "error",
        "message" => "Transaction failed: " . $e->getMessage()
    ]);
}

$conn->close();
?>
