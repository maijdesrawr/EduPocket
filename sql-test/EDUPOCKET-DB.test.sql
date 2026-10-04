CREATE DATABASE centraldb_import_test_20260816 CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
USE centraldb_import_test_20260816;

CREATE TABLE students (
  student_num VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci PRIMARY KEY,
  Fname VARCHAR(100) NOT NULL,
  Password VARCHAR(255) NOT NULL,
  qr_code VARCHAR(255) UNIQUE NOT NULL,
  balance DECIMAL(10,2) DEFAULT 0.00
);

CREATE TABLE parents (
  parent_id VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci PRIMARY KEY,
  Fname VARCHAR(100) NOT NULL,
  Password VARCHAR(255) NOT NULL,
  email VARCHAR(100) NOT NULL,
  linked_student_num VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  FOREIGN KEY (linked_student_num) REFERENCES students(student_num)
    ON DELETE SET NULL
    ON UPDATE CASCADE
);

CREATE TABLE transactions (
  transaction_id INT AUTO_INCREMENT PRIMARY KEY,
  student_num VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  amount DECIMAL(10,2) NOT NULL,
  transaction_type ENUM('payment','top-up') NOT NULL,
  description VARCHAR(255),
  date_time DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (student_num) REFERENCES students(student_num)
    ON DELETE CASCADE
    ON UPDATE CASCADE
);

CREATE TABLE topups (
  topup_id INT AUTO_INCREMENT PRIMARY KEY,
  parent_id VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  student_num VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci,
  amount DECIMAL(10,2) NOT NULL,
  method ENUM('Bank','GCash','Over-the-counter') NOT NULL,
  status ENUM('Pending','Completed') DEFAULT 'Pending',
  date_time DATETIME DEFAULT CURRENT_TIMESTAMP,
  FOREIGN KEY (parent_id) REFERENCES parents(parent_id)
    ON DELETE CASCADE
    ON UPDATE CASCADE,
  FOREIGN KEY (student_num) REFERENCES students(student_num)
    ON DELETE CASCADE
    ON UPDATE CASCADE
);

CREATE TABLE admins (
  admin_id VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci PRIMARY KEY,
  Fname VARCHAR(100) NOT NULL,
  role ENUM('system admin','cashier','registrar') NOT NULL,
  username VARCHAR(50) UNIQUE NOT NULL,
  password VARCHAR(255) NOT NULL
);

CREATE TABLE canteens (
  canteen_id VARCHAR(20) CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci PRIMARY KEY,
  Fname VARCHAR(100) NOT NULL,
  Password VARCHAR(255) NOT NULL,
  location VARCHAR(255)
);

CREATE TABLE parent_student_link (
  id INT AUTO_INCREMENT PRIMARY KEY,
  parent_id VARCHAR(10) NOT NULL,
  student_num VARCHAR(10) NOT NULL,
  FOREIGN KEY (parent_id) REFERENCES parents(parent_id) ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY (student_num) REFERENCES students(student_num) ON DELETE CASCADE ON UPDATE CASCADE
);

ALTER TABLE students ADD COLUMN transaction_limit DECIMAL(10,2) DEFAULT 0;
ALTER TABLE students ADD COLUMN parent_id VARCHAR(20);
ALTER TABLE students
ADD COLUMN pin VARCHAR(255) NOT NULL AFTER Password;

alter table parent_student_link modify parent_id varchar(20) not null;
alter table parent_student_link modify student_num varchar(20) not null;
ALTER TABLE transactions
ADD COLUMN date_created DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER amount;

UPDATE students s
INNER JOIN parent_student_link l ON s.student_num = l.student_num
SET s.parent_id = l.parent_id;

CREATE TABLE products (
  product_id INT AUTO_INCREMENT PRIMARY KEY,
  canteen_id VARCHAR(20),
  name VARCHAR(100) NOT NULL,
  price DECIMAL(10,2) NOT NULL,
  is_active BOOLEAN DEFAULT 1,
  FOREIGN KEY (canteen_id) REFERENCES canteens(canteen_id)
    ON DELETE CASCADE ON UPDATE CASCADE
);

ALTER TABLE products
ADD COLUMN stock_qty INT NOT NULL DEFAULT 0 AFTER price;

CREATE TABLE transaction_items (
  id INT AUTO_INCREMENT PRIMARY KEY,
  transaction_id INT,
  product_id INT,
  quantity INT NOT NULL,
  price DECIMAL(10,2) NOT NULL,
  FOREIGN KEY (transaction_id) REFERENCES transactions(transaction_id)
    ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(product_id)
);

CREATE TABLE pos_carts (
  cart_id INT AUTO_INCREMENT PRIMARY KEY,
  canteen_id VARCHAR(20) NOT NULL,
  cashier_id VARCHAR(20) NOT NULL,
  status ENUM('open','checked_out') DEFAULT 'open',
  created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  FOREIGN KEY (canteen_id) REFERENCES canteens(canteen_id)
    ON DELETE CASCADE ON UPDATE CASCADE,
  FOREIGN KEY (cashier_id) REFERENCES admins(admin_id)
    ON DELETE CASCADE ON UPDATE CASCADE
);

CREATE TABLE pos_cart_items (
  cart_item_id INT AUTO_INCREMENT PRIMARY KEY,
  cart_id INT NOT NULL,
  product_id INT NOT NULL,
  quantity INT NOT NULL,
  price DECIMAL(10,2) NOT NULL,
  notes VARCHAR(255) DEFAULT NULL,
  updated_at DATETIME DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE (cart_id, product_id),
  FOREIGN KEY (cart_id) REFERENCES pos_carts(cart_id)
    ON DELETE CASCADE,
  FOREIGN KEY (product_id) REFERENCES products(product_id)
    ON DELETE RESTRICT
);

ALTER TABLE transactions
ADD COLUMN canteen_id VARCHAR(20),
ADD COLUMN cashier_id VARCHAR(20),
ADD FOREIGN KEY (canteen_id) REFERENCES canteens(canteen_id),
ADD FOREIGN KEY (cashier_id) REFERENCES admins(admin_id);

ALTER TABLE transaction_items
ADD COLUMN notes VARCHAR(255) DEFAULT NULL;

ALTER TABLE transaction_items
MODIFY COLUMN transaction_id INT NOT NULL,
MODIFY COLUMN product_id INT NOT NULL;

ALTER TABLE admins 
ADD COLUMN canteen_id VARCHAR(20);

ALTER TABLE admins
ADD CONSTRAINT fk_admin_canteen
FOREIGN KEY (canteen_id) REFERENCES canteens(canteen_id)
ON DELETE SET NULL
ON UPDATE CASCADE;

UPDATE admins SET canteen_id = 'C101' WHERE admin_id = 'C4001';
UPDATE admins SET canteen_id = 'C102' WHERE admin_id = 'C4002';

update students set pin='123456' where student_num ='20231102208';
INSERT INTO students (student_num, Fname, Password, qr_code, balance)
VALUES
('S1001', 'Juan Dela Cruz', 'student123', 'QR-S1001-001', 250.00),
('S1002', 'Maria Santos', 'student456', 'QR-S1002-002', 120.00),
('S1003', 'Pedro Reyes', 'student789', 'QR-S1003-003', 500.00);

INSERT INTO parents (parent_id, Fname, Password, email, linked_student_num)
VALUES
('P2001', 'Jose Dela Cruz', 'parent123', 'jose.dc@example.com', 'S1001'),
('P2002', 'Ana Santos', 'parent456', 'ana.santos@example.com', 'S1002'),
('P2003', 'Luz Reyes', 'parent789', 'luz.reyes@example.com', 'S1003');

INSERT INTO transactions (student_num, amount, transaction_type, description)
VALUES
('S1001', 50.00, 'payment', 'Canteen purchase - Lunch'),
('S1001', 100.00, 'top-up', 'Parent Jose top-up'),
('S1002', 40.00, 'payment', 'Canteen purchase - Snack'),
('S1003', 200.00, 'top-up', 'Parent Luz top-up');

INSERT INTO topups (parent_id, student_num, amount, method, status)
VALUES
('P2001', 'S1001', 100.00, 'GCash', 'Completed'),
('P2002', 'S1002', 150.00, 'Bank', 'Completed'),
('P2003', 'S1003', 200.00, 'Over-the-counter', 'Pending');

INSERT INTO admins (admin_id, Fname, role, username, password)
VALUES
('A3001', 'Admin One', 'system admin', 'admin1', 'admin123'),
('A3002', 'Cashier A', 'cashier', 'cashier1', 'cash123'),
('A3003', 'Registrar B', 'registrar', 'registrar1', 'reg123');

INSERT INTO canteens (canteen_id, Fname, Password, location)
VALUES
('C4001', 'Canteen A', 'canteen123', 'Main Building'),
('C4002', 'Canteen B', 'canteen456', 'High School Wing');

INSERT INTO parent_student_link (parent_id, student_num)
VALUES
('P2001', 'S1001'),
('P2002', 'S1002'),
('P2003', 'S1003');

alter table parent_student_link modify parent_id varchar(20) not null;
alter table parent_student_link modify student_num varchar(20) not null;

SELECT * FROM parent_student_link;

use centraldb_import_test_20260816;
select * from topups;
select * from transactions where student_num = '20231102208';
select * from students;
select * from parents;

ALTER TABLE students MODIFY pin VARCHAR(10) NULL;

ALTER TABLE students ADD COLUMN transaction_limit DECIMAL(10,2) DEFAULT 0;
ALTER TABLE students ADD COLUMN parent_id VARCHAR(20);

alter table parent_student_link modify parent_id varchar(20) not null;
alter table parent_student_link modify student_num varchar(20) not null;

UPDATE students s
INNER JOIN parent_student_link l ON s.student_num = l.student_num
SET s.parent_id = l.parent_id;

INSERT INTO students (student_num, Fname, Password, qr_code, balance)
VALUES ('S1004', 'Carla Dela Cruz', 'student321', 'QR-S1004-004', 150.00);

INSERT INTO parent_student_link (parent_id, student_num)
VALUES ('P2001', 'S1004');

INSERT INTO students (student_num, Fname, Password, qr_code, balance)
VALUES
('S20231102208', 'Jamaica Ajose', 'hatdog', 'QR-20231102208', 00.00);

INSERT INTO students (student_num, Fname, Password, qr_code, balance)
VALUES
('20232201108', 'Joshua Ajose', 'kekeke', 'QR-20232201108', 00.00);

INSERT INTO parents (parent_id, Fname, Password, email, linked_student_num)
VALUES
('P20231102208', 'Norma Ajose', 'rawr', 'norma@gmail.com', 'S20231102208');

update students set student_num = 20231102208 where student_num = "S20231102208";
update students set qr_code = 20231102208 where student_num = "20231102208";

select * from parents;
update parents set  linked_student_num = 20231102208 where parent_id = "P20231102208";

INSERT INTO parent_student_link (parent_id, student_num)
VALUES ('P20231102208', '20232201108');

select * from parent_student_link where parent_id = "P20231102208";

INSERT INTO transactions (student_num, amount, transaction_type, description)
VALUES
('20232201108', 100.00, 'payment', 'Canteen purchase - Noodles'),
('20232201108', 550.00, 'payment', 'Canteen purchase - SchoolID');

INSERT INTO transactions (student_num, amount, transaction_type, description)
VALUES
('S1001', 150.00, 'payment', 'Canteen purchase - Breakfast');

INSERT INTO transactions (student_num, amount, transaction_type, description)
VALUES
('20231102208', 150.00, 'payment', 'Canteen purchase - Noodles');

SELECT * FROM parent_student_link WHERE parent_id = 'P2001';

INSERT INTO transactions (student_num, amount, transaction_type, description)
VALUES
(20232201108, 40, 'payment', 'Canteen purchase - Pancit Cantown');

SELECT admin_id, role, canteen_id FROM admins;

select * from canteens;
select * from admins;

DELETE FROM admins 
WHERE admin_id != 'A3001';

UPDATE admins 
SET role = 'cashier',
    canteen_id = 'C4001'
WHERE admin_id = 'A3001';

ALTER TABLE canteens
ADD COLUMN balance DECIMAL(10,2) NOT NULL DEFAULT 0;

ALTER TABLE students
ADD COLUMN first_name VARCHAR(50),
ADD COLUMN middle_name VARCHAR(50),
ADD COLUMN last_name VARCHAR(50);

ALTER TABLE parents
ADD COLUMN first_name VARCHAR(50) NOT NULL,
ADD COLUMN middle_name VARCHAR(50),
ADD COLUMN last_name VARCHAR(50) NOT NULL;

ALTER TABLE students
ADD COLUMN suffix VARCHAR(10) NULL AFTER last_name;

ALTER TABLE parents
ADD COLUMN suffix VARCHAR(10) NULL AFTER last_name;


ALTER TABLE students
ADD COLUMN password_changed BOOLEAN DEFAULT FALSE;

ALTER TABLE parents
ADD COLUMN password_changed BOOLEAN DEFAULT FALSE;

ALTER TABLE students
ADD COLUMN is_frozen TINYINT(1) DEFAULT 0;

CREATE TABLE pending_payments (
    id INT AUTO_INCREMENT PRIMARY KEY,
    checkout_id VARCHAR(100),
    parent_id VARCHAR(50),
    student_num VARCHAR(50),
    amount DECIMAL(10,2),
    method VARCHAR(50),
    status VARCHAR(20) DEFAULT 'pending',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE active_sessions (
    session_id INT AUTO_INCREMENT PRIMARY KEY,
    user_id VARCHAR(20) NOT NULL,
    user_role VARCHAR(20) NOT NULL,
    device_id VARCHAR(255) NOT NULL,
    session_token VARCHAR(255) NOT NULL,
    login_time DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_activity DATETIME DEFAULT CURRENT_TIMESTAMP,
    is_active TINYINT(1) DEFAULT 1,

    UNIQUE KEY unique_user (user_id, user_role),
    UNIQUE KEY unique_token (session_token)
);

select * from students;
DESCRIBE transactions;
SELECT * FROM pending_payments;
select * from topups;
select * from transactions;
use centraldb_import_test_20260816;