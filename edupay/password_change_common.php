<?php

declare(strict_types=1);

require_once __DIR__ . '/backend_audit_common.php';
ba_register_request_audit();

const PC_SECURITY_CONFIG_PATH = 'C:/xampp/edupocket-config/security.php';
const PC_CHALLENGE_TTL_SECONDS = 300;
const PC_MAX_ATTEMPTS = 5;
const PC_RESEND_COOLDOWN_SECONDS = 60;
const PC_MAX_RESENDS = 3;
const PC_TOTP_PERIOD_SECONDS = 30;
const PC_TOTP_DIGITS = 6;
const PC_TOTP_WINDOW = 1;
const PC_PASSWORD_REUSE_MESSAGE =
    'You cannot reuse your current password or any previous password. Please choose a password you have never used before.';

final class PasswordChangeClientException extends RuntimeException
{
    
    private array $details;

    
    public function __construct(string $message, array $details = [])
    {
        parent::__construct($message);
        $this->details = $details;
    }

    
    public function details(): array
    {
        return $this->details;
    }
}

function pc_bootstrap_json_endpoint(): void
{
    error_reporting(E_ALL);
    ini_set('display_errors', '0');
    $requestOrigin = trim((string)($_SERVER['HTTP_ORIGIN'] ?? ''));
    if (preg_match('#^http://(?:localhost|127\.0\.0\.1):\d{1,5}$#D', $requestOrigin) === 1) {
        header('Access-Control-Allow-Origin: ' . $requestOrigin);
        header('Vary: Origin');
    }
    header('Access-Control-Allow-Methods: POST, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Authorization');
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, max-age=0');
    header('Pragma: no-cache');
    header('X-Content-Type-Options: nosniff');

    if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
        http_response_code(204);
        exit;
    }
}


function pc_respond(array $payload): void
{
    ba_observe_response_payload($payload);
    echo json_encode($payload, JSON_UNESCAPED_SLASHES);
    exit;
}


function pc_reject(string $message, array $details = []): void
{
    throw new PasswordChangeClientException($message, $details);
}

function pc_require_post(): void
{
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') {
        pc_reject('Invalid request method.');
    }
}

function pc_uses_secure_or_local_transport(): bool
{
    if (PHP_SAPI === 'cli') {
        return true;
    }

    $https = strtolower(trim((string)($_SERVER['HTTPS'] ?? '')));
    $requestScheme = strtolower(trim((string)($_SERVER['REQUEST_SCHEME'] ?? '')));
    $serverPort = (string)($_SERVER['SERVER_PORT'] ?? '');
    if (($https !== '' && $https !== 'off') || $requestScheme === 'https' || $serverPort === '443') {
        return true;
    }

    $remoteAddress = trim((string)($_SERVER['REMOTE_ADDR'] ?? ''));
    if ($remoteAddress === '::1' || $remoteAddress === '::ffff:127.0.0.1') {
        return true;
    }

    if (filter_var($remoteAddress, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) === false) {
        return false;
    }

    return filter_var(
        $remoteAddress,
        FILTER_VALIDATE_IP,
        FILTER_FLAG_NO_PRIV_RANGE | FILTER_FLAG_NO_RES_RANGE
    ) === false;
}

function pc_post_string(string $key, bool $trim = true): string
{
    $value = $_POST[$key] ?? '';
    if (!is_string($value)) {
        return '';
    }
    return $trim ? trim($value) : $value;
}


function pc_security_config(): array
{
    static $cached = null;
    if (is_array($cached)) {
        return $cached;
    }

    $configuredPath = getenv('EDUPOCKET_SECURITY_CONFIG_PATH');
    $configPath = is_string($configuredPath) && trim($configuredPath) !== ''
        ? $configuredPath
        : PC_SECURITY_CONFIG_PATH;
    if (!is_file($configPath)) {
        pc_reject(
            'Password change security is not configured on this server. Please contact support.'
        );
    }

    $loaded = @include $configPath;
    if (!is_array($loaded)) {
        pc_reject(
            'Password change security is not configured on this server. Please contact support.'
        );
    }

    $section = $loaded['password_change'] ?? $loaded;
    if (!is_array($section)) {
        pc_reject(
            'Password change security is not configured on this server. Please contact support.'
        );
    }

    pc_master_key($section);
    $cached = $section;
    return $cached;
}


function pc_master_key(array $config): string
{
    $configured = $config['encryption_key'] ?? '';
    if (!is_string($configured) || $configured === '') {
        pc_reject(
            'Password change security is not configured on this server. Please contact support.'
        );
    }

    if (str_starts_with($configured, 'base64:')) {
        $decoded = base64_decode(substr($configured, 7), true);
        if (!is_string($decoded)) {
            $decoded = '';
        }
        $keyMaterial = $decoded;
    } else {
        $keyMaterial = $configured;
    }

    if (strlen($keyMaterial) < 32) {
        pc_reject(
            'Password change security is not configured on this server. Please contact support.'
        );
    }

    return $keyMaterial;
}


function pc_derived_key(array $config, string $purpose): string
{
    return hash_hkdf(
        'sha256',
        pc_master_key($config),
        32,
        'edupay/password-change/' . $purpose . '/v1'
    );
}


function pc_role_map(): array
{
    return [
        'student' => [
            'table' => 'students',
            'id_field' => 'student_num',
            'password_field' => 'Password',
        ],
        'parent' => [
            'table' => 'parents',
            'id_field' => 'parent_id',
            'password_field' => 'Password',
        ],
        'admin' => [
            'table' => 'admins',
            'id_field' => 'admin_id',
            'password_field' => 'password',
        ],
        'cashier' => [
            'table' => 'cashiers',
            'id_field' => 'cashier_id',
            'password_field' => 'password',
        ],
        'canteen' => [
            'table' => 'canteens',
            'id_field' => 'canteen_id',
            'password_field' => 'Password',
        ],
    ];
}


function pc_role_target(string $role): array
{
    $normalized = strtolower(trim($role));
    $map = pc_role_map();
    if (!isset($map[$normalized])) {
        pc_reject('Invalid user role.');
    }
    return $map[$normalized];
}

function pc_normalize_role(string $role): string
{
    $normalized = strtolower(trim($role));
    pc_role_target($normalized);
    return $normalized;
}

function pc_normalize_method(string $method): string
{
    $normalized = strtolower(trim($method));
    if ($normalized === 'authenticator') {
        return 'totp';
    }
    if (!in_array($normalized, ['email', 'totp'], true)) {
        pc_reject('Choose email or authenticator verification.');
    }
    return $normalized;
}

function pc_validate_user_id(string $userId): void
{
    if ($userId === '' || strlen($userId) > 191 || str_contains($userId, "\0")) {
        pc_reject('A valid account ID is required.');
    }
}

function pc_validate_strong_password(string $password): void
{
    $valid = strlen($password) >= 8
        && strlen($password) <= 72
        && !str_contains($password, "\0")
        && preg_match('/[A-Z]/', $password) === 1
        && preg_match('/[a-z]/', $password) === 1
        && preg_match('/[0-9]/', $password) === 1
        && preg_match('/[!@#$%^&*(),.?":{}|<>]/', $password) === 1;

    if (!$valid) {
        pc_reject(
            'Password must have 8-72 characters, uppercase, lowercase, number, and special character.'
        );
    }
}

function pc_password_matches(string $entered, string $stored): bool
{
    if ($stored === '') {
        return false;
    }

    if (password_verify($entered, $stored)) {
        return true;
    }

    return hash_equals($stored, $entered);
}

function pc_is_password_hash(string $credential): bool
{
    $info = password_get_info($credential);
    return !empty($info['algo']);
}

function pc_hash_password(string $password): string
{
    $hash = password_hash($password, PASSWORD_DEFAULT);
    if (!is_string($hash) || $hash === '') {
        throw new RuntimeException('Password hashing failed.');
    }
    return $hash;
}

function pc_prepare(mysqli $conn, string $sql): mysqli_stmt
{
    $statement = $conn->prepare($sql);
    if (!$statement) {
        error_log('Database statement prepare failed: ' . $conn->error);
        throw new RuntimeException('Database statement could not be prepared.');
    }
    return $statement;
}

function pc_open_database(): mysqli
{
    $configuredPath = getenv('EDUPOCKET_DATABASE_CONFIG_PATH');
    $databaseConfigPath = is_string($configuredPath) && trim($configuredPath) !== ''
        ? $configuredPath
        : 'C:/xampp/edupocket-config/database.php';
    if (!is_file($databaseConfigPath)) {
        throw new RuntimeException('Database configuration is missing.');
    }
    $databaseConfig = @include $databaseConfigPath;
    if (!is_array($databaseConfig)) {
        throw new RuntimeException('Database configuration is invalid.');
    }

    $port = filter_var(
        $databaseConfig['port'] ?? 3306,
        FILTER_VALIDATE_INT,
        ['options' => ['min_range' => 1, 'max_range' => 65535]]
    );
    if ($port === false) {
        throw new RuntimeException('Database port configuration is invalid.');
    }

    require_once __DIR__ . '/db_port_helper.php';
    try {
        $conn = connect_mysqli_with_fallback(
            (string)($databaseConfig['host'] ?? ''),
            (string)($databaseConfig['username'] ?? ''),
            (string)($databaseConfig['password'] ?? ''),
            (string)($databaseConfig['database'] ?? ''),
            [(int)$port]
        );
    } catch (Throwable $error) {
        error_log('Password-change database connection failed: ' . $error->getMessage());
        throw new RuntimeException('Database connection failed.');
    }

    if (!$conn->set_charset('utf8mb4')) {
        $conn->close();
        throw new RuntimeException('Database character set could not be configured.');
    }
    return $conn;
}

function pc_table_exists(mysqli $conn, string $table): bool
{
    $statement = pc_prepare(
        $conn,
        'SELECT 1 FROM information_schema.TABLES '
            . 'WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? LIMIT 1'
    );
    $statement->bind_param('s', $table);
    $statement->execute();
    $exists = $statement->get_result()->fetch_row() !== null;
    $statement->close();
    return $exists;
}

function pc_column_exists(mysqli $conn, string $table, string $column): bool
{
    $statement = pc_prepare(
        $conn,
        'SELECT 1 FROM information_schema.COLUMNS '
            . 'WHERE TABLE_SCHEMA = DATABASE() AND TABLE_NAME = ? '
            . 'AND COLUMN_NAME = ? LIMIT 1'
    );
    $statement->bind_param('ss', $table, $column);
    $statement->execute();
    $exists = $statement->get_result()->fetch_row() !== null;
    $statement->close();
    return $exists;
}


function pc_target_for_source(string $role, string $accountSource): array
{
    if ($role === 'cashier' && $accountSource === 'admins') {
        return [
            'table' => 'admins',
            'id_field' => 'admin_id',
            'password_field' => 'password',
        ];
    }

    $target = pc_role_target($role);
    if ($target['table'] !== $accountSource) {
        throw new RuntimeException('Account source does not match the requested role.');
    }
    return $target;
}


function pc_fetch_account_from_source_for_update(
    mysqli $conn,
    string $role,
    string $userId,
    string $accountSource
): ?array {
    $target = pc_target_for_source($role, $accountSource);
    if (!pc_table_exists($conn, $target['table'])) {
        return null;
    }

    $rolePredicate = '';
    if ($target['table'] === 'admins' && pc_column_exists($conn, 'admins', 'role')) {
        $rolePredicate = $role === 'cashier'
            ? " AND LOWER(COALESCE(`role`, '')) = 'cashier'"
            : " AND LOWER(COALESCE(`role`, '')) <> 'cashier'";
    } elseif ($role === 'cashier' && $accountSource === 'admins') {
        return null;
    }

    $sql = sprintf(
        'SELECT `%s` AS canonical_user_id, `%s` AS password_value '
            . 'FROM `%s` WHERE `%s` = ?%s FOR UPDATE',
        $target['id_field'],
        $target['password_field'],
        $target['table'],
        $target['id_field'],
        $rolePredicate
    );
    $statement = pc_prepare($conn, $sql);
    $statement->bind_param('s', $userId);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Account lookup failed.');
    }
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();

    if (!is_array($row)) {
        return null;
    }

    $canonicalUserId = (string)($row['canonical_user_id'] ?? '');
    if ($canonicalUserId === ''
        || strlen($canonicalUserId) > 191
        || str_contains($canonicalUserId, "\0")
    ) {
        throw new RuntimeException('Account has an invalid canonical ID.');
    }

    return [
        'password_value' => (string)($row['password_value'] ?? ''),
        'account_source' => $accountSource,
        'user_id' => $canonicalUserId,
    ];
}


function pc_fetch_account_for_update(
    mysqli $conn,
    string $role,
    string $userId,
    ?string $expectedAccountSource = null
): array {
    if ($expectedAccountSource !== null) {
        $account = pc_fetch_account_from_source_for_update(
            $conn,
            $role,
            $userId,
            $expectedAccountSource
        );
        if ($account === null) {
            pc_reject('Account not found.');
        }
        return $account;
    }

    if ($role === 'cashier') {
        foreach (['cashiers', 'admins'] as $source) {
            $account = pc_fetch_account_from_source_for_update(
                $conn,
                $role,
                $userId,
                $source
            );
            if ($account !== null) {
                return $account;
            }
        }
        pc_reject('Account not found.');
    }

    $source = pc_role_target($role)['table'];
    $account = pc_fetch_account_from_source_for_update(
        $conn,
        $role,
        $userId,
        $source
    );
    if ($account === null) {
        pc_reject('Account not found.');
    }
    return $account;
}

function pc_assert_current_password(string $entered, string $stored): void
{
    if ($entered === '' || !pc_password_matches($entered, $stored)) {
        pc_reject('Current password is incorrect.');
    }
}

function pc_assert_password_not_reused(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId,
    string $newPassword,
    string $currentCredential
): void {
    if (pc_password_matches($newPassword, $currentCredential)) {
        pc_reject(PC_PASSWORD_REUSE_MESSAGE);
    }

    $statement = pc_prepare(
        $conn,
        'SELECT password_hash FROM password_history '
            . 'WHERE role = ? AND account_source = ? AND user_id = ? '
            . 'ORDER BY history_id ASC'
    );
    $statement->bind_param('sss', $role, $accountSource, $userId);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Password history lookup failed.');
    }

    $result = $statement->get_result();
    while ($row = $result->fetch_assoc()) {
        $historicalHash = (string)($row['password_hash'] ?? '');
        if ($historicalHash !== '' && pc_password_matches($newPassword, $historicalHash)) {
            $statement->close();
            pc_reject(PC_PASSWORD_REUSE_MESSAGE);
        }
    }
    $statement->close();
}

function pc_history_fingerprint(
    string $role,
    string $accountSource,
    string $userId,
    string $passwordHash
): string {
    return hash(
        'sha256',
        $role . "\0" . $accountSource . "\0" . $userId . "\0" . $passwordHash
    );
}

function pc_record_password_history(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId,
    string $passwordHash
): void {
    $fingerprint = pc_history_fingerprint(
        $role,
        $accountSource,
        $userId,
        $passwordHash
    );
    $statement = pc_prepare(
        $conn,
        'INSERT IGNORE INTO password_history '
            . '(role, account_source, user_id, password_hash, password_fingerprint) '
            . 'VALUES (?, ?, ?, ?, ?)'
    );
    $statement->bind_param(
        'sssss',
        $role,
        $accountSource,
        $userId,
        $passwordHash,
        $fingerprint
    );
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Password history could not be recorded.');
    }
    $statement->close();
}

function pc_update_account_password(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId,
    string $newPasswordHash
): void {
    $target = pc_target_for_source($role, $accountSource);
    $sql = sprintf(
        'UPDATE `%s` SET `%s` = ? WHERE `%s` = ?',
        $target['table'],
        $target['password_field'],
        $target['id_field']
    );
    $statement = pc_prepare($conn, $sql);
    $statement->bind_param('ss', $newPasswordHash, $userId);
    if (!$statement->execute() || $statement->affected_rows !== 1) {
        $statement->close();
        throw new RuntimeException('Account password could not be updated.');
    }
    $statement->close();
}


function pc_account_fingerprint(
    string $role,
    string $accountSource,
    string $userId,
    string $storedCredential,
    array $config
): string {
    return hash_hmac(
        'sha256',
        $role . "\0" . $accountSource . "\0" . $userId . "\0" . $storedCredential,
        pc_derived_key($config, 'account-fingerprint')
    );
}

function pc_base64url_encode(string $bytes): string
{
    return rtrim(strtr(base64_encode($bytes), '+/', '-_'), '=');
}

function pc_base64url_decode(string $encoded): string
{
    if ($encoded === '' || preg_match('/^[A-Za-z0-9_-]+$/', $encoded) !== 1) {
        return '';
    }
    $padding = (4 - (strlen($encoded) % 4)) % 4;
    $decoded = base64_decode(
        strtr($encoded . str_repeat('=', $padding), '-_', '+/'),
        true
    );
    return is_string($decoded) ? $decoded : '';
}


function pc_new_challenge_token(): array
{
    $token = pc_base64url_encode(random_bytes(32));
    return ['token' => $token, 'hash' => hash('sha256', $token)];
}

function pc_challenge_token_hash(string $token): string
{
    if (strlen($token) < 40 || strlen($token) > 100 || pc_base64url_decode($token) === '') {
        pc_reject('The password-change request is invalid or has expired.');
    }
    return hash('sha256', $token);
}

function pc_generate_email_otp(): string
{
    return str_pad((string)random_int(0, 999999), 6, '0', STR_PAD_LEFT);
}


function pc_email_otp_hash(string $challengeTokenHash, string $code, array $config): string
{
    return hash_hmac(
        'sha256',
        $challengeTokenHash . "\0" . $code,
        pc_derived_key($config, 'email-otp')
    );
}




function pc_email_config(array $config): array
{
    $email = $config['email'] ?? $config['email_otp'] ?? null;
    if (!is_array($email)
        || ($email['enabled'] ?? false) !== true
        || !is_callable($email['send_callback'] ?? null)
    ) {
        pc_reject(
            'Email verification is not configured on this server. Choose Authenticator or contact support.'
        );
    }
    return $email;
}


function pc_resolve_email_destination(
    mysqli $conn,
    array $config,
    string $role,
    string $accountSource,
    string $userId,
    string $requestedAddress
): string {
    pc_email_config($config);
    require_once __DIR__ . '/email_verification_common.php';
    return ev_resolve_verified_email_destination(
        $conn,
        $config,
        $role,
        $accountSource,
        $userId,
        $requestedAddress
    );
}

function pc_mask_email(string $email): string
{
    $parts = explode('@', $email, 2);
    if (count($parts) !== 2) {
        return '';
    }
    $local = $parts[0];
    $domain = $parts[1];
    $visible = mb_substr($local, 0, min(2, mb_strlen($local)));
    return $visible . str_repeat('*', max(3, mb_strlen($local) - mb_strlen($visible)))
        . '@' . $domain;
}




function pc_send_email_otp(
    array $config,
    string $destination,
    string $code,
    array $context
): bool {
    $email = pc_email_config($config);
    $sender = $email['send_callback'];
    try {
        return $sender($destination, $code, $context) === true;
    } catch (Throwable $error) {
        error_log('Password-change email sender failed: ' . $error->getMessage());
        return false;
    }
}

function pc_base32_encode(string $bytes): string
{
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    $bits = '';
    $length = strlen($bytes);
    for ($index = 0; $index < $length; $index++) {
        $bits .= str_pad(decbin(ord($bytes[$index])), 8, '0', STR_PAD_LEFT);
    }
    $padding = (5 - (strlen($bits) % 5)) % 5;
    if ($padding > 0) {
        $bits .= str_repeat('0', $padding);
    }

    $encoded = '';
    for ($offset = 0; $offset < strlen($bits); $offset += 5) {
        $encoded .= $alphabet[bindec(substr($bits, $offset, 5))];
    }
    return $encoded;
}

function pc_base32_decode(string $encoded): string
{
    $alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    $normalized = strtoupper(preg_replace('/[\s=-]+/', '', $encoded) ?? '');
    if ($normalized === '') {
        return '';
    }

    $bits = '';
    $length = strlen($normalized);
    for ($index = 0; $index < $length; $index++) {
        $position = strpos($alphabet, $normalized[$index]);
        if ($position === false) {
            return '';
        }
        $bits .= str_pad(decbin($position), 5, '0', STR_PAD_LEFT);
    }

    $decoded = '';
    for ($offset = 0; $offset + 8 <= strlen($bits); $offset += 8) {
        $decoded .= chr(bindec(substr($bits, $offset, 8)));
    }
    return $decoded;
}

function pc_totp_code_for_counter(string $secretBytes, int $counter): string
{
    $high = ($counter >> 32) & 0xFFFFFFFF;
    $low = $counter & 0xFFFFFFFF;
    $counterBytes = pack('N2', $high, $low);
    $digest = hash_hmac('sha1', $counterBytes, $secretBytes, true);
    $offset = ord($digest[strlen($digest) - 1]) & 0x0F;
    $binary = ((ord($digest[$offset]) & 0x7F) << 24)
        | ((ord($digest[$offset + 1]) & 0xFF) << 16)
        | ((ord($digest[$offset + 2]) & 0xFF) << 8)
        | (ord($digest[$offset + 3]) & 0xFF);
    $modulus = 10 ** PC_TOTP_DIGITS;
    return str_pad((string)($binary % $modulus), PC_TOTP_DIGITS, '0', STR_PAD_LEFT);
}

function pc_match_totp_step(
    string $base32Secret,
    string $code,
    ?int $lastUsedStep = null,
    ?int $unixTime = null
): ?int
{
    if (preg_match('/^\d{6}$/', $code) !== 1) {
        return null;
    }
    $secretBytes = pc_base32_decode($base32Secret);
    if ($secretBytes === '') {
        return null;
    }

    $time = $unixTime ?? time();
    $counter = intdiv($time, PC_TOTP_PERIOD_SECONDS);
    for ($window = -PC_TOTP_WINDOW; $window <= PC_TOTP_WINDOW; $window++) {
        $candidateCounter = $counter + $window;
        if ($candidateCounter < 0) {
            continue;
        }
        if (hash_equals(pc_totp_code_for_counter($secretBytes, $candidateCounter), $code)
            && ($lastUsedStep === null || $candidateCounter > $lastUsedStep)
        ) {
            return $candidateCounter;
        }
    }
    return null;
}

function pc_verify_totp(string $base32Secret, string $code, ?int $unixTime = null): bool
{
    return pc_match_totp_step($base32Secret, $code, null, $unixTime) !== null;
}


function pc_encrypt_protected_value(
    string $plaintext,
    string $purpose,
    string $role,
    string $accountSource,
    string $userId,
    array $config
): string {
    if (!function_exists('openssl_encrypt')) {
        pc_reject('Authenticator verification is unavailable on this server.');
    }

    $iv = random_bytes(12);
    $tag = '';
    $aad = 'edupay/password-change/' . $purpose . '/v1/'
        . $role . '/' . $accountSource . '/' . $userId;
    $ciphertext = openssl_encrypt(
        $plaintext,
        'aes-256-gcm',
        pc_derived_key($config, $purpose . '-encryption'),
        OPENSSL_RAW_DATA,
        $iv,
        $tag,
        $aad,
        16
    );
    if (!is_string($ciphertext) || strlen($tag) !== 16) {
        throw new RuntimeException('Authenticator secret encryption failed.');
    }
    return 'v1:' . pc_base64url_encode($iv . $tag . $ciphertext);
}


function pc_decrypt_protected_value(
    string $encrypted,
    string $purpose,
    string $role,
    string $accountSource,
    string $userId,
    array $config
): string {
    if (!str_starts_with($encrypted, 'v1:')) {
        throw new RuntimeException('Unknown authenticator secret format.');
    }
    $payload = pc_base64url_decode(substr($encrypted, 3));
    if (strlen($payload) <= 28) {
        throw new RuntimeException('Invalid authenticator secret payload.');
    }
    $iv = substr($payload, 0, 12);
    $tag = substr($payload, 12, 16);
    $ciphertext = substr($payload, 28);
    $aad = 'edupay/password-change/' . $purpose . '/v1/'
        . $role . '/' . $accountSource . '/' . $userId;
    $plaintext = openssl_decrypt(
        $ciphertext,
        'aes-256-gcm',
        pc_derived_key($config, $purpose . '-encryption'),
        OPENSSL_RAW_DATA,
        $iv,
        $tag,
        $aad
    );
    if (!is_string($plaintext)) {
        throw new RuntimeException('Protected value decryption failed.');
    }
    return $plaintext;
}


function pc_encrypt_totp_secret(
    string $base32Secret,
    string $role,
    string $accountSource,
    string $userId,
    array $config
): string {
    return pc_encrypt_protected_value(
        $base32Secret,
        'totp',
        $role,
        $accountSource,
        $userId,
        $config
    );
}


function pc_decrypt_totp_secret(
    string $encrypted,
    string $role,
    string $accountSource,
    string $userId,
    array $config
): string {
    $secret = pc_decrypt_protected_value(
        $encrypted,
        'totp',
        $role,
        $accountSource,
        $userId,
        $config
    );
    if (pc_base32_decode($secret) === '') {
        throw new RuntimeException('Authenticator secret decryption failed.');
    }
    return $secret;
}


function pc_encrypt_email_destination(
    string $destination,
    string $role,
    string $accountSource,
    string $userId,
    array $config
): string {
    return pc_encrypt_protected_value(
        $destination,
        'email-destination',
        $role,
        $accountSource,
        $userId,
        $config
    );
}


function pc_decrypt_email_destination(
    string $encrypted,
    string $role,
    string $accountSource,
    string $userId,
    array $config
): string {
    $destination = pc_decrypt_protected_value(
        $encrypted,
        'email-destination',
        $role,
        $accountSource,
        $userId,
        $config
    );
    if (filter_var($destination, FILTER_VALIDATE_EMAIL) === false) {
        throw new RuntimeException('Email destination decryption failed.');
    }
    return $destination;
}


function pc_totp_issuer(array $config): string
{
    $issuer = trim((string)($config['totp_issuer'] ?? 'EduPocket'));
    return $issuer !== '' ? mb_substr($issuer, 0, 64) : 'EduPocket';
}


function pc_otpauth_uri(
    string $base32Secret,
    string $role,
    string $userId,
    array $config
): string {
    $issuer = pc_totp_issuer($config);
    $label = $issuer . ':' . $role . '-' . $userId;
    return 'otpauth://totp/' . rawurlencode($label)
        . '?secret=' . rawurlencode($base32Secret)
        . '&issuer=' . rawurlencode($issuer)
        . '&algorithm=SHA1&digits=6&period=30';
}


function pc_challenge_preview(mysqli $conn, string $tokenHash): ?array
{
    $statement = pc_prepare(
        $conn,
        'SELECT challenge_id, role, account_source, user_id '
            . 'FROM password_change_challenges '
            . 'WHERE challenge_token_hash = ? LIMIT 1'
    );
    $statement->bind_param('s', $tokenHash);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Challenge lookup failed.');
    }
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    return is_array($row) ? $row : null;
}


function pc_challenge_for_update(mysqli $conn, string $tokenHash): ?array
{
    $statement = pc_prepare(
        $conn,
        'SELECT *, '
            . '(expires_at <= NOW(6)) AS challenge_expired, '
            . '(otp_expires_at IS NULL OR otp_expires_at <= NOW(6)) AS otp_expired, '
            . 'TIMESTAMPDIFF(SECOND, last_sent_at, NOW(6)) AS seconds_since_last_send '
            . 'FROM password_change_challenges '
            . 'WHERE challenge_token_hash = ? LIMIT 1 FOR UPDATE'
    );
    $statement->bind_param('s', $tokenHash);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Challenge lookup failed.');
    }
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    return is_array($row) ? $row : null;
}

function pc_cancel_pending_challenges(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId
): void {
    $statement = pc_prepare(
        $conn,
        "UPDATE password_change_challenges SET status = 'cancelled' "
            . "WHERE role = ? AND account_source = ? AND user_id = ? "
            . "AND status = 'pending'"
    );
    $statement->bind_param('sss', $role, $accountSource, $userId);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Old challenges could not be cancelled.');
    }
    $statement->close();
}

function pc_mark_challenge_cancelled(mysqli $conn, string $tokenHash): void
{
    $statement = pc_prepare(
        $conn,
        "UPDATE password_change_challenges SET status = 'cancelled' "
            . "WHERE challenge_token_hash = ? AND status = 'pending'"
    );
    $statement->bind_param('s', $tokenHash);
    $statement->execute();
    $statement->close();
}

function pc_mark_challenge_verified(mysqli $conn, int $challengeId): void
{
    $statement = pc_prepare(
        $conn,
        "UPDATE password_change_challenges "
            . "SET status = 'verified', verified_at = NOW(6), "
            . 'otp_hash = NULL, destination_encrypted = NULL, '
            . 'pending_totp_secret_encrypted = NULL '
            . "WHERE challenge_id = ? AND status = 'pending'"
    );
    $statement->bind_param('i', $challengeId);
    if (!$statement->execute() || $statement->affected_rows !== 1) {
        $statement->close();
        throw new RuntimeException('Challenge could not be completed.');
    }
    $statement->close();
}

function pc_expire_challenge(mysqli $conn, int $challengeId): void
{
    $statement = pc_prepare(
        $conn,
        "UPDATE password_change_challenges SET status = 'expired' "
            . 'WHERE challenge_id = ?'
    );
    $statement->bind_param('i', $challengeId);
    $statement->execute();
    $statement->close();
}


function pc_assert_pending_challenge(array $challenge): void
{
    if (($challenge['status'] ?? '') !== 'pending') {
        pc_reject('The password-change request is no longer active. Start a new request.');
    }
    if ((int)($challenge['failed_attempts'] ?? PC_MAX_ATTEMPTS) >= PC_MAX_ATTEMPTS) {
        pc_reject(
            'Too many incorrect verification attempts. Start a new password-change request.',
            ['attempts_remaining' => 0]
        );
    }
}

function pc_datetime_has_passed(?string $databaseDateTime): bool
{
    if ($databaseDateTime === null || trim($databaseDateTime) === '') {
        return true;
    }
    $timestamp = strtotime($databaseDateTime);
    return $timestamp === false || $timestamp <= time();
}


function pc_authenticator_for_update(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId
): ?array {
    $statement = pc_prepare(
        $conn,
        'SELECT totp_secret_encrypted, last_used_step '
            . 'FROM password_change_authenticators '
            . 'WHERE role = ? AND account_source = ? AND user_id = ? FOR UPDATE'
    );
    $statement->bind_param('sss', $role, $accountSource, $userId);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Authenticator lookup failed.');
    }
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    return is_array($row) ? $row : null;
}

function pc_save_authenticator(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId,
    string $encryptedSecret,
    int $matchedStep
): void {
    $statement = pc_prepare(
        $conn,
        'INSERT INTO password_change_authenticators '
            . '(role, account_source, user_id, totp_secret_encrypted, '
            . 'enrolled_at, last_verified_at, last_used_step) '
            . 'VALUES (?, ?, ?, ?, NOW(6), NOW(6), ?)'
    );
    $statement->bind_param(
        'ssssi',
        $role,
        $accountSource,
        $userId,
        $encryptedSecret,
        $matchedStep
    );
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Authenticator enrollment failed.');
    }
    $statement->close();
}

function pc_touch_authenticator(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId,
    int $matchedStep
): void {
    $statement = pc_prepare(
        $conn,
        'UPDATE password_change_authenticators '
            . 'SET last_verified_at = NOW(6), last_used_step = ? '
            . 'WHERE role = ? AND account_source = ? AND user_id = ? '
            . 'AND (last_used_step IS NULL OR last_used_step < ?)'
    );
    $statement->bind_param(
        'isssi',
        $matchedStep,
        $role,
        $accountSource,
        $userId,
        $matchedStep
    );
    if (!$statement->execute() || $statement->affected_rows !== 1) {
        $statement->close();
        throw new RuntimeException('Authenticator state could not be updated.');
    }
    $statement->close();
}

function pc_increment_failed_attempt(
    mysqli $conn,
    int $challengeId,
    int $existingAttempts
): int {
    $failedAttempts = min(PC_MAX_ATTEMPTS, $existingAttempts + 1);
    $status = $failedAttempts >= PC_MAX_ATTEMPTS ? 'failed' : 'pending';
    $statement = pc_prepare(
        $conn,
        'UPDATE password_change_challenges '
            . 'SET failed_attempts = ?, status = ? WHERE challenge_id = ?'
    );
    $statement->bind_param('isi', $failedAttempts, $status, $challengeId);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Verification attempt could not be recorded.');
    }
    $statement->close();
    return PC_MAX_ATTEMPTS - $failedAttempts;
}





function pc_totp_material_for_challenge(
    mysqli $conn,
    array $challenge,
    array $config
): array {
    $role = (string)$challenge['role'];
    $accountSource = (string)$challenge['account_source'];
    $userId = (string)$challenge['user_id'];
    if ((int)($challenge['requires_totp_setup'] ?? 0) === 1) {
        $encrypted = (string)($challenge['pending_totp_secret_encrypted'] ?? '');
        if ($encrypted === '') {
            throw new RuntimeException('Pending authenticator secret is missing.');
        }
        return [
            'secret' => pc_decrypt_totp_secret(
                $encrypted,
                $role,
                $accountSource,
                $userId,
                $config
            ),
            'last_used_step' => null,
        ];
    }

    $authenticator = pc_authenticator_for_update(
        $conn,
        $role,
        $accountSource,
        $userId
    );
    if ($authenticator === null) {
        pc_reject('Authenticator enrollment was not found. Start a new request.');
    }
    $lastUsed = $authenticator['last_used_step'] ?? null;
    return [
        'secret' => pc_decrypt_totp_secret(
            (string)$authenticator['totp_secret_encrypted'],
            $role,
            $accountSource,
            $userId,
            $config
        ),
        'last_used_step' => $lastUsed === null ? null : (int)$lastUsed,
    ];
}


function pc_client_error_payload(
    string $message,
    array $exceptionDetails = []
): array {
    return array_merge(['status' => 'error', 'message' => $message], $exceptionDetails);
}
