<?php
header('Content-Type: application/json');
require_once __DIR__ . '/db_connect.php';
require_once __DIR__ . '/app_session_common.php';
require_once __DIR__ . '/paymongo_payment_common.php';
require_once __DIR__ . '/checkout_outcome_common.php';
try {
    $session = as_require_session($conn, false);
    $id = pm_checkout_id(trim((string)($_POST['checkout_id'] ?? '')));
    $pending = pm_pending_payment($conn, $id);
    as_assert_session_identity($session, 'parent', (string)$pending['parent_id']);
    if (($pending['status'] ?? '') === 'cancelled') {
        echo json_encode(['status'=>'cancelled','message'=>'Payment cancelled.']); exit;
    }
    if (($pending['status'] ?? '') !== 'completed') {
        $checkout = pm_retrieve_checkout_session($id);
        $outcome = checkout_outcome($checkout);
        if ($outcome !== 'paid') {
            $messages = [
                'failed'=>'Your payment was declined. Please choose a payment method and try again.',
                'expired'=>'This payment session expired. Please start a new payment.',
                'cancelled'=>'Your payment was cancelled. Please try again.',
                'pending'=>'Payment is not confirmed yet. Complete checkout, then check again.',
            ];
            echo json_encode(['status'=>$outcome,'message'=>$messages[$outcome]]); exit;
        }
        $verified = pm_verify_paid_checkout($pending, $checkout);
        $result = pm_fulfill_verified_checkout($conn, $id, $verified['provider_payment_id'], $verified['amount_centavos']);
    } else {
        $result = pm_verify_and_fulfill($conn, $id);
    }
    echo json_encode(['status'=>'success'] + $result);
} catch (Throwable $e) {
    error_log('Checkout status failed: '.$e->getMessage());
    echo json_encode(['status'=>'error','message'=>'Payment status could not be checked. Please try again.']);
}
