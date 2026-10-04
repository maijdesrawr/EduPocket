<?php
function migrate_account_cleanup_collations(mysqli $conn): int {
    $changed = 0;
    $triggers = $conn->query('SHOW TRIGGERS')->fetch_all(MYSQLI_ASSOC);
    foreach ($triggers as $trigger) {
        if (!in_array($trigger['Table'], ['parents','canteens','cashiers'], true)) continue;
        $body = preg_replace('/(?<!BINARY )\buser_id\s*=\s*OLD\.(parent_id|canteen_id|cashier_id)\b/i', 'BINARY user_id = BINARY OLD.$1', $trigger['Statement']);
        if ($body === $trigger['Statement']) continue;
        $name = str_replace('`','``',$trigger['Trigger']);
        $table = str_replace('`','``',$trigger['Table']);
        $create = 'CREATE TRIGGER `'.$name.'` '.$trigger['Timing'].' '.$trigger['Event'].' ON `'.$table.'` FOR EACH ROW ';
        $conn->query('DROP TRIGGER `'.$name.'`');
        try { $conn->query($create.$body); }
        catch (Throwable $e) { $conn->query($create.$trigger['Statement']); throw $e; }
        $changed++;
    }
    return $changed;
}
if (realpath($_SERVER['SCRIPT_FILENAME'] ?? '') === __FILE__) {
    if (PHP_SAPI !== 'cli') { http_response_code(403); exit; }
    require __DIR__.'/db_connect.php';
    mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
    echo 'Updated '.migrate_account_cleanup_collations($conn)." account cleanup triggers.\n";
}
