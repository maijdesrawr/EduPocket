<?php
function migrate_account_history(mysqli $conn): void {
    foreach (['transactions', 'topups'] as $table) {
        $column = $conn->query("SHOW FULL COLUMNS FROM `$table` LIKE 'student_num'")->fetch_assoc();
        $keys = $conn->query("SELECT k.CONSTRAINT_NAME FROM information_schema.KEY_COLUMN_USAGE k WHERE k.TABLE_SCHEMA = DATABASE() AND k.TABLE_NAME = '$table' AND k.COLUMN_NAME = 'student_num' AND k.REFERENCED_TABLE_NAME = 'students'")->fetch_all(MYSQLI_ASSOC);
        $changes = [];
        if ($column['Null'] === 'YES' && count($keys) === 1) {
            $name = $conn->real_escape_string($keys[0]['CONSTRAINT_NAME']);
            $rule = $conn->query("SELECT DELETE_RULE FROM information_schema.REFERENTIAL_CONSTRAINTS WHERE CONSTRAINT_SCHEMA = DATABASE() AND TABLE_NAME = '$table' AND CONSTRAINT_NAME = '$name'")->fetch_assoc();
            if (($rule['DELETE_RULE'] ?? '') === 'SET NULL') continue;
        }
        foreach ($keys as $key) {
            $name = str_replace('`', '``', $key['CONSTRAINT_NAME']);
            $changes[] = "DROP FOREIGN KEY `$name`";
        }
        $type = $column['Type'];
        $collation = $column['Collation'];
        $changes[] = "MODIFY student_num $type COLLATE $collation NULL";
        $changes[] = "ADD CONSTRAINT `fk_{$table}_student_history` FOREIGN KEY (student_num) REFERENCES students(student_num) ON DELETE SET NULL ON UPDATE CASCADE";
        $conn->query("ALTER TABLE `$table` " . implode(', ', $changes));
    }
}
if (PHP_SAPI === 'cli' && realpath($_SERVER['SCRIPT_FILENAME']) === __FILE__) {
    require __DIR__ . '/db_connect.php';
    migrate_account_history($conn);
    echo "Account history migration complete.\n";
}
