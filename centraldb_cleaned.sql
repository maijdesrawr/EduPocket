CREATE DATABASE IF NOT EXISTS `centraldb`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_general_ci;

USE `centraldb`;

CREATE TABLE `admins` (
  `admin_id` varchar(20) NOT NULL,
  `Fname` varchar(100) NOT NULL,
  `username` varchar(50) NOT NULL,
  `password` varchar(255) NOT NULL,
  `profile_photo` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`admin_id`),
  UNIQUE KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `canteens` (
  `canteen_id` varchar(20) NOT NULL,
  `Fname` varchar(100) NOT NULL,
  `Password` varchar(255) NOT NULL,
  `location` varchar(255) DEFAULT NULL,
  `balance` decimal(10,2) NOT NULL DEFAULT 0.00,
  `profile_photo` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`canteen_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `cashiers` (
  `cashier_id` varchar(20) NOT NULL,
  `Fname` varchar(100) NOT NULL,
  `username` varchar(50) NOT NULL,
  `password` varchar(255) NOT NULL,
  `balance` decimal(10,2) NOT NULL DEFAULT 0.00,
  `profile_photo` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`cashier_id`),
  UNIQUE KEY `username` (`username`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `students` (
  `student_num` varchar(20) NOT NULL,
  `Fname` varchar(100) NOT NULL,
  `Password` varchar(255) NOT NULL,
  `qr_code` varchar(255) NOT NULL,
  `balance` decimal(10,2) DEFAULT 0.00,
  `transaction_limit` decimal(10,2) DEFAULT 0.00,
  `parent_id` varchar(20) DEFAULT NULL,
  `pin` varchar(255) DEFAULT NULL,
  `profile_photo` varchar(255) DEFAULT NULL,
  `failed_attempts` int(11) DEFAULT 0,
  `is_locked` tinyint(1) DEFAULT 0,
  `transaction_limit_period` enum('daily','weekly','monthly') NOT NULL DEFAULT 'daily',
  PRIMARY KEY (`student_num`),
  UNIQUE KEY `qr_code` (`qr_code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `parents` (
  `parent_id` varchar(20) NOT NULL,
  `Fname` varchar(100) NOT NULL,
  `Password` varchar(255) NOT NULL,
  `email` varchar(100) NOT NULL,
  `linked_student_num` varchar(20) DEFAULT NULL,
  `profile_photo` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`parent_id`),
  KEY `linked_student_num` (`linked_student_num`),
  CONSTRAINT `parents_ibfk_1` FOREIGN KEY (`linked_student_num`) REFERENCES `students` (`student_num`) ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `products` (
  `product_id` int(11) NOT NULL AUTO_INCREMENT,
  `canteen_id` varchar(20) DEFAULT NULL,
  `name` varchar(100) NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `stock_qty` int(11) NOT NULL DEFAULT 0,
  `is_active` tinyint(1) DEFAULT 1,
  PRIMARY KEY (`product_id`),
  KEY `canteen_id` (`canteen_id`),
  CONSTRAINT `products_ibfk_1` FOREIGN KEY (`canteen_id`) REFERENCES `canteens` (`canteen_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `parent_student_link` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `parent_id` varchar(20) NOT NULL,
  `student_num` varchar(20) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `parent_id` (`parent_id`),
  KEY `student_num` (`student_num`),
  CONSTRAINT `parent_student_link_ibfk_1` FOREIGN KEY (`parent_id`) REFERENCES `parents` (`parent_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `parent_student_link_ibfk_2` FOREIGN KEY (`student_num`) REFERENCES `students` (`student_num`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=5 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `pos_carts` (
  `cart_id` int(11) NOT NULL AUTO_INCREMENT,
  `canteen_id` varchar(20) NOT NULL,
  `cashier_id` varchar(20) NOT NULL,
  `status` enum('open','checked_out') DEFAULT 'open',
  `created_at` datetime DEFAULT current_timestamp(),
  `updated_at` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`cart_id`),
  KEY `canteen_id` (`canteen_id`),
  KEY `cashier_id` (`cashier_id`),
  CONSTRAINT `pos_carts_ibfk_1` FOREIGN KEY (`canteen_id`) REFERENCES `canteens` (`canteen_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `pos_carts_ibfk_2` FOREIGN KEY (`cashier_id`) REFERENCES `cashiers` (`cashier_id`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `topups` (
  `topup_id` int(11) NOT NULL AUTO_INCREMENT,
  `parent_id` varchar(20) DEFAULT NULL,
  `student_num` varchar(20) DEFAULT NULL,
  `amount` decimal(10,2) NOT NULL,
  `method` enum('Bank','GCash','Over-the-counter') NOT NULL,
  `status` enum('Pending','Completed') DEFAULT 'Pending',
  `date_time` datetime DEFAULT current_timestamp(),
  PRIMARY KEY (`topup_id`),
  KEY `parent_id` (`parent_id`),
  KEY `student_num` (`student_num`),
  CONSTRAINT `topups_ibfk_1` FOREIGN KEY (`parent_id`) REFERENCES `parents` (`parent_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `topups_ibfk_2` FOREIGN KEY (`student_num`) REFERENCES `students` (`student_num`) ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB AUTO_INCREMENT=2 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `transactions` (
  `transaction_id` int(11) NOT NULL AUTO_INCREMENT,
  `student_num` varchar(20) NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `transaction_type` enum('payment','top-up') NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `date_time` datetime DEFAULT current_timestamp(),
  `date_created` datetime NOT NULL DEFAULT current_timestamp(),
  `canteen_id` varchar(20) DEFAULT NULL,
  `cashier_id` varchar(20) DEFAULT NULL,
  PRIMARY KEY (`transaction_id`),
  KEY `student_num` (`student_num`),
  KEY `canteen_id` (`canteen_id`),
  KEY `cashier_id` (`cashier_id`),
  CONSTRAINT `transactions_ibfk_1` FOREIGN KEY (`student_num`) REFERENCES `students` (`student_num`) ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `transactions_ibfk_2` FOREIGN KEY (`canteen_id`) REFERENCES `canteens` (`canteen_id`),
  CONSTRAINT `transactions_ibfk_3` FOREIGN KEY (`cashier_id`) REFERENCES `cashiers` (`cashier_id`)
) ENGINE=InnoDB AUTO_INCREMENT=4 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `pos_cart_items` (
  `cart_item_id` int(11) NOT NULL AUTO_INCREMENT,
  `cart_id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL,
  `quantity` int(11) NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `notes` varchar(255) DEFAULT NULL,
  `updated_at` datetime DEFAULT current_timestamp() ON UPDATE current_timestamp(),
  PRIMARY KEY (`cart_item_id`),
  UNIQUE KEY `cart_id` (`cart_id`,`product_id`),
  KEY `product_id` (`product_id`),
  CONSTRAINT `pos_cart_items_ibfk_1` FOREIGN KEY (`cart_id`) REFERENCES `pos_carts` (`cart_id`) ON DELETE CASCADE,
  CONSTRAINT `pos_cart_items_ibfk_2` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `transaction_items` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `transaction_id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL,
  `quantity` int(11) NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `notes` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `transaction_id` (`transaction_id`),
  KEY `product_id` (`product_id`),
  CONSTRAINT `transaction_items_ibfk_1` FOREIGN KEY (`transaction_id`) REFERENCES `transactions` (`transaction_id`) ON DELETE CASCADE,
  CONSTRAINT `transaction_items_ibfk_2` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`)
) ENGINE=InnoDB AUTO_INCREMENT=3 DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

INSERT INTO `admins` (`admin_id`, `Fname`, `role`, `username`, `password`, `profile_photo`) VALUES
('A3001', 'Admin One', 'system admin', 'admin1', 'admin123', 'uploads/profile/admin_A3001_20260326155941_94ecb6c8ee.png');

COMMIT;
