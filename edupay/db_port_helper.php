<?php
date_default_timezone_set('Asia/Manila');

require_once __DIR__ . '/backend_audit_common.php';
ba_register_request_audit();

if (!function_exists('connect_mysqli_with_fallback')) {
    function connect_mysqli_with_fallback(
        string $host,
        string $user,
        string $password,
        string $dbname,
        array $ports = [3306]
    ): mysqli {
        $lastError = 'Database connection failed.';
        $lastCode = 0;

        foreach ($ports as $port) {
            $conn = @new mysqli($host, $user, $password, $dbname, (int)$port);

            if (!$conn->connect_error) {
                $conn->query("SET time_zone = '+08:00'");
                ba_capture_database_config(
                    $host,
                    $user,
                    $password,
                    $dbname,
                    (int)$port
                );
                return $conn;
            }

            $lastError = $conn->connect_error ?: $lastError;
            $lastCode = $conn->connect_errno ?: $lastCode;
        }

        throw new mysqli_sql_exception($lastError, $lastCode);
    }
}

if (!function_exists('connect_pdo_with_fallback')) {
    function connect_pdo_with_fallback(
        string $host,
        string $user,
        string $password,
        string $dbname,
        string $charset = 'utf8mb4',
        array $ports = [3306] 
    ): PDO {
        $options = [
            PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
        ];

        $lastException = null;

        foreach ($ports as $port) {
            $dsn = "mysql:host=$host;port=$port;dbname=$dbname;charset=$charset";

            try {
                $pdo = new PDO($dsn, $user, $password, $options);
                $pdo->exec("SET time_zone = '+08:00'");
                ba_capture_database_config(
                    $host,
                    $user,
                    $password,
                    $dbname,
                    (int)$port
                );
                return $pdo;
            } catch (PDOException $e) {
                $lastException = $e;
            }
        }

        throw ($lastException ?? new PDOException('Database connection failed.'));
    }
}
?>
