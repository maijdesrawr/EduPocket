<?php

function profile_role_map(): array
{
    return [
        'student' => [
            'table' => 'students',
            'id_field' => 'student_num',
            'name_field' => 'Fname',
        ],
        'parent' => [
            'table' => 'parents',
            'id_field' => 'parent_id',
            'name_field' => 'Fname',
        ],
        'admin' => [
            'table' => 'admins',
            'id_field' => 'admin_id',
            'name_field' => 'Fname',
        ],
        'canteen' => [
            'table' => 'canteens',
            'id_field' => 'canteen_id',
            'name_field' => 'Fname',
        ],
        'cashier' => [
            'table' => 'cashiers',
            'id_field' => 'cashier_id',
            'name_field' => 'Fname',
        ],
    ];
}

function resolve_profile_target(string $role): ?array
{
    $key = strtolower(trim($role));
    $map = profile_role_map();
    return $map[$key] ?? null;
}

function ensure_profile_photo_column(mysqli $conn, string $table): bool
{
    $safeTable = preg_replace('/[^a-zA-Z0-9_]/', '', $table);
    if ($safeTable === '') {
        return false;
    }

    $check = $conn->query("SHOW COLUMNS FROM `$safeTable` LIKE 'profile_photo'");
    if (!$check) {
        return false;
    }
    if ($check->num_rows > 0) {
        return true;
    }

    return (bool)$conn->query(
        "ALTER TABLE `$safeTable` ADD COLUMN profile_photo VARCHAR(255) NULL"
    );
}

function normalize_profile_photo_path(?string $path): ?string
{
    $trimmed = trim((string)$path);
    if ($trimmed === '') {
        return null;
    }
    return str_replace('\\', '/', $trimmed);
}

function edupay_base_url(): string
{
    $https = $_SERVER['HTTPS'] ?? '';
    $isHttps = !empty($https) && strtolower($https) !== 'off';
    $scheme = $isHttps ? 'https' : 'http';
    $host = $_SERVER['HTTP_HOST'] ?? '158.62.100.205';
    return $scheme . '://' . $host . '/edupay';
}

function profile_photo_url(?string $path): ?string
{
    $normalized = normalize_profile_photo_path($path);
    if ($normalized === null) {
        return null;
    }

    if (preg_match('/^https?:\/\//i', $normalized)) {
        return $normalized;
    }

    return rtrim(edupay_base_url(), '/') . '/' . ltrim($normalized, '/');
}

