<?php

declare(strict_types=1);

const SD_SUPPORTED_PERIODS = ['daily', 'weekly', 'monthly', 'yearly'];

function sd_normalize_period(?string $value): ?string
{
    $period = strtolower(trim((string)$value));
    return in_array($period, SD_SUPPORTED_PERIODS, true) ? $period : null;
}

function sd_calendar_period_filter_sql(string $period, string $dateExpression): string
{
    $normalizedPeriod = sd_normalize_period($period);
    if ($normalizedPeriod === null) {
        throw new InvalidArgumentException('Unsupported student dashboard period.');
    }

    return match ($normalizedPeriod) {
        'daily' => "DATE({$dateExpression}) = CURDATE()",
        'weekly' => "YEARWEEK({$dateExpression}, 1) = YEARWEEK(CURDATE(), 1)",
        'monthly' => "MONTH({$dateExpression}) = MONTH(CURDATE())"
            . " AND YEAR({$dateExpression}) = YEAR(CURDATE())",
        'yearly' => "YEAR({$dateExpression}) = YEAR(CURDATE())",
    };
}

function sd_is_expense_transaction_type(?string $transactionType): bool
{
    return in_array(
        strtolower(trim((string)$transactionType)),
        ['payment', 'transfer-out'],
        true
    );
}

function sd_transaction_label(?string $transactionType): string
{
    $type = strtolower(trim((string)$transactionType));
    return match ($type) {
        'payment' => 'Payment',
        'top-up' => 'Top-Up',
        'transfer-out' => 'Fund Transfer',
        'transfer-in' => 'Funds Received',
        default => $type === ''
            ? 'Transaction'
            : ucwords(str_replace(['-', '_'], ' ', $type)),
    };
}
