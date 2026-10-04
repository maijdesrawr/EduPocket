<?php
require_once __DIR__ . '/cors_common.php';
error_reporting(E_ALL);
ini_set('display_errors', 0);

header('Content-Type: application/json');
include 'db_connect.php';

function generateTempPassword($length = 8) {
    $characters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    $password = '';

    for ($i = 0; $i < $length; $i++) {
        $password .= $characters[random_int(0, strlen($characters) - 1)];
    }

    return $password;
}

function generateTempPIN()
{
    return str_pad(random_int(0,999999), 6, '0', STR_PAD_LEFT);
}

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    echo json_encode(['status' => 'error', 'message' => 'Invalid request method']);
    exit;
}

$category = $_POST['category'] ?? '';

if (empty($category)) {
    echo json_encode(['status' => 'error', 'message' => 'Category is required']);
    exit;
}

function sanitize($conn, $value) {
    return mysqli_real_escape_string($conn, trim($value));
}

function prepareOrThrow(mysqli $conn, string $sql): mysqli_stmt
{
    $stmt = $conn->prepare($sql);
    if (!$stmt) {
        throw new RuntimeException($conn->error, $conn->errno);
    }

    return $stmt;
}

function executeOrThrow(mysqli_stmt $stmt): void
{
    if (!$stmt->execute()) {
        throw new RuntimeException($stmt->error, $stmt->errno);
    }
}

function generateParentID($conn)
{
    $year = date('y');

    $stmt = prepareOrThrow(
        $conn,
        "SELECT parent_id
         FROM parents
         WHERE parent_id LIKE CONCAT(?, '%')
         ORDER BY parent_id DESC
         LIMIT 1
         FOR UPDATE"
    );
    $stmt->bind_param('s', $year);
    executeOrThrow($stmt);
    $result = $stmt->get_result();
    $row = $result ? $result->fetch_assoc() : null;
    $stmt->close();

    if (!empty($row['parent_id'])) {

        $lastSequence = (int) substr($row['parent_id'], 2);

        $nextSequence = str_pad(
            $lastSequence + 1,
            9,
            '0',
            STR_PAD_LEFT
        );

    } else {

        $nextSequence = '000000001';
    }

    return $year . $nextSequence;
}

$response = ['status' => 'error', 'message' => 'Unknown error'];

switch ($category) {

case 'student':

    $student_first_name = sanitize($conn, $_POST['student_first_name'] ?? '');
    $student_middle_name = sanitize($conn, $_POST['student_middle_name'] ?? '');
    $student_last_name = sanitize($conn, $_POST['student_last_name'] ?? '');
    $student_suffix = sanitize($conn, $_POST['student_suffix'] ?? '');

    $parent_first_name = sanitize($conn, $_POST['parent_first_name'] ?? '');
    $parent_middle_name = sanitize($conn, $_POST['parent_middle_name'] ?? '');
    $parent_last_name = sanitize($conn, $_POST['parent_last_name'] ?? '');
    $parent_suffix = sanitize($conn, $_POST['parent_suffix'] ?? '');
      
    $student_name = trim(
        $student_first_name . ' ' .
        $student_middle_name . ' ' .
        $student_last_name . ' ' .
        $student_suffix
    );

    $parent_name = trim(
        $parent_first_name . ' ' .
        $parent_middle_name . ' ' .
        $parent_last_name . ' ' .
        $parent_suffix
    );

    $student_num = sanitize($conn, $_POST['student_num'] ?? '');

    if (
        empty($student_first_name) ||
        empty($student_last_name) ||
        empty($student_num) ||
        empty($parent_first_name) ||
        empty($parent_last_name)
    ) {
        $response['message'] = 'Student and Parent names are required';
        break;
    }

    if (!ctype_digit($student_num) || strlen($student_num) != 11) {
        $response['message'] = 'Student Number must be exactly 11 digits';
        break;
    }

    $balance = 0.00;
    $password_changed = 0;
    $student_temp_password = generateTempPassword();
    $student_password = password_hash($student_temp_password, PASSWORD_DEFAULT);
    $parent_temp_password = generateTempPassword();
    $parent_password = password_hash($parent_temp_password, PASSWORD_DEFAULT);
    $student_temp_pin = generateTempPIN();
    $student_pin = password_hash($student_temp_pin, PASSWORD_DEFAULT);
    $qr_code = 'QR_' . $student_num;

    $conn->begin_transaction();

    try {
        $parent_id = generateParentID($conn);

        $student_stmt = prepareOrThrow(
            $conn,
            "INSERT INTO students (
                student_num, Fname, first_name, middle_name, last_name, suffix,
                Password, pin, balance, parent_id, qr_code, password_changed
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        );
        $student_stmt->bind_param(
            'ssssssssdssi',
            $student_num,
            $student_name,
            $student_first_name,
            $student_middle_name,
            $student_last_name,
            $student_suffix,
            $student_password,
            $student_pin,
            $balance,
            $parent_id,
            $qr_code,
            $password_changed
        );
        executeOrThrow($student_stmt);
        $student_stmt->close();

        $parent_stmt = prepareOrThrow(
            $conn,
            "INSERT INTO parents (
                parent_id, Fname, first_name, middle_name, last_name, suffix,
                Password, linked_student_num, password_changed
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)"
        );
        $parent_stmt->bind_param(
            'ssssssssi',
            $parent_id,
            $parent_name,
            $parent_first_name,
            $parent_middle_name,
            $parent_last_name,
            $parent_suffix,
            $parent_password,
            $student_num,
            $password_changed
        );
        executeOrThrow($parent_stmt);
        $parent_stmt->close();

        $link_stmt = prepareOrThrow(
            $conn,
            'INSERT INTO parent_student_link (parent_id, student_num) VALUES (?, ?)'
        );
        $link_stmt->bind_param('ss', $parent_id, $student_num);
        executeOrThrow($link_stmt);
        $link_stmt->close();

        $conn->commit();

        $response = [
            'status' => 'success',
            'message' => 'Student and Parent account created successfully',
            'student_num' => $student_num,
            'parent_id' => $parent_id,
            'student_temp_password' => $student_temp_password,
            'parent_temp_password' => $parent_temp_password,
            'student_temp_pin' => $student_temp_pin
        ];
    } catch (Throwable $error) {
        $conn->rollback();
        $response['message'] = $error->getCode() === 1062
            ? 'Student Number already exists'
            : 'Unable to create the student and parent accounts: ' . $error->getMessage();
    }
    break;

case 'child':

    $parent_id = sanitize($conn, $_POST['parent_id'] ?? '');

    $student_first_name = sanitize($conn, $_POST['student_first_name'] ?? '');
    $student_middle_name = sanitize($conn, $_POST['student_middle_name'] ?? '');
    $student_last_name = sanitize($conn, $_POST['student_last_name'] ?? '');
    $student_suffix = sanitize($conn, $_POST['student_suffix'] ?? '');

    $student_num = sanitize($conn, $_POST['student_num'] ?? '');

    $student_name = trim(
        $student_first_name . ' ' .
        $student_middle_name . ' ' .
        $student_last_name . ' ' .
        $student_suffix
    );

    if (
    empty($parent_id) ||
    empty($student_first_name) ||
    empty($student_last_name) ||
    empty($student_num)
) {
    $response['message'] = 'Missing required fields';
    break;
}


if (!ctype_digit($student_num) || strlen($student_num) != 11) {
    $response['message'] = 'Student Number must be exactly 11 digits';
    break;
}

    $check_parent = prepareOrThrow(
        $conn,
        'SELECT parent_id FROM parents WHERE parent_id = ? LIMIT 1'
    );
    $check_parent->bind_param('s', $parent_id);
    executeOrThrow($check_parent);
    $parent_exists = $check_parent->get_result();
    $check_parent->close();

    if (!$parent_exists || $parent_exists->num_rows === 0) {
        $response['message'] = 'Parent ID does not exist';
        break;
    }

    $balance = 0.00;
    $password_changed = 0;
    $student_temp_password = generateTempPassword();
    $student_password = password_hash($student_temp_password, PASSWORD_DEFAULT);
    $student_temp_pin = generateTempPIN();
    $student_pin = password_hash($student_temp_pin, PASSWORD_DEFAULT);

    $check_student = prepareOrThrow(
        $conn,
        'SELECT student_num FROM students WHERE student_num = ? LIMIT 1'
    );
    $check_student->bind_param('s', $student_num);
    executeOrThrow($check_student);
    $student_exists = $check_student->get_result();
    $check_student->close();

    if ($student_exists && $student_exists->num_rows > 0) {
        $response['message'] = 'Student already exists';
        break;
    }

    $qr_code = 'QR_' . $student_num;
    $conn->begin_transaction();

    try {
        $student_stmt = prepareOrThrow(
            $conn,
            "INSERT INTO students (
                student_num, Fname, first_name, middle_name, last_name, suffix,
                Password, pin, balance, parent_id, qr_code, password_changed
             ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
        );
        $student_stmt->bind_param(
            'ssssssssdssi',
            $student_num,
            $student_name,
            $student_first_name,
            $student_middle_name,
            $student_last_name,
            $student_suffix,
            $student_password,
            $student_pin,
            $balance,
            $parent_id,
            $qr_code,
            $password_changed
        );
        executeOrThrow($student_stmt);
        $student_stmt->close();

        $link_stmt = prepareOrThrow(
            $conn,
            'INSERT INTO parent_student_link (parent_id, student_num) VALUES (?, ?)'
        );
        $link_stmt->bind_param('ss', $parent_id, $student_num);
        executeOrThrow($link_stmt);
        $link_stmt->close();

        $conn->commit();

        $response = [
            'status' => 'success',
            'message' => 'Child account created successfully',
            'student_num' => $student_num,
            'parent_id' => $parent_id,
            'student_temp_password' => $student_temp_password,
            'student_temp_pin' => $student_temp_pin
        ];
    } catch (Throwable $error) {
        $conn->rollback();
        $response['message'] = $error->getCode() === 1062
            ? 'Student already exists'
            : 'Unable to create the child account: ' . $error->getMessage();
    }

break;


case 'pos':
    $name = sanitize($conn, $_POST['name'] ?? '');
    $canteen_id = sanitize($conn, $_POST['canteen_id'] ?? '');
    $location = sanitize($conn, $_POST['location'] ?? '');
    $password_raw = $_POST['password'] ?? '';

    if (empty($name) || empty($canteen_id) || empty($password_raw)) {
        $response['message'] = 'Canteen Name, ID, and Password are required';
        break;
    }

    $password = password_hash($password_raw, PASSWORD_DEFAULT);

    $sql = "INSERT INTO canteens (canteen_id, Fname, Password, location)
            VALUES ('$canteen_id', '$name', '$password', '$location')";

    if (mysqli_query($conn, $sql)) {
        $response = ['status' => 'success', 'message' => 'POS added successfully'];
    } else {
        $response['message'] = mysqli_error($conn);
    }
    break;

case 'cashier':
    $name = sanitize($conn, $_POST['name'] ?? '');
    $cashier_id = sanitize($conn, $_POST['cashier_id'] ?? '');
    $username = sanitize($conn, $_POST['username'] ?? '');
    $password_raw = $_POST['password'] ?? '';

    if (empty($name) || empty($cashier_id) || empty($username) || empty($password_raw)) {
        $response['message'] = 'Name, Cashier ID, Username, and Password are required';
        break;
    }

    $password = password_hash($password_raw, PASSWORD_DEFAULT);

    $sql = "INSERT INTO cashiers (cashier_id, Fname, username, password)
            VALUES ('$cashier_id', '$name', '$username', '$password')";

    if (mysqli_query($conn, $sql)) {
        $response = ['status' => 'success', 'message' => 'Cashier added successfully'];
    } else {
        $response['message'] = mysqli_error($conn);
    }
    break;

}

echo json_encode($response);
?>
