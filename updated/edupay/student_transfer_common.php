<?php

declare(strict_types=1);

require_once __DIR__ . '/app_session_common.php';
require_once __DIR__ . '/pin_management_common.php';

const ST_MIN_TRANSFER_CENTS = 100; 
const ST_MAX_TRANSFER_CENTS = 5000000; 
const ST_MAX_WALLET_CENTS = 9999999999; 
const ST_MAX_PIN_ATTEMPTS = 3;

final class StudentTransferClientException extends RuntimeException
{
    
    private array $details;
    private int $httpStatus;
    private bool $audited;

    
    public function __construct(
        string $message,
        string $code,
        int $httpStatus = 422,
        array $details = [],
        bool $audited = false
    ) {
        parent::__construct($message);
        $this->details = array_merge(['code' => $code], $details);
        $this->httpStatus = $httpStatus;
        $this->audited = $audited;
    }

    
    public function details(): array
    {
        return $this->details;
    }

    public function httpStatus(): int
    {
        return $this->httpStatus;
    }

    public function wasAudited(): bool
    {
        return $this->audited;
    }

    public function markAudited(): void
    {
        $this->audited = true;
    }
}


function st_reject(
    string $message,
    string $code,
    int $httpStatus = 422,
    array $details = []
): void {
    throw new StudentTransferClientException($message, $code, $httpStatus, $details);
}

function st_prepare(mysqli $conn, string $sql): mysqli_stmt
{
    $statement = $conn->prepare($sql);
    if (!$statement) {
        error_log('Student transfer statement prepare failed: ' . $conn->error);
        throw new RuntimeException('Student transfer database operation could not be prepared.');
    }
    return $statement;
}

function st_assert_schema(mysqli $conn): void
{
    foreach (
        [
            'students',
            'transactions',
            'student_transfers',
            'transaction_receipts',
            'account_notifications',
            'app_activity_events',
        ] as $table
    ) {
        if (!pc_table_exists($conn, $table)) {
            throw new RuntimeException('The student-transfer database migration has not been applied.');
        }
    }
}

function st_normalize_student_id(string $studentId, string $label): string
{
    $studentId = trim($studentId);
    if (preg_match('/^[A-Za-z0-9][A-Za-z0-9._-]{0,19}$/D', $studentId) !== 1) {
        st_reject('Enter a valid ' . $label . '.', 'invalid_student_id');
    }
    return $studentId;
}

function st_normalize_request_id(string $requestId): string
{
    $requestId = strtolower(trim($requestId));
    if (preg_match(
        '/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/D',
        $requestId
    ) !== 1) {
        st_reject('A valid transfer request ID is required.', 'invalid_request_id');
    }
    return $requestId;
}

function st_amount_to_cents(string $amount): int
{
    $amount = trim($amount);
    if (preg_match('/^(0|[1-9][0-9]{0,7})(?:\.([0-9]{1,2}))?$/D', $amount, $matches) !== 1) {
        st_reject(
            'Enter an amount with no more than two decimal places.',
            'invalid_amount'
        );
    }

    $whole = (int)$matches[1];
    $fraction = isset($matches[2]) ? str_pad((string)$matches[2], 2, '0') : '00';
    $cents = ($whole * 100) + (int)$fraction;
    if ($cents < ST_MIN_TRANSFER_CENTS) {
        st_reject('The minimum transfer is PHP 1.00.', 'amount_below_minimum');
    }
    if ($cents > ST_MAX_TRANSFER_CENTS) {
        st_reject('The maximum transfer is PHP 50,000.00.', 'amount_above_maximum');
    }
    return $cents;
}

function st_database_money_to_cents(string $amount): int
{
    $amount = trim($amount);
    $negative = str_starts_with($amount, '-');
    if ($negative) {
        $amount = substr($amount, 1);
    }
    if (preg_match('/^(\d+)(?:\.(\d{1,2}))?$/D', $amount, $matches) !== 1) {
        throw new RuntimeException('A stored wallet amount is invalid.');
    }
    $fraction = isset($matches[2]) ? str_pad((string)$matches[2], 2, '0') : '00';
    $cents = ((int)$matches[1] * 100) + (int)$fraction;
    return $negative ? -$cents : $cents;
}

function st_format_cents(int $cents): string
{
    $negative = $cents < 0;
    $absolute = abs($cents);
    $formatted = intdiv($absolute, 100) . '.' . str_pad((string)($absolute % 100), 2, '0', STR_PAD_LEFT);
    return $negative ? '-' . $formatted : $formatted;
}

function st_request_fingerprint(
    string $senderStudentNumber,
    string $recipientStudentNumber,
    int $amountCents
): string {
    return hash(
        'sha256',
        implode("\0", [
            'student-transfer-v1',
            $senderStudentNumber,
            $recipientStudentNumber,
            (string)$amountCents,
        ])
    );
}


function st_find_student(mysqli $conn, string $studentNumber): ?array
{
    $statement = st_prepare(
        $conn,
        'SELECT student_num FROM students WHERE student_num = ? LIMIT 1'
    );
    $statement->bind_param('s', $studentNumber);
    $statement->execute();
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    return is_array($row) ? $row : null;
}


function st_lock_student(mysqli $conn, string $studentNumber): array
{
    $failedAttempts = pc_column_exists($conn, 'students', 'failed_attempts')
        ? 'failed_attempts'
        : '0 AS failed_attempts';
    $isLocked = pc_column_exists($conn, 'students', 'is_locked')
        ? 'is_locked'
        : '0 AS is_locked';
    $isFrozen = pc_column_exists($conn, 'students', 'is_frozen')
        ? 'is_frozen'
        : '0 AS is_frozen';
    $transactionLimit = pc_column_exists($conn, 'students', 'transaction_limit')
        ? 'transaction_limit'
        : '0.00 AS transaction_limit';
    $transactionLimitPeriod = pc_column_exists($conn, 'students', 'transaction_limit_period')
        ? "COALESCE(transaction_limit_period, 'daily') AS transaction_limit_period"
        : "'daily' AS transaction_limit_period";

    $statement = st_prepare(
        $conn,
        "SELECT student_num, Fname, balance, pin, {$failedAttempts}, {$isLocked}, "
            . "{$isFrozen}, {$transactionLimit}, {$transactionLimitPeriod} "
            . 'FROM students WHERE student_num = ? LIMIT 1 FOR UPDATE'
    );
    $statement->bind_param('s', $studentNumber);
    $statement->execute();
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    if (!is_array($row)) {
        st_reject('Student account not found.', 'student_not_found', 404);
    }
    return $row;
}

function st_reset_pin_attempts(mysqli $conn, string $senderStudentNumber): void
{
    if (!pc_column_exists($conn, 'students', 'failed_attempts')) {
        return;
    }
    $statement = st_prepare(
        $conn,
        'UPDATE students SET failed_attempts = 0 WHERE student_num = ? AND failed_attempts <> 0'
    );
    $statement->bind_param('s', $senderStudentNumber);
    $statement->execute();
    $statement->close();
}


function st_register_invalid_pin(
    mysqli $conn,
    string $senderStudentNumber,
    int $currentAttempts
): void {
    $hasAttempts = pc_column_exists($conn, 'students', 'failed_attempts');
    $hasLock = pc_column_exists($conn, 'students', 'is_locked');
    if (!$hasAttempts) {
        st_reject('Incorrect PIN.', 'invalid_pin', 422);
    }

    $attempts = min(ST_MAX_PIN_ATTEMPTS, max(0, $currentAttempts) + 1);
    if ($hasLock && $attempts >= ST_MAX_PIN_ATTEMPTS) {
        $statement = st_prepare(
            $conn,
            'UPDATE students SET failed_attempts = ?, is_locked = 1 WHERE student_num = ?'
        );
        $statement->bind_param('is', $attempts, $senderStudentNumber);
        $statement->execute();
        $statement->close();
        st_reject(
            'Too many incorrect PIN attempts. Your account is locked.',
            'account_locked',
            423,
            ['remaining_attempts' => 0]
        );
    }

    $statement = st_prepare(
        $conn,
        'UPDATE students SET failed_attempts = ? WHERE student_num = ?'
    );
    $statement->bind_param('is', $attempts, $senderStudentNumber);
    $statement->execute();
    $statement->close();
    st_reject(
        'Incorrect PIN.',
        'invalid_pin',
        422,
        ['remaining_attempts' => max(0, ST_MAX_PIN_ATTEMPTS - $attempts)]
    );
}

function st_upgrade_pin_if_needed(
    mysqli $conn,
    string $studentNumber,
    string $enteredPin,
    string $storedPin
): void {
    $needsUpgrade = !pc_is_password_hash($storedPin)
        || password_needs_rehash($storedPin, PASSWORD_DEFAULT);
    if (!$needsUpgrade) {
        return;
    }
    $hash = pm_hash_pin($enteredPin);
    $statement = st_prepare($conn, 'UPDATE students SET pin = ? WHERE student_num = ?');
    $statement->bind_param('ss', $hash, $studentNumber);
    if (!$statement->execute() || $statement->affected_rows !== 1) {
        $statement->close();
        throw new RuntimeException('The account PIN could not be secured.');
    }
    $statement->close();
}

function st_period_filter(string $period): string
{
    return match (strtolower(trim($period))) {
        'weekly' => 'YEARWEEK(COALESCE(date_time, date_created, NOW()), 1) = '
            . 'YEARWEEK(CURDATE(), 1)',
        'monthly' => 'MONTH(COALESCE(date_time, date_created, NOW())) = MONTH(CURDATE()) '
            . 'AND YEAR(COALESCE(date_time, date_created, NOW())) = YEAR(CURDATE())',
        default => 'DATE(COALESCE(date_time, date_created, NOW())) = CURDATE()',
    };
}

function st_assert_within_spending_limit(
    mysqli $conn,
    string $senderStudentNumber,
    int $amountCents,
    string $limitAmount,
    string $period
): void {
    $limitCents = st_database_money_to_cents($limitAmount);
    if ($limitCents <= 0) {
        return;
    }
    $normalizedPeriod = in_array(strtolower($period), ['daily', 'weekly', 'monthly'], true)
        ? strtolower($period)
        : 'daily';
    $filter = st_period_filter($normalizedPeriod);
    $statement = st_prepare(
        $conn,
        "SELECT COALESCE(SUM(amount), 0.00) AS spent FROM transactions "
            . "WHERE student_num = ? AND transaction_type IN ('payment', 'transfer-out') "
            . "AND {$filter}"
    );
    $statement->bind_param('s', $senderStudentNumber);
    $statement->execute();
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    $spentCents = st_database_money_to_cents((string)($row['spent'] ?? '0.00'));
    if (($spentCents + $amountCents) > $limitCents) {
        $remaining = max(0, $limitCents - $spentCents);
        st_reject(
            'This transfer exceeds your ' . $normalizedPeriod
                . ' spending limit. You have PHP ' . st_format_cents($remaining) . ' remaining.',
            'spending_limit_exceeded',
            409,
            ['remaining_limit' => st_format_cents($remaining)]
        );
    }
}


function st_find_existing_request(
    mysqli $conn,
    string $senderStudentNumber,
    string $clientRequestId
): ?array {
    $statement = st_prepare(
        $conn,
        'SELECT * FROM student_transfers '
            . 'WHERE sender_student_num = ? AND client_request_id = ? LIMIT 1 FOR UPDATE'
    );
    $statement->bind_param('ss', $senderStudentNumber, $clientRequestId);
    $statement->execute();
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    return is_array($row) ? $row : null;
}


function st_completed_result(array $row, bool $idempotent): array
{
    return [
        'transfer_id' => (int)$row['transfer_id'],
        'sender_transaction_id' => (int)$row['sender_transaction_id'],
        'recipient_transaction_id' => (int)$row['recipient_transaction_id'],
        'new_balance' => st_format_cents(
            st_database_money_to_cents((string)$row['sender_balance_after'])
        ),
        'recipient_balance' => st_format_cents(
            st_database_money_to_cents((string)$row['recipient_balance_after'])
        ),
        'recipient_name' => (string)$row['recipient_name_snapshot'],
        'amount' => st_format_cents(st_database_money_to_cents((string)$row['amount'])),
        'idempotent' => $idempotent,
    ];
}

function st_insert_transaction(
    mysqli $conn,
    string $studentNumber,
    string $amount,
    string $transactionType,
    string $description,
    string $senderStudentNumber
): int {
    $statement = st_prepare(
        $conn,
        'INSERT INTO transactions '
            . '(student_num, amount, transaction_type, description, '
            . 'processor_role, processor_account_source, processor_id, date_time) '
            . "VALUES (?, ?, ?, ?, 'student', 'students', ?, NOW())"
    );
    $statement->bind_param(
        'sssss',
        $studentNumber,
        $amount,
        $transactionType,
        $description,
        $senderStudentNumber
    );
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('The transfer history could not be recorded.');
    }
    $transactionId = (int)$statement->insert_id;
    $statement->close();
    if ($transactionId <= 0) {
        throw new RuntimeException('The transfer transaction ID is unavailable.');
    }
    return $transactionId;
}

function st_ensure_receipt(mysqli $conn, int $transactionId): void
{
    $statement = st_prepare(
        $conn,
        'INSERT IGNORE INTO transaction_receipts '
            . '(transaction_id, receipt_number, issued_at, transaction_type, '
            . 'description_snapshot, student_num_snapshot, student_name_snapshot, '
            . 'canteen_id_snapshot, canteen_name_snapshot, cashier_id_snapshot, '
            . 'cashier_name_snapshot, processor_role_snapshot, '
            . 'processor_account_source_snapshot, processor_id_snapshot, '
            . 'processor_name_snapshot, total_amount, legacy_backfilled) '
            . 'SELECT t.transaction_id, '
            . "CONCAT('EP-', DATE_FORMAT(COALESCE(t.date_time, t.date_created, NOW()), '%Y%m%d'), "
            . "'-', LPAD(t.transaction_id, 8, '0')), "
            . 'COALESCE(t.date_time, t.date_created, NOW()), t.transaction_type, t.description, '
            . 't.student_num, COALESCE(s.Fname, t.student_num), t.canteen_id, c.Fname, '
            . 't.cashier_id, COALESCE(ch.Fname, a.Fname), t.processor_role, '
            . 't.processor_account_source, t.processor_id, CASE '
            . "WHEN t.processor_role = 'student' AND t.processor_account_source = 'students' "
            . "THEN ps.Fname WHEN t.processor_role = 'parent' "
            . "AND t.processor_account_source = 'parents' THEN pp.Fname "
            . "WHEN t.processor_role = 'canteen' AND t.processor_account_source = 'canteens' "
            . "THEN pc.Fname WHEN t.processor_role = 'cashier' "
            . "AND t.processor_account_source = 'cashiers' THEN pch.Fname "
            . "WHEN t.processor_role = 'cashier' AND t.processor_account_source = 'admins' "
            . 'THEN pa.Fname '
            . 'ELSE NULL END, t.amount, 0 '
            . 'FROM transactions t '
            . 'LEFT JOIN students s ON s.student_num = t.student_num '
            . 'LEFT JOIN canteens c ON c.canteen_id = t.canteen_id '
            . 'LEFT JOIN cashiers ch ON ch.cashier_id = t.cashier_id '
            . 'LEFT JOIN admins a ON a.admin_id = t.cashier_id '
            . "AND LOWER(COALESCE(a.role, '')) = 'cashier' "
            . "LEFT JOIN students ps ON t.processor_role = 'student' "
            . "AND t.processor_account_source = 'students' "
            . 'AND ps.student_num = t.processor_id '
            . "LEFT JOIN parents pp ON t.processor_role = 'parent' "
            . "AND t.processor_account_source = 'parents' "
            . 'AND pp.parent_id = t.processor_id '
            . "LEFT JOIN canteens pc ON t.processor_role = 'canteen' "
            . "AND t.processor_account_source = 'canteens' "
            . 'AND pc.canteen_id = t.processor_id '
            . "LEFT JOIN cashiers pch ON t.processor_role = 'cashier' "
            . "AND t.processor_account_source = 'cashiers' "
            . 'AND pch.cashier_id = t.processor_id '
            . "LEFT JOIN admins pa ON t.processor_role = 'cashier' "
            . "AND t.processor_account_source = 'admins' "
            . 'AND pa.admin_id = t.processor_id '
            . "AND LOWER(COALESCE(pa.role, '')) = 'cashier' "
            . 'WHERE t.transaction_id = ?'
    );
    $statement->bind_param('i', $transactionId);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('The transfer receipt could not be issued.');
    }
    $statement->close();
}

function st_create_notifications(
    mysqli $conn,
    string $studentNumber,
    int $transactionId,
    string $title,
    string $body
): void {
    $student = st_prepare(
        $conn,
        'INSERT IGNORE INTO account_notifications '
            . '(recipient_role, account_source, user_id, transaction_id, title, body) '
            . "VALUES ('student', 'students', ?, ?, ?, ?)"
    );
    $student->bind_param('siss', $studentNumber, $transactionId, $title, $body);
    if (!$student->execute()) {
        $student->close();
        throw new RuntimeException('The transfer notification could not be created.');
    }
    $student->close();

    if (pc_table_exists($conn, 'parent_student_link') && pc_table_exists($conn, 'parents')) {
        $parents = st_prepare(
            $conn,
            'INSERT IGNORE INTO account_notifications '
                . '(recipient_role, account_source, user_id, transaction_id, title, body) '
                . "SELECT 'parent', 'parents', linked.parent_id, ?, ?, ? FROM ("
                . 'SELECT psl.parent_id FROM parent_student_link psl WHERE psl.student_num = ? '
                . 'UNION SELECT p.parent_id FROM parents p WHERE p.linked_student_num = ?'
                . ') linked'
        );
        $parents->bind_param(
            'issss',
            $transactionId,
            $title,
            $body,
            $studentNumber,
            $studentNumber
        );
        if (!$parents->execute()) {
            $parents->close();
            throw new RuntimeException('The linked account notification could not be created.');
        }
        $parents->close();
    }

    $normalize = st_prepare(
        $conn,
        'UPDATE account_notifications SET title = ?, body = ? WHERE transaction_id = ?'
    );
    $normalize->bind_param('ssi', $title, $body, $transactionId);
    if (!$normalize->execute()) {
        $normalize->close();
        throw new RuntimeException('The transfer notification could not be finalized.');
    }
    $normalize->close();
}

function st_execute_transfer(
    mysqli $conn,
    array $session,
    string $senderStudentNumber,
    string $recipientStudentNumber,
    string $amount,
    string $pin,
    string $clientRequestId
): array {
    st_assert_schema($conn);
    $senderStudentNumber = st_normalize_student_id($senderStudentNumber, 'sender ID');
    $recipientStudentNumber = st_normalize_student_id($recipientStudentNumber, 'recipient ID');
    $clientRequestId = st_normalize_request_id($clientRequestId);
    $amountCents = st_amount_to_cents($amount);
    $money = st_format_cents($amountCents);
    if (preg_match('/^\d{6}$/D', $pin) !== 1) {
        st_reject('PIN must be exactly 6 digits.', 'invalid_pin_format');
    }

    as_assert_session_identity($session, 'student', $senderStudentNumber, 'students');

    $transactionActive = false;
    $auditMetadata = [
        'recipient_student_num' => $recipientStudentNumber,
        'amount' => $money,
        'client_request_id' => $clientRequestId,
    ];

    try {
        if (!$conn->begin_transaction()) {
            throw new RuntimeException('The transfer transaction could not be started.');
        }
        $transactionActive = true;

        $senderIdentity = st_find_student($conn, $senderStudentNumber);
        if (!is_array($senderIdentity)) {
            st_reject('Sender account not found.', 'sender_not_found', 404);
        }
        $recipientIdentity = st_find_student($conn, $recipientStudentNumber);
        if (!is_array($recipientIdentity)) {
            st_reject('Recipient student not found.', 'recipient_not_found', 404);
        }
        $senderStudentNumber = (string)$senderIdentity['student_num'];
        $recipientStudentNumber = (string)$recipientIdentity['student_num'];
        $auditMetadata['recipient_student_num'] = $recipientStudentNumber;

        if (hash_equals($senderStudentNumber, $recipientStudentNumber)) {
            st_reject('You cannot transfer funds to your own account.', 'self_transfer');
        }

        $lockOrder = [$senderStudentNumber, $recipientStudentNumber];
        usort(
            $lockOrder,
            static function (string $left, string $right): int {
                $caseInsensitive = strcasecmp($left, $right);
                return $caseInsensitive !== 0 ? $caseInsensitive : strcmp($left, $right);
            }
        );
        $locked = [];
        foreach ($lockOrder as $studentNumber) {
            $row = st_lock_student($conn, $studentNumber);
            $locked[(string)$row['student_num']] = $row;
        }
        $sender = $locked[$senderStudentNumber] ?? null;
        $recipient = $locked[$recipientStudentNumber] ?? null;
        if (!is_array($sender) || !is_array($recipient)) {
            throw new RuntimeException('The transfer accounts could not be locked.');
        }

        if ((int)($sender['is_locked'] ?? 0) === 1) {
            st_reject('Your account is locked. Contact an administrator.', 'account_locked', 423);
        }
        if ((int)($sender['is_frozen'] ?? 0) === 1) {
            st_reject(
                'Your account is frozen. Fund transfers are disabled.',
                'account_frozen',
                403
            );
        }

        $storedPin = trim((string)($sender['pin'] ?? ''));
        if ($storedPin === '') {
            st_reject(
                'Set up your 6-digit PIN in your profile before transferring funds.',
                'pin_not_configured',
                409
            );
        }
        if (!pm_pin_matches($pin, $storedPin)) {
            st_register_invalid_pin(
                $conn,
                $senderStudentNumber,
                (int)($sender['failed_attempts'] ?? 0)
            );
        }
        st_reset_pin_attempts($conn, $senderStudentNumber);
        st_upgrade_pin_if_needed($conn, $senderStudentNumber, $pin, $storedPin);

        $fingerprint = st_request_fingerprint(
            $senderStudentNumber,
            $recipientStudentNumber,
            $amountCents
        );
        $existing = st_find_existing_request($conn, $senderStudentNumber, $clientRequestId);
        if (is_array($existing)) {
            if (!hash_equals((string)$existing['request_fingerprint'], $fingerprint)) {
                st_reject(
                    'That transfer request ID was already used for different details.',
                    'idempotency_conflict',
                    409
                );
            }
            if ((string)$existing['status'] !== 'completed'
                || $existing['sender_transaction_id'] === null
                || $existing['recipient_transaction_id'] === null
            ) {
                st_reject(
                    'This transfer request is still being processed. Please try again.',
                    'transfer_in_progress',
                    409
                );
            }
            as_record_activity(
                $conn,
                $session,
                'student_transfer_replayed',
                [
                    'transfer_id' => (int)$existing['transfer_id'],
                    'recipient_student_num' => $recipientStudentNumber,
                    'amount' => $money,
                    'client_request_id' => $clientRequestId,
                ],
                'server',
                'info'
            );
            if (!$conn->commit()) {
                throw new RuntimeException('The transfer response could not be committed.');
            }
            $transactionActive = false;
            return st_completed_result($existing, true);
        }

        $senderBalanceCents = st_database_money_to_cents((string)$sender['balance']);
        $recipientBalanceCents = st_database_money_to_cents((string)$recipient['balance']);
        if ($senderBalanceCents < $amountCents) {
            st_reject('Insufficient wallet balance.', 'insufficient_balance', 409);
        }
        if (($recipientBalanceCents + $amountCents) > ST_MAX_WALLET_CENTS) {
            st_reject(
                'The recipient wallet cannot accept this amount.',
                'recipient_balance_limit',
                409
            );
        }
        st_assert_within_spending_limit(
            $conn,
            $senderStudentNumber,
            $amountCents,
            (string)($sender['transaction_limit'] ?? '0.00'),
            (string)($sender['transaction_limit_period'] ?? 'daily')
        );

        $senderName = trim((string)$sender['Fname']);
        $recipientName = trim((string)$recipient['Fname']);
        if ($senderName === '') {
            $senderName = $senderStudentNumber;
        }
        if ($recipientName === '') {
            $recipientName = $recipientStudentNumber;
        }
        $sessionId = isset($session['session_id']) ? (int)$session['session_id'] : null;
        $create = st_prepare(
            $conn,
            'INSERT INTO student_transfers '
                . '(client_request_id, request_fingerprint, sender_student_num, '
                . 'recipient_student_num, sender_name_snapshot, recipient_name_snapshot, '
                . 'amount, session_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)'
        );
        $create->bind_param(
            'sssssssi',
            $clientRequestId,
            $fingerprint,
            $senderStudentNumber,
            $recipientStudentNumber,
            $senderName,
            $recipientName,
            $money,
            $sessionId
        );
        if (!$create->execute()) {
            $create->close();
            throw new RuntimeException('The transfer request could not be recorded.');
        }
        $transferId = (int)$create->insert_id;
        $create->close();

        $senderBalanceAfter = $senderBalanceCents - $amountCents;
        $recipientBalanceAfter = $recipientBalanceCents + $amountCents;
        $senderBalance = st_format_cents($senderBalanceAfter);
        $recipientBalance = st_format_cents($recipientBalanceAfter);

        $debit = st_prepare(
            $conn,
            'UPDATE students SET balance = ? '
                . 'WHERE student_num = ? AND balance >= ?'
        );
        $debit->bind_param('sss', $senderBalance, $senderStudentNumber, $money);
        if (!$debit->execute() || $debit->affected_rows !== 1) {
            $debit->close();
            throw new RuntimeException('The sender wallet could not be debited.');
        }
        $debit->close();

        $credit = st_prepare(
            $conn,
            'UPDATE students SET balance = ? WHERE student_num = ?'
        );
        $credit->bind_param('ss', $recipientBalance, $recipientStudentNumber);
        if (!$credit->execute() || $credit->affected_rows !== 1) {
            $credit->close();
            throw new RuntimeException('The recipient wallet could not be credited.');
        }
        $credit->close();

        $senderDescription = 'Transfer sent to ' . $recipientName;
        $recipientDescription = 'Transfer received from ' . $senderName;
        $senderTransactionId = st_insert_transaction(
            $conn,
            $senderStudentNumber,
            $money,
            'transfer-out',
            $senderDescription,
            $senderStudentNumber
        );
        $recipientTransactionId = st_insert_transaction(
            $conn,
            $recipientStudentNumber,
            $money,
            'transfer-in',
            $recipientDescription,
            $senderStudentNumber
        );

        st_ensure_receipt($conn, $senderTransactionId);
        st_ensure_receipt($conn, $recipientTransactionId);
        st_create_notifications(
            $conn,
            $senderStudentNumber,
            $senderTransactionId,
            'Fund transfer sent',
            'PHP ' . $money . ' was transferred to ' . $recipientName . '.'
        );
        st_create_notifications(
            $conn,
            $recipientStudentNumber,
            $recipientTransactionId,
            'Fund transfer received',
            'PHP ' . $money . ' was received from ' . $senderName . '.'
        );

        $complete = st_prepare(
            $conn,
            "UPDATE student_transfers SET status = 'completed', "
                . 'sender_transaction_id = ?, recipient_transaction_id = ?, '
                . 'sender_balance_after = ?, recipient_balance_after = ?, completed_at = NOW(6) '
                . "WHERE transfer_id = ? AND status = 'pending'"
        );
        $complete->bind_param(
            'iissi',
            $senderTransactionId,
            $recipientTransactionId,
            $senderBalance,
            $recipientBalance,
            $transferId
        );
        if (!$complete->execute() || $complete->affected_rows !== 1) {
            $complete->close();
            throw new RuntimeException('The transfer record could not be finalized.');
        }
        $complete->close();

        as_record_activity(
            $conn,
            $session,
            'student_transfer_completed',
            [
                'transfer_id' => $transferId,
                'sender_transaction_id' => $senderTransactionId,
                'recipient_transaction_id' => $recipientTransactionId,
                'recipient_student_num' => $recipientStudentNumber,
                'amount' => $money,
                'client_request_id' => $clientRequestId,
            ],
            'server',
            'success'
        );

        if (!$conn->commit()) {
            throw new RuntimeException('The transfer could not be committed.');
        }
        $transactionActive = false;
        return [
            'transfer_id' => $transferId,
            'sender_transaction_id' => $senderTransactionId,
            'recipient_transaction_id' => $recipientTransactionId,
            'new_balance' => $senderBalance,
            'recipient_balance' => $recipientBalance,
            'recipient_name' => $recipientName,
            'amount' => $money,
            'idempotent' => false,
        ];
    } catch (StudentTransferClientException $error) {
        if ($transactionActive) {
            try {
                as_record_activity(
                    $conn,
                    $session,
                    'student_transfer_failed',
                    array_merge($auditMetadata, ['reason' => $error->details()['code'] ?? 'rejected']),
                    'server',
                    'failure'
                );
                if (!$conn->commit()) {
                    throw new RuntimeException('The rejected transfer audit could not be committed.');
                }
                $transactionActive = false;
                $error->markAudited();
            } catch (Throwable $auditError) {
                $conn->rollback();
                $transactionActive = false;
                error_log('Student transfer rejection audit failed: ' . $auditError->getMessage());
                throw new RuntimeException('The transfer could not be processed safely.');
            }
        }
        throw $error;
    } catch (Throwable $error) {
        if ($transactionActive) {
            $conn->rollback();
        }
        throw $error;
    }
}
