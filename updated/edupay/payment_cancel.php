<?php
require_once __DIR__ . '/backend_audit_common.php';
ba_register_request_audit();

echo "
<h1>Payment Cancelled</h1>
<p>Your payment was not completed.</p>
";
?>
