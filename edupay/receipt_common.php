<?php

function receipt_prepare(mysqli $conn, string $sql): mysqli_stmt
{
    $statement = $conn->prepare($sql);
    if (!$statement) {
        throw new RuntimeException('Receipt query could not be prepared.');
    }
    return $statement;
}

function receipt_table_exists(mysqli $conn, string $table): bool
{
    $safe = preg_replace('/[^a-zA-Z0-9_]/', '', $table);
    if ($safe === '') {
        return false;
    }
    $result = $conn->query("SHOW TABLES LIKE '$safe'");
    return $result instanceof mysqli_result && $result->num_rows > 0;
}

function receipt_column_exists(mysqli $conn, string $table, string $column): bool
{
    $safeTable = preg_replace('/[^a-zA-Z0-9_]/', '', $table);
    $safeColumn = preg_replace('/[^a-zA-Z0-9_]/', '', $column);
    if ($safeTable === '' || $safeColumn === '') {
        return false;
    }
    $result = $conn->query("SHOW COLUMNS FROM `$safeTable` LIKE '$safeColumn'");
    return $result instanceof mysqli_result && $result->num_rows > 0;
}


function receipt_processed_by(array $transaction): array
{
    $processorId = trim((string)($transaction['processor_id_snapshot'] ?? ''));
    $processorRole = strtolower(trim(
        (string)($transaction['processor_role_snapshot'] ?? '')
    ));
    $processorSource = strtolower(trim(
        (string)($transaction['processor_account_source_snapshot'] ?? '')
    ));
    $processorName = trim((string)($transaction['processor_name_snapshot'] ?? ''));
    if ($processorName !== '') {
        return [
            'id' => $processorId,
            'name' => $processorName,
            'role' => in_array(
                $processorRole,
                ['student', 'parent', 'canteen', 'cashier'],
                true
            ) ? $processorRole : null,
            'account_source' => in_array(
                $processorSource,
                ['students', 'parents', 'canteens', 'cashiers', 'admins'],
                true
            ) ? $processorSource : null,
        ];
    }

    if ($processorId !== '' || $processorRole !== '' || $processorSource !== '') {
        return [
            'id' => $processorId,
            'name' => 'N/A',
            'role' => in_array(
                $processorRole,
                ['student', 'parent', 'canteen', 'cashier'],
                true
            ) ? $processorRole : null,
            'account_source' => in_array(
                $processorSource,
                ['students', 'parents', 'canteens', 'cashiers', 'admins'],
                true
            ) ? $processorSource : null,
        ];
    }

    $cashierName = trim((string)($transaction['cashier_name_snapshot'] ?? ''));
    if ($cashierName !== '') {
        return [
            'id' => trim((string)($transaction['cashier_id_snapshot'] ?? '')),
            'name' => $cashierName,
            'role' => 'cashier',
            'account_source' => null,
        ];
    }

    $canteenName = trim((string)($transaction['canteen_name_snapshot'] ?? ''));
    if ($canteenName !== '') {
        return [
            'id' => trim((string)($transaction['canteen_id_snapshot'] ?? '')),
            'name' => $canteenName,
            'role' => 'canteen',
            'account_source' => 'canteens',
        ];
    }

    return [
        'id' => '',
        'name' => 'N/A',
        'role' => null,
        'account_source' => null,
    ];
}

function receipt_assert_viewer_access(
    mysqli $conn,
    array $transaction,
    string $viewerRole,
    string $viewerId
): void {
    if ($viewerId === '') {
        throw new InvalidArgumentException('A receipt viewer ID is required.');
    }
    switch ($viewerRole) {
        case 'student':
            if (!hash_equals((string)$transaction['student_num'], $viewerId)) {
                throw new RuntimeException('This receipt is not available to that account.');
            }
            return;
        case 'canteen':
            if (!hash_equals((string)($transaction['canteen_id'] ?? ''), $viewerId)) {
                throw new RuntimeException('This receipt is not available to that account.');
            }
            return;
        case 'cashier':
            if (!hash_equals((string)($transaction['cashier_id'] ?? ''), $viewerId)) {
                throw new RuntimeException('This receipt is not available to that account.');
            }
            return;
        case 'admin':
            $statement = receipt_prepare(
                $conn,
                'SELECT 1 FROM admins WHERE admin_id = ? '
                    . "AND LOWER(COALESCE(role, '')) <> 'cashier' LIMIT 1"
            );
            $statement->bind_param('s', $viewerId);
            $statement->execute();
            $allowed = $statement->get_result()->fetch_row() !== null;
            $statement->close();
            if (!$allowed) {
                throw new RuntimeException('This receipt is not available to that account.');
            }
            return;
        case 'parent':
            $studentNumber = (string)$transaction['student_num'];
            $statement = receipt_prepare(
                $conn,
                'SELECT 1 FROM parents p '
                    . 'LEFT JOIN parent_student_link psl '
                    . 'ON psl.parent_id = p.parent_id AND psl.student_num = ? '
                    . 'WHERE p.parent_id = ? '
                    . 'AND (psl.id IS NOT NULL OR p.linked_student_num = ?) LIMIT 1'
            );
            $statement->bind_param('sss', $studentNumber, $viewerId, $studentNumber);
            $statement->execute();
            $allowed = $statement->get_result()->fetch_row() !== null;
            $statement->close();
            if (!$allowed) {
                throw new RuntimeException('This receipt is not available to that account.');
            }
            return;
        default:
            throw new InvalidArgumentException('Invalid receipt viewer role.');
    }
}


function receipt_fetch(
    mysqli $conn,
    int $transactionId,
    string $viewerRole,
    string $viewerId
): array {
    if ($transactionId <= 0) {
        throw new InvalidArgumentException('A valid transaction ID is required.');
    }
    $viewerRole = strtolower(trim($viewerRole));
    $viewerId = trim($viewerId);
    if (!receipt_table_exists($conn, 'transaction_receipts')) {
        throw new RuntimeException('The receipt database migration has not been applied.');
    }

    $statement = receipt_prepare(
        $conn,
        'SELECT t.transaction_id, t.student_num, t.canteen_id, t.cashier_id, t.bill_payment_id, '
            . 'COALESCE(t.date_time, t.date_created, NOW()) AS event_time, '
            . 'r.receipt_number, r.issued_at, r.status AS receipt_status, r.currency, '
            . 'r.transaction_type, r.description_snapshot AS description, '
            . 'r.total_amount AS amount, r.legacy_backfilled, '
            . 'r.student_num_snapshot, r.student_name_snapshot, '
            . 'r.canteen_id_snapshot, r.canteen_name_snapshot, '
            . 'r.cashier_id_snapshot, r.cashier_name_snapshot, '
            . 'r.processor_role_snapshot, r.processor_account_source_snapshot, '
            . 'r.processor_id_snapshot, '
            . 'r.processor_name_snapshot, '
            . 'c.location AS canteen_location '
            . 'FROM transactions t '
            . 'JOIN transaction_receipts r ON r.transaction_id = t.transaction_id '
            . 'LEFT JOIN canteens c ON c.canteen_id = t.canteen_id '
            . 'WHERE t.transaction_id = ? LIMIT 1'
    );
    $statement->bind_param('i', $transactionId);
    $statement->execute();
    $transaction = $statement->get_result()->fetch_assoc();
    $statement->close();
    if (!is_array($transaction)) {
        throw new RuntimeException('Receipt not found.');
    }

    receipt_assert_viewer_access($conn, $transaction, $viewerRole, $viewerId);

    // An outgoing transfer is owned by the sender for access-control purposes,
    // but the receipt's Student fields identify the party receiving the funds.
    if ((string)$transaction['transaction_type'] === 'transfer-out'
        && receipt_table_exists($conn, 'student_transfers')) {
        $recipientStatement = receipt_prepare(
            $conn,
            'SELECT rr.student_num_snapshot, rr.student_name_snapshot '
                . 'FROM student_transfers st '
                . 'JOIN transaction_receipts rr '
                . 'ON rr.transaction_id = st.recipient_transaction_id '
                . 'WHERE st.sender_transaction_id = ? '
                . "AND st.status = 'completed' LIMIT 1"
        );
        $recipientStatement->bind_param('i', $transactionId);
        $recipientStatement->execute();
        $recipient = $recipientStatement->get_result()->fetch_assoc();
        $recipientStatement->close();
        if (is_array($recipient)) {
            $transaction['student_num_snapshot'] = $recipient['student_num_snapshot'];
            $transaction['student_name_snapshot'] = $recipient['student_name_snapshot'];
        }
    }

    $items = [];
    if (receipt_table_exists($conn, 'transaction_items')) {
        $itemNameExpression = receipt_column_exists($conn, 'transaction_items', 'item_name')
            ? "COALESCE(NULLIF(ti.item_name, ''), p.name, CONCAT('Product #', ti.product_id))"
            : "COALESCE(p.name, CONCAT('Product #', ti.product_id))";
        $itemStatement = receipt_prepare(
            $conn,
            "SELECT ti.product_id, $itemNameExpression AS item_name, "
                . 'ti.quantity, ti.price, (ti.quantity * ti.price) AS line_total '
                . 'FROM transaction_items ti '
                . 'LEFT JOIN products p ON p.product_id = ti.product_id '
                . 'WHERE ti.transaction_id = ? ORDER BY ti.id ASC'
        );
        $itemStatement->bind_param('i', $transactionId);
        $itemStatement->execute();
        $result = $itemStatement->get_result();
        while ($row = $result->fetch_assoc()) {
            $items[] = [
                'product_id' => (int)$row['product_id'],
                'name' => (string)$row['item_name'],
                'quantity' => (int)$row['quantity'],
                'unit_price' => number_format((float)$row['price'], 2, '.', ''),
                'line_total' => number_format((float)$row['line_total'], 2, '.', ''),
            ];
        }
        $itemStatement->close();
    }

    return [
        'transaction_id' => (int)$transaction['transaction_id'],
        'receipt_number' => (string)$transaction['receipt_number'],
        'status' => (string)$transaction['receipt_status'],
        'currency' => (string)$transaction['currency'],
        'legacy_backfilled' => (bool)$transaction['legacy_backfilled'],
        'transaction_type' => (string)$transaction['transaction_type'],
        'description' => (string)($transaction['description'] ?? ''),
        'amount' => number_format((float)$transaction['amount'], 2, '.', ''),
        'date_time' => (string)$transaction['event_time'],
        'issued_at' => (string)$transaction['issued_at'],
        'student' => [
            'id' => (string)$transaction['student_num_snapshot'],
            'name' => (string)$transaction['student_name_snapshot'],
        ],
        'processed_by' => receipt_processed_by($transaction),
        'canteen' => [
            'id' => (string)($transaction['canteen_id_snapshot'] ?? ''),
            'name' => (string)($transaction['canteen_name_snapshot'] ?? ''),
            'location' => (string)($transaction['canteen_location'] ?? ''),
        ],
        'cashier' => [
            'id' => (string)($transaction['cashier_id_snapshot'] ?? ''),
            'name' => (string)($transaction['cashier_name_snapshot'] ?? ''),
        ],
        'items' => $items,
    ];
}
