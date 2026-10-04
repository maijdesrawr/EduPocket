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
    if (!$stmt) throw new Exception($errorMessage . ': ' . $conn->error);
    return $stmt;
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

try {
    $appSession = as_require_session($conn, false);
} catch (PasswordChangeClientException $error) {
    respond_json(pc_client_error_payload($error->getMessage(), $error->details()));
} catch (Throwable $error) {
    error_log('cashier_topup.php session validation failed: ' . $error->getMessage());
    respond_json(['status' => 'error', 'message' => 'Your session could not be validated.']);
}

$student_num = trim($_POST['student_id'] ?? '');
$cashier_id  = trim($_POST['cashier_id'] ?? '');
$amount      = floatval($_POST['amount'] ?? 0);
$pin         = trim($_POST['pin'] ?? '');

if ($student_num === '' || $pin === '') {
    respond_json(['status'=>'error', 'message'=>'Missing student number or PIN']);
}

if (!preg_match('/^\d{6}$/', $pin)) {
    respond_json(['status'=>'error', 'message'=>'PIN must be exactly 6 digits']);
}

if ($amount <= 0) {
    respond_json(['status'=>'error', 'message'=>'Invalid top-up amount']);
}

$conn->begin_transaction();

try {
    as_assert_session_identity($appSession, 'cashier', $cashier_id);
    $cashier_account_source = strtolower(trim(
        (string)($appSession['account_source'] ?? '')
    ));
    if ($cashier_account_source !== 'cashiers') {
        throw new Exception('The cashier session account source is invalid.');
    }

    $cashier_account_stmt = prepare_or_throw(
        $conn,
        'SELECT balance, pin FROM cashiers WHERE cashier_id = ? LIMIT 1 FOR UPDATE',
        'Failed to load cashier account'
    );
    $cashier_account_stmt->bind_param('s', $cashier_id);
    $cashier_account_stmt->execute();
    $cashier_result = $cashier_account_stmt->get_result();
    if (!$cashier_result || $cashier_result->num_rows === 0) {
        throw new Exception('Cashier not found');
    }
    $cashier = $cashier_result->fetch_assoc();
    $cashier_account_stmt->close();

    if (!pin_matches($pin, $cashier['pin'] ?? '')) {
        throw new Exception('Invalid cashier PIN');
    }

    $cashier_balance = floatval($cashier['balance'] ?? 0);
    if ($cashier_balance < $amount) {
        throw new Exception('Insufficient cashier balance');
    }

    $stmt = prepare_or_throw(
        $conn,
        'SELECT balance FROM students WHERE student_num = ? LIMIT 1 FOR UPDATE',
        'Failed to load student account'
    );
    $stmt->bind_param('s', $student_num);
    $stmt->execute();
    $result = $stmt->get_result();
    if (!$result || $result->num_rows === 0) {
        throw new Exception('Student not found');
    }
    $student = $result->fetch_assoc();
    $stmt->close();

    $new_balance = floatval($student['balance'] ?? 0) + $amount;

    $update_stmt = prepare_or_throw(
        $conn,
        'UPDATE students SET balance = ? WHERE student_num = ?',
        'Failed to update balance'
    );

    $update_stmt->bind_param('ds', $new_balance, $student_num);

    if (!$update_stmt->execute()) {
        throw new Exception('Failed to update balance');
    }

    $update_stmt->close();

    $cashier_stmt = prepare_or_throw(
        $conn,
        'UPDATE cashiers SET balance = balance - ? WHERE cashier_id = ? AND balance >= ?',
        'Failed to update cashier balance'
    );

    $cashier_stmt->bind_param('dsd', $amount, $cashier_id, $amount);

    if (!$cashier_stmt->execute() || $cashier_stmt->affected_rows < 1) {
        throw new Exception('Failed to update cashier balance');
    }

    $cashier_stmt->close();

    $topup_record_stmt = prepare_or_throw(
        $conn,
        "INSERT INTO topups (parent_id, student_num, amount, method, status, date_time) VALUES (NULL, ?, ?, 'Over-the-counter', 'Completed', NOW())",
        'Failed to record top-up'
    );

    $topup_record_stmt->bind_param('sd', $student_num, $amount);

    if (!$topup_record_stmt->execute()) {
        throw new Exception('Failed to record top-up');
    }

    $topup_id = intval($topup_record_stmt->insert_id);
    $topup_record_stmt->close();
    if ($topup_id <= 0) {
        throw new Exception('Failed to resolve top-up record id');
    }

    $txn_type = 'top-up';
    $description = 'Student Top-up';

    $txn_stmt = prepare_or_throw(
        $conn,
        'INSERT INTO transactions 
        (student_num, amount, transaction_type, description, cashier_id,
         processor_role, processor_account_source, processor_id, date_time) 
        VALUES (?, ?, ?, ?, ?, \'cashier\', ?, ?, NOW())',
        'Failed to create transaction'
    );

    $txn_stmt->bind_param(
        'sdsssss',
        $student_num,
        $amount,
        $txn_type,
        $description,
        $cashier_id,
        $cashier_account_source,
        $cashier_id
    );

    if (!$txn_stmt->execute()) {
        throw new Exception('Failed to insert transaction: ' . $txn_stmt->error);
    }

    $transaction_id = intval($conn->insert_id);
    $txn_stmt->close();
    if ($transaction_id <= 0) {
        throw new Exception('Failed to resolve transaction id');
    }

    $link_topup_stmt = prepare_or_throw(
        $conn,
        'UPDATE topups SET transaction_id = ? '
            . 'WHERE topup_id = ? AND transaction_id IS NULL',
        'Failed to link top-up receipt'
    );
    $link_topup_stmt->bind_param('ii', $transaction_id, $topup_id);
    if (!$link_topup_stmt->execute() || $link_topup_stmt->affected_rows !== 1) {
        $link_topup_stmt->close();
        throw new Exception('Failed to link top-up receipt');
    }
    $link_topup_stmt->close();

    as_record_activity(
        $conn,
        $appSession,
        'topup_completed',
        [
            'transaction_id' => $transaction_id,
            'student_num' => $student_num,
            'amount' => number_format($amount, 2, '.', ''),
            'method' => 'Over-the-counter',
        ],
        'server'
    );

    $conn->commit();

    respond_json([
        'status' => 'success',
        'data' => [
            'student_id' => $student_num,
            'amount' => number_format($amount, 2, '.', ''),
            'new_balance' => number_format($new_balance, 2, '.', ''),
            'cashier_new_balance' => number_format($cashier_balance - $amount, 2, '.', ''),
            'transaction_id' => $transaction_id
        ]
    ]);

} catch (Exception $e) {

    $conn->rollback();

    respond_json([
        'status' => 'error',
        'message' => $e->getMessage()
    ]);
}
?>
