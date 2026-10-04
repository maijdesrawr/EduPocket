<?php

ob_start();
ini_set('display_errors', '0');
error_reporting(0);
header('Content-Type: application/json; charset=utf-8');
require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/app_session_common.php';

function topup_json(array $payload): void
{
    if (ob_get_length()) {
        ob_clean();
    }
    echo json_encode($payload);
    exit;
}

function topup_prepare(mysqli $conn, string $sql): mysqli_stmt
{
    $statement = $conn->prepare($sql);
    if (!$statement) {
        throw new RuntimeException('The top-up could not be prepared.');
    }
    return $statement;
}

try {
    $appSession = as_require_session($conn, false);
} catch (PasswordChangeClientException $error) {
    topup_json(pc_client_error_payload($error->getMessage(), $error->details()));
} catch (Throwable $error) {
    error_log('record_topup.php session validation failed: ' . $error->getMessage());
    topup_json(['status' => 'error', 'message' => 'Your session could not be validated.']);
}

$parentId = trim((string)($_POST['parent_id'] ?? ''));
$studentNumber = trim((string)($_POST['child_id'] ?? ''));
$amount = filter_var($_POST['amount'] ?? null, FILTER_VALIDATE_FLOAT);
$method = trim((string)($_POST['method'] ?? 'Bank'));
$allowedMethods = ['Bank'];

if ($parentId === '' || $studentNumber === '' || $amount === false || $amount <= 0) {
    topup_json(['status' => 'error', 'message' => 'Enter valid top-up details.']);
}
if (!in_array($method, $allowedMethods, true)) {
    topup_json(['status' => 'error', 'message' => 'Invalid top-up method.']);
}

$transactionStarted = false;
try {
    if (!$conn->begin_transaction()) {
        throw new RuntimeException('The top-up could not be started.');
    }
    $transactionStarted = true;
    as_assert_session_identity($appSession, 'parent', $parentId, 'parents');

    $link = topup_prepare(
        $conn,
        'SELECT 1 FROM parents p '
            . 'LEFT JOIN parent_student_link psl '
            . 'ON psl.parent_id = p.parent_id AND psl.student_num = ? '
            . 'WHERE p.parent_id = ? '
            . 'AND (psl.id IS NOT NULL OR p.linked_student_num = ?) LIMIT 1 FOR UPDATE'
    );
    $link->bind_param('sss', $studentNumber, $parentId, $studentNumber);
    $link->execute();
    $isLinked = $link->get_result()->fetch_row() !== null;
    $link->close();
    if (!$isLinked) {
        throw new RuntimeException('This student is not linked to the parent account.');
    }

    $student = topup_prepare(
        $conn,
        'SELECT balance FROM students WHERE student_num = ? LIMIT 1 FOR UPDATE'
    );
    $student->bind_param('s', $studentNumber);
    $student->execute();
    $studentRow = $student->get_result()->fetch_assoc();
    $student->close();
    if (!is_array($studentRow)) {
        throw new RuntimeException('Student account not found.');
    }

    $newBalance = (float)$studentRow['balance'] + (float)$amount;
    $update = topup_prepare(
        $conn,
        'UPDATE students SET balance = ? WHERE student_num = ?'
    );
    $update->bind_param('ds', $newBalance, $studentNumber);
    if (!$update->execute() || $update->affected_rows !== 1) {
        $update->close();
        throw new RuntimeException('The student balance could not be updated.');
    }
    $update->close();

    $topup = topup_prepare(
        $conn,
        "INSERT INTO topups (parent_id, student_num, amount, method, status, date_time) "
            . "VALUES (?, ?, ?, ?, 'Completed', NOW())"
    );
    $topup->bind_param('ssds', $parentId, $studentNumber, $amount, $method);
    if (!$topup->execute()) {
        $topup->close();
        throw new RuntimeException('The top-up record could not be created.');
    }
    $topupId = (int)$topup->insert_id;
    $topup->close();
    if ($topupId <= 0) {
        throw new RuntimeException('The top-up record ID is unavailable.');
    }

    $description = $method . ' Wallet Top-up';
    $transaction = topup_prepare(
        $conn,
        "INSERT INTO transactions "
            . "(student_num, amount, transaction_type, description, "
            . "processor_role, processor_account_source, processor_id, date_time) "
            . "VALUES (?, ?, 'top-up', ?, 'parent', 'parents', ?, NOW())"
    );
    $transaction->bind_param('sdss', $studentNumber, $amount, $description, $parentId);
    if (!$transaction->execute()) {
        $transaction->close();
        throw new RuntimeException('The wallet transaction could not be created.');
    }
    $transactionId = (int)$conn->insert_id;
    $transaction->close();
    if ($transactionId <= 0) {
        throw new RuntimeException('The wallet transaction ID is unavailable.');
    }

    $linkTopup = topup_prepare(
        $conn,
        'UPDATE topups SET transaction_id = ? WHERE topup_id = ? AND transaction_id IS NULL'
    );
    $linkTopup->bind_param('ii', $transactionId, $topupId);
    if (!$linkTopup->execute() || $linkTopup->affected_rows !== 1) {
        $linkTopup->close();
        throw new RuntimeException('The top-up receipt link could not be created.');
    }
    $linkTopup->close();

    $receiptNumber = null;
    $receipt = $conn->prepare(
        'SELECT receipt_number FROM transaction_receipts WHERE transaction_id = ? LIMIT 1'
    );
    if ($receipt) {
        $receipt->bind_param('i', $transactionId);
        $receipt->execute();
        $receiptRow = $receipt->get_result()->fetch_assoc();
        $receiptNumber = $receiptRow['receipt_number'] ?? null;
        $receipt->close();
    }

    as_record_activity(
        $conn,
        $appSession,
        'topup_completed',
        [
            'transaction_id' => $transactionId,
            'student_num' => $studentNumber,
            'amount' => number_format((float)$amount, 2, '.', ''),
            'method' => $method,
        ],
        'server'
    );

    if (!$conn->commit()) {
        throw new RuntimeException('The top-up could not be committed.');
    }
    $transactionStarted = false;
    topup_json([
        'status' => 'success',
        'message' => 'Top-up completed.',
        'student_num' => $studentNumber,
        'amount' => number_format((float)$amount, 2, '.', ''),
        'method' => $method,
        'new_balance' => number_format($newBalance, 2, '.', ''),
        'transaction_id' => $transactionId,
        'receipt_number' => $receiptNumber,
    ]);
} catch (Throwable $error) {
    if ($transactionStarted) {
        $conn->rollback();
    }
    error_log('record_topup.php failed: ' . $error->getMessage());
    topup_json(['status' => 'error', 'message' => $error->getMessage()]);
} finally {
    $conn->close();
}
