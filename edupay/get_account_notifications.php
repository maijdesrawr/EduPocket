<?php
require_once __DIR__ . '/cors_common.php';
ob_start();
ini_set('display_errors', '0');
error_reporting(0);

header('Content-Type: application/json; charset=utf-8');

require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/app_session_common.php';

function notification_json(array $payload): void
{
    if (ob_get_length()) {
        ob_clean();
    }

    echo json_encode($payload);
    exit;
}

try {
    $appSession = as_require_session($conn, false);
} catch (PasswordChangeClientException $error) {
    notification_json(
        pc_client_error_payload(
            $error->getMessage(),
            $error->details()
        )
    );
} catch (Throwable $error) {
    error_log(
        'get_account_notifications.php session validation failed: '
        . $error->getMessage()
    );

    notification_json([
        'status' => 'error',
        'message' => 'Your session could not be validated.'
    ]);
}

$role = strtolower(trim((string)($_GET['role'] ?? '')));
$accountSource = strtolower(
    trim((string)($_GET['account_source'] ?? ''))
);
$userId = trim((string)($_GET['user_id'] ?? ''));
$afterId = max(0, (int)($_GET['after_id'] ?? 0));

$allowedSources = [
    'student' => ['students'],
    'parent' => ['parents'],
    'canteen' => ['canteens'],
    'cashier' => ['cashiers', 'admins'],
    'admin' => ['admins'],
];

if (
    !in_array(
        $accountSource,
        $allowedSources[$role] ?? [],
        true
    )
    || $userId === ''
) {
    notification_json([
        'status' => 'error',
        'message' => 'Invalid notification account.'
    ]);
}

try {
    as_assert_session_identity(
        $appSession,
        $role,
        $userId,
        $accountSource
    );
} catch (PasswordChangeClientException $error) {
    notification_json(
        pc_client_error_payload(
            $error->getMessage(),
            $error->details()
        )
    );
}

/*
 * Get the latest notification ID for this account.
 */
$latestStatement = $conn->prepare(
    "SELECT COALESCE(MAX(notification_id), 0) AS latest_id
     FROM account_notifications
     WHERE recipient_role = ?
       AND account_source = ?
       AND user_id = ?"
);

if (!$latestStatement) {
    notification_json([
        'status' => 'error',
        'message' => 'Notifications could not be loaded.'
    ]);
}

$latestStatement->bind_param(
    'sss',
    $role,
    $accountSource,
    $userId
);

$latestStatement->execute();

$latestRow = $latestStatement
    ->get_result()
    ->fetch_assoc();

$latestId = (int)($latestRow['latest_id'] ?? 0);

$latestStatement->close();

/*
 * First activation:
 * Do not show old notifications.
 * Just establish the current notification cursor.
 */
if ($afterId === 0) {
    notification_json([
        'status' => 'success',
        'notifications' => [],
        'latest_id' => $latestId
    ]);
}

/*
 * Get newly-created notifications.
 */
$statement = $conn->prepare(
    "SELECT
        notification_id,
        transaction_id,
        title,
        body,
        created_at
     FROM account_notifications
     WHERE recipient_role = ?
       AND account_source = ?
       AND user_id = ?
       AND notification_id > ?
     ORDER BY notification_id ASC
     LIMIT 20"
);

if (!$statement) {
    notification_json([
        'status' => 'error',
        'message' => 'Notifications could not be loaded.'
    ]);
}

$statement->bind_param(
    'sssi',
    $role,
    $accountSource,
    $userId,
    $afterId
);

$statement->execute();

$result = $statement->get_result();

$notifications = [];
$deliveryLatestId = $afterId;

while ($row = $result->fetch_assoc()) {

    $notificationId = (int)$row['notification_id'];
    $transactionId = (int)$row['transaction_id'];

    $deliveryLatestId = $notificationId;

    $notifications[] = [
        'notification_id' => $notificationId,
        'transaction_id' => $transactionId,
        'title' => (string)$row['title'],
        'body' => (string)$row['body'],
        'created_at' => (string)$row['created_at'],
    ];
}

$statement->close();

notification_json([
    'status' => 'success',
    'notifications' => $notifications,
    'latest_id' => $deliveryLatestId,
]);