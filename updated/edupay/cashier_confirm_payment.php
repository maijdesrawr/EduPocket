<?php
require_once __DIR__ . '/cors_common.php';
ob_start();
ini_set('display_errors', '0');
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');

include 'db_connect.php';
require_once __DIR__ . '/app_session_common.php';

function respond_json(array $payload): void {
    ob_clean();
    echo json_encode($payload);
    exit;
}

function prepare_or_throw(mysqli $conn, string $sql, string $errorMessage): mysqli_stmt {
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        throw new Exception($errorMessage . ': ' . $conn->error);
    }
    return $stmt;
}

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
    error_log('cashier_confirm_payment.php session validation failed: ' . $error->getMessage());
    respond_json(['status' => 'error', 'message' => 'Your session could not be validated.']);
}

$student_num = trim($_POST['student_num'] ?? '');
$pin = trim($_POST['pin'] ?? '');
$amount = floatval($_POST['amount'] ?? 0);
$bill_payment_id = intval($_POST['bill_payment_id'] ?? 0);
$cashier_id = trim($_POST['cashier_id'] ?? '');
$selected_description = trim($_POST['description'] ?? '');

if ($student_num === '' || $pin === '') {
    respond_json(['status' => 'error', 'message' => 'Missing student number or PIN']);
}
if (!preg_match('/^\d{6}$/', $pin)) {
    respond_json(['status' => 'error', 'message' => 'PIN must be exactly 6 digits']);
}
if ($amount <= 0) {
    respond_json(['status' => 'error', 'message' => 'Invalid payment amount']);
}

$description = '';
if ($bill_payment_id === 0) {
    $description = 'Cashier Payment';
} elseif ($selected_description !== '') {
    $description = $selected_description;
}

if ($bill_payment_id > 0 && table_exists($conn, 'bill_payments')) {
    $bp_stmt = prepare_or_throw(
        $conn,
        'SELECT description FROM bill_payments WHERE id = ? AND cashier_id = ? LIMIT 1',
        'Failed to fetch bill payment'
    );
    $bp_stmt->bind_param('is', $bill_payment_id, $cashier_id);
    $bp_stmt->execute();
    $bp_result = $bp_stmt->get_result();
    if ($bp_result && $bp_result->num_rows > 0) {
        $row = $bp_result->fetch_assoc();
        $description = $row['description'];
    }
    $bp_stmt->close();
    if (!$bp_result || $bp_result->num_rows === 0) respond_json(['status'=>'error','message'=>'Payment option was not found for this cashier.']);
}

if ($description === '') {
    $description = 'Cashier Payment';
}

$hasFailedAttempts = column_exists($conn, 'students', 'failed_attempts');
$hasIsLocked = column_exists($conn, 'students', 'is_locked');
$hasTransactionLimit = column_exists($conn, 'students', 'transaction_limit');
$hasTransactionLimitPeriod = column_exists($conn, 'students', 'transaction_limit_period');
$hasIsFrozen = column_exists($conn, 'students', 'is_frozen');
$failedAttemptsSelect = $hasFailedAttempts ? 'failed_attempts' : '0 AS failed_attempts';
$isLockedSelect = $hasIsLocked ? 'is_locked' : '0 AS is_locked';
$isFrozenSelect = $hasIsFrozen ? 'is_frozen' : '0 AS is_frozen';
$transactionLimitSelect = $hasTransactionLimit ? 'transaction_limit' : '0 AS transaction_limit';
$transactionLimitPeriodSelect = $hasTransactionLimitPeriod
    ? "COALESCE(transaction_limit_period, 'daily') AS transaction_limit_period"
    : "'daily' AS transaction_limit_period";

$conn->begin_transaction();

try {
    as_assert_session_identity($appSession, 'cashier', $cashier_id);
    $cashier_account_source = strtolower(trim(
        (string)($appSession['account_source'] ?? '')
    ));
    if ($cashier_account_source !== 'cashiers') {
        throw new Exception('The cashier session account source is invalid.');
    }
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
    $student_result = $student_stmt->get_result();
    if (!$student_result || $student_result->num_rows === 0) {
        throw new Exception('Student not found');
    }
    $student = $student_result->fetch_assoc();
    $student_stmt->close();

    if ((int)($student['is_locked'] ?? 0) === 1) {
        $conn->rollback();
        respond_json([
            'status' => 'locked',
            'message' => 'Account is locked. Contact admin.'
        ]);
    }

    if ((int)($student['is_frozen'] ?? 0) === 1) {
    $conn->rollback();

    respond_json([
        'status' => 'frozen',
        'message' => 'Account is frozen by parent. Transactions are disabled.'
    ]);
}

    $stored_pin = $student['pin'] ?? '';
    $attempts = intval($student['failed_attempts'] ?? 0);

    if (!pin_matches($pin, $stored_pin)) {
        if ($hasFailedAttempts && $hasIsLocked) {
            $attempts++;

            if ($attempts >= 3) {
                $lock_stmt = prepare_or_throw(
                    $conn,
                    'UPDATE students SET failed_attempts = ?, is_locked = 1 WHERE student_num = ?',
                    'Failed to lock account'
                );
                $lock_stmt->bind_param('is', $attempts, $student_num);
                $lock_stmt->execute();
                $lock_stmt->close();

                $conn->commit();
                respond_json([
                    'status' => 'locked',
                    'message' => 'Too many attempts. Account locked.'
                ]);
            }

            $attempt_stmt = prepare_or_throw(
                $conn,
                'UPDATE students SET failed_attempts = ? WHERE student_num = ?',
                'Failed to update attempts'
            );
            $attempt_stmt->bind_param('is', $attempts, $student_num);
            $attempt_stmt->execute();
            $attempt_stmt->close();

            $conn->commit();
            respond_json([
                'status' => 'failed',
                'message' => 'Invalid PIN',
                'remaining_attempts' => 3 - $attempts
            ]);
        }

        $conn->rollback();
        respond_json([
            'status' => 'failed',
            'message' => 'Invalid PIN',
            'remaining_attempts' => 0
        ]);
    }

    $current_balance = floatval($student['balance'] ?? 0);
    if ($current_balance < $amount) {
        throw new Exception('Insufficient balance');
    }

    assert_within_spending_limit(
        $conn,
        $student_num,
        $amount,
        floatval($student['transaction_limit'] ?? 0),
        $student['transaction_limit_period'] ?? 'daily'
    );

    if ($hasFailedAttempts) {
        $reset_stmt = prepare_or_throw(
            $conn,
            'UPDATE students SET failed_attempts = 0 WHERE student_num = ?',
            'Failed to reset attempts'
        );
        $reset_stmt->bind_param('s', $student_num);
        $reset_stmt->execute();
        $reset_stmt->close();
    }

    $new_balance = $current_balance - $amount;
    $update_stmt = prepare_or_throw(
        $conn,
        'UPDATE students SET balance = ? WHERE student_num = ?',
        'Failed to update student balance'
    );
    $update_stmt->bind_param('ds', $new_balance, $student_num);
    if (!$update_stmt->execute()) {
        throw new Exception('Failed to update student balance');
    }
    $update_stmt->close();

    $txn_type = 'payment';
    $persisted_bill_payment_id = $bill_payment_id > 0 ? $bill_payment_id : null;
    $txn_stmt = prepare_or_throw(
        $conn,
        'INSERT INTO transactions '
            . '(student_num, amount, transaction_type, description, cashier_id, '
            . 'processor_role, processor_account_source, processor_id, '
            . 'bill_payment_id, date_time) '
            . "VALUES (?, ?, ?, ?, ?, 'cashier', ?, ?, ?, NOW())",
        'Failed to create transaction'
    );
    $txn_stmt->bind_param(
        'sdsssssi',
        $student_num,
        $amount,
        $txn_type,
        $description,
        $cashier_id,
        $cashier_account_source,
        $cashier_id,
        $persisted_bill_payment_id
    );
    if (!$txn_stmt->execute()) {
        throw new Exception('Failed to insert transaction: ' . $txn_stmt->error);
    }
    $transaction_id = intval($conn->insert_id);
    $txn_stmt->close();

    $cashier_stmt = prepare_or_throw(
        $conn,
        'UPDATE cashiers SET balance = balance + ? WHERE cashier_id = ?',
        'Failed to update cashier balance'
    );
    $cashier_stmt->bind_param('ds', $amount, $cashier_id);
    if (!$cashier_stmt->execute() || $cashier_stmt->affected_rows !== 1) {
        throw new Exception('Failed to update cashier balance');
    }
    $cashier_stmt->close();

    as_record_activity(
        $conn,
        $appSession,
        'payment_completed',
        [
            'transaction_id' => $transaction_id,
            'student_num' => $student_num,
            'amount' => number_format($amount, 2, '.', ''),
            'bill_payment_id' => $persisted_bill_payment_id,
        ],
        'server'
    );

    $conn->commit();

    respond_json([
        'status' => 'success',
        'transaction_id' => $transaction_id,
        'new_balance' => number_format($new_balance, 2, '.', ''),
        'deducted_amount' => number_format($amount, 2, '.', ''),
        'description' => $description
    ]);
} catch (Exception $e) {
    $conn->rollback();
    respond_json(['status' => 'error', 'message' => $e->getMessage()]);
}
?>
