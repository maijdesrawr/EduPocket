<?php

declare(strict_types=1);

function edupocket_allow_local_web_app(): void
{
    $origin = trim((string)($_SERVER['HTTP_ORIGIN'] ?? ''));
    if (preg_match('#^http://(?:localhost|127\.0\.0\.1):\d{1,5}$#D', $origin) === 1) {
        header('Access-Control-Allow-Origin: ' . $origin);
        header('Vary: Origin');
    }
    header('Access-Control-Allow-Methods: GET, POST, OPTIONS');
    header('Access-Control-Allow-Headers: Content-Type, Authorization');

    if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
        http_response_code(204);
        exit;
    }
}

edupocket_allow_local_web_app();
