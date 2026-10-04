<?php
header('Content-Type: application/json');
require_once __DIR__ . '/admin_account_common.php';
try {
    if (($_SERVER['REQUEST_METHOD'] ?? '') !== 'POST') throw new InvalidArgumentException('POST is required.');
    $session = account_admin($conn);
    $category = trim((string)($_POST['category'] ?? ''));
    [$table,$key] = account_target($category);
    $id = trim((string)($_POST['id'] ?? ''));
    $name = trim((string)($_POST['Fname'] ?? ''));
    if ($id === '' || $name === '') throw new InvalidArgumentException('Account ID and name are required.');
    $conn->begin_transaction();
    if (!account_query($conn, "SELECT `$key` FROM `$table` WHERE `$key` = ? FOR UPDATE", [$id])->get_result()->fetch_assoc()) throw new InvalidArgumentException('Account not found.');
    account_query($conn, "UPDATE `$table` SET Fname = ? WHERE `$key` = ?", [$name,$id]);
    if ($category === 'pos') account_query($conn, 'UPDATE canteens SET location = ? WHERE canteen_id = ?', [trim($_POST['location'] ?? ''),$id]);
    if ($category === 'cashier') {
        $username = trim($_POST['username'] ?? '');
        if ($username === '') throw new InvalidArgumentException('Username is required.');
        account_query($conn, 'UPDATE cashiers SET username = ? WHERE cashier_id = ?', [$username,$id]);
    }
    if ($category === 'parent' && array_key_exists('linked_id', $_POST)) account_set_children($conn, $id, preg_split('/[,\s]+/', $_POST['linked_id']));
    if ($category === 'student' && array_key_exists('linked_id', $_POST)) {
        $parent = trim($_POST['linked_id']);
        if ($parent !== '' && !account_query($conn, 'SELECT parent_id FROM parents WHERE parent_id = ? FOR UPDATE', [$parent])->get_result()->fetch_assoc()) throw new InvalidArgumentException('Parent not found.');
        account_query($conn, 'DELETE FROM parent_student_link WHERE student_num = ?', [$id]);
        account_query($conn, 'UPDATE parents SET linked_student_num = NULL WHERE linked_student_num = ?', [$id]);
        account_query($conn, 'UPDATE students SET parent_id = ? WHERE student_num = ?', [$parent ?: null,$id]);
        if ($parent !== '') account_query($conn, 'INSERT INTO parent_student_link (parent_id, student_num) VALUES (?, ?)', [$parent,$id]);
    }
    as_record_activity($conn, $session, 'account_updated', ['category'=>$category,'account_id'=>$id], 'server');
    $conn->commit();
    echo json_encode(['status'=>'success','message'=>'Account updated successfully.']);
} catch (Throwable $e) {
    $conn->rollback();
    error_log('Account update failed: '.$e->getMessage());
    echo json_encode(['status'=>'error','message'=>$e instanceof InvalidArgumentException ? $e->getMessage() : 'Account could not be updated. Check the details and try again.']);
}
