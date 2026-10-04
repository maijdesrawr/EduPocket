<?php

declare(strict_types=1);

require_once __DIR__ . '/authenticator_management_common.php';
require_once __DIR__ . '/app_session_common.php';

pc_bootstrap_json_endpoint();

$conn = null;
$transactionStarted = false;

try {
    pc_require_post();
    am_require_secure_transport();

    $role = pc_normalize_role(pc_post_string('role'));
    $userId = pc_post_string('user_id');
    $action = am_normalize_action(pc_post_string('action'));
    $challengeToken = pc_post_string('challenge_token');
    $authenticatorCode = pc_post_string('authenticator_code');
    pc_validate_user_id($userId);
    $challengeTokenHash = am_challenge_token_hash($challengeToken);

    $config = pc_security_config();
    $conn = pc_open_database();
    $appSession = as_require_session($conn, false);
    am_require_schema($conn);

    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Authenticator cleanup transaction could not start.');
    }
    $transactionStarted = true;
    am_purge_stale_security_state($conn);
    if (!$conn->commit()) {
        throw new RuntimeException('Authenticator cleanup transaction could not be committed.');
    }
    $transactionStarted = false;

    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Authenticator IP rate-limit transaction could not start.');
    }
    $transactionStarted = true;
    $verifyIpLimit = am_consume_verify_ip_attempt($conn, $config);
    if (!$conn->commit()) {
        throw new RuntimeException('Authenticator IP rate-limit transaction could not be committed.');
    }
    $transactionStarted = false;
    if ((int)$verifyIpLimit['retry_after'] > 0) {
        pc_reject(
            'Too many authenticator verification attempts. Please try again later.',
            ['retry_after' => (int)$verifyIpLimit['retry_after']]
        );
    }

    $preview = am_challenge_preview($conn, $challengeTokenHash);
    $previewUserId = is_array($preview) ? (string)$preview['user_id'] : '';
    if ($preview === null
        || !hash_equals($role, (string)$preview['role'])
        || !hash_equals(
            mb_strtoupper($userId, 'UTF-8'),
            mb_strtoupper($previewUserId, 'UTF-8')
        )
        || !hash_equals($action, (string)$preview['action'])
    ) {
        pc_reject('The authenticator-management request is invalid or has expired.');
    }
    $accountSource = (string)$preview['account_source'];
    $userId = $previewUserId;
    as_assert_session_identity($appSession, $role, $userId, $accountSource);

    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Authenticator account rate-limit transaction could not start.');
    }
    $transactionStarted = true;
    $accountRetryAfter = am_consume_verify_account_attempt(
        $conn,
        $role,
        (string)$preview['user_id'],
        $config
    );
    if (!$conn->commit()) {
        throw new RuntimeException('Authenticator account rate-limit transaction could not be committed.');
    }
    $transactionStarted = false;
    if ($accountRetryAfter > 0) {
        pc_reject(
            'Too many authenticator verification attempts. Please try again later.',
            ['retry_after' => $accountRetryAfter]
        );
    }

    if (!$conn->begin_transaction()) {
        throw new RuntimeException('Authenticator verification transaction could not start.');
    }
    $transactionStarted = true;

    $account = pc_fetch_account_for_update($conn, $role, $userId, $accountSource);
    $canonicalUserId = (string)$account['user_id'];
    if (!hash_equals((string)$preview['user_id'], $canonicalUserId)) {
        throw new RuntimeException('Authenticator account binding changed unexpectedly.');
    }
    $userId = $canonicalUserId;

    $challenge = am_challenge_for_update($conn, $challengeTokenHash);
    if ($challenge === null
        || (int)$challenge['challenge_id'] !== (int)$preview['challenge_id']
        || !hash_equals($role, (string)$challenge['role'])
        || !hash_equals($accountSource, (string)$challenge['account_source'])
        || !hash_equals($userId, (string)$challenge['user_id'])
        || !hash_equals($action, (string)$challenge['action'])
    ) {
        throw new RuntimeException('Authenticator challenge binding changed unexpectedly.');
    }

    am_assert_pending_challenge($challenge);
    if ((int)($challenge['challenge_expired'] ?? 1) === 1) {
        am_expire_challenge($conn, (int)$challenge['challenge_id']);
        if (!$conn->commit()) {
            throw new RuntimeException('Expired authenticator challenge could not be committed.');
        }
        $transactionStarted = false;
        pc_reject('The authenticator-management request expired. Start a new request.');
    }

    $currentFingerprint = pc_account_fingerprint(
        $role,
        $accountSource,
        $userId,
        (string)$account['password_value'],
        $config
    );
    if (!hash_equals((string)$challenge['account_fingerprint'], $currentFingerprint)) {
        am_mark_challenge_cancelled($conn, (int)$challenge['challenge_id']);
        if (!$conn->commit()) {
            throw new RuntimeException('Stale authenticator challenge could not be committed.');
        }
        $transactionStarted = false;
        pc_reject('Your account password changed after this request started. Start a new request.');
    }

    $authenticator = am_authenticator_for_update($conn, $role, $accountSource, $userId);
    $secret = '';
    $lastUsedStep = null;
    if ($action === 'enroll') {
        if ($authenticator !== null) {
            am_mark_challenge_cancelled($conn, (int)$challenge['challenge_id']);
            if (!$conn->commit()) {
                throw new RuntimeException('Changed authenticator state could not be committed.');
            }
            $transactionStarted = false;
            pc_reject('An authenticator was linked after this request started. Start a new request.');
        }
        if (($challenge['expected_authenticator_fingerprint'] ?? null) !== null) {
            throw new RuntimeException('Enrollment challenge contains invalid prior state.');
        }
        $pendingSecret = (string)($challenge['pending_totp_secret_encrypted'] ?? '');
        if ($pendingSecret === '') {
            throw new RuntimeException('Pending authenticator secret is missing.');
        }
        $secret = pc_decrypt_totp_secret(
            $pendingSecret,
            $role,
            $accountSource,
            $userId,
            $config
        );
    } else {
        if ($authenticator === null) {
            am_mark_challenge_cancelled($conn, (int)$challenge['challenge_id']);
            if (!$conn->commit()) {
                throw new RuntimeException('Missing authenticator state could not be committed.');
            }
            $transactionStarted = false;
            pc_reject('The linked authenticator changed after this request started. Start a new request.');
        }
        if (($challenge['pending_totp_secret_encrypted'] ?? null) !== null) {
            throw new RuntimeException('Removal challenge contains unexpected pending secret state.');
        }
        $encryptedSecret = (string)$authenticator['totp_secret_encrypted'];
        $expectedFingerprint = (string)($challenge['expected_authenticator_fingerprint'] ?? '');
        $actualFingerprint = am_authenticator_fingerprint(
            $role,
            $accountSource,
            $userId,
            $encryptedSecret,
            $config
        );
        if ($expectedFingerprint === '' || !hash_equals($expectedFingerprint, $actualFingerprint)) {
            am_mark_challenge_cancelled($conn, (int)$challenge['challenge_id']);
            if (!$conn->commit()) {
                throw new RuntimeException('Changed authenticator state could not be committed.');
            }
            $transactionStarted = false;
            pc_reject('The linked authenticator changed after this request started. Start a new request.');
        }
        $secret = pc_decrypt_totp_secret(
            $encryptedSecret,
            $role,
            $accountSource,
            $userId,
            $config
        );
        $storedStep = $authenticator['last_used_step'] ?? null;
        $lastUsedStep = $storedStep === null ? null : (int)$storedStep;
    }

    $matchedStep = pc_match_totp_step(
        $secret,
        $authenticatorCode,
        $lastUsedStep
    );
    unset($secret);
    if ($matchedStep === null) {
        $attemptsRemaining = am_increment_failed_attempt(
            $conn,
            (int)$challenge['challenge_id'],
            (int)$challenge['failed_attempts']
        );
        if (!$conn->commit()) {
            throw new RuntimeException('Failed authenticator attempt could not be committed.');
        }
        $transactionStarted = false;
        pc_reject(
            $attemptsRemaining > 0
                ? 'Incorrect or already-used authenticator code. Please try again.'
                : 'Too many incorrect authenticator codes. Start a new request.',
            ['attempts_remaining' => $attemptsRemaining]
        );
    }

    if ($action === 'enroll') {
        am_insert_authenticator(
            $conn,
            $role,
            $accountSource,
            $userId,
            (string)$challenge['pending_totp_secret_encrypted'],
            $matchedStep
        );
        $eventType = 'enrolled';
        $enrolled = true;
        $message = 'Authenticator app linked successfully.';
    } else {
        am_delete_authenticator($conn, $role, $accountSource, $userId);
        $eventType = 'removed';
        $enrolled = false;
        $message = 'Authenticator app removed successfully.';
    }

    am_mark_challenge_verified($conn, (int)$challenge['challenge_id']);
    am_cancel_pending_challenges($conn, $role, $accountSource, $userId);
    am_cancel_pending_password_totp_challenges($conn, $role, $accountSource, $userId);
    am_record_event(
        $conn,
        (int)$challenge['challenge_id'],
        $role,
        $accountSource,
        $userId,
        $eventType,
        (string)$verifyIpLimit['ip_hash']
    );
    as_record_activity(
        $conn,
        $appSession,
        $action === 'enroll' ? 'authenticator_enrolled' : 'authenticator_removed',
        ['action' => $action],
        'server'
    );

    if (!$conn->commit()) {
        throw new RuntimeException('Authenticator verification transaction could not be committed.');
    }
    $transactionStarted = false;
    $conn->close();
    $conn = null;

    pc_respond([
        'status' => 'success',
        'action' => $action,
        'enrolled' => $enrolled,
        'message' => $message,
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
    error_log('verify_authenticator_management.php failed: ' . $error->getMessage());
    pc_respond([
        'status' => 'error',
        'message' => 'Authenticator management is temporarily unavailable. Please try again later.',
    ]);
}
