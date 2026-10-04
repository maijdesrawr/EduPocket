<?php

declare(strict_types=1);

require_once __DIR__ . '/password_change_common.php';

function pm_require_secure_transport(): void
{
    if (pc_uses_secure_or_local_transport()) return;

    pc_reject('PIN management requires a secure HTTPS connection.');
}

function pm_validate_pin(string $pin, string $label, bool $rejectRepeatedDigit = false): void
{
    if (preg_match('/^\d{6}$/D', $pin) !== 1) {
        pc_reject($label . ' must be exactly 6 digits.');
    }
    if ($rejectRepeatedDigit && preg_match('/^(\d)\1{5}$/D', $pin) === 1) {
        pc_reject($label . ' cannot use the same digit six times.');
    }
}

function pm_pin_matches(string $enteredPin, string $storedPin): bool
{
    if ($enteredPin === '' || $storedPin === '') {
        return false;
    }

    if (password_verify($enteredPin, $storedPin)) {
        return true;
    }
    return hash_equals($storedPin, $enteredPin);
}

function pm_hash_pin(string $pin): string
{
    $hash = password_hash($pin, PASSWORD_DEFAULT);
    if (!is_string($hash) || $hash === '') {
        throw new RuntimeException('PIN hashing failed.');
    }
    return $hash;
}

/** @return array<string, string> */
function pm_pin_target(mysqli $conn, string $role, string $accountSource): array
{
    $target = pc_target_for_source($role, $accountSource);
    if (!pc_table_exists($conn, $target['table'])
        || !pc_column_exists($conn, $target['table'], 'pin')
    ) {
        throw new RuntimeException('PIN management database migration is missing.');
    }
    return $target;
}

function pm_fetch_pin_for_update(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId
): string {
    $target = pm_pin_target($conn, $role, $accountSource);
    $sql = sprintf(
        'SELECT `pin` FROM `%s` WHERE `%s` = ? FOR UPDATE',
        $target['table'],
        $target['id_field']
    );
    $statement = pc_prepare($conn, $sql);
    $statement->bind_param('s', $userId);
    if (!$statement->execute()) {
        $statement->close();
        throw new RuntimeException('Account PIN lookup failed.');
    }
    $row = $statement->get_result()->fetch_assoc();
    $statement->close();
    if (!is_array($row)) {
        throw new RuntimeException('The locked account disappeared during PIN lookup.');
    }
    return trim((string)($row['pin'] ?? ''));
}

function pm_update_account_pin(
    mysqli $conn,
    string $role,
    string $accountSource,
    string $userId,
    string $newPinHash
): void {
    $target = pm_pin_target($conn, $role, $accountSource);
    $setParts = ['`pin` = ?'];

    if ($role === 'student' && $accountSource === 'students') {
        if (pc_column_exists($conn, 'students', 'failed_attempts')) {
            $setParts[] = '`failed_attempts` = 0';
        }
        if (pc_column_exists($conn, 'students', 'is_locked')) {
            $setParts[] = '`is_locked` = 0';
        }
    }

    $sql = sprintf(
        'UPDATE `%s` SET %s WHERE `%s` = ?',
        $target['table'],
        implode(', ', $setParts),
        $target['id_field']
    );
    $statement = pc_prepare($conn, $sql);
    $statement->bind_param('ss', $newPinHash, $userId);
    if (!$statement->execute() || $statement->affected_rows !== 1) {
        $statement->close();
        throw new RuntimeException('Account PIN could not be updated.');
    }
    $statement->close();
}
