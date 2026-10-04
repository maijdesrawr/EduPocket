<?php

declare(strict_types=1);

ini_set('display_errors', '0');
error_reporting(0);
header('Cache-Control: no-store, max-age=0');
header('Pragma: no-cache');
header('Referrer-Policy: no-referrer');
header('X-Content-Type-Options: nosniff');
header("Content-Security-Policy: default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'");
require_once __DIR__ . '/receipt_print_token_common.php';

function receipt_html_escape(mixed $value): string
{
    return htmlspecialchars((string)$value, ENT_QUOTES | ENT_SUBSTITUTE, 'UTF-8');
}

try {
    if (($_SERVER['REQUEST_METHOD'] ?? 'GET') !== 'GET') {
        throw new InvalidArgumentException('Invalid request method.');
    }
    $conn = pc_open_database();
    $receipt = rpt_consume_print_token($conn, (string)($_GET['print_token'] ?? ''));
} catch (Throwable $error) {
    http_response_code(404);
    $receipt = null;
} finally {
    if (isset($conn) && $conn instanceof mysqli) {
        $conn->close();
    }
}
?><!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>EduPocket Official Transaction Receipt</title>
  <style>
    :root { color-scheme: light; font-family: Arial, sans-serif; }
    body { margin: 0; background: #f4f4f4; color: #222; }
    .actions { max-width: 760px; margin: 20px auto 0; text-align: right; }
    button { border: 0; border-radius: 24px; padding: 11px 22px; color: #fff;
      background: #c62828; font-weight: 700; cursor: pointer; }
    .receipt { max-width: 680px; margin: 16px auto 40px; padding: 38px 40px;
      background: #fff; box-shadow: 0 8px 30px #0002; }
    header { display: flex; justify-content: space-between; gap: 24px;
      border-bottom: 3px solid #c62828; padding-bottom: 18px; }
    h1 { margin: 0; color: #c62828; font-size: 28px; }
    .muted { color: #666; font-size: 13px; }
    .meta { display: grid; grid-template-columns: 1fr 1fr; gap: 8px 24px;
      margin: 24px 0; }
    table { width: 100%; border-collapse: collapse; margin-top: 20px; }
    th, td { padding: 10px 8px; border-bottom: 1px solid #ddd; text-align: left; }
    th:last-child, td:last-child { text-align: right; }
    .total { margin-top: 22px; text-align: right; font-size: 22px; font-weight: 800; }
    footer { margin-top: 36px; border-top: 1px solid #ddd; padding-top: 16px;
      text-align: center; color: #666; font-size: 12px; }
    .error { max-width: 600px; margin: 80px auto; padding: 28px; background: #fff; }
    @media print { body { background: #fff; } .actions { display: none; }
      .receipt { margin: 0; max-width: none; box-shadow: none; } }
  </style>
</head>
<body>
<?php if ($receipt === null): ?>
  <div class="error"><h1>Receipt unavailable</h1><p>This receipt could not be loaded.</p></div>
<?php else: ?>
  <div class="actions"><button type="button" onclick="window.print()">Print receipt</button></div>
  <main class="receipt">
    <header>
      <div><h1>EduPocket</h1><div class="muted">Official Transaction Receipt</div></div>
      <div><strong><?= receipt_html_escape($receipt['receipt_number']) ?></strong><br>
        <span class="muted"><?= receipt_html_escape($receipt['date_time']) ?></span></div>
    </header>
    <section class="meta">
      <div><span class="muted">Student</span><br><strong><?= receipt_html_escape($receipt['student']['name']) ?></strong></div>
      <div><span class="muted">Student ID</span><br><strong><?= receipt_html_escape($receipt['student']['id']) ?></strong></div>
      <div><span class="muted">Processed by:</span><br><strong><?= receipt_html_escape($receipt['processed_by']['name'] ?? 'N/A') ?></strong></div>
      <div><span class="muted">Transaction</span><br><strong>#<?= receipt_html_escape($receipt['transaction_id']) ?></strong></div>
      <div><span class="muted">Status</span><br><strong>PAID</strong></div>
    </section>
    <table>
      <thead><tr><th>Description</th><th>Qty</th><th>Unit price</th><th>Amount</th></tr></thead>
      <tbody>
      <?php if ($receipt['items'] !== []): ?>
        <?php foreach ($receipt['items'] as $item): ?>
          <tr><td><?= receipt_html_escape($item['name']) ?></td><td><?= receipt_html_escape($item['quantity']) ?></td>
            <td>PHP <?= receipt_html_escape($item['unit_price']) ?></td><td>PHP <?= receipt_html_escape($item['line_total']) ?></td></tr>
        <?php endforeach; ?>
      <?php else: ?>
        <tr><td><?= receipt_html_escape($receipt['description'] ?: ucfirst($receipt['transaction_type'])) ?></td><td>1</td>
          <td>PHP <?= receipt_html_escape($receipt['amount']) ?></td><td>PHP <?= receipt_html_escape($receipt['amount']) ?></td></tr>
      <?php endif; ?>
      </tbody>
    </table>
    <div class="total">Total: PHP <?= receipt_html_escape($receipt['amount']) ?></div>
    <footer>This computer-generated official receipt is valid without a signature.</footer>
  </main>
<?php endif; ?>
</body>
</html>
