<?php

declare(strict_types=1);

require_once __DIR__ . '/app_session_common.php';
require_once __DIR__ . '/receipt_common.php';

const RPT_PRINT_TOKEN_TTL_SECONDS = 120;

function rpt_assert_schema(mysqli $conn): void
{
    if (!pc_table_exists($conn, 'receipt_print_tokens')) {
        throw new RuntimeException('The receipt print-token migration has not been applied.');
    }
}

function rpt_new_plaintext_token(): string
{
    return rtrim(strtr(base64_encode(random_bytes(32)), '+/', '-_'), '=');
}

function rpt_token_hash(string $token): string
{
    $token = trim($token);
    if (preg_match('/^[A-Za-z0-9_-]{43}$/D', $token) !== 1) {
        throw new InvalidArgumentException('This printable receipt link is invalid or expired.');
    }
    return hash('sha256', $token);
}

function rpt_assert_receipt_account_source(
    mysqli $conn,
    int $transactionId,
    string $role,
    string $accountSource,
    string $userId
): void {
    if ($role !== 'cashier') {
        return;
    }

    $statement = pc_prepare(
        $conn,
        'SELECT t.cashier_id, t.processor_role, t.processor_account_source, '
            . 't.processor_id, r.processor_role_snapshot, '
            . 'r.processor_account_source_snapshot, r.processor_id_snapshot '
            . 'FROM transactions t JOIN transaction_receipts r '
            . 'ON r.transaction_id = t.transaction_id '
            . 'WHERE t.transaction_id = ? LIMIT 1'
    );
    $statement->bind_param('i', $transactionId);
    $statement->execute();
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    if (!is_array($row)
        || !hash_equals(trim((string)($row['cashier_id'] ?? '')), $userId)) {
        throw new RuntimeException('This receipt is not available to that account.');
    }

    $processorRole = strtolower(trim((string)($row['processor_role_snapshot'] ?? '')));
    if ($processorRole === '') {
        $processorRole = strtolower(trim((string)($row['processor_role'] ?? '')));
    }
    $processorSource = strtolower(trim(
        (string)($row['processor_account_source_snapshot'] ?? '')
    ));
    if ($processorSource === '') {
        $processorSource = strtolower(trim(
            (string)($row['processor_account_source'] ?? '')
        ));
    }
    $processorId = trim((string)($row['processor_id_snapshot'] ?? ''));
    if ($processorId === '') {
        $processorId = trim((string)($row['processor_id'] ?? ''));
    }
    if ($processorRole === 'cashier'
        && hash_equals($processorId, $userId)
        && $processorSource !== '') {
        if (!hash_equals($processorSource, $accountSource)) {
            throw new RuntimeException('This receipt is not available to that account.');
        }
        return;
    }

    $accounts = pc_prepare(
        $conn,
        'SELECT '
            . '(SELECT COUNT(*) FROM cashiers WHERE cashier_id = ?) AS dedicated_count, '
            . '(SELECT COUNT(*) FROM admins WHERE admin_id = ? '
            . "AND LOWER(COALESCE(role, '')) = 'cashier') AS legacy_count"
    );
    $accounts->bind_param('ss', $userId, $userId);
    $accounts->execute();
    $counts = $accounts->get_result()->fetch_assoc();
    $accounts->close();
    $dedicatedCount = (int)($counts['dedicated_count'] ?? 0);
    $legacyCount = (int)($counts['legacy_count'] ?? 0);
    $sourceMatches = ($accountSource === 'cashiers' && $dedicatedCount === 1)
        || ($accountSource === 'admins' && $legacyCount === 1);
    if (!$sourceMatches || ($dedicatedCount + $legacyCount) !== 1) {
        throw new RuntimeException('This receipt is not available to that account.');
    }
}

/** @return array<string, mixed> */
function rpt_fetch_receipt_for_identity(
    mysqli $conn,
    int $transactionId,
    string $role,
    string $accountSource,
    string $userId
): array {
    $role = pc_normalize_role($role);
    $accountSource = strtolower(trim($accountSource));
    pc_target_for_source($role, $accountSource);
    pc_validate_user_id($userId);
    rpt_assert_receipt_account_source(
        $conn,
        $transactionId,
        $role,
        $accountSource,
        $userId
    );
    return receipt_fetch($conn, $transactionId, $role, $userId);
}

function rpt_bound_session_is_active(
    mysqli $conn,
    int $sessionId,
    string $role,
    string $accountSource,
    string $userId
): bool {
    if ($sessionId <= 0) {
        return false;
    }

    $claim = pc_prepare(
        $conn,
        'SELECT current_session_id FROM app_session_accounts '
            . 'WHERE role = ? AND account_source = ? AND user_id = ? LIMIT 1 FOR UPDATE'
    );
    $claim->bind_param('sss', $role, $accountSource, $userId);
    $claim->execute();
    $claimRow = $claim->get_result()->fetch_assoc();
    $claim->close();
    if (!is_array($claimRow) || (int)($claimRow['current_session_id'] ?? 0) !== $sessionId) {
        return false;
    }

    $idleTimeout = AS_SESSION_IDLE_TIMEOUT_SECONDS;
    $session = pc_prepare(
        $conn,
        'SELECT 1 FROM app_sessions WHERE session_id = ? AND role = ? '
            . 'AND account_source = ? AND user_id = ? AND revoked_at IS NULL '
            . 'AND expires_at > NOW(6) '
            . "AND last_seen_at > DATE_SUB(NOW(6), INTERVAL {$idleTimeout} SECOND) "
            . 'LIMIT 1 FOR UPDATE'
    );
    $session->bind_param('isss', $sessionId, $role, $accountSource, $userId);
    $session->execute();
    $active = $session->get_result()->fetch_row() !== null;
    $session->close();
    return $active;
}

function rpt_insert_authorized_token(
    mysqli $conn,
    int $transactionId,
    string $role,
    string $accountSource,
    string $userId,
    ?int $sessionId,
    string $authorizationContext
): array {
    rpt_assert_schema($conn);
    $role = pc_normalize_role($role);
    $accountSource = strtolower(trim($accountSource));
    pc_target_for_source($role, $accountSource);
    pc_validate_user_id($userId);
    if (!in_array($authorizationContext, ['app_session', 'verified_payment_callback'], true)) {
        throw new InvalidArgumentException('Invalid receipt authorization context.');
    }
    if ($authorizationContext === 'app_session' && ($sessionId ?? 0) <= 0) {
        throw new InvalidArgumentException('An active app session is required.');
    }
    if ($authorizationContext === 'verified_payment_callback'
        && ($sessionId !== null || $role !== 'parent' || $accountSource !== 'parents')) {
        throw new InvalidArgumentException('Invalid payment callback receipt identity.');
    }

    rpt_fetch_receipt_for_identity(
        $conn,
        $transactionId,
        $role,
        $accountSource,
        $userId
    );

    $revoke = pc_prepare(
        $conn,
        'UPDATE receipt_print_tokens SET revoked_at = NOW(6) '
            . 'WHERE transaction_id = ? AND viewer_role = ? '
            . 'AND viewer_account_source = ? AND viewer_user_id = ? '
            . 'AND consumed_at IS NULL AND revoked_at IS NULL AND expires_at > NOW(6)'
    );
    $revoke->bind_param('isss', $transactionId, $role, $accountSource, $userId);
    $revoke->execute();
    $revoke->close();

    for ($attempt = 0; $attempt < 3; $attempt++) {
        $token = rpt_new_plaintext_token();
        $tokenHash = hash('sha256', $token);
        $insert = pc_prepare(
            $conn,
            'INSERT INTO receipt_print_tokens '
                . '(token_hash, transaction_id, session_id, viewer_role, '
                . 'viewer_account_source, viewer_user_id, authorization_context, expires_at) '
                . 'VALUES (?, ?, ?, ?, ?, ?, ?, '
                . 'DATE_ADD(NOW(6), INTERVAL ' . RPT_PRINT_TOKEN_TTL_SECONDS . ' SECOND))'
        );
        $insert->bind_param(
            'siissss',
            $tokenHash,
            $transactionId,
            $sessionId,
            $role,
            $accountSource,
            $userId,
            $authorizationContext
        );
        $inserted = $insert->execute();
        $errorNumber = $insert->errno;
        $insert->close();
        if ($inserted) {
            return [
                'print_token' => $token,
                'expires_in' => RPT_PRINT_TOKEN_TTL_SECONDS,
            ];
        }
        if ($errorNumber !== 1062) {
            throw new RuntimeException('The printable receipt link could not be created.');
        }
    }
    throw new RuntimeException('The printable receipt link could not be created.');
}

/** @return array{print_token:string,expires_in:int} */
function rpt_issue_for_authenticated_request(mysqli $conn, int $transactionId): array
{
    $session = as_require_session($conn);
    $started = false;
    try {
        if (!$conn->begin_transaction()) {
            throw new RuntimeException('The printable receipt request could not be started.');
        }
        $started = true;
        $sessionId = (int)$session['session_id'];
        $role = (string)$session['role'];
        $accountSource = (string)$session['account_source'];
        $userId = (string)$session['user_id'];
        if (!rpt_bound_session_is_active($conn, $sessionId, $role, $accountSource, $userId)) {
            as_reject_session(
                'session_replaced',
                'This account was opened on another device. Please log in again.'
            );
        }
        $issued = rpt_insert_authorized_token(
            $conn,
            $transactionId,
            $role,
            $accountSource,
            $userId,
            $sessionId,
            'app_session'
        );
        as_record_activity(
            $conn,
            $session,
            'receipt_print_link_issued',
            ['transaction_id' => $transactionId, 'expires_in' => RPT_PRINT_TOKEN_TTL_SECONDS]
        );
        if (!$conn->commit()) {
            throw new RuntimeException('The printable receipt link could not be committed.');
        }
        $started = false;
        return $issued;
    } catch (Throwable $error) {
        if ($started) {
            $conn->rollback();
        }
        throw $error;
    }
}

/** @return array{print_token:string,expires_in:int} */
function rpt_issue_for_verified_parent_callback(
    mysqli $conn,
    int $transactionId,
    string $parentId
): array {
    $started = false;
    try {
        if (!$conn->begin_transaction()) {
            throw new RuntimeException('The printable receipt request could not be started.');
        }
        $started = true;
        $issued = rpt_insert_authorized_token(
            $conn,
            $transactionId,
            'parent',
            'parents',
            trim($parentId),
            null,
            'verified_payment_callback'
        );
        as_record_activity(
            $conn,
            [
                'role' => 'parent',
                'account_source' => 'parents',
                'user_id' => trim($parentId),
            ],
            'receipt_print_link_issued',
            [
                'transaction_id' => $transactionId,
                'authorization_context' => 'verified_payment_callback',
                'expires_in' => RPT_PRINT_TOKEN_TTL_SECONDS,
            ]
        );
        if (!$conn->commit()) {
            throw new RuntimeException('The printable receipt link could not be committed.');
        }
        $started = false;
        return $issued;
    } catch (Throwable $error) {
        if ($started) {
            $conn->rollback();
        }
        throw $error;
    }
}

/** @return array<string, mixed> */
function rpt_consume_print_token(mysqli $conn, string $token): array
{
    rpt_assert_schema($conn);
    $tokenHash = rpt_token_hash($token);

    $lookup = pc_prepare(
        $conn,
        'SELECT session_id, viewer_role, viewer_account_source, viewer_user_id, '
            . 'authorization_context FROM receipt_print_tokens WHERE token_hash = ? LIMIT 1'
    );
    $lookup->bind_param('s', $tokenHash);
    $lookup->execute();
    $identity = $lookup->get_result()->fetch_assoc();
    $lookup->close();
    if (!is_array($identity)) {
        throw new InvalidArgumentException('This printable receipt link is invalid or expired.');
    }

    $started = false;
    try {
        if (!$conn->begin_transaction()) {
            throw new RuntimeException('The printable receipt could not be opened.');
        }
        $started = true;
        $sessionId = $identity['session_id'] === null ? null : (int)$identity['session_id'];
        $role = (string)$identity['viewer_role'];
        $accountSource = (string)$identity['viewer_account_source'];
        $userId = (string)$identity['viewer_user_id'];
        $authorizationContext = (string)$identity['authorization_context'];

        if ($authorizationContext === 'app_session') {
            if ($sessionId === null
                || !rpt_bound_session_is_active(
                    $conn,
                    $sessionId,
                    $role,
                    $accountSource,
                    $userId
                )) {
                throw new InvalidArgumentException(
                    'This printable receipt link is invalid or expired.'
                );
            }
        } elseif ($authorizationContext !== 'verified_payment_callback'
            || $sessionId !== null
            || $role !== 'parent'
            || $accountSource !== 'parents') {
            throw new InvalidArgumentException('This printable receipt link is invalid or expired.');
        }

        $locked = pc_prepare(
            $conn,
            'SELECT token_id, transaction_id, session_id, viewer_role, '
                . 'viewer_account_source, viewer_user_id, authorization_context, '
                . '(expires_at <= NOW(6)) AS expired, consumed_at, revoked_at '
                . 'FROM receipt_print_tokens WHERE token_hash = ? LIMIT 1 FOR UPDATE'
        );
        $locked->bind_param('s', $tokenHash);
        $locked->execute();
        $row = $locked->get_result()->fetch_assoc();
        $locked->close();
        if (!is_array($row)
            || $row['consumed_at'] !== null
            || $row['revoked_at'] !== null
            || (int)($row['expired'] ?? 1) === 1
            || (int)($row['session_id'] ?? 0) !== ($sessionId ?? 0)
            || !hash_equals((string)$row['viewer_role'], $role)
            || !hash_equals((string)$row['viewer_account_source'], $accountSource)
            || !hash_equals((string)$row['viewer_user_id'], $userId)
            || !hash_equals((string)$row['authorization_context'], $authorizationContext)) {
            throw new InvalidArgumentException('This printable receipt link is invalid or expired.');
        }

        $transactionId = (int)$row['transaction_id'];
        $receipt = rpt_fetch_receipt_for_identity(
            $conn,
            $transactionId,
            $role,
            $accountSource,
            $userId
        );
        $consume = pc_prepare(
            $conn,
            'UPDATE receipt_print_tokens SET consumed_at = NOW(6) '
                . 'WHERE token_id = ? AND consumed_at IS NULL AND revoked_at IS NULL '
                . 'AND expires_at > NOW(6)'
        );
        $tokenId = (int)$row['token_id'];
        $consume->bind_param('i', $tokenId);
        $consume->execute();
        $consumed = $consume->affected_rows === 1;
        $consume->close();
        if (!$consumed) {
            throw new InvalidArgumentException('This printable receipt link is invalid or expired.');
        }

        as_record_activity(
            $conn,
            [
                'session_id' => $sessionId,
                'role' => $role,
                'account_source' => $accountSource,
                'user_id' => $userId,
            ],
            'receipt_printed',
            [
                'transaction_id' => $transactionId,
                'authorization_context' => $authorizationContext,
            ]
        );
        if (!$conn->commit()) {
            throw new RuntimeException('The printable receipt could not be committed.');
        }
        $started = false;
        return $receipt;
    } catch (Throwable $error) {
        if ($started) {
            $conn->rollback();
        }
        throw $error;
    }
}
