<?php
header('Content-Type: application/json');
require_once __DIR__ . '/admin_account_common.php';
try {
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') throw new InvalidArgumentException('POST is required.');
    $session = account_admin($conn);
    $category = trim((string)($_POST['category'] ?? ''));
    [$table,$key] = account_target($category);
    $id = trim((string)($_POST['id'] ?? ''));
    if ($id === '') throw new InvalidArgumentException('Account ID is required.');
    $conn->begin_transaction();
    if (!account_query($conn, "SELECT `$key` FROM `$table` WHERE `$key` = ? FOR UPDATE", [$id])->get_result()->fetch_assoc()) throw new InvalidArgumentException('Account not found.');
    if ($category === 'parent') {
        account_query($conn, 'UPDATE students SET parent_id = NULL WHERE parent_id = ?', [$id]);
        account_query($conn, 'UPDATE topups SET parent_id = NULL WHERE parent_id = ?', [$id]);
        account_query($conn, 'DELETE FROM parent_student_link WHERE parent_id = ?', [$id]);
        account_query($conn, "UPDATE pending_payments SET status = 'cancelled' WHERE parent_id = ? AND status = 'pending'", [$id]);
    } elseif ($category === 'pos') {
        account_query($conn, 'DELETE i FROM pos_cart_items i JOIN pos_carts c ON c.cart_id = i.cart_id WHERE c.canteen_id = ?', [$id]);
        account_query($conn, 'DELETE FROM pos_carts WHERE canteen_id = ?', [$id]);
        account_query($conn, 'UPDATE products SET canteen_id = NULL, is_active = 0 WHERE canteen_id = ?', [$id]);
        foreach (['cashiers','admins','transactions'] as $t) account_query($conn, "UPDATE `$t` SET canteen_id = NULL WHERE canteen_id = ?", [$id]);
    } elseif ($category === 'cashier') {
        account_query($conn, 'DELETE i FROM pos_cart_items i JOIN pos_carts c ON c.cart_id = i.cart_id WHERE c.cashier_id = ?', [$id]);
        account_query($conn, 'DELETE FROM pos_carts WHERE cashier_id = ?', [$id]);
        account_query($conn, 'UPDATE transactions t JOIN bill_payments b ON b.id = t.bill_payment_id SET t.bill_payment_id = NULL WHERE b.cashier_id = ?', [$id]);
        account_query($conn, 'DELETE FROM bill_payments WHERE cashier_id = ?', [$id]);
        account_query($conn, 'UPDATE transactions SET cashier_id = NULL WHERE cashier_id = ?', [$id]);
    } else {
        account_query($conn, 'UPDATE transactions SET student_num = NULL WHERE student_num = ?', [$id]);
        account_query($conn, 'UPDATE topups SET student_num = NULL WHERE student_num = ?', [$id]);
        account_query($conn, "UPDATE pending_payments SET status = 'cancelled' WHERE student_num = ? AND status = 'pending'", [$id]);
        account_query($conn, 'UPDATE parents SET linked_student_num = NULL WHERE linked_student_num = ?', [$id]);
        account_query($conn, 'DELETE FROM parent_student_link WHERE student_num = ?', [$id]);
    }
    account_query($conn, "DELETE FROM `$table` WHERE `$key` = ?", [$id]);
    as_record_activity($conn, $session, 'account_deleted', ['category'=>$category,'account_id'=>$id], 'server');
    $conn->commit();
    echo json_encode(['status'=>'success','message'=>'Account deleted successfully.']);
} catch (Throwable $e) {
    $conn->rollback();
    error_log('Account deletion failed: '.$e->getMessage());
    echo json_encode(['status'=>'error','message'=>$e instanceof InvalidArgumentException ? $e->getMessage() : 'The account could not be deleted. Please try again.']);
}
