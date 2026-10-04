<?php

require_once __DIR__ . '/password_change_common.php';
require_once __DIR__ . '/email_verification_common.php';
require_once __DIR__ . '/app_session_common.php';

const LO_CHALLENGE_TTL_SECONDS = 300;
const LO_MAX_ATTEMPTS = 5;
const LO_MAX_RESENDS = 5;
const LO_RESEND_COOLDOWN_SECONDS = 30;
const LO_RATE_WINDOW_SECONDS = 900;
const LO_EMAIL_CHALLENGE_LIMIT = 6;
const LO_TOTP_CHALLENGE_LIMIT = 20;
const LO_IP_CHALLENGE_LIMIT = 60;
const LO_DUMMY_PASSWORD_HASH = '$2y$10$wHhJfCdLJjTjvV1QYqM7J.WtKbn71m4n5cVhRX5S4DVfSRqbdL5JC';

function lo_require_secure_transport(): void
{
    if (pc_uses_secure_or_local_transport()) return;

    pc_reject('Login requires a secure HTTPS connection.');
}

/** @param array<string, mixed> $config */
function lo_remote_ip_hash(array $config): string
{
    $address = trim((string)($_SERVER['REMOTE_ADDR'] ?? 'unknown'));
    if ($address === '') {
        $address = 'unknown';
    }
    return hash_hmac(
        'sha256',
        'login-ip' . "\0" . $address,
        pc_derived_key($config, 'login-otp-rate-limit')
    );
}

function lo_rate_retry_after(?string $oldestCreatedAt): int
{
    $oldest = $oldestCreatedAt === null ? false : strtotime($oldestCreatedAt);
    if ($oldest === false) {
        return LO_RATE_WINDOW_SECONDS;
    }
    return max(1, LO_RATE_WINDOW_SECONDS - (time() - $oldest));
}

function lo_enforce_challenge_rate_limits(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId,
    string $method,
    string $ipHash
): void {
    $window = LO_RATE_WINDOW_SECONDS;
    $accountLimit = $method === 'email'
        ? LO_EMAIL_CHALLENGE_LIMIT
        : LO_TOTP_CHALLENGE_LIMIT;

    $account = pc_prepare(
        $conn,
        'SELECT COUNT(*) AS request_count, MIN(created_at) AS oldest_created_at '
            . 'FROM login_otp_challenges '
            . 'WHERE role = ? AND account_source = ? AND user_id = ? '
            . "AND created_at > DATE_SUB(NOW(6), INTERVAL {$window} SECOND)"
    );
    $account->bind_param('sss', $role, $accountSource, $userId);
    $account->execute();
    $accountUsage = $account->get_result()->fetch_assoc();
    $account->close();
    if ((int)($accountUsage['request_count'] ?? 0) >= $accountLimit) {
        pc_reject(
            'Too many login verification requests. Please wait before trying again.',
            ['retry_after' => lo_rate_retry_after($accountUsage['oldest_created_at'] ?? null)]
        );
    }

    $ip = pc_prepare(
        $conn,
        'SELECT COUNT(*) AS request_count, MIN(created_at) AS oldest_created_at '
            . 'FROM login_otp_challenges WHERE request_ip_hash = ? '
            . "AND created_at > DATE_SUB(NOW(6), INTERVAL {$window} SECOND)"
    );
    $ip->bind_param('s', $ipHash);
    $ip->execute();
    $ipUsage = $ip->get_result()->fetch_assoc();
    $ip->close();
    if ((int)($ipUsage['request_count'] ?? 0) >= LO_IP_CHALLENGE_LIMIT) {
        pc_reject(
            'Too many login verification requests from this device. Please wait and try again.',
            ['retry_after' => lo_rate_retry_after($ipUsage['oldest_created_at'] ?? null)]
        );
    }
}

function lo_normalize_login_id(string $value): string
{
    $value = trim($value);
    $withoutInvisibleSpacing = preg_replace(
        '/[\p{Z}\s\x{200B}-\x{200D}\x{FEFF}]+/u',
        '',
        $value
    );
    if (is_string($withoutInvisibleSpacing)) {
        $value = $withoutInvisibleSpacing;
    }

    if (!function_exists('mb_ord')) {
        return $value;
    }

    $letterRanges = [
        [0x1D400, 0x1D419, 65], [0x1D41A, 0x1D433, 97],
        [0x1D434, 0x1D44D, 65], [0x1D44E, 0x1D467, 97],
        [0x1D468, 0x1D481, 65], [0x1D482, 0x1D49B, 97],
        [0x1D49C, 0x1D4B5, 65], [0x1D4B6, 0x1D4CF, 97],
        [0x1D4D0, 0x1D4E9, 65], [0x1D4EA, 0x1D503, 97],
        [0x1D504, 0x1D51D, 65], [0x1D51E, 0x1D537, 97],
        [0x1D538, 0x1D551, 65], [0x1D552, 0x1D56B, 97],
        [0x1D56C, 0x1D585, 65], [0x1D586, 0x1D59F, 97],
        [0x1D5A0, 0x1D5B9, 65], [0x1D5BA, 0x1D5D3, 97],
        [0x1D5D4, 0x1D5ED, 65], [0x1D5EE, 0x1D607, 97],
        [0x1D608, 0x1D621, 65], [0x1D622, 0x1D63B, 97],
        [0x1D63C, 0x1D655, 65], [0x1D656, 0x1D66F, 97],
        [0x1D670, 0x1D689, 65], [0x1D68A, 0x1D6A3, 97],
        [0xFF21, 0xFF3A, 65], [0xFF41, 0xFF5A, 97],
    ];
    $digitStarts = [0x1D7CE, 0x1D7D8, 0x1D7E2, 0x1D7EC, 0x1D7F6, 0xFF10];
    $characters = preg_split('//u', $value, -1, PREG_SPLIT_NO_EMPTY);
    if (!is_array($characters)) {
        return $value;
    }

    $normalized = '';
    foreach ($characters as $character) {
        $codePoint = mb_ord($character, 'UTF-8');
        foreach ($letterRanges as [$start, $end, $asciiStart]) {
            if ($codePoint >= $start && $codePoint <= $end) {
                $normalized .= chr($asciiStart + ($codePoint - $start));
                continue 2;
            }
        }
        foreach ($digitStarts as $start) {
            if ($codePoint >= $start && $codePoint <= $start + 9) {
                $normalized .= chr(48 + ($codePoint - $start));
                continue 2;
            }
        }
        $normalized .= $character;
    }
    return $normalized;
}

/** @return array<string, mixed>|null */
function lo_find_login_account(mysqli $conn, string $loginId): ?array
{
    $queries = [];
    if (pc_table_exists($conn, 'students')) {
        $passwordChanged = pc_column_exists($conn, 'students', 'password_changed')
            ? 'password_changed'
            : '1 AS password_changed';
        $queries[] = [
            'sql' => "SELECT student_num AS id, Fname AS name, Password AS password_value, "
                . "$passwordChanged, 'student' AS app_role, 'students' AS account_source "
                . 'FROM students WHERE student_num = ? LIMIT 1',
            'types' => 's',
            'params' => [$loginId],
        ];
    }
    if (pc_table_exists($conn, 'parents')) {
        $passwordChanged = pc_column_exists($conn, 'parents', 'password_changed')
            ? 'password_changed'
            : '1 AS password_changed';
        $queries[] = [
            'sql' => "SELECT parent_id AS id, Fname AS name, Password AS password_value, "
                . "$passwordChanged, 'parent' AS app_role, 'parents' AS account_source "
                . 'FROM parents WHERE parent_id = ? LIMIT 1',
            'types' => 's',
            'params' => [$loginId],
        ];
    }
    if (pc_table_exists($conn, 'admins')) {
        $roleExpression = pc_column_exists($conn, 'admins', 'role')
            ? "CASE WHEN LOWER(COALESCE(role, '')) = 'cashier' THEN 'cashier' ELSE 'admin' END"
            : "'admin'";
        $queries[] = [
            'sql' => "SELECT admin_id AS id, Fname AS name, password AS password_value, "
                . "1 AS password_changed, $roleExpression AS app_role, 'admins' AS account_source "
                . 'FROM admins WHERE username = ? OR admin_id = ? LIMIT 1',
            'types' => 'ss',
            'params' => [$loginId, $loginId],
        ];
    }
    if (pc_table_exists($conn, 'cashiers')) {
        $queries[] = [
            'sql' => "SELECT cashier_id AS id, Fname AS name, password AS password_value, "
                . "1 AS password_changed, 'cashier' AS app_role, 'cashiers' AS account_source "
                . 'FROM cashiers WHERE cashier_id = ? OR username = ? LIMIT 1',
            'types' => 'ss',
            'params' => [$loginId, $loginId],
        ];
    }
    if (pc_table_exists($conn, 'canteens')) {
        $queries[] = [
            'sql' => "SELECT canteen_id AS id, Fname AS name, Password AS password_value, "
                . "1 AS password_changed, 'canteen' AS app_role, 'canteens' AS account_source "
                . 'FROM canteens WHERE canteen_id = ? LIMIT 1',
            'types' => 's',
            'params' => [$loginId],
        ];
    }

    foreach ($queries as $query) {
        $statement = pc_prepare($conn, $query['sql']);
        $statement->bind_param($query['types'], ...$query['params']);
        if (!$statement->execute()) {
            $statement->close();
            continue;
        }
        $row = $statement->get_result()->fetch_assoc();
        $statement->close();
        if (is_array($row)) {
            return $row;
        }
    }
    return null;
}

/** @return list<string> */
function lo_available_methods(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId
): array {
    $methods = [];
    if (pc_table_exists($conn, 'password_change_authenticators')) {
        $statement = pc_prepare(
            $conn,
            'SELECT 1 FROM password_change_authenticators '
                . 'WHERE role = ? AND account_source = ? AND user_id = ? LIMIT 1'
        );
        $statement->bind_param('sss', $role, $accountSource, $userId);
        $statement->execute();
        if ($statement->get_result()->fetch_row() !== null) {
            $methods[] = 'totp';
        }
        $statement->close();
    }
    if (pc_table_exists($conn, 'account_verified_emails')) {
        $statement = pc_prepare(
            $conn,
            'SELECT 1 FROM account_verified_emails '
                . 'WHERE role = ? AND account_source = ? AND user_id = ? LIMIT 1'
        );
        $statement->bind_param('sss', $role, $accountSource, $userId);
        $statement->execute();
        if ($statement->get_result()->fetch_row() !== null) {
            $methods[] = 'email';
        }
        $statement->close();
    }
    return $methods;
}

/** @param array<string, mixed> $config */
function lo_email_destination(
    mysqli $conn,
    array $config,
    string $role,
    string $accountSource,
    string $userId
): array {
    $destination = ev_resolve_verified_email_destination(
        $conn,
        $config,
        $role,
        $accountSource,
        $userId
    );
    return [
        'address' => $destination,
        'masked' => pc_mask_email($destination),
    ];
}

/** @param array<string, mixed> $config */
function lo_send_email_code(
    array $config,
    string $destination,
    string $code,
    string $role,
    string $accountSource,
    string $userId
): bool {
    return pc_send_email_otp(
        $config,
        $destination,
        $code,
        [
            'purpose' => 'login',
            'role' => $role,
            'account_source' => $accountSource,
            'user_id' => $userId,
            'expires_in' => LO_CHALLENGE_TTL_SECONDS,
        ]
    );
}

/** @return array<string, mixed>|null */
function lo_challenge_for_update(mysqli $conn, string $tokenHash): ?array
{
    $statement = pc_prepare(
        $conn,
        'SELECT *, (expires_at <= NOW(6)) AS challenge_expired, '
            . '(otp_expires_at IS NULL OR otp_expires_at <= NOW(6)) AS otp_expired '
            . 'FROM login_otp_challenges WHERE challenge_token_hash = ? FOR UPDATE'
    );
    $statement->bind_param('s', $tokenHash);
    $statement->execute();
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    return is_array($row) ? $row : null;
}

function lo_cancel_pending_challenges(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId
): void {
    $statement = pc_prepare(
        $conn,
        "UPDATE login_otp_challenges SET status = 'cancelled' "
            . "WHERE role = ? AND account_source = ? AND user_id = ? AND status = 'pending'"
    );
    $statement->bind_param('sss', $role, $accountSource, $userId);
    $statement->execute();
    $statement->close();
}

function lo_assert_pending_challenge(array $challenge): void
{
    if (($challenge['status'] ?? '') !== 'pending') {
        pc_reject('This login verification request is no longer active. Please log in again.');
    }
    if ((int)($challenge['challenge_expired'] ?? 1) === 1) {
        pc_reject('This login verification request expired. Please log in again.');
    }
    if ((int)($challenge['failed_attempts'] ?? LO_MAX_ATTEMPTS) >= LO_MAX_ATTEMPTS) {
        pc_reject('Too many incorrect codes. Please log in again.');
    }
}

function lo_record_failed_attempt(mysqli $conn, int $challengeId, int $attempts): int
{
    $next = min(LO_MAX_ATTEMPTS, $attempts + 1);
    $status = $next >= LO_MAX_ATTEMPTS ? 'failed' : 'pending';
    $statement = pc_prepare(
        $conn,
        'UPDATE login_otp_challenges SET failed_attempts = ?, status = ? WHERE challenge_id = ?'
    );
    $statement->bind_param('isi', $next, $status, $challengeId);
    $statement->execute();
    $statement->close();
    return max(0, LO_MAX_ATTEMPTS - $next);
}

/** @return array<string, mixed> */
function lo_login_payload(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId
): array {
    $target = pc_target_for_source($role, $accountSource);
    $passwordChanged = pc_column_exists($conn, $target['table'], 'password_changed')
        ? 'password_changed'
        : '1 AS password_changed';
    $rolePredicate = '';
    if ($target['table'] === 'admins' && pc_column_exists($conn, 'admins', 'role')) {
        $rolePredicate = $role === 'cashier'
            ? " AND LOWER(COALESCE(role, '')) = 'cashier'"
            : " AND LOWER(COALESCE(role, '')) <> 'cashier'";
    }
    $sql = sprintf(
        'SELECT `%s` AS id, Fname AS name, %s FROM `%s` WHERE `%s` = ?%s LIMIT 1',
        $target['id_field'],
        $passwordChanged,
        $target['table'],
        $target['id_field'],
        $rolePredicate
    );
    $statement = pc_prepare($conn, $sql);
    $statement->bind_param('s', $userId);
    $statement->execute();
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    if (!is_array($row)) {
        throw new RuntimeException('The verified account is no longer available.');
    }
    return [
        'status' => 'success',
        'role' => $role,
        'account_source' => $accountSource,
        'id' => (string)$row['id'],
        'name' => (string)$row['name'],
        'password_changed' => (bool)($row['password_changed'] ?? true),
    ];
}
