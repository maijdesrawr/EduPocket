<?php

declare(strict_types=1);

require_once __DIR__ . '/password_change_common.php';

const EV_OTP_TTL_SECONDS = 300;
const EV_MAX_ATTEMPTS = 5;
const EV_RESEND_COOLDOWN_SECONDS = 60;
const EV_MAX_RESENDS = 3;
const EV_ACCOUNT_REQUEST_LIMIT = 3;
const EV_ACCOUNT_REQUEST_WINDOW_SECONDS = 120;
const EV_PREAUTH_ACCOUNT_ATTEMPT_LIMIT = 5;
const EV_PREAUTH_ACCOUNT_WINDOW_SECONDS = 900;
const EV_PREAUTH_IP_ATTEMPT_LIMIT = 30;
const EV_PREAUTH_IP_WINDOW_SECONDS = 3600;
const EV_CHALLENGE_RETENTION_SECONDS = 2592000;
const EV_RATE_LIMIT_RETENTION_SECONDS = 86400;
const EV_PURGE_BATCH_SIZE = 250;
const EV_DUMMY_PASSWORD_HASH = '$2y$10$clswDbybqTmePMnXRsPSoeVZCtUnwEKE2ooAPc/g1aimLdJKROG1u';

function ev_require_schema(mysqli $conn): void
{
    foreach (
        [
            'account_verified_emails',
            'email_verification_challenges',
            'email_verification_rate_limits',
        ] as $table
    ) {
        if (!pc_table_exists($conn, $table)) {
            throw new RuntimeException('Email verification database migration is missing.');
        }
    }
}

function ev_purge_stale_security_state(mysqli $conn): void
{
    $challengeRetention = EV_CHALLENGE_RETENTION_SECONDS;
    $rateRetention = EV_RATE_LIMIT_RETENTION_SECONDS;
    $batchSize = EV_PURGE_BATCH_SIZE;

    $sql = "DELETE FROM email_verification_challenges "
        . "WHERE status = 'pending' "
        . "AND expires_at < DATE_SUB(NOW(6), INTERVAL {$challengeRetention} SECOND) "
        . "LIMIT {$batchSize}";
    if (!$conn->query($sql)) {
        throw new RuntimeException('Stale pending email challenges could not be purged.');
    }

    $sql = "UPDATE email_verification_challenges SET status = 'expired' "
        . "WHERE status = 'pending' AND expires_at <= NOW(6) LIMIT {$batchSize}";
    if (!$conn->query($sql)) {
        throw new RuntimeException('Expired email challenges could not be marked.');
    }

    $sql = "DELETE FROM email_verification_challenges "
        . "WHERE status IN ('expired', 'cancelled', 'failed', 'verified') "
        . "AND updated_at < DATE_SUB(NOW(6), INTERVAL {$challengeRetention} SECOND) "
        . "LIMIT {$batchSize}";
    if (!$conn->query($sql)) {
        throw new RuntimeException('Retained email challenges could not be purged.');
    }

    $sql = "DELETE FROM email_verification_rate_limits "
        . "WHERE updated_at < DATE_SUB(NOW(6), INTERVAL {$rateRetention} SECOND) "
        . "AND window_started_at < DATE_SUB(NOW(6), INTERVAL {$rateRetention} SECOND) "
        . "LIMIT {$batchSize}";
    if (!$conn->query($sql)) {
        throw new RuntimeException('Stale email rate limits could not be purged.');
    }
}

function ev_normalize_email(string $email): string
{
    $normalized = strtolower(trim($email));
    if ($normalized === ''
        || strlen($normalized) > 254
        || preg_match('/[\r\n\0]/', $normalized) === 1
        || filter_var($normalized, FILTER_VALIDATE_EMAIL) === false
    ) {
        pc_reject('Enter a valid email address.');
    }
    return $normalized;
}


function ev_email_fingerprint(string $email, array $config): string
{
    return hash_hmac(
        'sha256',
        strtolower(trim($email)),
        pc_derived_key($config, 'verified-email-fingerprint')
    );
}


function ev_encrypt_verified_email(
    string $email,
    string $role,
    string $accountSource,
    string $userId,
    array $config
): string {
    return pc_encrypt_protected_value(
        $email,
        'verified-email',
        $role,
        $accountSource,
        $userId,
        $config
    );
}


function ev_decrypt_verified_email(
    string $encrypted,
    string $role,
    string $accountSource,
    string $userId,
    array $config
): string {
    $email = pc_decrypt_protected_value(
        $encrypted,
        'verified-email',
        $role,
        $accountSource,
        $userId,
        $config
    );
    if (filter_var($email, FILTER_VALIDATE_EMAIL) === false || strlen($email) > 254) {
        throw new RuntimeException('Verified email decryption failed.');
    }
    return strtolower($email);
}


function ev_encrypt_challenge_email(
    string $email,
    string $purpose,
    string $role,
    string $accountSource,
    string $userId,
    array $config
): string {
    if (!in_array($purpose, ['proposed', 'destination'], true)) {
        throw new RuntimeException('Invalid email-verification encryption purpose.');
    }
    return pc_encrypt_protected_value(
        $email,
        'email-verification-' . $purpose,
        $role,
        $accountSource,
        $userId,
        $config
    );
}


function ev_decrypt_challenge_email(
    string $encrypted,
    string $purpose,
    string $role,
    string $accountSource,
    string $userId,
    array $config
): string {
    if (!in_array($purpose, ['proposed', 'destination'], true)) {
        throw new RuntimeException('Invalid email-verification encryption purpose.');
    }
    $email = pc_decrypt_protected_value(
        $encrypted,
        'email-verification-' . $purpose,
        $role,
        $accountSource,
        $userId,
        $config
    );
    if (filter_var($email, FILTER_VALIDATE_EMAIL) === false || strlen($email) > 254) {
        throw new RuntimeException('Email-verification destination decryption failed.');
    }
    return strtolower($email);
}


function ev_otp_hash(string $challengeTokenHash, string $code, array $config): string
{
    return hash_hmac(
        'sha256',
        $challengeTokenHash . "\0" . $code,
        pc_derived_key($config, 'email-verification-otp')
    );
}


function ev_new_challenge_token(): array
{
    return pc_new_challenge_token();
}

function ev_challenge_token_hash(string $token): string
{
    if (strlen($token) < 40 || strlen($token) > 100 || pc_base64url_decode($token) === '') {
        pc_reject('The email-verification request is invalid or has expired.');
    }
    return hash('sha256', $token);
}


function ev_rate_scope_hash(string $scopeValue, array $config): string
{
    return hash_hmac(
        'sha256',
        $scopeValue,
        pc_derived_key($config, 'email-verification-rate-limit')
    );
}


function ev_remote_ip_hash(array $config): string
{
    $address = trim((string)($_SERVER['REMOTE_ADDR'] ?? ''));
    if (filter_var($address, FILTER_VALIDATE_IP) === false) {
        $address = 'unknown';
    }
    return ev_rate_scope_hash('ip' . "\0" . $address, $config);
}

function ev_consume_rate_limit(
    mysqli $conn,
    string $scope,
    string $scopeHash,
    int $limit,
    int $windowSeconds
): int {
    if ($scope === '' || strlen($scope) > 16 || preg_match('/^[a-z_]+$/', $scope) !== 1
        || preg_match('/^[a-f0-9]{64}$/', $scopeHash) !== 1
        || $limit < 1
        || $windowSeconds < 1
    ) {
        throw new RuntimeException('Email verification rate limit configuration is invalid.');
    }

    $statement = pc_prepare(
        $conn,
        'INSERT INTO email_verification_rate_limits '
            . '(scope, scope_hash, window_started_at, request_count) '
            . 'VALUES (?, ?, NOW(6), 0) '
            . 'ON DUPLICATE KEY UPDATE scope_hash = VALUES(scope_hash)'
    );
    $statement->bind_param('ss', $scope, $scopeHash);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Email verification rate limit could not be locked.');
    }
    $statement->close();

    $statement = pc_prepare(
        $conn,
        'SELECT request_count, '
            . 'TIMESTAMPDIFF(SECOND, window_started_at, NOW(6)) AS elapsed_seconds '
            . 'FROM email_verification_rate_limits '
            . 'WHERE scope = ? AND scope_hash = ? FOR UPDATE'
    );
    $statement->bind_param('ss', $scope, $scopeHash);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Email verification rate limit lookup failed.');
    }
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();

    if (!is_array($row)) {
        throw new RuntimeException('Email verification rate limit lock disappeared.');
    }

    $elapsed = max(0, (int)($row['elapsed_seconds'] ?? 0));
    if ($elapsed >= $windowSeconds) {
        $statement = pc_prepare(
            $conn,
            'UPDATE email_verification_rate_limits '
                . 'SET window_started_at = NOW(6), request_count = 1 '
                . 'WHERE scope = ? AND scope_hash = ?'
        );
        $statement->bind_param('ss', $scope, $scopeHash);
        if (!$statement->execute() || $statement->affected_rows !== 1) {
            $statement->close();
            throw new RuntimeException('Email verification rate limit could not be reset.');
        }
        $statement->close();
        return 0;
    }

    if ((int)($row['request_count'] ?? 0) >= $limit) {
        return max(1, $windowSeconds - $elapsed);
    }

    $statement = pc_prepare(
        $conn,
        'UPDATE email_verification_rate_limits '
            . 'SET request_count = request_count + 1 '
            . 'WHERE scope = ? AND scope_hash = ?'
    );
    $statement->bind_param('ss', $scope, $scopeHash);
    if (!$statement->execute() || $statement->affected_rows !== 1) {
        $statement->close();
        throw new RuntimeException('Email verification rate limit could not be updated.');
    }
    $statement->close();
    return 0;
}


function ev_enforce_request_rate_limits(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId,
    array $config
): void {
    $windowSeconds = EV_ACCOUNT_REQUEST_WINDOW_SECONDS;
    $statement = pc_prepare(
        $conn,
        'SELECT COUNT(*) AS request_count, '
            . 'TIMESTAMPDIFF(SECOND, MIN(created_at), NOW(6)) AS oldest_age '
            . 'FROM email_verification_challenges '
            . 'WHERE role = ? AND account_source = ? AND user_id = ? '
            . "AND created_at > DATE_SUB(NOW(6), INTERVAL {$windowSeconds} SECOND)"
    );
    $statement->bind_param('sss', $role, $accountSource, $userId);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Email verification request history lookup failed.');
    }
    $history = $statement->get_result()->fetch_assoc();
    $statement->close();
    if ((int)($history['request_count'] ?? 0) >= EV_ACCOUNT_REQUEST_LIMIT) {
        $oldestAge = max(0, (int)($history['oldest_age'] ?? 0));
        pc_reject(
            'Too many email-verification requests. Please try again later.',
            ['retry_after' => max(1, EV_ACCOUNT_REQUEST_WINDOW_SECONDS - $oldestAge)]
        );
    }

    unset($config);
}




function ev_consume_pre_auth_attempt(
    mysqli $conn,
    string $role,
    string $claimedUserId,
    array $config
): array {
    $rateUserId = mb_strtoupper($claimedUserId, 'UTF-8');
    $claimedAccountHash = ev_rate_scope_hash(
        'claimed-account' . "\0" . $role . "\0" . $rateUserId,
        $config
    );
    $ipHash = ev_remote_ip_hash($config);
    return [
        'account_retry_after' => ev_consume_rate_limit(
            $conn,
            'preauth_account',
            $claimedAccountHash,
            EV_PREAUTH_ACCOUNT_ATTEMPT_LIMIT,
            EV_PREAUTH_ACCOUNT_WINDOW_SECONDS
        ),
        'ip_retry_after' => ev_consume_rate_limit(
            $conn,
            'preauth_ip',
            $ipHash,
            EV_PREAUTH_IP_ATTEMPT_LIMIT,
            EV_PREAUTH_IP_WINDOW_SECONDS
        ),
        'ip_hash' => $ipHash,
    ];
}


function ev_authenticate_account_for_enrollment(
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
        password_verify($currentPassword, EV_DUMMY_PASSWORD_HASH);
        pc_reject('Account ID or current password is incorrect.');
    }
    $storedCredential = (string)$account['password_value'];
    if (!pc_password_matches($currentPassword, $storedCredential)) {
        if (!pc_is_password_hash($storedCredential)) {
            password_verify($currentPassword, EV_DUMMY_PASSWORD_HASH);
        }
        pc_reject('Account ID or current password is incorrect.');
    }
    return $account;
}


function ev_verified_email_record(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId,
    bool $forUpdate = false
): ?array {
    $sql = 'SELECT email_encrypted, email_masked, email_fingerprint, verified_at '
        . 'FROM account_verified_emails '
        . 'WHERE role = ? AND account_source = ? AND user_id = ?'
        . ($forUpdate ? ' FOR UPDATE' : '');
    $statement = pc_prepare($conn, $sql);
    $statement->bind_param('sss', $role, $accountSource, $userId);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Verified email lookup failed.');
    }
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    return is_array($row) ? $row : null;
}


function ev_resolve_verified_email_destination(
    mysqli $conn,
    array $config,
    string $role,
    string $accountSource,
    string $userId,
    string $requestedAddress = ''
): string {
    ev_require_schema($conn);
    $record = ev_verified_email_record($conn, $role, $accountSource, $userId);
    if ($record === null) {
        pc_reject(
            'No verified email is enrolled for this account. Verify an email address first or choose Authenticator.'
        );
    }

    $destination = ev_decrypt_verified_email(
        (string)($record['email_encrypted'] ?? ''),
        $role,
        $accountSource,
        $userId,
        $config
    );
    $expectedFingerprint = ev_email_fingerprint($destination, $config);
    if (!hash_equals((string)($record['email_fingerprint'] ?? ''), $expectedFingerprint)) {
        throw new RuntimeException('Verified email integrity check failed.');
    }

    if (trim($requestedAddress) !== '') {
        $requested = ev_normalize_email($requestedAddress);
        if (!hash_equals($destination, $requested)) {
            pc_reject('The email address is not the verified address for this account.');
        }
    }
    return $destination;
}


function ev_save_verified_email(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId,
    string $email,
    array $config
): string {
    $normalized = ev_normalize_email($email);
    $encrypted = ev_encrypt_verified_email(
        $normalized,
        $role,
        $accountSource,
        $userId,
        $config
    );
    $masked = pc_mask_email($normalized);
    $fingerprint = ev_email_fingerprint($normalized, $config);
    $statement = pc_prepare(
        $conn,
        'INSERT INTO account_verified_emails '
            . '(role, account_source, user_id, email_encrypted, email_masked, '
            . 'email_fingerprint, verified_at) '
            . 'VALUES (?, ?, ?, ?, ?, ?, NOW(6)) '
            . 'ON DUPLICATE KEY UPDATE '
            . 'email_encrypted = VALUES(email_encrypted), '
            . 'email_masked = VALUES(email_masked), '
            . 'email_fingerprint = VALUES(email_fingerprint), '
            . 'verified_at = NOW(6)'
    );
    $statement->bind_param(
        'ssssss',
        $role,
        $accountSource,
        $userId,
        $encrypted,
        $masked,
        $fingerprint
    );
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Verified email could not be saved.');
    }
    $statement->close();
    return $masked;
}

function ev_cancel_pending_challenges(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId
): void {
    $statement = pc_prepare(
        $conn,
        "UPDATE email_verification_challenges SET status = 'cancelled' "
            . "WHERE role = ? AND account_source = ? AND user_id = ? AND status = 'pending'"
    );
    $statement->bind_param('sss', $role, $accountSource, $userId);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Previous email-verification requests could not be cancelled.');
    }
    $statement->close();
}


function ev_challenge_preview(mysqli $conn, string $tokenHash): ?array
{
    $statement = pc_prepare(
        $conn,
        'SELECT challenge_id, role, account_source, user_id '
            . 'FROM email_verification_challenges '
            . 'WHERE challenge_token_hash = ? LIMIT 1'
    );
    $statement->bind_param('s', $tokenHash);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Email-verification challenge lookup failed.');
    }
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    return is_array($row) ? $row : null;
}


function ev_challenge_for_update(mysqli $conn, string $tokenHash): ?array
{
    $statement = pc_prepare(
        $conn,
        'SELECT *, '
            . '(expires_at <= NOW(6)) AS challenge_expired, '
            . '(otp_expires_at <= NOW(6)) AS otp_expired, '
            . 'TIMESTAMPDIFF(SECOND, last_sent_at, NOW(6)) AS seconds_since_last_send '
            . 'FROM email_verification_challenges '
            . 'WHERE challenge_token_hash = ? FOR UPDATE'
    );
    $statement->bind_param('s', $tokenHash);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Email-verification challenge lookup failed.');
    }
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    return is_array($row) ? $row : null;
}


function ev_assert_pending_challenge(array $challenge): void
{
    if ((string)($challenge['status'] ?? '') !== 'pending') {
        pc_reject('The email-verification request is no longer active. Start a new request.');
    }
    if ((int)($challenge['failed_attempts'] ?? EV_MAX_ATTEMPTS) >= EV_MAX_ATTEMPTS) {
        pc_reject(
            'Too many incorrect verification attempts. Start a new request.',
            ['attempts_remaining' => 0]
        );
    }
}

function ev_set_challenge_status(mysqli $conn, int $challengeId, string $status): void
{
    $statement = pc_prepare(
        $conn,
        'UPDATE email_verification_challenges '
            . 'SET status = ?, verified_at = '
            . "CASE WHEN ? = 'verified' THEN NOW(6) ELSE verified_at END "
            . 'WHERE challenge_id = ?'
    );
    $statement->bind_param('ssi', $status, $status, $challengeId);
    if (!$statement->execute() || $statement->affected_rows !== 1) {
        $statement->close();
        throw new RuntimeException('Email-verification challenge state could not be updated.');
    }
    $statement->close();
}

function ev_cancel_challenge_by_hash(mysqli $conn, string $tokenHash): void
{
    $statement = pc_prepare(
        $conn,
        "UPDATE email_verification_challenges SET status = 'cancelled' "
            . "WHERE challenge_token_hash = ? AND status = 'pending'"
    );
    $statement->bind_param('s', $tokenHash);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Email-verification challenge could not be cancelled.');
    }
    $statement->close();
}

function ev_increment_failed_attempt(
    mysqli $conn,
    int $challengeId,
    int $existingAttempts
): int {
    $failedAttempts = min(EV_MAX_ATTEMPTS, $existingAttempts + 1);
    $status = $failedAttempts >= EV_MAX_ATTEMPTS ? 'failed' : 'pending';
    $statement = pc_prepare(
        $conn,
        'UPDATE email_verification_challenges '
            . 'SET failed_attempts = ?, status = ? WHERE challenge_id = ?'
    );
    $statement->bind_param('isi', $failedAttempts, $status, $challengeId);
    if (!$statement->execute() || $statement->affected_rows !== 1) {
        $statement->close();
        throw new RuntimeException('Email-verification attempt could not be recorded.');
    }
    $statement->close();
    return EV_MAX_ATTEMPTS - $failedAttempts;
}
