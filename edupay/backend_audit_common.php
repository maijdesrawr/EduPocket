<?php

declare(strict_types=1);

const BA_MAX_METADATA_BYTES = 16384;
const BA_MAX_METADATA_DEPTH = 6;
const BA_MAX_ARRAY_ITEMS = 50;
const BA_MAX_STRING_BYTES = 512;
const BA_DEFAULT_DATABASE_CONFIG_PATH = 'C:/xampp/edupocket-config/database.php';
const BA_DEFAULT_SECURITY_CONFIG_PATH = 'C:/xampp/edupocket-config/security.php';

/** @return array<string, mixed> */
function ba_state(): array
{
    $state = $GLOBALS['EDUPOCKET_BACKEND_AUDIT_STATE'] ?? null;
    return is_array($state) ? $state : [];
}

/** @param array<string, mixed> $state */
function ba_store_state(array $state): void
{
    $GLOBALS['EDUPOCKET_BACKEND_AUDIT_STATE'] = $state;
}

function ba_is_http_request(): bool
{
    if (getenv('EDUPOCKET_BACKEND_AUDIT_DISABLED') === '1') {
        return false;
    }
    return PHP_SAPI !== 'cli' || getenv('EDUPOCKET_BACKEND_AUDIT_FORCE') === '1';
}

function ba_now(): string
{
    $now = new DateTimeImmutable('now', new DateTimeZone('Asia/Manila'));
    return $now->format('Y-m-d H:i:s.u');
}

function ba_new_request_id(): string
{
    try {
        return bin2hex(random_bytes(16));
    } catch (Throwable $error) {
        return hash('sha256', uniqid('', true) . microtime(true));
    }
}

function ba_register_request_audit(): void
{
    if (!ba_is_http_request()) {
        return;
    }

    $state = ba_state();
    if (($state['registered'] ?? false) === true) {
        return;
    }

    $state['registered'] = true;
    $state['writing'] = false;
    $state['request_id'] = ba_new_request_id();
    $state['started_at'] = ba_now();
    $state['started_monotonic'] = hrtime(true);
    ba_store_state($state);
    register_shutdown_function('ba_write_request_audit');
}

function ba_capture_database_config(
    string $host,
    string $username,
    string $password,
    string $database,
    int $port
): void {
    $state = ba_state();
    if (($state['registered'] ?? false) !== true || isset($state['database'])) {
        return;
    }
    if ($host === '' || $database === '' || $port < 1 || $port > 65535) {
        return;
    }
    $state['database'] = [
        'host' => $host,
        'username' => $username,
        'password' => $password,
        'database' => $database,
        'port' => $port,
    ];
    ba_store_state($state);
}

function ba_mark_outcome(string $outcome): void
{
    $normalized = strtolower(trim($outcome));
    $allowed = [
        'completed',
        'challenge',
        'ignored',
        'application_error',
        'client_error',
        'server_error',
        'redirect',
        'fatal',
    ];
    if (!in_array($normalized, $allowed, true)) {
        return;
    }
    $state = ba_state();
    if (($state['registered'] ?? false) !== true) {
        return;
    }
    $state['marked_outcome'] = $normalized;
    ba_store_state($state);
}

/** @param array<string, mixed> $payload */
function ba_observe_response_payload(array $payload): void
{
    $status = strtolower(trim((string)($payload['status'] ?? '')));
    $success = $payload['success'] ?? null;
    if ($status === 'error' || $status === 'failed' || $success === false) {
        ba_mark_outcome('application_error');
        return;
    }
    if (in_array($status, ['otp_required', 'pending', 'verification_required'], true)) {
        ba_mark_outcome('challenge');
        return;
    }
    if ($status === 'ignored') {
        ba_mark_outcome('ignored');
        return;
    }
    if ($status === 'success' || $status === 'received' || $success === true) {
        ba_mark_outcome('completed');
    }
}

/** @return array<string, mixed>|null */
function ba_load_database_config(): ?array
{
    $state = ba_state();
    if (isset($state['database']) && is_array($state['database'])) {
        return $state['database'];
    }

    $configuredPath = getenv('EDUPOCKET_DATABASE_CONFIG_PATH');
    $path = is_string($configuredPath) && trim($configuredPath) !== ''
        ? trim($configuredPath)
        : BA_DEFAULT_DATABASE_CONFIG_PATH;
    if (!is_file($path)) {
        return null;
    }
    $loaded = @include $path;
    if (!is_array($loaded)) {
        return null;
    }
    $port = filter_var(
        $loaded['port'] ?? 3306,
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1, 'max_range' => 65535]]
    );
    if ($port === false) {
        return null;
    }
    $database = [
        'host' => (string)($loaded['host'] ?? ''),
        'username' => (string)($loaded['username'] ?? ''),
        'password' => (string)($loaded['password'] ?? ''),
        'database' => (string)($loaded['database'] ?? ''),
        'port' => (int)$port,
    ];
    if ($database['host'] === '' || $database['database'] === '') {
        return null;
    }
    return $database;
}

function ba_valid_utf8(string $value): string
{
    if (preg_match('//u', $value) === 1) {
        return $value;
    }
    if (function_exists('iconv')) {
        $converted = @iconv('UTF-8', 'UTF-8//IGNORE', $value);
        if (is_string($converted)) {
            return $converted;
        }
    }
    return '[invalid utf-8 removed]';
}

function ba_limit_text(string $value, int $maxBytes): string
{
    $value = ba_valid_utf8($value);
    if (strlen($value) <= $maxBytes) {
        return $value;
    }
    if (function_exists('mb_strcut')) {
        return mb_strcut($value, 0, $maxBytes, 'UTF-8');
    }
    return substr($value, 0, $maxBytes);
}

function ba_sensitive_key(string $key): bool
{
    $normalized = strtolower(trim($key));
    if ($normalized === '') {
        return false;
    }
    return preg_match(
        '/(?:password|passcode|passwd|pin|otp|code|token|secret|'
            . 'authorization|credential|cookie|session|api[_-]?key|signature|private[_-]?key|'
            . 'csrf|nonce|card|cvv|cvc)/i',
        $normalized
    ) === 1;
}

/** @return mixed */
function ba_sanitize_metadata_value($value, string $key = '', int $depth = 0)
{
    if ($key !== '' && ba_sensitive_key($key)) {
        return '[redacted]';
    }
    if ($depth >= BA_MAX_METADATA_DEPTH) {
        return '[depth limit]';
    }
    if ($value === null) {
        return '[not provided]';
    }
    if (is_bool($value) || is_int($value) || is_float($value)) {
        return $value;
    }
    if (is_string($value)) {
        $trimmed = trim($value);
        if (
            strlen($trimmed) <= 8192
            && $trimmed !== ''
            && (($trimmed[0] ?? '') === '{' || ($trimmed[0] ?? '') === '[')
        ) {
            $decoded = json_decode($trimmed, true, BA_MAX_METADATA_DEPTH);
            if (is_array($decoded)) {
                return ba_sanitize_metadata_value($decoded, '', $depth + 1);
            }
        }
        $withoutBearer = preg_replace(
            '/\bBearer\s+[A-Za-z0-9._~+\/-]{16,}/i',
            'Bearer [redacted]',
            $value
        );
        return ba_limit_text(
            is_string($withoutBearer) ? $withoutBearer : $value,
            BA_MAX_STRING_BYTES
        );
    }
    if (is_array($value)) {
        $clean = [];
        $count = 0;
        foreach ($value as $childKey => $childValue) {
            if ($count >= BA_MAX_ARRAY_ITEMS) {
                $clean['_truncated'] = true;
                break;
            }
            $safeKey = ba_limit_text((string)$childKey, 100);
            $clean[$safeKey] = ba_sanitize_metadata_value(
                $childValue,
                $safeKey,
                $depth + 1
            );
            $count++;
        }
        return $clean;
    }
    return '[' . get_debug_type($value) . ' omitted]';
}

/** @return array<string, mixed> */
function ba_file_metadata(): array
{
    $result = [];
    foreach ($_FILES as $field => $file) {
        if (!is_array($file)) {
            continue;
        }
        $safeField = ba_limit_text((string)$field, 100);
        $result[$safeField] = [
            'size' => ba_sanitize_metadata_value($file['size'] ?? null),
            'type' => ba_limit_text((string)($file['type'] ?? ''), 100),
            'upload_error' => ba_sanitize_metadata_value($file['error'] ?? null),
        ];
    }
    return $result;
}

/** @return array<string, mixed> */
function ba_request_metadata(): array
{
    $contentType = strtolower(trim((string)($_SERVER['CONTENT_TYPE'] ?? '')));
    if (str_contains($contentType, ';')) {
        $contentType = trim(explode(';', $contentType, 2)[0]);
    }
    $metadata = [
        'content_type' => ba_limit_text($contentType, 100),
        'content_length' => max(0, (int)($_SERVER['CONTENT_LENGTH'] ?? 0)),
    ];
    if ($_GET !== []) {
        $metadata['query'] = ba_sanitize_metadata_value($_GET);
    }
    if ($_POST !== []) {
        $metadata['form'] = ba_sanitize_metadata_value($_POST);
    }
    if ($_FILES !== []) {
        $metadata['files'] = ba_file_metadata();
    }

    if (str_contains($contentType, 'json')) {
        $raw = file_get_contents('php://input');
        if (is_string($raw) && $raw !== '') {
            if (strlen($raw) <= 1048576) {
                $decoded = json_decode($raw, true, BA_MAX_METADATA_DEPTH);
                if (is_array($decoded)) {
                    $metadata['json'] = ba_sanitize_metadata_value($decoded);
                } else {
                    $metadata['json'] = ['valid' => false, 'bytes' => strlen($raw)];
                }
            } else {
                $metadata['json'] = ['truncated' => true, 'bytes' => strlen($raw)];
            }
        }
    }

    return $metadata;
}

/** @param array<string, mixed> $metadata */
function ba_metadata_json(array $metadata): string
{
    $json = json_encode(
        $metadata,
        JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_INVALID_UTF8_SUBSTITUTE
    );
    if (!is_string($json)) {
        return '{"omitted":true}';
    }
    if (strlen($json) <= BA_MAX_METADATA_BYTES) {
        return $json;
    }
    $summary = [
        'truncated' => true,
        'content_type' => $metadata['content_type'] ?? '',
        'content_length' => $metadata['content_length'] ?? 0,
        'query_field_count' => isset($_GET) && is_array($_GET) ? count($_GET) : 0,
        'form_field_count' => isset($_POST) && is_array($_POST) ? count($_POST) : 0,
        'file_field_count' => isset($_FILES) && is_array($_FILES) ? count($_FILES) : 0,
    ];
    $encoded = json_encode($summary, JSON_UNESCAPED_SLASHES);
    return is_string($encoded) ? $encoded : '{"truncated":true}';
}

function ba_request_route(): string
{
    $uri = (string)($_SERVER['REQUEST_URI'] ?? $_SERVER['SCRIPT_NAME'] ?? 'unknown');
    $path = parse_url($uri, PHP_URL_PATH);
    if (!is_string($path) || $path === '') {
        $path = (string)($_SERVER['SCRIPT_NAME'] ?? 'unknown');
    }
    $path = preg_replace('/[\x00-\x1F\x7F]/', '', $path) ?? 'unknown';
    return ba_limit_text($path, 255);
}

function ba_request_method(): string
{
    $method = strtoupper(trim((string)($_SERVER['REQUEST_METHOD'] ?? 'UNKNOWN')));
    if (preg_match('/^[A-Z]{1,12}$/D', $method) !== 1) {
        return 'UNKNOWN';
    }
    return $method;
}

function ba_user_agent(): string
{
    $value = ba_sanitize_metadata_value((string)($_SERVER['HTTP_USER_AGENT'] ?? ''));
    $normalized = ba_limit_text(is_string($value) ? trim($value) : '', 255);
    return $normalized === '' ? 'Unknown client' : $normalized;
}

function ba_authorization_header(): string
{
    foreach (['HTTP_AUTHORIZATION', 'REDIRECT_HTTP_AUTHORIZATION'] as $key) {
        $value = trim((string)($_SERVER[$key] ?? ''));
        if ($value !== '') {
            return $value;
        }
    }
    if (function_exists('getallheaders')) {
        $headers = getallheaders();
        if (is_array($headers)) {
            foreach ($headers as $key => $value) {
                if (strcasecmp((string)$key, 'Authorization') === 0) {
                    return trim((string)$value);
                }
            }
        }
    }
    return '';
}

function ba_session_token_hash(): ?string
{
    $header = ba_authorization_header();
    if ($header !== '' && preg_match('/^Bearer\s+([^\s]+)$/iD', $header, $match) === 1) {
        $token = (string)$match[1];
    } else {
        $token = isset($_POST['session_token']) && is_string($_POST['session_token'])
            ? trim($_POST['session_token'])
            : '';
    }
    if ($token === '' || strlen($token) < 20 || strlen($token) > 512) {
        return null;
    }
    return hash('sha256', $token);
}

/** @return array{session_id:int,authenticated:int,role:string,account_source:string,user_id:string} */
function ba_resolve_actor(mysqli $conn): array
{
    $unknown = [
        'session_id' => 0,
        'authenticated' => 0,
        'role' => 'guest',
        'account_source' => 'public',
        'user_id' => 'anonymous',
    ];
    $tokenHash = ba_session_token_hash();
    if ($tokenHash === null) {
        return $unknown;
    }
    try {
        $statement = $conn->prepare(
            'SELECT s.session_id, s.role, s.account_source, s.user_id, '
                . '(s.revoked_at IS NULL AND s.expires_at > NOW(6) '
                . 'AND a.current_session_id = s.session_id) AS authenticated '
                . 'FROM app_sessions s LEFT JOIN app_session_accounts a '
                . 'ON a.role = s.role AND a.account_source = s.account_source '
                . 'AND a.user_id = s.user_id WHERE s.token_hash = ? LIMIT 1'
        );
        if (!$statement) {
            return $unknown;
        }
        $statement->bind_param('s', $tokenHash);
        $statement->execute();
        $row = $statement->get_result()->fetch_assoc();
        $statement->close();
        if (!is_array($row)) {
            return $unknown;
        }
        return [
            'session_id' => (int)$row['session_id'],
            'authenticated' => (int)$row['authenticated'] === 1 ? 1 : 0,
            'role' => ba_limit_text((string)$row['role'], 20),
            'account_source' => ba_limit_text((string)$row['account_source'], 32),
            'user_id' => ba_limit_text((string)$row['user_id'], 191),
        ];
    } catch (Throwable $error) {
        return $unknown;
    }
}

function ba_security_key(): ?string
{
    $configuredPath = getenv('EDUPOCKET_SECURITY_CONFIG_PATH');
    $path = is_string($configuredPath) && trim($configuredPath) !== ''
        ? trim($configuredPath)
        : BA_DEFAULT_SECURITY_CONFIG_PATH;
    if (!is_file($path)) {
        return null;
    }
    $loaded = @include $path;
    if (!is_array($loaded)) {
        return null;
    }
    $section = $loaded['password_change'] ?? $loaded;
    $configured = is_array($section) ? ($section['encryption_key'] ?? '') : '';
    if (!is_string($configured) || $configured === '') {
        return null;
    }
    if (str_starts_with($configured, 'base64:')) {
        $material = base64_decode(substr($configured, 7), true);
        if (!is_string($material)) {
            return null;
        }
    } else {
        $material = $configured;
    }
    if (strlen($material) < 32) {
        return null;
    }
    return hash_hkdf('sha256', $material, 32, 'edupay/backend-audit/ip-hash/v1');
}

function ba_ip_hash_with_key(string $address, string $key): string
{
    return hash_hmac('sha256', "backend-audit-ip\0" . $address, $key);
}

function ba_request_ip_hash(): string
{
    $key = ba_security_key();
    if ($key === null) {
        return hash('sha256', 'unavailable-ip-hash');
    }
    $address = trim((string)($_SERVER['REMOTE_ADDR'] ?? 'unknown'));
    if ($address === '') {
        $address = 'unknown';
    }
    return ba_ip_hash_with_key($address, $key);
}

/** @return array{status:int,outcome:string} */
function ba_response_result(): array
{
    $status = http_response_code();
    if (!is_int($status) || $status < 100 || $status > 599) {
        $status = 200;
    }
    $lastError = error_get_last();
    $fatalTypes = [E_ERROR, E_PARSE, E_CORE_ERROR, E_COMPILE_ERROR, E_USER_ERROR];
    if (is_array($lastError) && in_array((int)($lastError['type'] ?? 0), $fatalTypes, true)) {
        return ['status' => max(500, $status), 'outcome' => 'fatal'];
    }
    if ($status >= 500) {
        return ['status' => $status, 'outcome' => 'server_error'];
    }
    if ($status >= 400) {
        return ['status' => $status, 'outcome' => 'client_error'];
    }
    if ($status >= 300) {
        return ['status' => $status, 'outcome' => 'redirect'];
    }
    $state = ba_state();
    $marked = (string)($state['marked_outcome'] ?? '');
    if ($marked !== '') {
        return ['status' => $status, 'outcome' => $marked];
    }
    return ['status' => $status, 'outcome' => 'completed'];
}

function ba_persist_current_request(mysqli $conn): int
{
    $state = ba_state();
    $actor = ba_resolve_actor($conn);
    $result = ba_response_result();
    $completedAt = ba_now();
    $startedMonotonic = isset($state['started_monotonic'])
        ? (int)$state['started_monotonic']
        : hrtime(true);
    $durationMs = max(0, (int)round((hrtime(true) - $startedMonotonic) / 1000000));
    $durationMs = min($durationMs, 4294967295);

    $requestId = ba_limit_text((string)($state['request_id'] ?? ba_new_request_id()), 64);
    $sessionId = $actor['session_id'];
    $authenticated = $actor['authenticated'];
    $role = $actor['role'];
    $accountSource = $actor['account_source'];
    $userId = $actor['user_id'];
    $route = ba_request_route();
    $method = ba_request_method();
    $responseStatus = $result['status'];
    $outcome = $result['outcome'];
    $metadataJson = ba_metadata_json(ba_request_metadata());
    $requestIpHash = ba_request_ip_hash();
    $userAgent = ba_user_agent();
    $startedAt = (string)($state['started_at'] ?? $completedAt);

    $statement = $conn->prepare(
        'INSERT INTO backend_audit_log '
            . '(request_id, session_id, actor_authenticated, role, account_source, user_id, '
            . 'route, request_method, response_status, outcome, metadata_json, '
            . 'request_ip_hash, user_agent, started_at, completed_at, duration_ms) '
            . 'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)'
    );
    if (!$statement) {
        throw new RuntimeException('Backend audit insert could not be prepared.');
    }
    $statement->bind_param(
        'siisssssissssssi',
        $requestId,
        $sessionId,
        $authenticated,
        $role,
        $accountSource,
        $userId,
        $route,
        $method,
        $responseStatus,
        $outcome,
        $metadataJson,
        $requestIpHash,
        $userAgent,
        $startedAt,
        $completedAt,
        $durationMs
    );
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Backend audit insert failed.');
    }
    $auditId = (int)$conn->insert_id;
    $statement->close();
    return $auditId;
}

function ba_write_request_audit(): void
{
    $state = ba_state();
    if (($state['registered'] ?? false) !== true || ($state['writing'] ?? false) === true) {
        return;
    }
    $state['writing'] = true;
    ba_store_state($state);

    $config = ba_load_database_config();
    if ($config === null) {
        error_log('EduPocket backend audit skipped: database configuration unavailable.');
        return;
    }

    $conn = null;
    try {
        $conn = @new mysqli(
            (string)$config['host'],
            (string)$config['username'],
            (string)$config['password'],
            (string)$config['database'],
            (int)$config['port']
        );
        if ($conn->connect_errno !== 0) {
            throw new RuntimeException('Audit database connection failed.');
        }
        $conn->set_charset('utf8mb4');
        $conn->query("SET time_zone = '+08:00'");
        ba_persist_current_request($conn);
    } catch (Throwable $error) {
        error_log(
            'EduPocket backend audit write failed (' . get_class($error) . ':'
                . (string)$error->getCode() . ').'
        );
    } finally {
        if ($conn instanceof mysqli && $conn->connect_errno === 0) {
            $conn->close();
        }
    }
}
