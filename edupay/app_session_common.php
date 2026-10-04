<?php

declare(strict_types=1);

require_once __DIR__ . '/password_change_common.php';

const AS_SESSION_TTL_SECONDS = 43200;
const AS_SESSION_IDLE_TIMEOUT_SECONDS = 300;
const AS_MAX_ACTIVITY_METADATA_BYTES = 8192;

function as_require_secure_transport(): void
{
    if (pc_uses_secure_or_local_transport()) return;

    pc_reject('This request requires a secure HTTPS connection.');
}

function as_normalize_device_id(string $deviceId): string
{
    $deviceId = trim($deviceId);
    if (strlen($deviceId) < 8
        || strlen($deviceId) > 191
        || preg_match('/^[A-Za-z0-9][A-Za-z0-9._:-]{7,190}$/D', $deviceId) !== 1
    ) {
        pc_reject('A valid device installation ID is required.');
    }
    return $deviceId;
}

function as_device_id_hash(string $deviceId): string
{
    return hash('sha256', as_normalize_device_id($deviceId));
}

/** @return array{token:string,hash:string} */
function as_new_session_token(): array
{
    $token = rtrim(strtr(base64_encode(random_bytes(32)), '+/', '-_'), '=');
    return ['token' => $token, 'hash' => hash('sha256', $token)];
}

function as_session_token_hash(string $token): string
{
    if (preg_match('/^[A-Za-z0-9_-]{40,200}$/D', $token) !== 1) {
        as_reject_session('session_invalid', 'Your session is invalid. Please log in again.');
    }
    return hash('sha256', $token);
}

function as_authorization_header(): string
{
    foreach (['HTTP_AUTHORIZATION', 'REDIRECT_HTTP_AUTHORIZATION'] as $key) {
        $value = $_SERVER[$key] ?? '';
        if (is_string($value) && trim($value) !== '') {
            return trim($value);
        }
    }

    if (function_exists('getallheaders')) {
        $headers = getallheaders();
        if (is_array($headers)) {
            foreach ($headers as $name => $value) {
                if (strcasecmp((string)$name, 'Authorization') === 0 && is_string($value)) {
                    return trim($value);
                }
            }
        }
    }
    return '';
}

function as_request_session_token(): string
{
    $authorization = as_authorization_header();
    if ($authorization !== '') {
        if (preg_match('/^Bearer\s+([A-Za-z0-9_-]{40,200})$/iD', $authorization, $matches) !== 1) {
            as_reject_session('session_invalid', 'Your session is invalid. Please log in again.');
        }
        return (string)$matches[1];
    }

    $fallback = pc_post_string('session_token');
    if ($fallback === '') {
        as_reject_session('session_invalid', 'Your session is missing. Please log in again.');
    }
    return $fallback;
}

function as_reject_session(string $code, string $message): void
{
    if (!headers_sent()) {
        http_response_code(401);
        header('WWW-Authenticate: Bearer');
    }
    pc_reject($message, ['code' => $code]);
}

/** @param array<string, mixed> $session */
function as_assert_session_identity(
    array $session,
    string $role,
    string $userId,
    ?string $accountSource = null
): void {
    $role = pc_normalize_role($role);
    pc_validate_user_id($userId);
    $matches = hash_equals((string)$session['role'], $role)
        && hash_equals((string)$session['user_id'], $userId)
        && ($accountSource === null
            || hash_equals((string)$session['account_source'], $accountSource));
    if (!$matches) {
        if (!headers_sent()) {
            http_response_code(403);
        }
        pc_reject('This session cannot act on the requested account.', [
            'code' => 'session_forbidden',
        ]);
    }
}

/**
 * @param array<string, mixed> $session
 * @param list<string> $allowedRoles
 */
function as_assert_session_role(array $session, array $allowedRoles): void
{
    if (!in_array((string)$session['role'], $allowedRoles, true)) {
        if (!headers_sent()) {
            http_response_code(403);
        }
        pc_reject('This account is not allowed to perform that action.', [
            'code' => 'session_forbidden',
        ]);
    }
}

function as_assert_tables(mysqli $conn): void
{
    foreach (['app_sessions', 'app_session_accounts', 'app_activity_events'] as $table) {
        if (!pc_table_exists($conn, $table)) {
            throw new RuntimeException('The app-session database migration has not been applied.');
        }
    }
}

/** @param array<string, mixed> $config */
function as_request_ip_hash(array $config): string
{
    $address = trim((string)($_SERVER['REMOTE_ADDR'] ?? 'unknown'));
    if ($address === '') {
        $address = 'unknown';
    }
    return hash_hmac(
        'sha256',
        'app-session-ip' . "\0" . $address,
        pc_derived_key($config, 'app-session-audit')
    );
}

function as_user_agent(): string
{
    $value = (string)($_SERVER['HTTP_USER_AGENT'] ?? '');
    $printable = preg_replace('/[^\x20-\x7E]/', '?', $value);
    return substr(is_string($printable) ? $printable : '', 0, 255);
}

function as_request_route(): string
{
    $uri = (string)($_SERVER['REQUEST_URI'] ?? '');
    $path = parse_url($uri, PHP_URL_PATH);
    if (!is_string($path)) {
        $path = '';
    }
    return substr($path, 0, 191);
}

function as_valid_event_name(string $eventName): string
{
    $eventName = strtolower(trim($eventName));
    if (preg_match('/^[a-z][a-z0-9_.:-]{1,63}$/D', $eventName) !== 1) {
        pc_reject('A valid activity event name is required.');
    }
    return $eventName;
}

function as_utf8_truncate(string $value, int $maximumBytes): string
{
    if (strlen($value) <= $maximumBytes) {
        return $value;
    }
    if (function_exists('mb_strcut')) {
        return mb_strcut($value, 0, $maximumBytes, 'UTF-8');
    }
    $truncated = substr($value, 0, $maximumBytes);
    while ($truncated !== '' && preg_match('//u', $truncated) !== 1) {
        $truncated = substr($truncated, 0, -1);
    }
    return $truncated;
}

/** @return mixed */
function as_sanitize_metadata_value($value, string $key = '', int $depth = 0)
{
    if ($key !== ''
        && preg_match('/password|passcode|pin|otp|token|secret|authorization|credential/i', $key) === 1
    ) {
        return '[redacted]';
    }
    if ($depth >= 4) {
        return '[depth-limited]';
    }
    if ($value === null || is_bool($value) || is_int($value) || is_float($value)) {
        return $value;
    }
    if (is_string($value)) {
        $clean = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]/', '', $value);
        return as_utf8_truncate(is_string($clean) ? $clean : '', 500);
    }
    if (is_array($value)) {
        $clean = [];
        $count = 0;
        foreach ($value as $childKey => $childValue) {
            if ($count >= 30) {
                $clean['_truncated'] = true;
                break;
            }
            $normalizedKey = is_int($childKey)
                ? $childKey
                : as_utf8_truncate((string)$childKey, 80);
            $clean[$normalizedKey] = as_sanitize_metadata_value(
                $childValue,
                is_int($childKey) ? '' : (string)$childKey,
                $depth + 1
            );
            $count++;
        }
        return $clean;
    }
    return as_utf8_truncate((string)$value, 500);
}

/** @param mixed $metadata */
function as_metadata_json($metadata): ?string
{
    if ($metadata === null || $metadata === '' || $metadata === []) {
        return null;
    }
    if (is_string($metadata)) {
        if (strlen($metadata) > AS_MAX_ACTIVITY_METADATA_BYTES) {
            pc_reject('Activity metadata is too large.');
        }
        try {
            $metadata = json_decode($metadata, true, 16, JSON_THROW_ON_ERROR);
        } catch (JsonException $error) {
            pc_reject('Activity metadata must be valid JSON.');
        }
    }
    if (!is_array($metadata)) {
        pc_reject('Activity metadata must be a JSON object or array.');
    }
    $sanitized = as_sanitize_metadata_value($metadata);
    $encoded = json_encode($sanitized, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
    if (!is_string($encoded)) {
        throw new RuntimeException('Activity metadata could not be encoded.');
    }
    return $encoded;
}

/**
 * @param array<string, mixed> $session
 * @param mixed $metadata
 */
function as_record_activity(
    mysqli $conn,
    array $session,
    string $eventName,
    $metadata = null,
    string $eventSource = 'server',
    string $eventStatus = 'success',
    ?array $config = null
): int {
    $eventName = as_valid_event_name($eventName);
    if (!in_array($eventSource, ['server', 'client'], true)) {
        throw new RuntimeException('Invalid activity source.');
    }
    if (!in_array($eventStatus, ['success', 'info', 'failure', 'cancelled'], true)) {
        throw new RuntimeException('Invalid activity status.');
    }
    $config = $config ?? pc_security_config();
    $metadataJson = as_metadata_json($metadata);
    $route = as_request_route();
    $ipHash = as_request_ip_hash($config);
    $userAgent = as_user_agent();
    $sessionId = isset($session['session_id']) ? (int)$session['session_id'] : null;
    $role = (string)$session['role'];
    $accountSource = (string)$session['account_source'];
    $userId = (string)$session['user_id'];

    $statement = pc_prepare(
        $conn,
        'INSERT INTO app_activity_events '
            . '(session_id, role, account_source, user_id, event_name, event_source, '
            . 'event_status, route, metadata_json, request_ip_hash, user_agent) '
            . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );
    $statement->bind_param(
        'issssssssss',
        $sessionId,
        $role,
        $accountSource,
        $userId,
        $eventName,
        $eventSource,
        $eventStatus,
        $route,
        $metadataJson,
        $ipHash,
        $userAgent
    );
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('App activity could not be recorded.');
    }
    $eventId = (int)$statement->insert_id;
    $statement->close();
    return $eventId;
}

/**
 * Issue inside the caller's database transaction.
 *
 * @param array<string, mixed> $config
 * @return array{session_token:string,session_expires_at:string,session_expires_in:int,expires_in:int,session_idle_timeout_seconds:int,session_idle_expires_at:string,session_idle_expires_in:int,session_id:int}
 */
function as_issue_session(
    mysqli $conn,
    array $config,
    string $role,
    string $accountSource,
    string $userId,
    string $deviceId,
    string $passwordCredential,
    string $authenticationMethod
): array {
    as_assert_tables($conn);
    $role = pc_normalize_role($role);
    pc_validate_user_id($userId);
    pc_target_for_source($role, $accountSource);
    $deviceId = as_normalize_device_id($deviceId);
    $deviceIdHash = as_device_id_hash($deviceId);
    ['token' => $token, 'hash' => $tokenHash] = as_new_session_token();
    $accountFingerprint = pc_account_fingerprint(
        $role,
        $accountSource,
        $userId,
        $passwordCredential,
        $config
    );
    $requestIpHash = as_request_ip_hash($config);
    $userAgent = as_user_agent();

    $claim = pc_prepare(
        $conn,
        'INSERT INTO app_session_accounts '
            . '(role, account_source, user_id, current_session_id) VALUES (?, ?, ?, NULL) '
            . 'ON DUPLICATE KEY UPDATE current_session_id = current_session_id'
    );
    $claim->bind_param('sss', $role, $accountSource, $userId);
    if (!$claim->execute()) {
        $claim->close();
        throw new RuntimeException('The account session could not be locked.');
    }
    $claim->close();

    $claim = pc_prepare(
        $conn,
        'SELECT current_session_id FROM app_session_accounts '
            . 'WHERE role = ? AND account_source = ? AND user_id = ? FOR UPDATE'
    );
    $claim->bind_param('sss', $role, $accountSource, $userId);
    $claim->execute();
    $claimRow = $claim->get_result()->fetch_assoc();
    $claim->close();
    if (!is_array($claimRow)) {
        throw new RuntimeException('The account session lock is unavailable.');
    }
    $previousSessionId = $claimRow['current_session_id'] === null
        ? null
        : (int)$claimRow['current_session_id'];

    if ($previousSessionId !== null) {
        $revoke = pc_prepare(
            $conn,
            "UPDATE app_sessions SET revocation_reason = CASE WHEN revoked_at IS NULL THEN 'replaced' "
                . 'ELSE revocation_reason END, revoked_at = COALESCE(revoked_at, NOW(6)) '
                . 'WHERE session_id = ?'
        );
        $revoke->bind_param('i', $previousSessionId);
        $revoke->execute();
        $revoke->close();
    }

    $ttl = AS_SESSION_TTL_SECONDS;
    $insert = pc_prepare(
        $conn,
        'INSERT INTO app_sessions '
            . '(token_hash, role, account_source, user_id, device_id_hash, account_fingerprint, '
            . 'request_ip_hash, user_agent, expires_at) '
            . "VALUES (?, ?, ?, ?, ?, ?, ?, ?, DATE_ADD(NOW(6), INTERVAL {$ttl} SECOND))"
    );
    $insert->bind_param(
        'ssssssss',
        $tokenHash,
        $role,
        $accountSource,
        $userId,
        $deviceIdHash,
        $accountFingerprint,
        $requestIpHash,
        $userAgent
    );
    if (!$insert->execute()) {
        $insert->close();
        throw new RuntimeException('A secure app session could not be created.');
    }
    $sessionId = (int)$insert->insert_id;
    $insert->close();

    $updateClaim = pc_prepare(
        $conn,
        'UPDATE app_session_accounts SET current_session_id = ? '
            . 'WHERE role = ? AND account_source = ? AND user_id = ?'
    );
    $updateClaim->bind_param('isss', $sessionId, $role, $accountSource, $userId);
    if (!$updateClaim->execute() || $updateClaim->affected_rows !== 1) {
        $updateClaim->close();
        throw new RuntimeException('The secure app session could not be activated.');
    }
    $updateClaim->close();

    if ($previousSessionId !== null) {
        $replacement = pc_prepare(
            $conn,
            'UPDATE app_sessions SET replaced_by_session_id = ? WHERE session_id = ?'
        );
        $replacement->bind_param('ii', $sessionId, $previousSessionId);
        $replacement->execute();
        $replacement->close();
        as_record_activity(
            $conn,
            [
                'session_id' => $previousSessionId,
                'role' => $role,
                'account_source' => $accountSource,
                'user_id' => $userId,
            ],
            'session_replaced',
            ['replacement_session_id' => $sessionId],
            'server',
            'info',
            $config
        );
    }

    $session = [
        'session_id' => $sessionId,
        'role' => $role,
        'account_source' => $accountSource,
        'user_id' => $userId,
    ];
    as_record_activity(
        $conn,
        $session,
        'login_success',
        [
            'authentication_method' => $authenticationMethod,
            'replaced_previous_session' => $previousSessionId !== null,
        ],
        'server',
        'success',
        $config
    );

    $idleTimeout = AS_SESSION_IDLE_TIMEOUT_SECONDS;
    $expiry = pc_prepare(
        $conn,
        'SELECT UNIX_TIMESTAMP(expires_at) AS expires_epoch, '
            . "UNIX_TIMESTAMP(DATE_ADD(last_seen_at, INTERVAL {$idleTimeout} SECOND)) "
            . 'AS idle_expires_epoch FROM app_sessions WHERE session_id = ?'
    );
    $expiry->bind_param('i', $sessionId);
    $expiry->execute();
    $expiryRow = $expiry->get_result()->fetch_assoc();
    $expiry->close();
    $expiresEpoch = (int)($expiryRow['expires_epoch'] ?? (time() + AS_SESSION_TTL_SECONDS));
    $idleExpiresEpoch = (int)($expiryRow['idle_expires_epoch'] ?? (time() + AS_SESSION_IDLE_TIMEOUT_SECONDS));

    return [
        'session_token' => $token,
        'session_expires_at' => gmdate(DATE_ATOM, $expiresEpoch),
        'session_expires_in' => max(0, $expiresEpoch - time()),
        'expires_in' => max(0, $expiresEpoch - time()),
        'session_idle_timeout_seconds' => AS_SESSION_IDLE_TIMEOUT_SECONDS,
        'session_idle_expires_at' => gmdate(DATE_ATOM, $idleExpiresEpoch),
        'session_idle_expires_in' => max(0, $idleExpiresEpoch - time()),
        'session_id' => $sessionId,
    ];
}

/**
 * @param array<string, mixed> $issued
 * @return array{session_token:string,session_expires_at:string,session_expires_in:int,expires_in:int,session_idle_timeout_seconds:int,session_idle_expires_at:string,session_idle_expires_in:int}
 */
function as_public_session_payload(array $issued): array
{
    return [
        'session_token' => (string)$issued['session_token'],
        'session_expires_at' => (string)$issued['session_expires_at'],
        'session_expires_in' => (int)$issued['session_expires_in'],
        'expires_in' => (int)$issued['expires_in'],
        'session_idle_timeout_seconds' => (int)$issued['session_idle_timeout_seconds'],
        'session_idle_expires_at' => (string)$issued['session_idle_expires_at'],
        'session_idle_expires_in' => (int)$issued['session_idle_expires_in'],
    ];
}

/** @param array<string, mixed> $session */
function as_mark_session_revoked(
    mysqli $conn,
    array $session,
    string $reason,
    ?array $config = null
): void {
    $sessionId = (int)$session['session_id'];
    $statement = pc_prepare(
        $conn,
        'UPDATE app_sessions SET '
            . 'revocation_reason = CASE WHEN revoked_at IS NULL THEN ? ELSE revocation_reason END, '
            . 'revoked_at = COALESCE(revoked_at, NOW(6)) '
            . 'WHERE session_id = ?'
    );
    $statement->bind_param('si', $reason, $sessionId);
    $statement->execute();
    $statement->close();

    $claim = pc_prepare(
        $conn,
        'UPDATE app_session_accounts SET current_session_id = NULL '
            . 'WHERE role = ? AND account_source = ? AND user_id = ? AND current_session_id = ?'
    );
    $role = (string)$session['role'];
    $accountSource = (string)$session['account_source'];
    $userId = (string)$session['user_id'];
    $claim->bind_param('sssi', $role, $accountSource, $userId, $sessionId);
    $claim->execute();
    $claim->close();

    $eventName = match ($reason) {
        'logout' => 'logout',
        'idle_timeout', 'inactivity_timeout' => 'inactivity_timeout',
        'login_page_opened' => 'login_page_opened',
        default => 'session_revoked',
    };
    as_record_activity(
        $conn,
        $session,
        $eventName,
        ['reason' => $reason],
        'server',
        'info',
        $config
    );
}

/** @return array<string, mixed> */
function as_require_session(mysqli $conn, bool $touch = true): array
{
    as_require_secure_transport();
    as_assert_tables($conn);
    $tokenHash = as_session_token_hash(as_request_session_token());
    $idleTimeout = AS_SESSION_IDLE_TIMEOUT_SECONDS;
    $statement = pc_prepare(
        $conn,
        'SELECT *, (expires_at <= NOW(6)) AS session_expired, '
            . "(last_seen_at <= DATE_SUB(NOW(6), INTERVAL {$idleTimeout} SECOND)) AS idle_expired, "
            . 'UNIX_TIMESTAMP(expires_at) AS expires_epoch, '
            . "UNIX_TIMESTAMP(DATE_ADD(last_seen_at, INTERVAL {$idleTimeout} SECOND)) "
            . 'AS idle_expires_epoch '
            . 'FROM app_sessions WHERE token_hash = ? LIMIT 1'
    );
    $statement->bind_param('s', $tokenHash);
    $statement->execute();
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    if (!is_array($row)) {
        as_reject_session('session_invalid', 'Your session is invalid. Please log in again.');
    }

    $reason = (string)($row['revocation_reason'] ?? '');
    if ($row['revoked_at'] !== null) {
        $expired = in_array($reason, ['expired', 'idle_timeout'], true);
        as_reject_session(
            $reason === 'replaced'
                ? 'session_replaced'
                : ($expired ? 'session_expired' : 'session_invalid'),
            $reason === 'replaced'
                ? 'This account was opened on another device. Please log in again.'
                : ($reason === 'idle_timeout'
                    ? 'Your session expired after 5 minutes of inactivity. Please log in again.'
                    : ($reason === 'expired'
                        ? 'Your session expired. Please log in again.'
                        : 'Your session is no longer active. Please log in again.'))
        );
    }
    if ((int)($row['session_expired'] ?? 1) === 1) {
        as_mark_session_revoked($conn, $row, 'expired');
        as_reject_session('session_expired', 'Your session expired. Please log in again.');
    }
    if ((int)($row['idle_expired'] ?? 1) === 1) {
        as_mark_session_revoked($conn, $row, 'idle_timeout');
        as_reject_session(
            'session_expired',
            'Your session expired after 5 minutes of inactivity. Please log in again.'
        );
    }

    $role = (string)$row['role'];
    $accountSource = (string)$row['account_source'];
    $userId = (string)$row['user_id'];
    // Keep the same account-then-session-claim lock order used by login
    // issuance. FOR UPDATE on the claim makes an in-flight replacement finish
    // before this request is authorized.
    $config = pc_security_config();
    $account = pc_fetch_account_from_source_for_update($conn, $role, $userId, $accountSource);
    if ($account === null) {
        as_mark_session_revoked($conn, $row, 'account_removed', $config);
        as_reject_session('session_invalid', 'Your account is no longer available.');
    }
    $actualFingerprint = pc_account_fingerprint(
        $role,
        $accountSource,
        $userId,
        (string)$account['password_value'],
        $config
    );
    if (!hash_equals((string)$row['account_fingerprint'], $actualFingerprint)) {
        as_mark_session_revoked($conn, $row, 'account_changed', $config);
        as_reject_session('session_invalid', 'Your account security changed. Please log in again.');
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
    if (!is_array($claimRow) || (int)($claimRow['current_session_id'] ?? 0) !== (int)$row['session_id']) {
        as_mark_session_revoked($conn, $row, 'replaced', $config);
        as_reject_session(
            'session_replaced',
            'This account was opened on another device. Please log in again.'
        );
    }

    $lastSeenAt = (string)$row['last_seen_at'];
    $idleExpiresEpoch = (int)($row['idle_expires_epoch'] ?? 0);
    if ($touch) {
        $touchStatement = pc_prepare(
            $conn,
            'UPDATE app_sessions SET last_seen_at = NOW(6) WHERE session_id = ?'
        );
        $sessionId = (int)$row['session_id'];
        $touchStatement->bind_param('i', $sessionId);
        $touchStatement->execute();
        $touchStatement->close();
        $lastSeenAt = gmdate('Y-m-d H:i:s');
        $idleExpiresEpoch = time() + AS_SESSION_IDLE_TIMEOUT_SECONDS;
    }

    $expiresEpoch = (int)($row['expires_epoch'] ?? 0);
    return [
        'session_id' => (int)$row['session_id'],
        'role' => $role,
        'account_source' => $accountSource,
        'user_id' => $userId,
        'issued_at' => (string)$row['issued_at'],
        'last_seen_at' => $lastSeenAt,
        'session_expires_at' => gmdate(DATE_ATOM, $expiresEpoch),
        'session_expires_in' => max(0, $expiresEpoch - time()),
        'expires_in' => max(0, $expiresEpoch - time()),
        'session_idle_timeout_seconds' => AS_SESSION_IDLE_TIMEOUT_SECONDS,
        'session_idle_expires_at' => gmdate(DATE_ATOM, $idleExpiresEpoch),
        'session_idle_expires_in' => max(0, $idleExpiresEpoch - time()),
    ];
}
