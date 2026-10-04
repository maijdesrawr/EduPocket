<?php
mysqli_report(MYSQLI_REPORT_OFF);
ini_set('display_errors', '0');
error_reporting(0);
require_once __DIR__ . '/db_port_helper.php';

$configuredPath = getenv('EDUPOCKET_DATABASE_CONFIG_PATH');
$databaseConfigPath = is_string($configuredPath) && trim($configuredPath) !== ''
    ? $configuredPath
    : 'C:/xampp/edupocket-config/database.php';
$databaseConfig = require $databaseConfigPath;
$servername = $databaseConfig['host'];
$username = $databaseConfig['username'];
$password = $databaseConfig['password'];
$dbname = $databaseConfig['database'];
$port = filter_var(
    $databaseConfig['port'] ?? 3306,
    FILTER_VALIDATE_INT,
    ['options' => ['min_range' => 1, 'max_range' => 65535]]
);
if ($port === false) {
    echo json_encode([
        "status" => "error",
        "message" => "Database connection failed: invalid port configuration."
    ]);
    exit;
}

try {
    $conn = connect_mysqli_with_fallback(
        $servername,
        $username,
        $password,
        $dbname,
        [(int)$port]
    );
} catch (mysqli_sql_exception $e) {
    echo json_encode([
        "status" => "error",
        "message" => "Database connection failed: " . $e->getMessage()
    ]);
    exit;
}
?>
