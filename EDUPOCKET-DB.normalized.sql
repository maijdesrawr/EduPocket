SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

DROP DATABASE IF EXISTS `centraldb`;
CREATE DATABASE `centraldb`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_general_ci;
USE `centraldb`;

CREATE TABLE `students` (
  `student_num` varchar(20) NOT NULL,
  `Fname` varchar(100) NOT NULL,
  `first_name` varchar(50) NOT NULL,
  `middle_name` varchar(50) DEFAULT NULL,
  `last_name` varchar(50) NOT NULL,
  `suffix` varchar(10) DEFAULT NULL,
  `Password` varchar(255) NOT NULL,
  `pin` varchar(255) DEFAULT NULL,
  `qr_code` varchar(255) NOT NULL,
  `balance` decimal(10,2) NOT NULL DEFAULT 0.00,
  `transaction_limit` decimal(10,2) NOT NULL DEFAULT 0.00,
  `transaction_limit_period` enum('daily','weekly','monthly') NOT NULL DEFAULT 'daily',
  `parent_id` varchar(20) DEFAULT NULL,
  `profile_photo` varchar(255) DEFAULT NULL,
  `failed_attempts` int NOT NULL DEFAULT 0,
  `is_locked` tinyint(1) NOT NULL DEFAULT 0,
  `is_frozen` tinyint(1) NOT NULL DEFAULT 0,
  `password_changed` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`student_num`),
  UNIQUE KEY `uq_students_qr_code` (`qr_code`),
  KEY `idx_students_parent_id` (`parent_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `parents` (
  `parent_id` varchar(20) NOT NULL,
  `Fname` varchar(100) NOT NULL,
  `first_name` varchar(50) NOT NULL,
  `middle_name` varchar(50) DEFAULT NULL,
  `last_name` varchar(50) NOT NULL,
  `suffix` varchar(10) DEFAULT NULL,
  `Password` varchar(255) NOT NULL,
  `email` varchar(100) DEFAULT NULL,
  `linked_student_num` varchar(20) DEFAULT NULL,
  `profile_photo` varchar(255) DEFAULT NULL,
  `password_changed` tinyint(1) NOT NULL DEFAULT 0,
  PRIMARY KEY (`parent_id`),
  KEY `idx_parents_linked_student` (`linked_student_num`),
  CONSTRAINT `fk_parents_linked_student`
    FOREIGN KEY (`linked_student_num`) REFERENCES `students` (`student_num`)
    ON DELETE SET NULL ON UPDATE CASCADE
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

CREATE TABLE `admins` (
  `admin_id` varchar(20) NOT NULL,
  `Fname` varchar(100) NOT NULL,
  `role` enum('system admin','cashier','registrar') NOT NULL DEFAULT 'system admin',
  `username` varchar(50) NOT NULL,
  `password` varchar(255) NOT NULL,
  `canteen_id` varchar(20) DEFAULT NULL,
  `profile_photo` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`admin_id`),
  UNIQUE KEY `uq_admins_username` (`username`),
  KEY `idx_admins_canteen_id` (`canteen_id`),
  CONSTRAINT `fk_admins_canteen`
    FOREIGN KEY (`canteen_id`) REFERENCES `canteens` (`canteen_id`)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `cashiers` (
  `cashier_id` varchar(20) NOT NULL,
  `Fname` varchar(100) NOT NULL,
  `username` varchar(50) NOT NULL,
  `password` varchar(255) NOT NULL,
  `canteen_id` varchar(20) DEFAULT NULL,
  `balance` decimal(10,2) NOT NULL DEFAULT 0.00,
  `profile_photo` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`cashier_id`),
  UNIQUE KEY `uq_cashiers_username` (`username`),
  KEY `idx_cashiers_canteen_id` (`canteen_id`),
  CONSTRAINT `fk_cashiers_canteen`
    FOREIGN KEY (`canteen_id`) REFERENCES `canteens` (`canteen_id`)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `parent_student_link` (
  `id` int NOT NULL AUTO_INCREMENT,
  `parent_id` varchar(20) NOT NULL,
  `student_num` varchar(20) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_parent_student` (`parent_id`, `student_num`),
  KEY `idx_link_student_num` (`student_num`),
  CONSTRAINT `fk_link_parent`
    FOREIGN KEY (`parent_id`) REFERENCES `parents` (`parent_id`)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_link_student`
    FOREIGN KEY (`student_num`) REFERENCES `students` (`student_num`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `products` (
  `product_id` int NOT NULL AUTO_INCREMENT,
  `canteen_id` varchar(20) DEFAULT NULL,
  `name` varchar(100) NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `stock_qty` int NOT NULL DEFAULT 0,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`product_id`),
  KEY `idx_products_canteen_id` (`canteen_id`),
  CONSTRAINT `fk_products_canteen`
    FOREIGN KEY (`canteen_id`) REFERENCES `canteens` (`canteen_id`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `transactions` (
  `transaction_id` int NOT NULL AUTO_INCREMENT,
  `student_num` varchar(20) NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `transaction_type` enum('payment','top-up') NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `date_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `date_created` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `canteen_id` varchar(20) DEFAULT NULL,
  `cashier_id` varchar(20) DEFAULT NULL,
  `bill_payment_id` int DEFAULT NULL,
  PRIMARY KEY (`transaction_id`),
  KEY `idx_transactions_student_num` (`student_num`),
  KEY `idx_transactions_canteen_id` (`canteen_id`),
  KEY `idx_transactions_cashier_id` (`cashier_id`),
  KEY `idx_transactions_bill_payment_id` (`bill_payment_id`),
  CONSTRAINT `fk_transactions_student`
    FOREIGN KEY (`student_num`) REFERENCES `students` (`student_num`)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_transactions_canteen`
    FOREIGN KEY (`canteen_id`) REFERENCES `canteens` (`canteen_id`)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `topups` (
  `topup_id` int NOT NULL AUTO_INCREMENT,
  `parent_id` varchar(20) DEFAULT NULL,
  `student_num` varchar(20) NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `method` enum('Bank','GCash','Maya','Over-the-counter') NOT NULL,
  `status` enum('Pending','Completed') NOT NULL DEFAULT 'Pending',
  `date_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`topup_id`),
  KEY `idx_topups_parent_id` (`parent_id`),
  KEY `idx_topups_student_num` (`student_num`),
  CONSTRAINT `fk_topups_parent`
    FOREIGN KEY (`parent_id`) REFERENCES `parents` (`parent_id`)
    ON DELETE SET NULL ON UPDATE CASCADE,
  CONSTRAINT `fk_topups_student`
    FOREIGN KEY (`student_num`) REFERENCES `students` (`student_num`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `transaction_items` (
  `id` int NOT NULL AUTO_INCREMENT,
  `transaction_id` int NOT NULL,
  `product_id` int NOT NULL,
  `quantity` int NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `notes` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_transaction_items_transaction_id` (`transaction_id`),
  KEY `idx_transaction_items_product_id` (`product_id`),
  CONSTRAINT `fk_transaction_items_transaction`
    FOREIGN KEY (`transaction_id`) REFERENCES `transactions` (`transaction_id`)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_transaction_items_product`
    FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `pos_carts` (
  `cart_id` int NOT NULL AUTO_INCREMENT,
  `canteen_id` varchar(20) NOT NULL,
  `cashier_id` varchar(20) NOT NULL,
  `status` enum('open','checked_out') NOT NULL DEFAULT 'open',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`cart_id`),
  KEY `idx_pos_carts_canteen_id` (`canteen_id`),
  KEY `idx_pos_carts_cashier_id` (`cashier_id`),
  CONSTRAINT `fk_pos_carts_canteen`
    FOREIGN KEY (`canteen_id`) REFERENCES `canteens` (`canteen_id`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `pos_cart_items` (
  `cart_item_id` int NOT NULL AUTO_INCREMENT,
  `cart_id` int NOT NULL,
  `product_id` int NOT NULL,
  `quantity` int NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `notes` varchar(255) DEFAULT NULL,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`cart_item_id`),
  UNIQUE KEY `uq_pos_cart_product` (`cart_id`, `product_id`),
  KEY `idx_pos_cart_items_product_id` (`product_id`),
  CONSTRAINT `fk_pos_cart_items_cart`
    FOREIGN KEY (`cart_id`) REFERENCES `pos_carts` (`cart_id`)
    ON DELETE CASCADE ON UPDATE CASCADE,
  CONSTRAINT `fk_pos_cart_items_product`
    FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `bill_payments` (
  `id` int NOT NULL AUTO_INCREMENT,
  `description` varchar(255) NOT NULL,
  `cashier_id` varchar(20) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_bill_payments_cashier_id` (`cashier_id`),
  CONSTRAINT `fk_bill_payments_cashier`
    FOREIGN KEY (`cashier_id`) REFERENCES `cashiers` (`cashier_id`)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

ALTER TABLE `transactions`
  ADD CONSTRAINT `fk_transactions_bill_payment`
    FOREIGN KEY (`bill_payment_id`) REFERENCES `bill_payments` (`id`)
    ON DELETE SET NULL ON UPDATE CASCADE;

CREATE TABLE `app_settings` (
  `setting_id` int NOT NULL AUTO_INCREMENT,
  `setting_key` varchar(100) NOT NULL,
  `setting_value` text DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`setting_id`),
  UNIQUE KEY `uq_app_settings_key` (`setting_key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `pending_payments` (
  `id` int NOT NULL AUTO_INCREMENT,
  `checkout_id` varchar(100) DEFAULT NULL,
  `parent_id` varchar(50) DEFAULT NULL,
  `student_num` varchar(50) DEFAULT NULL,
  `amount` decimal(10,2) DEFAULT NULL,
  `method` varchar(50) DEFAULT NULL,
  `status` varchar(20) NOT NULL DEFAULT 'pending',
  `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_pending_payments_checkout_id` (`checkout_id`),
  KEY `idx_pending_payments_parent_id` (`parent_id`),
  KEY `idx_pending_payments_student_num` (`student_num`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `active_sessions` (
  `session_id` int NOT NULL AUTO_INCREMENT,
  `user_id` varchar(20) NOT NULL,
  `user_role` varchar(20) NOT NULL,
  `device_id` varchar(255) NOT NULL,
  `session_token` varchar(255) NOT NULL,
  `login_time` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_activity` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `is_active` tinyint(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`session_id`),
  UNIQUE KEY `uq_active_sessions_user` (`user_id`, `user_role`),
  UNIQUE KEY `uq_active_sessions_token` (`session_token`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

CREATE TABLE `password_history` (
  `history_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `password_hash` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `password_fingerprint` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `recorded_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`history_id`),
  UNIQUE KEY `uq_password_history_exact_credential`
    (`role`, `account_source`, `user_id`, `password_fingerprint`),
  KEY `ix_password_history_account`
    (`role`, `account_source`, `user_id`, `recorded_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `password_change_authenticators` (
  `role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `totp_secret_encrypted` text CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `enrolled_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `last_verified_at` datetime(6) DEFAULT NULL,
  `last_used_step` bigint unsigned DEFAULT NULL,
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
    ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`role`, `account_source`, `user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `password_change_challenges` (
  `challenge_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `challenge_token_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `method` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `new_password_hash` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_fingerprint` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `otp_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `otp_expires_at` datetime(6) DEFAULT NULL,
  `destination_encrypted` text CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `destination_masked` varchar(320) DEFAULT NULL,
  `pending_totp_secret_encrypted` text CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `requires_totp_setup` tinyint(1) NOT NULL DEFAULT 0,
  `failed_attempts` tinyint unsigned NOT NULL DEFAULT 0,
  `resend_count` tinyint unsigned NOT NULL DEFAULT 0,
  `last_sent_at` datetime(6) DEFAULT NULL,
  `expires_at` datetime(6) NOT NULL,
  `status` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'pending',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `verified_at` datetime(6) DEFAULT NULL,
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
    ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`challenge_id`),
  UNIQUE KEY `uq_password_change_challenge_token` (`challenge_token_hash`),
  KEY `ix_password_change_challenge_account`
    (`role`, `account_source`, `user_id`, `status`),
  KEY `ix_password_change_challenge_expiry` (`status`, `expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `authenticator_management_challenges` (
  `challenge_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `challenge_token_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `action` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `account_fingerprint` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `pending_totp_secret_encrypted` text CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `expected_authenticator_fingerprint` char(64)
    CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `failed_attempts` tinyint unsigned NOT NULL DEFAULT 0,
  `expires_at` datetime(6) NOT NULL,
  `request_ip_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `status` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'pending',
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  `verified_at` datetime(6) DEFAULT NULL,
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
    ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`challenge_id`),
  UNIQUE KEY `uq_auth_management_challenge_token` (`challenge_token_hash`),
  KEY `ix_auth_management_challenge_account`
    (`role`, `account_source`, `user_id`, `status`),
  KEY `ix_auth_management_challenge_expiry` (`status`, `expires_at`),
  KEY `ix_auth_management_challenge_ip` (`request_ip_hash`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `authenticator_management_rate_limits` (
  `scope` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `scope_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `window_started_at` datetime(6) NOT NULL,
  `request_count` smallint unsigned NOT NULL,
  `updated_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
    ON UPDATE CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`scope`, `scope_hash`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE `authenticator_management_events` (
  `event_id` bigint unsigned NOT NULL AUTO_INCREMENT,
  `challenge_id` bigint unsigned NOT NULL,
  `role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `event_type` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `request_ip_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
  PRIMARY KEY (`event_id`),
  UNIQUE KEY `uq_auth_management_event_challenge` (`challenge_id`),
  KEY `ix_auth_management_event_account`
    (`role`, `account_source`, `user_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$

CREATE TRIGGER edupocket_students_auth_management_delete
AFTER DELETE ON students
FOR EACH ROW
BEGIN
  DELETE FROM password_change_authenticators
  WHERE role = 'student' AND account_source = 'students'
    AND user_id = OLD.student_num;
  DELETE FROM authenticator_management_challenges
  WHERE role = 'student' AND account_source = 'students'
    AND user_id = OLD.student_num;
  DELETE FROM authenticator_management_events
  WHERE role = 'student' AND account_source = 'students'
    AND user_id = OLD.student_num;
END$$

CREATE TRIGGER edupocket_students_auth_management_identity_update
AFTER UPDATE ON students
FOR EACH ROW
BEGIN
  IF NOT (OLD.student_num <=> NEW.student_num) THEN
    DELETE FROM password_change_authenticators
    WHERE role = 'student' AND account_source = 'students'
      AND user_id = OLD.student_num;
    DELETE FROM authenticator_management_challenges
    WHERE role = 'student' AND account_source = 'students'
      AND user_id = OLD.student_num;
    DELETE FROM authenticator_management_events
    WHERE role = 'student' AND account_source = 'students'
      AND user_id = OLD.student_num;
  END IF;
END$$

CREATE TRIGGER edupocket_parents_auth_management_delete
AFTER DELETE ON parents
FOR EACH ROW
BEGIN
  DELETE FROM password_change_authenticators
  WHERE role = 'parent' AND account_source = 'parents'
    AND user_id = OLD.parent_id;
  DELETE FROM authenticator_management_challenges
  WHERE role = 'parent' AND account_source = 'parents'
    AND user_id = OLD.parent_id;
  DELETE FROM authenticator_management_events
  WHERE role = 'parent' AND account_source = 'parents'
    AND user_id = OLD.parent_id;
END$$

CREATE TRIGGER edupocket_parents_auth_management_identity_update
AFTER UPDATE ON parents
FOR EACH ROW
BEGIN
  IF NOT (OLD.parent_id <=> NEW.parent_id) THEN
    DELETE FROM password_change_authenticators
    WHERE role = 'parent' AND account_source = 'parents'
      AND user_id = OLD.parent_id;
    DELETE FROM authenticator_management_challenges
    WHERE role = 'parent' AND account_source = 'parents'
      AND user_id = OLD.parent_id;
    DELETE FROM authenticator_management_events
    WHERE role = 'parent' AND account_source = 'parents'
      AND user_id = OLD.parent_id;
  END IF;
END$$

CREATE TRIGGER edupocket_admins_auth_management_delete
AFTER DELETE ON admins
FOR EACH ROW
BEGIN
  DELETE FROM password_change_authenticators
  WHERE role = CASE
          WHEN LOWER(COALESCE(OLD.role, '')) = 'cashier' THEN 'cashier'
          ELSE 'admin'
        END
    AND account_source = 'admins' AND user_id = OLD.admin_id;
  DELETE FROM authenticator_management_challenges
  WHERE role = CASE
          WHEN LOWER(COALESCE(OLD.role, '')) = 'cashier' THEN 'cashier'
          ELSE 'admin'
        END
    AND account_source = 'admins' AND user_id = OLD.admin_id;
  DELETE FROM authenticator_management_events
  WHERE role = CASE
          WHEN LOWER(COALESCE(OLD.role, '')) = 'cashier' THEN 'cashier'
          ELSE 'admin'
        END
    AND account_source = 'admins' AND user_id = OLD.admin_id;
END$$

CREATE TRIGGER edupocket_admins_auth_management_identity_update
AFTER UPDATE ON admins
FOR EACH ROW
BEGIN
  IF NOT (OLD.admin_id <=> NEW.admin_id)
     OR ((LOWER(COALESCE(OLD.role, '')) = 'cashier')
         <> (LOWER(COALESCE(NEW.role, '')) = 'cashier')) THEN
    DELETE FROM password_change_authenticators
    WHERE role = CASE
            WHEN LOWER(COALESCE(OLD.role, '')) = 'cashier' THEN 'cashier'
            ELSE 'admin'
          END
      AND account_source = 'admins' AND user_id = OLD.admin_id;
    DELETE FROM authenticator_management_challenges
    WHERE role = CASE
            WHEN LOWER(COALESCE(OLD.role, '')) = 'cashier' THEN 'cashier'
            ELSE 'admin'
          END
      AND account_source = 'admins' AND user_id = OLD.admin_id;
    DELETE FROM authenticator_management_events
    WHERE role = CASE
            WHEN LOWER(COALESCE(OLD.role, '')) = 'cashier' THEN 'cashier'
            ELSE 'admin'
          END
      AND account_source = 'admins' AND user_id = OLD.admin_id;
  END IF;
END$$

CREATE TRIGGER edupocket_cashiers_auth_management_delete
AFTER DELETE ON cashiers
FOR EACH ROW
BEGIN
  DELETE FROM password_change_authenticators
  WHERE role = 'cashier' AND account_source = 'cashiers'
    AND user_id = OLD.cashier_id;
  DELETE FROM authenticator_management_challenges
  WHERE role = 'cashier' AND account_source = 'cashiers'
    AND user_id = OLD.cashier_id;
  DELETE FROM authenticator_management_events
  WHERE role = 'cashier' AND account_source = 'cashiers'
    AND user_id = OLD.cashier_id;
END$$

CREATE TRIGGER edupocket_cashiers_auth_management_identity_update
AFTER UPDATE ON cashiers
FOR EACH ROW
BEGIN
  IF NOT (OLD.cashier_id <=> NEW.cashier_id) THEN
    DELETE FROM password_change_authenticators
    WHERE role = 'cashier' AND account_source = 'cashiers'
      AND user_id = OLD.cashier_id;
    DELETE FROM authenticator_management_challenges
    WHERE role = 'cashier' AND account_source = 'cashiers'
      AND user_id = OLD.cashier_id;
    DELETE FROM authenticator_management_events
    WHERE role = 'cashier' AND account_source = 'cashiers'
      AND user_id = OLD.cashier_id;
  END IF;
END$$

CREATE TRIGGER edupocket_canteens_auth_management_delete
AFTER DELETE ON canteens
FOR EACH ROW
BEGIN
  DELETE FROM password_change_authenticators
  WHERE role = 'canteen' AND account_source = 'canteens'
    AND user_id = OLD.canteen_id;
  DELETE FROM authenticator_management_challenges
  WHERE role = 'canteen' AND account_source = 'canteens'
    AND user_id = OLD.canteen_id;
  DELETE FROM authenticator_management_events
  WHERE role = 'canteen' AND account_source = 'canteens'
    AND user_id = OLD.canteen_id;
END$$

CREATE TRIGGER edupocket_canteens_auth_management_identity_update
AFTER UPDATE ON canteens
FOR EACH ROW
BEGIN
  IF NOT (OLD.canteen_id <=> NEW.canteen_id) THEN
    DELETE FROM password_change_authenticators
    WHERE role = 'canteen' AND account_source = 'canteens'
      AND user_id = OLD.canteen_id;
    DELETE FROM authenticator_management_challenges
    WHERE role = 'canteen' AND account_source = 'canteens'
      AND user_id = OLD.canteen_id;
    DELETE FROM authenticator_management_events
    WHERE role = 'canteen' AND account_source = 'canteens'
      AND user_id = OLD.canteen_id;
  END IF;
END$$

DELIMITER ;

SET FOREIGN_KEY_CHECKS = 1;

INSERT INTO `students` (
  `student_num`, `Fname`, `first_name`, `middle_name`, `last_name`, `suffix`,
  `Password`, `pin`, `qr_code`, `balance`, `parent_id`, `password_changed`
) VALUES
  ('S1001', 'Juan Dela Cruz', 'Juan', NULL, 'Dela Cruz', NULL,
   'student123', NULL, 'QR-S1001-001', 250.00, 'P2001', 0),
  ('S1002', 'Maria Santos', 'Maria', NULL, 'Santos', NULL,
   'student456', NULL, 'QR-S1002-002', 120.00, 'P2002', 0),
  ('S1003', 'Pedro Reyes', 'Pedro', NULL, 'Reyes', NULL,
   'student789', NULL, 'QR-S1003-003', 500.00, 'P2003', 0),
  ('S1004', 'Carla Dela Cruz', 'Carla', NULL, 'Dela Cruz', NULL,
   'student321', NULL, 'QR-S1004-004', 150.00, 'P2001', 0),
  ('20231102208', 'Jamaica Ajose', 'Jamaica', NULL, 'Ajose', NULL,
   'hatdog', '123456', '20231102208', 0.00, 'P20231102208', 0),
  ('20232201108', 'Joshua Ajose', 'Joshua', NULL, 'Ajose', NULL,
   'kekeke', NULL, 'QR-20232201108', 0.00, 'P20231102208', 0);

INSERT INTO `parents` (
  `parent_id`, `Fname`, `first_name`, `middle_name`, `last_name`, `suffix`,
  `Password`, `email`, `linked_student_num`, `password_changed`
) VALUES
  ('P2001', 'Jose Dela Cruz', 'Jose', NULL, 'Dela Cruz', NULL,
   'parent123', 'jose.dc@example.com', 'S1001', 0),
  ('P2002', 'Ana Santos', 'Ana', NULL, 'Santos', NULL,
   'parent456', 'ana.santos@example.com', 'S1002', 0),
  ('P2003', 'Luz Reyes', 'Luz', NULL, 'Reyes', NULL,
   'parent789', 'luz.reyes@example.com', 'S1003', 0),
  ('P20231102208', 'Norma Ajose', 'Norma', NULL, 'Ajose', NULL,
   'rawr', 'norma@gmail.com', '20231102208', 0);

INSERT INTO `canteens` (`canteen_id`, `Fname`, `Password`, `location`, `balance`) VALUES
  ('C4001', 'Canteen A', 'canteen123', 'Main Building', 0.00),
  ('C4002', 'Canteen B', 'canteen456', 'High School Wing', 0.00);

INSERT INTO `admins` (
  `admin_id`, `Fname`, `role`, `username`, `password`, `canteen_id`, `profile_photo`
) VALUES
  ('A3001', 'Admin One', 'system admin', 'admin1', 'admin123', NULL, NULL),
  ('A3003', 'Registrar B', 'registrar', 'registrar1', 'reg123', NULL, NULL);

INSERT INTO `cashiers` (
  `cashier_id`, `Fname`, `username`, `password`, `canteen_id`, `balance`
) VALUES
  ('CASH001', 'Cashier One', 'cashier1', 'cash123', 'C4001', 0.00);

INSERT INTO `parent_student_link` (`parent_id`, `student_num`) VALUES
  ('P2001', 'S1001'),
  ('P2001', 'S1004'),
  ('P2002', 'S1002'),
  ('P2003', 'S1003'),
  ('P20231102208', '20231102208'),
  ('P20231102208', '20232201108');

INSERT INTO `transactions` (
  `student_num`, `amount`, `transaction_type`, `description`
) VALUES
  ('S1001', 50.00, 'payment', 'Canteen purchase - Lunch'),
  ('S1001', 100.00, 'top-up', 'Parent Jose top-up'),
  ('S1002', 40.00, 'payment', 'Canteen purchase - Snack'),
  ('S1003', 200.00, 'top-up', 'Parent Luz top-up'),
  ('20232201108', 100.00, 'payment', 'Canteen purchase - Noodles'),
  ('20232201108', 550.00, 'payment', 'Canteen purchase - SchoolID'),
  ('S1001', 150.00, 'payment', 'Canteen purchase - Breakfast'),
  ('20231102208', 150.00, 'payment', 'Canteen purchase - Noodles'),
  ('20232201108', 40.00, 'payment', 'Canteen purchase - Pancit Cantown');

INSERT INTO `topups` (
  `parent_id`, `student_num`, `amount`, `method`, `status`
) VALUES
  ('P2001', 'S1001', 100.00, 'GCash', 'Completed'),
  ('P2002', 'S1002', 150.00, 'Bank', 'Completed'),
  ('P2003', 'S1003', 200.00, 'Over-the-counter', 'Pending');

INSERT INTO `bill_payments` (`id`, `description`, `cashier_id`) VALUES
  (1, 'Cashier Payment', NULL);

INSERT INTO `app_settings` (
  `setting_id`, `setting_key`, `setting_value`, `description`
) VALUES
  (1, 'bill_payment_default', '1', 'Default bill payment record id used by the app');
