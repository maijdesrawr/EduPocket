<?php
header('Content-Type: application/json; charset=utf-8');
require_once __DIR__.'/db_connect.php';
require_once __DIR__.'/app_session_common.php';
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT);
try {
    if (!in_array($paymentOptionAction ?? '', ['edit', 'delete'], true)) throw new InvalidArgumentException('Invalid payment action.');
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') throw new InvalidArgumentException('POST is required.');
    $session=as_require_session($conn,false);
    as_assert_session_role($session,['cashier']);
    $cashier=(string)$session['user_id'];
    as_assert_session_identity($session,'cashier',$cashier,'cashiers');
    $id=filter_var($_POST['id'] ?? null,FILTER_VALIDATE_INT,['options'=>['min_range'=>1]]);
    if (!$id) throw new InvalidArgumentException('Select a valid payment option.');
    $conn->begin_transaction();
    $stmt=$conn->prepare('SELECT id FROM bill_payments WHERE id = ? AND cashier_id = ? FOR UPDATE');
    $stmt->bind_param('is',$id,$cashier);$stmt->execute();
    if (!$stmt->get_result()->fetch_row()) throw new InvalidArgumentException('Payment option was not found for this cashier.');
    if ($paymentOptionAction === 'edit') {
        $description=trim((string)($_POST['description'] ?? ''));
        if ($description === '' || mb_strlen($description)>255) throw new InvalidArgumentException('Enter a payment name of 1 to 255 characters.');
        $stmt=$conn->prepare('UPDATE bill_payments SET description = ? WHERE id = ? AND cashier_id = ?');
        $stmt->bind_param('sis',$description,$id,$cashier);$stmt->execute();
    } else {
        $stmt=$conn->prepare('UPDATE transactions SET bill_payment_id = NULL WHERE bill_payment_id = ?');
        $stmt->bind_param('i',$id);$stmt->execute();
        $stmt=$conn->prepare('DELETE FROM bill_payments WHERE id = ? AND cashier_id = ?');
        $stmt->bind_param('is',$id,$cashier);$stmt->execute();
    }
    as_record_activity($conn,$session,'payment_option_'.$paymentOptionAction,['payment_option_id'=>$id],'server');
    $conn->commit();
    echo json_encode(['status'=>'success','message'=>$paymentOptionAction==='edit'?'Payment updated.':'Payment deleted.']);
} catch (Throwable $e) {
    $conn->rollback();
    error_log('Payment option mutation failed: '.$e->getMessage());
    echo json_encode(['status'=>'error','message'=>$e instanceof InvalidArgumentException?$e->getMessage():'Unable to update this payment option. Please try again.']);
}
