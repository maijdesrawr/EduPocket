<?php

declare(strict_types=1);

require_once __DIR__ . '/password_change_common.php';

const AM_CHALLENGE_TTL_SECONDS = 300;
const AM_MAX_ATTEMPTS = 5;
const AM_PREAUTH_ACCOUNT_LIMIT = 5;
const AM_PREAUTH_ACCOUNT_WINDOW_SECONDS = 900;
const AM_PREAUTH_IP_LIMIT = 30;
const AM_PREAUTH_IP_WINDOW_SECONDS = 3600;
const AM_VERIFY_ACCOUNT_LIMIT = 5;
const AM_VERIFY_ACCOUNT_WINDOW_SECONDS = 900;
const AM_VERIFY_IP_LIMIT = 30;
const AM_VERIFY_IP_WINDOW_SECONDS = 3600;
const AM_CHALLENGE_RETENTION_SECONDS = 2592000;
const AM_RATE_LIMIT_RETENTION_SECONDS = 86400;
const AM_PURGE_BATCH_SIZE = 250;
const AM_DUMMY_PASSWORD_HASH = '$2y$10$clswDbybqTmePMnXRsPSoeVZCtUnwEKE2ooAPc/g1aimLdJKROG1u';

function am_require_secure_transport(): void
{
    if (pc_uses_secure_or_local_transport()) return;

    pc_reject('A secure HTTPS connection is required for authenticator management.');
}

function am_normalize_action(string $action): string
{
    $normalized = strtolower(trim($action));
    if (!in_array($normalized, ['enroll', 'remove'], true)) {
        pc_reject('Choose a valid authenticator action.');
    }
    return $normalized;
}

function am_require_schema(mysqli $conn): void
{
    foreach (
        [
            'password_change_authenticators',
            'password_change_challenges',
            'authenticator_management_challenges',
            'authenticator_management_rate_limits',
            'authenticator_management_events',
        ] as $table
    ) {
        if (!pc_table_exists($conn, $table)) {
            throw new RuntimeException('Authenticator management database migration is missing.');
        }
    }
}

function am_purge_stale_security_state(mysqli $conn): void
{
    $challengeRetention = AM_CHALLENGE_RETENTION_SECONDS;
    $rateRetention = AM_RATE_LIMIT_RETENTION_SECONDS;
    $batchSize = AM_PURGE_BATCH_SIZE;

    $sql = "UPDATE authenticator_management_challenges "
        . "SET status = 'expired', pending_totp_secret_encrypted = NULL, "
        . 'expected_authenticator_fingerprint = NULL '
        . "WHERE status = 'pending' AND expires_at <= NOW(6) LIMIT {$batchSize}";
    if (!$conn->query($sql)) {
        throw new RuntimeException('Expired authenticator challenges could not be marked.');
    }

    $sql = 'DELETE FROM authenticator_management_challenges '
        . "WHERE status IN ('expired', 'cancelled', 'failed', 'verified') "
        . "AND updated_at < DATE_SUB(NOW(6), INTERVAL {$challengeRetention} SECOND) "
        . "LIMIT {$batchSize}";
    if (!$conn->query($sql)) {
        throw new RuntimeException('Retained authenticator challenges could not be purged.');
    }

    $sql = 'DELETE FROM authenticator_management_rate_limits '
        . "WHERE updated_at < DATE_SUB(NOW(6), INTERVAL {$rateRetention} SECOND) "
        . "AND window_started_at < DATE_SUB(NOW(6), INTERVAL {$rateRetention} SECOND) "
        . "LIMIT {$batchSize}";
    if (!$conn->query($sql)) {
        throw new RuntimeException('Stale authenticator rate limits could not be purged.');
    }
}

/** @param array<string, mixed> $config */
function am_rate_scope_hash(string $scopeValue, array $config): string
{
    return hash_hmac(
        'sha256',
        $scopeValue,
        pc_derived_key($config, 'authenticator-management-rate-limit')
    );
}

/** @param array<string, mixed> $config */
function am_remote_ip_hash(array $config): string
{
    $address = trim((string)($_SERVER['REMOTE_ADDR'] ?? ''));
    if (filter_var($address, FILTER_VALIDATE_IP) === false) {
        $address = 'unknown';
    }
    return am_rate_scope_hash('ip' . "\0" . $address, $config);
}

function am_consume_rate_limit(
    mysqli $conn,
    string $scope,
    string $scopeHash,
    int $limit,
    int $windowSeconds
): int {
    if ($scope === '' || strlen($scope) > 16 || preg_match('/^[a-z_]+$/D', $scope) !== 1
        || preg_match('/^[a-f0-9]{64}$/D', $scopeHash) !== 1
        || $limit < 1
        || $windowSeconds < 1
    ) {
        throw new RuntimeException('Authenticator rate limit configuration is invalid.');
    }

    $statement = pc_prepare(
        $conn,
        'INSERT INTO authenticator_management_rate_limits '
            . '(scope, scope_hash, window_started_at, request_count) '
            . 'VALUES (?, ?, NOW(6), 0) '
            . 'ON DUPLICATE KEY UPDATE scope_hash = VALUES(scope_hash)'
    );
    $statement->bind_param('ss', $scope, $scopeHash);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Authenticator rate limit could not be locked.');
    }
    $statement->close();

    $statement = pc_prepare(
        $conn,
        'SELECT request_count, '
            . 'TIMESTAMPDIFF(SECOND, window_started_at, NOW(6)) AS elapsed_seconds '
            . 'FROM authenticator_management_rate_limits '
            . 'WHERE scope = ? AND scope_hash = ? FOR UPDATE'
    );
    $statement->bind_param('ss', $scope, $scopeHash);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Authenticator rate limit lookup failed.');
    }
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    if (!is_array($row)) {
        throw new RuntimeException('Authenticator rate limit lock disappeared.');
    }

    $elapsed = max(0, (int)($row['elapsed_seconds'] ?? 0));
    if ($elapsed >= $windowSeconds) {
        $statement = pc_prepare(
            $conn,
            'UPDATE authenticator_management_rate_limits '
                . 'SET window_started_at = NOW(6), request_count = 1 '
                . 'WHERE scope = ? AND scope_hash = ?'
        );
        $statement->bind_param('ss', $scope, $scopeHash);
        if (!$statement->execute() || $statement->affected_rows !== 1) {
            $statement->close();
            throw new RuntimeException('Authenticator rate limit could not be reset.');
        }
        $statement->close();
        return 0;
    }

    if ((int)($row['request_count'] ?? 0) >= $limit) {
        return max(1, $windowSeconds - $elapsed);
    }

    $statement = pc_prepare(
        $conn,
        'UPDATE authenticator_management_rate_limits '
            . 'SET request_count = request_count + 1 '
            . 'WHERE scope = ? AND scope_hash = ?'
    );
    $statement->bind_param('ss', $scope, $scopeHash);
    if (!$statement->execute() || $statement->affected_rows !== 1) {
        $statement->close();
        throw new RuntimeException('Authenticator rate limit could not be updated.');
    }
    $statement->close();
    return 0;
}

/**
 * @param array<string, mixed> $config
 * @return array{account_retry_after:int,ip_retry_after:int,ip_hash:string}
 */
function am_consume_pre_auth_attempt(
    mysqli $conn,
    string $role,
    string $claimedUserId,
    array $config
): array {
    $rateUserId = mb_strtoupper($claimedUserId, 'UTF-8');
    $accountHash = am_rate_scope_hash(
        'preauth-account' . "\0" . $role . "\0" . $rateUserId,
        $config
    );
    $ipHash = am_remote_ip_hash($config);
    return [
        'account_retry_after' => am_consume_rate_limit(
            $conn,
            'preauth_account',
            $accountHash,
            AM_PREAUTH_ACCOUNT_LIMIT,
            AM_PREAUTH_ACCOUNT_WINDOW_SECONDS
        ),
        'ip_retry_after' => am_consume_rate_limit(
            $conn,
            'preauth_ip',
            $ipHash,
            AM_PREAUTH_IP_LIMIT,
            AM_PREAUTH_IP_WINDOW_SECONDS
        ),
        'ip_hash' => $ipHash,
    ];
}

/**
 * @param array<string, mixed> $config
 * @return array{retry_after:int,ip_hash:string}
 */
function am_consume_verify_ip_attempt(mysqli $conn, array $config): array
{
    $ipHash = am_remote_ip_hash($config);
    return [
        'retry_after' => am_consume_rate_limit(
            $conn,
            'verify_ip',
            $ipHash,
            AM_VERIFY_IP_LIMIT,
            AM_VERIFY_IP_WINDOW_SECONDS
        ),
        'ip_hash' => $ipHash,
    ];
}

/** @param array<string, mixed> $config */
function am_consume_verify_account_attempt(
    mysqli $conn,
    string $role,
    string $userId,
    array $config
): int {
    $rateUserId = mb_strtoupper($userId, 'UTF-8');
    $accountHash = am_rate_scope_hash(
        'verify-account' . "\0" . $role . "\0" . $rateUserId,
        $config
    );
    return am_consume_rate_limit(
        $conn,
        'verify_account',
        $accountHash,
        AM_VERIFY_ACCOUNT_LIMIT,
        AM_VERIFY_ACCOUNT_WINDOW_SECONDS
    );
}

/** @return array{password_value:string,account_source:string,user_id:string} */
function am_authenticate_account_for_management(
    mysqli $conn,
    string $role,
    string $userId,
    string $currentPassword,
    ?string $expectedAccountSource = null
): array {
    try {
        $account = pc_fetch_account_for_update(
            $conn,
            $role,
            $userId,
            $expectedAccountSource
        );
    } catch (PasswordChangeClientException $error) {
        password_verify($currentPassword, AM_DUMMY_PASSWORD_HASH);
        pc_reject('Account ID or current password is incorrect.');
    }

    $storedCredential = (string)$account['password_value'];
    if (!pc_password_matches($currentPassword, $storedCredential)) {
        if (!pc_is_password_hash($storedCredential)) {
            password_verify($currentPassword, AM_DUMMY_PASSWORD_HASH);
        }
        pc_reject('Account ID or current password is incorrect.');
    }
    return $account;
}

/** @return array<string, mixed>|null */
function am_authenticator_for_update(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId
): ?array {
    $statement = pc_prepare(
        $conn,
        'SELECT totp_secret_encrypted, enrolled_at, last_verified_at, '
            . 'last_used_step, updated_at '
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

/** @param array<string, mixed> $config */
function am_authenticator_fingerprint(
    string $role,
    string $accountSource,
    string $userId,
    string $encryptedSecret,
    array $config
): string {
    return hash_hmac(
        'sha256',
        $role . "\0" . $accountSource . "\0" . $userId . "\0" . $encryptedSecret,
        pc_derived_key($config, 'authenticator-management-state')
    );
}

function am_challenge_token_hash(string $token): string
{
    if (strlen($token) < 40 || strlen($token) > 100 || pc_base64url_decode($token) === '') {
        pc_reject('The authenticator-management request is invalid or has expired.');
    }
    return hash('sha256', $token);
}

/** @return array<string, mixed>|null */
function am_challenge_preview(mysqli $conn, string $tokenHash): ?array
{
    $statement = pc_prepare(
        $conn,
        'SELECT challenge_id, role, account_source, user_id, action '
            . 'FROM authenticator_management_challenges '
            . 'WHERE challenge_token_hash = ? LIMIT 1'
    );
    $statement->bind_param('s', $tokenHash);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Authenticator challenge lookup failed.');
    }
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    return is_array($row) ? $row : null;
}

/** @return array<string, mixed>|null */
function am_challenge_for_update(mysqli $conn, string $tokenHash): ?array
{
    $statement = pc_prepare(
        $conn,
        'SELECT *, (expires_at <= NOW(6)) AS challenge_expired '
            . 'FROM authenticator_management_challenges '
            . 'WHERE challenge_token_hash = ? LIMIT 1 FOR UPDATE'
    );
    $statement->bind_param('s', $tokenHash);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Authenticator challenge lookup failed.');
    }
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    return is_array($row) ? $row : null;
}

/** @param array<string, mixed> $challenge */
function am_assert_pending_challenge(array $challenge): void
{
    if (($challenge['status'] ?? '') !== 'pending') {
        pc_reject('The authenticator-management request is no longer active. Start a new request.');
    }
    if ((int)($challenge['failed_attempts'] ?? AM_MAX_ATTEMPTS) >= AM_MAX_ATTEMPTS) {
        pc_reject(
            'Too many incorrect authenticator codes. Start a new request.',
            ['attempts_remaining' => 0]
        );
    }
}

function am_cancel_pending_challenges(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId
): void {
    $statement = pc_prepare(
        $conn,
        "UPDATE authenticator_management_challenges SET status = 'cancelled', "
            . 'pending_totp_secret_encrypted = NULL, '
            . 'expected_authenticator_fingerprint = NULL '
            . 'WHERE role = ? AND account_source = ? AND user_id = ? '
            . "AND status = 'pending'"
    );
    $statement->bind_param('sss', $role, $accountSource, $userId);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Old authenticator challenges could not be cancelled.');
    }
    $statement->close();
}

function am_mark_challenge_cancelled(mysqli $conn, int $challengeId): void
{
    $statement = pc_prepare(
        $conn,
        "UPDATE authenticator_management_challenges SET status = 'cancelled', "
            . 'pending_totp_secret_encrypted = NULL, '
            . 'expected_authenticator_fingerprint = NULL '
            . "WHERE challenge_id = ? AND status = 'pending'"
    );
    $statement->bind_param('i', $challengeId);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Authenticator challenge could not be cancelled.');
    }
    $statement->close();
}

function am_expire_challenge(mysqli $conn, int $challengeId): void
{
    $statement = pc_prepare(
        $conn,
        "UPDATE authenticator_management_challenges SET status = 'expired', "
            . 'pending_totp_secret_encrypted = NULL, '
            . 'expected_authenticator_fingerprint = NULL '
            . "WHERE challenge_id = ? AND status = 'pending'"
    );
    $statement->bind_param('i', $challengeId);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Authenticator challenge could not be expired.');
    }
    $statement->close();
}

function am_increment_failed_attempt(
    mysqli $conn,
    int $challengeId,
    int $existingAttempts
): int {
    $failedAttempts = min(AM_MAX_ATTEMPTS, $existingAttempts + 1);
    if ($failedAttempts >= AM_MAX_ATTEMPTS) {
        $statement = pc_prepare(
            $conn,
            "UPDATE authenticator_management_challenges SET failed_attempts = ?, "
                . "status = 'failed', pending_totp_secret_encrypted = NULL, "
                . 'expected_authenticator_fingerprint = NULL '
                . "WHERE challenge_id = ? AND status = 'pending'"
        );
    } else {
        $statement = pc_prepare(
            $conn,
            'UPDATE authenticator_management_challenges SET failed_attempts = ? '
                . "WHERE challenge_id = ? AND status = 'pending'"
        );
    }
    $statement->bind_param('ii', $failedAttempts, $challengeId);
    if (!$statement->execute() || $statement->affected_rows !== 1) {
        $statement->close();
        throw new RuntimeException('Authenticator verification attempt could not be recorded.');
    }
    $statement->close();
    return AM_MAX_ATTEMPTS - $failedAttempts;
}

function am_mark_challenge_verified(mysqli $conn, int $challengeId): void
{
    $statement = pc_prepare(
        $conn,
        "UPDATE authenticator_management_challenges SET status = 'verified', "
            . 'verified_at = NOW(6), pending_totp_secret_encrypted = NULL, '
            . 'expected_authenticator_fingerprint = NULL '
            . "WHERE challenge_id = ? AND status = 'pending'"
    );
    $statement->bind_param('i', $challengeId);
    if (!$statement->execute() || $statement->affected_rows !== 1) {
        $statement->close();
        throw new RuntimeException('Authenticator challenge could not be completed.');
    }
    $statement->close();
}

function am_insert_authenticator(
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
    if (!$statement->execute() || $statement->affected_rows !== 1) {
        $statement->close();
        throw new RuntimeException('Authenticator enrollment could not be saved.');
    }
    $statement->close();
}

function am_delete_authenticator(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId
): void {
    $statement = pc_prepare(
        $conn,
        'DELETE FROM password_change_authenticators '
            . 'WHERE role = ? AND account_source = ? AND user_id = ?'
    );
    $statement->bind_param('sss', $role, $accountSource, $userId);
    if (!$statement->execute() || $statement->affected_rows !== 1) {
        $statement->close();
        throw new RuntimeException('Authenticator enrollment could not be removed.');
    }
    $statement->close();
}

function am_cancel_pending_password_totp_challenges(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId
): void {
    $statement = pc_prepare(
        $conn,
        "UPDATE password_change_challenges SET status = 'cancelled', "
            . 'pending_totp_secret_encrypted = NULL '
            . 'WHERE role = ? AND account_source = ? AND user_id = ? '
            . "AND method = 'totp' AND status = 'pending'"
    );
    $statement->bind_param('sss', $role, $accountSource, $userId);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Pending password challenges could not be cancelled.');
    }
    $statement->close();
}

function am_record_event(
    mysqli $conn,
    int $challengeId,
    string $role,
    string $accountSource,
    string $userId,
    string $eventType,
    string $requestIpHash
): void {
    if (!in_array($eventType, ['enrolled', 'removed'], true)) {
        throw new RuntimeException('Invalid authenticator event type.');
    }
    $statement = pc_prepare(
        $conn,
        'INSERT INTO authenticator_management_events '
            . '(challenge_id, role, account_source, user_id, event_type, request_ip_hash) '
            . 'VALUES (?, ?, ?, ?, ?, ?)'
    );
    $statement->bind_param(
        'isssss',
        $challengeId,
        $role,
        $accountSource,
        $userId,
        $eventType,
        $requestIpHash
    );
    if (!$statement->execute() || $statement->affected_rows !== 1) {
        $statement->close();
        throw new RuntimeException('Authenticator event could not be recorded.');
    }
    $statement->close();
}
