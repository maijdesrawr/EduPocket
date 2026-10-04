<?php
function checkout_outcome(array $checkout): string {
    $attributes=$checkout['data']['attributes'] ?? [];
    $intent=$attributes['payment_intent']['attributes'] ?? [];
    $payments=array_merge($attributes['payments'] ?? [],$intent['payments'] ?? []);
    foreach ($payments as $payment) {
        if (($payment['attributes']['status'] ?? '') === 'paid') return 'paid';
    }
    if (($attributes['status'] ?? '') === 'expired') return 'expired';
    $status=$intent['status'] ?? '';
    if (in_array($status,['processing','awaiting_next_action','succeeded'],true)) return 'pending';
    if (in_array($status,['cancelled','canceled'],true)) return 'cancelled';
    if (!empty($intent['last_payment_error'])) return 'failed';
    foreach ($payments as $payment) {
        if (($payment['attributes']['status'] ?? '') === 'failed') return 'failed';
    }
    return 'pending';
}
