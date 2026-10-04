<?php

declare(strict_types=1);

require_once __DIR__ . '/email_verification_common.php';
require_once __DIR__ . '/app_session_common.php';

pc_bootstrap_json_endpoint();

$conn = null;
$transactionStarted = false;

try {
    pc_require_post();
    $role = pc_normalize_role(pc_post_string('role'));
    $userId = pc_post_string('id');
    pc_validate_user_id($userId);

    $config = pc_security_config();
    $conn = pc_open_database();
    $appSession = as_require_session($conn);
    as_assert_session_identity($appSession, $role, $userId);
    ev_require_schema($conn);
    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Verified email lookup transaction could not start.');
    }
    $transactionStarted = true;

    $account = pc_fetch_account_for_update(
        $conn,
        $role,
        $userId,
        (string)$appSession['account_source']
    );
    $userId = (string)$account['user_id'];
    $accountSource = (string)$account['account_source'];
    as_assert_session_identity($appSession, $role, $userId, $accountSource);
    $record = ev_verified_email_record($conn, $role, $accountSource, $userId);
    $verified = $record !== null;
    $emailMasked = null;
    if ($record !== null) {
        ev_resolve_verified_email_destination(
            $conn,
            $config,
            $role,
            $accountSource,
            $userId
        );
        $emailMasked = (string)$record['email_masked'];
    }

    if (!$conn->commit()) {
        throw new RuntimeException('Verified email lookup transaction could not be committed.');
    }
    $transactionStarted = false;
    $conn->close();
    $conn = null;

    pc_respond([
        'status' => 'success',
        'verified' => $verified,
        'email_masked' => $emailMasked,
    ]);
} catch (PasswordChangeClientException $error) {
    if ($transactionStarted && $conn instanceof mysqli) {
        $conn->rollback();
    }
    if ($conn instanceof mysqli) {
        $conn->close();
    }
    pc_respond(pc_client_error_payload($error->getMessage(), $error->details()));
} catch (Throwable $error) {
    if ($transactionStarted && $conn instanceof mysqli) {
        $conn->rollback();
    }
    if ($conn instanceof mysqli) {
        $conn->close();
    }
    error_log('get_verified_email.php failed: ' . $error->getMessage());
    pc_respond([
        'status' => 'error',
        'message' => 'Verified email status is temporarily unavailable. Please try again later.',
    ]);
}
