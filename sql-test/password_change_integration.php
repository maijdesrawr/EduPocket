<?php

declare(strict_types=1);

require_once __DIR__ . '/../rawr/edupay/password_change_common.php';

const TEST_API_BASE = 'http://127.0.0.1/edupay';
const TEST_CURRENT_PASSWORD = 'LegacyCurrent1!';

/** @return array<string, mixed> */
function test_post(string $endpoint, array $fields): array
{
    $handle = curl_init(TEST_API_BASE . '/' . $endpoint);
    if ($handle === false) {
        throw new RuntimeException('Could not initialize HTTP client.');
    }
    curl_setopt_array($handle, [
        CURLOPT_POST => true,
        CURLOPT_POSTFIELDS => http_build_query($fields),
        CURLOPT_RETURNTRANSFER => true,
        CURLOPT_TIMEOUT => 20,
        CURLOPT_HTTPHEADER => ['Accept: application/json'],
    ]);
    $body = curl_exec($handle);
    $status = (int)curl_getinfo($handle, CURLINFO_RESPONSE_CODE);
    $transportError = curl_error($handle);
    curl_close($handle);

    if (!is_string($body) || $transportError !== '') {
        throw new RuntimeException('HTTP request failed: ' . $transportError);
    }
    $decoded = json_decode($body, true);
    if ($status !== 200 || !is_array($decoded)) {
        throw new RuntimeException(
            'Invalid HTTP response (' . $status . '): ' . substr($body, 0, 200)
        );
    }
    return $decoded;
}

function test_assert(bool $condition, string $message): void
{
    if (!$condition) {
        throw new RuntimeException($message);
    }
}

/** @return array<int, array{role:string,id:string,new_password:string}> */
function test_accounts(): array
{
    return [
        ['role' => 'student', 'id' => 'ZZSEC_STUDENT', 'new_password' => 'FreshStudent2!'],
        ['role' => 'parent', 'id' => 'ZZSEC_PARENT', 'new_password' => 'FreshParent2!'],
        ['role' => 'admin', 'id' => 'ZZSEC_ADMIN', 'new_password' => 'FreshAdmin2!'],
        ['role' => 'cashier', 'id' => 'ZZSEC_CASHIER', 'new_password' => 'FreshCashier2!'],
        ['role' => 'canteen', 'id' => 'ZZSEC_CANTEEN', 'new_password' => 'FreshCanteen2!'],
    ];
}

function test_cleanup(mysqli $conn): void
{
    foreach (test_accounts() as $account) {
        $id = $account['id'];
        foreach (
            [
                'password_change_challenges',
                'password_change_authenticators',
                'password_history',
            ] as $securityTable
        ) {
            $statement = pc_prepare(
                $conn,
                'DELETE FROM `' . $securityTable . '` WHERE user_id = ?'
            );
            $statement->bind_param('s', $id);
            $statement->execute();
            $statement->close();
        }
    }

    $deletes = [
        ['DELETE FROM students WHERE student_num = ?', 'ZZSEC_STUDENT'],
        ['DELETE FROM parents WHERE parent_id = ?', 'ZZSEC_PARENT'],
        ['DELETE FROM admins WHERE admin_id = ?', 'ZZSEC_ADMIN'],
        ['DELETE FROM cashiers WHERE cashier_id = ?', 'ZZSEC_CASHIER'],
        ['DELETE FROM canteens WHERE canteen_id = ?', 'ZZSEC_CANTEEN'],
    ];
    foreach ($deletes as [$sql, $id]) {
        $statement = pc_prepare($conn, $sql);
        $statement->bind_param('s', $id);
        $statement->execute();
        $statement->close();
    }
}

function test_seed(mysqli $conn): void
{
    $password = TEST_CURRENT_PASSWORD;

    $statement = pc_prepare(
        $conn,
        'INSERT INTO students '
            . '(student_num, Fname, first_name, last_name, Password, qr_code) '
            . 'VALUES (?, ?, ?, ?, ?, ?)'
    );
    $id = 'ZZSEC_STUDENT';
    $name = 'Security Student';
    $firstName = 'Security';
    $lastName = 'Student';
    $qr = 'QR-ZZSEC-STUDENT';
    $statement->bind_param('ssssss', $id, $name, $firstName, $lastName, $password, $qr);
    test_assert($statement->execute(), 'Could not seed test student.');
    $statement->close();

    $statement = pc_prepare(
        $conn,
        'INSERT INTO parents '
            . '(parent_id, Fname, first_name, last_name, Password) '
            . 'VALUES (?, ?, ?, ?, ?)'
    );
    $id = 'ZZSEC_PARENT';
    $name = 'Security Parent';
    $firstName = 'Security';
    $lastName = 'Parent';
    $statement->bind_param('sssss', $id, $name, $firstName, $lastName, $password);
    test_assert($statement->execute(), 'Could not seed test parent.');
    $statement->close();

    $statement = pc_prepare(
        $conn,
        'INSERT INTO admins (admin_id, Fname, role, username, password) '
            . 'VALUES (?, ?, ?, ?, ?)'
    );
    $id = 'ZZSEC_ADMIN';
    $name = 'Security Admin';
    $role = 'system admin';
    $username = 'zzsec_admin';
    $statement->bind_param('sssss', $id, $name, $role, $username, $password);
    test_assert($statement->execute(), 'Could not seed test admin.');
    $statement->close();

    $statement = pc_prepare(
        $conn,
        'INSERT INTO cashiers (cashier_id, Fname, username, password) '
            . 'VALUES (?, ?, ?, ?)'
    );
    $id = 'ZZSEC_CASHIER';
    $name = 'Security Cashier';
    $username = 'zzsec_cashier';
    $statement->bind_param('ssss', $id, $name, $username, $password);
    test_assert($statement->execute(), 'Could not seed test cashier.');
    $statement->close();

    $statement = pc_prepare(
        $conn,
        'INSERT INTO canteens (canteen_id, Fname, Password, location) '
            . 'VALUES (?, ?, ?, ?)'
    );
    $id = 'ZZSEC_CANTEEN';
    $name = 'Security Canteen';
    $location = 'Test Only';
    $statement->bind_param('ssss', $id, $name, $password, $location);
    test_assert($statement->execute(), 'Could not seed test canteen.');
    $statement->close();
}

function test_stored_password(mysqli $conn, string $role, string $id): string
{
    $account = pc_fetch_account_for_update($conn, $role, $id);
    return $account['password_value'];
}

function test_history_count(mysqli $conn, string $role, string $id): int
{
    $statement = pc_prepare(
        $conn,
        'SELECT COUNT(*) AS total FROM password_history WHERE role = ? AND user_id = ?'
    );
    $statement->bind_param('ss', $role, $id);
    $statement->execute();
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    return (int)($row['total'] ?? 0);
}

$connection = pc_open_database();
$passed = [];

try {
    test_cleanup($connection);
    test_seed($connection);

    foreach (test_accounts() as $index => $account) {
        $request = test_post('request_password_change.php', [
            'role' => $account['role'],
            'id' => $account['id'],
            'current_password' => TEST_CURRENT_PASSWORD,
            'new_password' => $account['new_password'],
            'method' => 'authenticator',
            'email' => '',
        ]);
        test_assert(($request['status'] ?? '') === 'success', 'Request failed for ' . $account['role']);
        test_assert(($request['requires_totp_setup'] ?? false) === true, 'TOTP setup was not returned.');
        $secret = (string)($request['totp_setup_key'] ?? '');
        $token = (string)($request['challenge_token'] ?? '');
        test_assert($secret !== '' && $token !== '', 'Challenge material is missing.');

        $code = pc_totp_code_for_counter(
            pc_base32_decode($secret),
            intdiv(time(), PC_TOTP_PERIOD_SECONDS)
        );
        if ($index === 0) {
            $lastDigit = (int)$code[5];
            $wrongCode = substr($code, 0, 5) . (string)(($lastDigit + 1) % 10);
            $wrong = test_post('verify_password_change.php', [
                'challenge_token' => $token,
                'code' => $wrongCode,
            ]);
            test_assert(($wrong['status'] ?? '') === 'error', 'Wrong OTP was accepted.');
            test_assert((int)($wrong['attempts_remaining'] ?? -1) === 4, 'OTP attempts were not decremented.');
        }

        $verified = test_post('verify_password_change.php', [
            'challenge_token' => $token,
            'code' => $code,
        ]);
        test_assert(($verified['status'] ?? '') === 'success', 'Verification failed for ' . $account['role']);

        $login = test_post('login.php', [
            'id' => $account['id'],
            'password' => $account['new_password'],
        ]);
        test_assert(($login['status'] ?? '') === 'success', 'New password login failed for ' . $account['role']);
        test_assert(($login['role'] ?? '') === $account['role'], 'Login role mismatch for ' . $account['role']);

        $stored = test_stored_password($connection, $account['role'], $account['id']);
        test_assert(pc_is_password_hash($stored), 'New credential was not hashed.');
        test_assert(password_verify($account['new_password'], $stored), 'Stored hash does not verify.');
        test_assert(test_history_count($connection, $account['role'], $account['id']) >= 2, 'History was not recorded.');

        $reuse = test_post('request_password_change.php', [
            'role' => $account['role'],
            'id' => $account['id'],
            'current_password' => $account['new_password'],
            'new_password' => TEST_CURRENT_PASSWORD,
            'method' => 'authenticator',
            'email' => '',
        ]);
        test_assert(($reuse['status'] ?? '') === 'error', 'Old password reuse was accepted.');
        test_assert(str_contains((string)($reuse['message'] ?? ''), 'cannot reuse'), 'Reuse message is not helpful.');

        $passed[] = $account['role'];
    }

    $emailDisabled = test_post('request_password_change.php', [
        'role' => 'admin',
        'id' => 'ZZSEC_ADMIN',
        'current_password' => 'FreshAdmin2!',
        'new_password' => 'AnotherAdmin3!',
        'method' => 'email',
        'email' => 'security@example.com',
    ]);
    test_assert(($emailDisabled['status'] ?? '') === 'error', 'Disabled email transport was accepted.');
    test_assert(str_contains((string)($emailDisabled['message'] ?? ''), 'not configured'), 'Email config error is unclear.');

    echo json_encode([
        'status' => 'success',
        'roles_verified' => $passed,
        'password_history_reuse_rejected' => true,
        'wrong_otp_attempt_recorded' => true,
        'email_fails_closed_when_unconfigured' => true,
    ], JSON_PRETTY_PRINT | JSON_UNESCAPED_SLASHES), PHP_EOL;
} finally {
    test_cleanup($connection);
    $connection->close();
}

