<?php

require_once __DIR__ . '/backend_audit_common.php';
ba_register_request_audit();
require_once __DIR__ . '/paymongo_config.php';

function pm_prepare(mysqli $conn, string $sql): mysqli_stmt
{
    $statement = $conn->prepare($sql);
    if (!$statement) {
        throw new RuntimeException('The payment could not be prepared.');
    }
    return $statement;
}

function pm_checkout_id(string $value): string
{
    $value = trim($value);
    if (!preg_match('/^cs_[A-Za-z0-9_-]{8,96}$/', $value)) {
        throw new InvalidArgumentException('A valid checkout ID is required.');
    }
    return $value;
}

function pm_checkout_id_for_callback(mysqli $conn, string $reference): string
{
    $reference = trim($reference);
    if (!preg_match('/^EP-[a-f0-9]{48}$/', $reference)) {
        throw new InvalidArgumentException('A valid payment reference is required.');
    }
    $referenceHash = hash('sha256', $reference);
    $statement = pm_prepare(
        $conn,
        'SELECT checkout_id FROM pending_payments '
            . 'WHERE callback_token_hash = ? LIMIT 1'
    );
    $statement->bind_param('s', $referenceHash);
    $statement->execute();
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    if (!is_array($row)) {
        throw new RuntimeException('Payment request not found.');
    }
    return pm_checkout_id((string)($row['checkout_id'] ?? ''));
}

function pm_amount_centavos(mixed $amount): int
{
    $value = trim((string)$amount);
    if (!preg_match('/^(?:0|[1-9][0-9]{0,6})(?:\.([0-9]{1,2}))?$/', $value, $matches)) {
        throw new RuntimeException('The stored payment amount is invalid.');
    }
    $fraction = str_pad((string)($matches[1] ?? ''), 2, '0');
    return ((int)strtok($value, '.')) * 100 + (int)$fraction;
}

function pm_verify_webhook_signature(string $payload, string $header): bool
{
    $webhookSecret = trim((string)getenv('PAYMONGO_WEBHOOK_SECRET'));
    if ($webhookSecret === '' && defined('PAYMONGO_WEBHOOK_SECRET')) {
        $webhookSecret = trim((string)constant('PAYMONGO_WEBHOOK_SECRET'));
    }
    if ($webhookSecret === '') {
        throw new RuntimeException('The PayMongo webhook secret is not configured.');
    }

    $parts = [];
    foreach (explode(',', $header) as $segment) {
        $pair = explode('=', trim($segment), 2);
        if (count($pair) === 2) {
            $parts[trim($pair[0])] = trim($pair[1]);
        }
    }
    $timestamp = (string)($parts['t'] ?? '');
    $signatureField = str_starts_with(PAYMONGO_SECRET_KEY, 'sk_live_') ? 'li' : 'te';
    $signature = strtolower((string)($parts[$signatureField] ?? ''));
    if (!preg_match('/^[0-9]{1,20}$/', $timestamp)
        || !preg_match('/^[a-f0-9]{64}$/', $signature)) {
        return false;
    }

    $expected = hash_hmac('sha256', $timestamp . '.' . $payload, $webhookSecret);
    return hash_equals($expected, $signature);
}

/** @return array<string, mixed> */
function pm_pending_payment(mysqli $conn, string $checkoutId): array
{
    $statement = pm_prepare(
        $conn,
        'SELECT * FROM pending_payments WHERE checkout_id = ? LIMIT 1'
    );
    $statement->bind_param('s', $checkoutId);
    $statement->execute();
    $payment = $statement->get_result()->fetch_assoc();
    $statement->close();
    if (!is_array($payment)) {
        throw new RuntimeException('Payment request not found.');
    }
    return $payment;
}

/** @return array<string, mixed> */
function pm_retrieve_checkout_session(string $checkoutId): array
{
    $curl = curl_init();
    if ($curl === false) {
        throw new RuntimeException('Payment verification is unavailable.');
    }
    curl_setopt_array($curl, [
        CURLOPT_URL => 'https://api.paymongo.com/v1/checkout_sessions/' . rawurlencode($checkoutId),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_HTTPGET => true,
        CURLOPT_CONNECTTIMEOUT => 10,
        CURLOPT_TIMEOUT => 25,
        CURLOPT_HTTPHEADER => [
            'Accept: application/json',
            'Authorization: Basic ' . base64_encode(PAYMONGO_SECRET_KEY . ':'),
        ],
    ]);
    $response = curl_exec($curl);
    $status = (int)curl_getinfo($curl, CURLINFO_RESPONSE_CODE);
    $error = curl_error($curl);
    curl_close($curl);

    if (!is_string($response) || $response === '' || $status !== 200) {
        error_log('PayMongo checkout verification failed: HTTP ' . $status . ' ' . $error);
        throw new RuntimeException('PayMongo has not confirmed this payment.');
    }
    $decoded = json_decode($response, true);
    if (!is_array($decoded)) {
        throw new RuntimeException('PayMongo returned an invalid verification response.');
    }
    return $decoded;
}

function pm_verify_paid_checkout(array $pending, array $session): array
{
    $checkoutId = (string)($pending['checkout_id'] ?? '');
    $resource = $session['data'] ?? null;
    if (!is_array($resource) || !hash_equals($checkoutId, (string)($resource['id'] ?? ''))) {
        throw new RuntimeException('The checkout verification did not match this payment.');
    }
    $attributes = $resource['attributes'] ?? null;
    if (!is_array($attributes)) {
        throw new RuntimeException('The checkout verification is incomplete.');
    }

    $expectedReferenceHash = trim((string)($pending['callback_token_hash'] ?? ''));
    $remoteReference = trim((string)($attributes['reference_number'] ?? ''));
    if ($expectedReferenceHash !== ''
        && !hash_equals($expectedReferenceHash, hash('sha256', $remoteReference))) {
        throw new RuntimeException('The checkout reference does not match the payment request.');
    }

    $metadata = $attributes['metadata'] ?? null;
    if ($expectedReferenceHash !== '') {
        if (!is_array($metadata)) {
            throw new RuntimeException('The checkout metadata is incomplete.');
        }
        $expectedParent = (string)($pending['parent_id'] ?? '');
        $expectedStudent = (string)($pending['student_num'] ?? '');
        $expectedMethod = (string)($pending['method'] ?? '');
        $expectedAmount = number_format(
            pm_amount_centavos($pending['amount'] ?? '') / 100,
            2,
            '.',
            ''
        );
        if (!isset($metadata['parent_id'])
            || !hash_equals($expectedParent, (string)$metadata['parent_id'])) {
            throw new RuntimeException('The checkout parent does not match the payment request.');
        }
        if (!isset($metadata['child_id'])
            || !hash_equals($expectedStudent, (string)$metadata['child_id'])) {
            throw new RuntimeException('The checkout student does not match the payment request.');
        }
        if (!isset($metadata['method'])
            || !hash_equals($expectedMethod, (string)$metadata['method'])) {
            throw new RuntimeException('The checkout method does not match the payment request.');
        }
        if (!isset($metadata['amount'])
            || !hash_equals($expectedAmount, (string)$metadata['amount'])) {
            throw new RuntimeException('The checkout amount does not match the payment request.');
        }
        if (!isset($metadata['callback_reference'])
            || !hash_equals(
                $expectedReferenceHash,
                hash('sha256', (string)$metadata['callback_reference'])
            )) {
            throw new RuntimeException('The checkout callback does not match the payment request.');
        }
    }

    $payments = [];
    if (isset($attributes['payments']) && is_array($attributes['payments'])) {
        $payments = $attributes['payments'];
    }
    $intentPayments = $attributes['payment_intent']['attributes']['payments'] ?? null;
    if (is_array($intentPayments)) {
        $payments = array_merge($payments, $intentPayments);
    }

    $expectedCentavos = pm_amount_centavos($pending['amount'] ?? '');
    foreach ($payments as $payment) {
        if (!is_array($payment)) {
            continue;
        }
        $paymentAttributes = $payment['attributes'] ?? null;
        if (!is_array($paymentAttributes)
            || strtolower((string)($paymentAttributes['status'] ?? '')) !== 'paid') {
            continue;
        }
        $remoteAmount = (int)($paymentAttributes['amount'] ?? 0);
        $currency = strtoupper((string)($paymentAttributes['currency'] ?? ''));
        $providerPaymentId = trim((string)($payment['id'] ?? ''));
        if ($expectedCentavos <= 0
            || $remoteAmount !== $expectedCentavos
            || $currency !== 'PHP'
            || !preg_match('/^pay_[A-Za-z0-9_-]{8,96}$/', $providerPaymentId)) {
            continue;
        }
        return [
            'provider_payment_id' => $providerPaymentId,
            'amount_centavos' => $remoteAmount,
        ];
    }

    throw new RuntimeException('PayMongo has not confirmed a matching paid transaction.');
}

/**
 * Credit a verified checkout exactly once.
 *
 * @return array<string, mixed>
 */
function pm_fulfill_verified_checkout(
    mysqli $conn,
    string $checkoutId,
    string $providerPaymentId,
    int $verifiedAmountCentavos
): array {
    $transactionStarted = false;
    try {
        if (!$conn->begin_transaction()) {
            throw new RuntimeException('The payment could not be started.');
        }
        $transactionStarted = true;

        $pendingStatement = pm_prepare(
            $conn,
            'SELECT * FROM pending_payments WHERE checkout_id = ? LIMIT 1 FOR UPDATE'
        );
        $pendingStatement->bind_param('s', $checkoutId);
        $pendingStatement->execute();
        $pending = $pendingStatement->get_result()->fetch_assoc();
        $pendingStatement->close();
        if (!is_array($pending)) {
            throw new RuntimeException('Payment request not found.');
        }

        if (strtolower((string)$pending['status']) === 'completed') {
            $transactionId = (int)($pending['transaction_id'] ?? 0);
            if ($transactionId <= 0) {
                throw new RuntimeException('This legacy payment needs administrator review.');
            }
            $conn->commit();
            $transactionStarted = false;
            return [
                'transaction_id' => $transactionId,
                'parent_id' => (string)$pending['parent_id'],
                'student_num' => (string)$pending['student_num'],
                'amount' => number_format((float)$pending['amount'], 2, '.', ''),
                'method' => (string)$pending['method'],
                'already_completed' => true,
            ];
        }
        if (strtolower((string)$pending['status']) !== 'pending') {
            throw new RuntimeException('This payment request is no longer pending.');
        }

        $parentId = trim((string)$pending['parent_id']);
        $studentNumber = trim((string)$pending['student_num']);
        $amountCentavos = pm_amount_centavos($pending['amount'] ?? '');
        $amount = number_format($amountCentavos / 100, 2, '.', '');
        $method = trim((string)$pending['method']);
        if (!in_array($method, ['GCash', 'Maya'], true)
            || $amountCentavos !== $verifiedAmountCentavos
            || $amountCentavos <= 0) {
            throw new RuntimeException('The verified payment details are invalid.');
        }

        $parent = pm_prepare(
            $conn,
            'SELECT 1 FROM parents WHERE parent_id = ? LIMIT 1 FOR UPDATE'
        );
        $parent->bind_param('s', $parentId);
        $parent->execute();
        $parentExists = $parent->get_result()->fetch_row() !== null;
        $parent->close();
        if (!$parentExists) {
            throw new RuntimeException('The parent account no longer exists.');
        }

        $student = pm_prepare(
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

        $updateStudent = pm_prepare(
            $conn,
            'UPDATE students SET balance = balance + ? WHERE student_num = ?'
        );
        $updateStudent->bind_param('ss', $amount, $studentNumber);
        if (!$updateStudent->execute() || $updateStudent->affected_rows !== 1) {
            $updateStudent->close();
            throw new RuntimeException('The student wallet could not be updated.');
        }
        $updateStudent->close();

        $balanceStatement = pm_prepare(
            $conn,
            'SELECT balance FROM students WHERE student_num = ? LIMIT 1'
        );
        $balanceStatement->bind_param('s', $studentNumber);
        $balanceStatement->execute();
        $balanceRow = $balanceStatement->get_result()->fetch_assoc();
        $balanceStatement->close();
        if (!is_array($balanceRow)) {
            throw new RuntimeException('The updated student wallet could not be read.');
        }
        $newBalance = number_format((float)$balanceRow['balance'], 2, '.', '');

        $topup = pm_prepare(
            $conn,
            "INSERT INTO topups (parent_id, student_num, amount, method, status, date_time) "
                . "VALUES (?, ?, ?, ?, 'Completed', NOW())"
        );
        $topup->bind_param('ssss', $parentId, $studentNumber, $amount, $method);
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
        $transaction = pm_prepare(
            $conn,
            "INSERT INTO transactions "
                . "(student_num, amount, transaction_type, description, "
                . "processor_role, processor_account_source, processor_id, date_time) "
                . "VALUES (?, ?, 'top-up', ?, 'parent', 'parents', ?, NOW())"
        );
        $transaction->bind_param('ssss', $studentNumber, $amount, $description, $parentId);
        if (!$transaction->execute()) {
            $transaction->close();
            throw new RuntimeException('The wallet transaction could not be recorded.');
        }
        $transactionId = (int)$conn->insert_id;
        $transaction->close();
        if ($transactionId <= 0) {
            throw new RuntimeException('The wallet transaction ID is unavailable.');
        }

        $linkTopup = pm_prepare(
            $conn,
            'UPDATE topups SET transaction_id = ? '
                . 'WHERE topup_id = ? AND transaction_id IS NULL'
        );
        $linkTopup->bind_param('ii', $transactionId, $topupId);
        if (!$linkTopup->execute() || $linkTopup->affected_rows !== 1) {
            $linkTopup->close();
            throw new RuntimeException('The top-up receipt link could not be created.');
        }
        $linkTopup->close();

        $complete = pm_prepare(
            $conn,
            "UPDATE pending_payments SET status = 'completed', transaction_id = ?, "
                . 'provider_payment_id = ?, completed_at = NOW(6) '
                . "WHERE id = ? AND status = 'pending'"
        );
        $pendingId = (int)$pending['id'];
        $complete->bind_param('isi', $transactionId, $providerPaymentId, $pendingId);
        if (!$complete->execute() || $complete->affected_rows !== 1) {
            $complete->close();
            throw new RuntimeException('The payment could not be finalized.');
        }
        $complete->close();

        if (!$conn->commit()) {
            throw new RuntimeException('The payment could not be committed.');
        }
        $transactionStarted = false;
        return [
            'transaction_id' => $transactionId,
            'parent_id' => $parentId,
            'student_num' => $studentNumber,
            'amount' => $amount,
            'method' => $method,
            'new_balance' => $newBalance,
            'already_completed' => false,
        ];
    } catch (Throwable $error) {
        if ($transactionStarted) {
            $conn->rollback();
        }
        throw $error;
    }
}

/** @return array<string, mixed> */
function pm_verify_and_fulfill(mysqli $conn, string $checkoutId): array
{
    $checkoutId = pm_checkout_id($checkoutId);
    $pending = pm_pending_payment($conn, $checkoutId);
    if (strtolower((string)$pending['status']) === 'completed'
        && (int)($pending['transaction_id'] ?? 0) > 0) {
        return pm_fulfill_verified_checkout(
            $conn,
            $checkoutId,
            (string)($pending['provider_payment_id'] ?? ''),
            pm_amount_centavos($pending['amount'] ?? '')
        );
    }
    $session = pm_retrieve_checkout_session($checkoutId);
    $verified = pm_verify_paid_checkout($pending, $session);
    return pm_fulfill_verified_checkout(
        $conn,
        $checkoutId,
        $verified['provider_payment_id'],
        $verified['amount_centavos']
    );
}
