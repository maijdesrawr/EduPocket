drop database try;
create database try;
use try;

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;


-- --------------------------------------------------------

--
-- Table structure for table `account_notifications`
--

CREATE TABLE `account_notifications` (
  `notification_id` bigint(20) UNSIGNED NOT NULL,
  `recipient_role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `transaction_id` int(11) NOT NULL,
  `title` varchar(120) NOT NULL,
  `body` varchar(500) NOT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `read_at` datetime(6) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `account_verified_emails`
--

CREATE TABLE `account_verified_emails` (
  `role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `email_encrypted` text CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `email_masked` varchar(254) NOT NULL,
  `email_fingerprint` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `verified_at` datetime(6) NOT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `updated_at` datetime(6) NOT NULL DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `active_sessions`
--

CREATE TABLE `active_sessions` (
  `session_id` int(11) NOT NULL,
  `user_id` varchar(20) NOT NULL,
  `user_role` varchar(20) NOT NULL,
  `device_id` varchar(255) NOT NULL,
  `session_token` varchar(255) NOT NULL,
  `login_time` datetime NOT NULL DEFAULT current_timestamp(),
  `last_activity` datetime NOT NULL DEFAULT current_timestamp(),
  `is_active` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `admins`
--

CREATE TABLE `admins` (
  `admin_id` varchar(20) NOT NULL,
  `Fname` varchar(100) NOT NULL,
  `role` enum('system admin','cashier','registrar') NOT NULL DEFAULT 'system admin',
  `username` varchar(50) NOT NULL,
  `password` varchar(255) NOT NULL,
  `pin` varchar(255) DEFAULT NULL,
  `canteen_id` varchar(20) DEFAULT NULL,
  `profile_photo` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `admins`
--

INSERT INTO `admins` (`admin_id`, `Fname`, `role`, `username`, `password`, `pin`, `canteen_id`, `profile_photo`) VALUES
('A3001', 'Admin One', 'system admin', 'admin1', 'admin123', NULL, NULL, NULL);

--
-- Triggers `admins`
--
DELIMITER $$
CREATE TRIGGER `edupocket_admins_auth_management_delete` AFTER DELETE ON `admins` FOR EACH ROW BEGIN
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
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_admins_auth_management_identity_update` AFTER UPDATE ON `admins` FOR EACH ROW BEGIN
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
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_admins_login_otp_delete` AFTER DELETE ON `admins` FOR EACH ROW BEGIN
    DELETE FROM login_otp_challenges
    WHERE account_source = 'admins'
      AND BINARY user_id = BINARY OLD.admin_id;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_admins_login_otp_identity_update` AFTER UPDATE ON `admins` FOR EACH ROW BEGIN
    IF NOT (OLD.admin_id <=> NEW.admin_id)
       OR NOT (LOWER(COALESCE(OLD.role, '')) <=> LOWER(COALESCE(NEW.role, ''))) THEN
        DELETE FROM login_otp_challenges
        WHERE account_source = 'admins'
          AND BINARY user_id = BINARY OLD.admin_id;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_admins_password_history` BEFORE UPDATE ON `admins` FOR EACH ROW BEGIN
    IF NOT (OLD.password <=> NEW.password) THEN
        IF OLD.password REGEXP '^$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                CASE WHEN LOWER(COALESCE(OLD.role, '')) = 'cashier' THEN 'cashier' ELSE 'admin' END,
                'admins', OLD.admin_id, OLD.password,
                SHA2(CONCAT(
                    CASE WHEN LOWER(COALESCE(OLD.role, '')) = 'cashier' THEN 'cashier' ELSE 'admin' END,
                    CHAR(0), 'admins', CHAR(0), OLD.admin_id, CHAR(0), OLD.password
                ), 256)
            );
        END IF;
        IF NEW.password REGEXP '^$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                CASE WHEN LOWER(COALESCE(NEW.role, '')) = 'cashier' THEN 'cashier' ELSE 'admin' END,
                'admins', NEW.admin_id, NEW.password,
                SHA2(CONCAT(
                    CASE WHEN LOWER(COALESCE(NEW.role, '')) = 'cashier' THEN 'cashier' ELSE 'admin' END,
                    CHAR(0), 'admins', CHAR(0), NEW.admin_id, CHAR(0), NEW.password
                ), 256)
            );
        END IF;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_admins_security_cleanup` AFTER DELETE ON `admins` FOR EACH ROW BEGIN
    DELETE FROM account_verified_emails
    WHERE role = CASE
            WHEN LOWER(COALESCE(OLD.role, '')) = 'cashier' THEN 'cashier'
            ELSE 'admin'
          END
      AND account_source = 'admins' AND user_id = OLD.admin_id;
    DELETE FROM email_verification_challenges
    WHERE role = CASE
            WHEN LOWER(COALESCE(OLD.role, '')) = 'cashier' THEN 'cashier'
            ELSE 'admin'
          END
      AND account_source = 'admins' AND user_id = OLD.admin_id;
    DELETE FROM password_change_authenticators
    WHERE role = CASE
            WHEN LOWER(COALESCE(OLD.role, '')) = 'cashier' THEN 'cashier'
            ELSE 'admin'
          END
      AND account_source = 'admins' AND user_id = OLD.admin_id;
    DELETE FROM password_change_challenges
    WHERE role = CASE
            WHEN LOWER(COALESCE(OLD.role, '')) = 'cashier' THEN 'cashier'
            ELSE 'admin'
          END
      AND account_source = 'admins' AND user_id = OLD.admin_id;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `app_activity_events`
--

CREATE TABLE `app_activity_events` (
  `event_id` bigint(20) UNSIGNED NOT NULL,
  `session_id` bigint(20) UNSIGNED DEFAULT NULL,
  `role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `event_name` varchar(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `event_source` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'client',
  `event_status` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'success',
  `route` varchar(191) DEFAULT NULL,
  `metadata_json` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin DEFAULT NULL,
  `request_ip_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `app_sessions`
--

CREATE TABLE `app_sessions` (
  `session_id` bigint(20) UNSIGNED NOT NULL,
  `token_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `device_id_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_fingerprint` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `request_ip_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `user_agent` varchar(255) DEFAULT NULL,
  `issued_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `last_seen_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `expires_at` datetime(6) NOT NULL,
  `revoked_at` datetime(6) DEFAULT NULL,
  `revocation_reason` varchar(32) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `replaced_by_session_id` bigint(20) UNSIGNED DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `app_session_accounts`
--

CREATE TABLE `app_session_accounts` (
  `role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `current_session_id` bigint(20) UNSIGNED DEFAULT NULL,
  `updated_at` datetime(6) NOT NULL DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `app_settings`
--

CREATE TABLE `app_settings` (
  `setting_id` int(11) NOT NULL,
  `setting_key` varchar(100) NOT NULL,
  `setting_value` text DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `authenticator_management_challenges`
--

CREATE TABLE `authenticator_management_challenges` (
  `challenge_id` bigint(20) UNSIGNED NOT NULL,
  `challenge_token_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `action` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `account_fingerprint` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `pending_totp_secret_encrypted` text CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `expected_authenticator_fingerprint` char(64) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `failed_attempts` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `expires_at` datetime(6) NOT NULL,
  `request_ip_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `status` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'pending',
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `verified_at` datetime(6) DEFAULT NULL,
  `updated_at` datetime(6) NOT NULL DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `authenticator_management_events`
--

CREATE TABLE `authenticator_management_events` (
  `event_id` bigint(20) UNSIGNED NOT NULL,
  `challenge_id` bigint(20) UNSIGNED NOT NULL,
  `role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `event_type` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `request_ip_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `authenticator_management_rate_limits`
--

CREATE TABLE `authenticator_management_rate_limits` (
  `scope` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `scope_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `window_started_at` datetime(6) NOT NULL,
  `request_count` smallint(5) UNSIGNED NOT NULL,
  `updated_at` datetime(6) NOT NULL DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `backend_audit_log`
--

CREATE TABLE `backend_audit_log` (
  `audit_id` bigint(20) UNSIGNED NOT NULL,
  `request_id` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `session_id` bigint(20) UNSIGNED NOT NULL DEFAULT 0,
  `actor_authenticated` tinyint(1) NOT NULL DEFAULT 0,
  `role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'guest',
  `account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'public',
  `user_id` varchar(191) NOT NULL DEFAULT 'anonymous',
  `route` varchar(255) NOT NULL,
  `request_method` varchar(12) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `response_status` smallint(5) UNSIGNED NOT NULL,
  `outcome` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `metadata_json` longtext CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
  `request_ip_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `user_agent` varchar(255) NOT NULL DEFAULT 'Unknown client',
  `started_at` datetime(6) NOT NULL,
  `completed_at` datetime(6) NOT NULL,
  `duration_ms` int(10) UNSIGNED NOT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Triggers `backend_audit_log`
--
DELIMITER $$
CREATE TRIGGER `edupocket_backend_audit_no_delete` BEFORE DELETE ON `backend_audit_log` FOR EACH ROW SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'EduPocket backend audit rows are append-only'
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_backend_audit_no_update` BEFORE UPDATE ON `backend_audit_log` FOR EACH ROW SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'EduPocket backend audit rows are append-only'
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `bill_payments`
--

CREATE TABLE `bill_payments` (
  `id` int(11) NOT NULL,
  `description` varchar(255) NOT NULL,
  `cashier_id` varchar(20) DEFAULT NULL,
  `created_at` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `canteens`
--

CREATE TABLE `canteens` (
  `canteen_id` varchar(20) NOT NULL,
  `Fname` varchar(100) NOT NULL,
  `Password` varchar(255) NOT NULL,
  `pin` varchar(255) DEFAULT NULL,
  `location` varchar(255) DEFAULT NULL,
  `balance` decimal(10,2) NOT NULL DEFAULT 0.00,
  `profile_photo` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `canteens`
--

INSERT INTO `canteens` (`canteen_id`, `Fname`, `Password`, `pin`, `location`, `balance`, `profile_photo`) VALUES
('C4001', 'Canteen A', 'canteen123', NULL, 'Main Building', 350.00, 'uploads/profile/canteen_C4001_20260830205215_aa3192f035.jpg'),
('C4002', 'Canteen B', 'canteen456', NULL, 'High School Wing', 0.00, NULL),
('ZZSEC_CANTEEN', 'Security Canteen', '$2y$10$vemXRZAET0aEWvwX5rYD3Ol9l/ip30XeokWCJguQ0vRLvL38mZQGe', NULL, 'Test Only', 0.00, NULL);

--
-- Triggers `canteens`
--
DELIMITER $$
CREATE TRIGGER `edupocket_canteens_auth_management_delete` 
AFTER DELETE ON `canteens` 
FOR EACH ROW 
BEGIN
    DELETE FROM password_change_authenticators 
    WHERE role = 'canteen' 
        AND account_source = 'canteens' 
        AND user_id COLLATE utf8mb4_general_ci = OLD.canteen_id COLLATE utf8mb4_general_ci; DELETE FROM authenticator_management_challenges WHERE role = 'canteen' AND account_source = 'canteens' AND user_id COLLATE utf8mb4_general_ci = OLD.canteen_id COLLATE utf8mb4_general_ci; DELETE FROM authenticator_management_events WHERE role = 'canteen' AND account_source = 'canteens' AND user_id COLLATE utf8mb4_general_ci = OLD.canteen_id COLLATE utf8mb4_general_ci; END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_canteens_auth_management_identity_update` AFTER UPDATE ON `canteens` FOR EACH ROW BEGIN IF NOT (OLD.canteen_id <=> NEW.canteen_id) THEN DELETE FROM password_change_authenticators WHERE role = 'canteen' AND account_source = 'canteens' AND user_id COLLATE utf8mb4_general_ci = OLD.canteen_id COLLATE utf8mb4_general_ci; DELETE FROM authenticator_management_challenges WHERE role = 'canteen' AND account_source = 'canteens' AND user_id COLLATE utf8mb4_general_ci = OLD.canteen_id COLLATE utf8mb4_general_ci; DELETE FROM authenticator_management_events WHERE role = 'canteen' AND account_source = 'canteens' AND user_id COLLATE utf8mb4_general_ci = OLD.canteen_id COLLATE utf8mb4_general_ci; END IF; END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_canteens_login_otp_delete` AFTER DELETE ON `canteens` FOR EACH ROW BEGIN
    DELETE FROM login_otp_challenges
    WHERE account_source = 'canteens'
      AND BINARY user_id = BINARY OLD.canteen_id;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_canteens_login_otp_identity_update` AFTER UPDATE ON `canteens` FOR EACH ROW BEGIN
    IF NOT (OLD.canteen_id <=> NEW.canteen_id) THEN
        DELETE FROM login_otp_challenges
        WHERE account_source = 'canteens'
          AND BINARY user_id = BINARY OLD.canteen_id;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_canteens_password_history` BEFORE UPDATE ON `canteens` FOR EACH ROW BEGIN
    IF NOT (OLD.Password <=> NEW.Password) THEN
        IF OLD.Password REGEXP '^$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                'canteen', 'canteens', OLD.canteen_id, OLD.Password,
                SHA2(CONCAT('canteen', CHAR(0), 'canteens', CHAR(0), OLD.canteen_id, CHAR(0), OLD.Password), 256)
            );
        END IF;
        IF NEW.Password REGEXP '^$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                'canteen', 'canteens', NEW.canteen_id, NEW.Password,
                SHA2(CONCAT('canteen', CHAR(0), 'canteens', CHAR(0), NEW.canteen_id, CHAR(0), NEW.Password), 256)
            );
        END IF;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_canteens_security_cleanup` AFTER DELETE ON `canteens` FOR EACH ROW BEGIN DELETE FROM account_verified_emails WHERE role = 'canteen' AND account_source = 'canteens' AND user_id COLLATE utf8mb4_general_ci = OLD.canteen_id COLLATE utf8mb4_general_ci; DELETE FROM email_verification_challenges WHERE role = 'canteen' AND account_source = 'canteens' AND user_id COLLATE utf8mb4_general_ci = OLD.canteen_id COLLATE utf8mb4_general_ci; DELETE FROM password_change_authenticators WHERE role = 'canteen' AND account_source = 'canteens' AND user_id COLLATE utf8mb4_general_ci = OLD.canteen_id COLLATE utf8mb4_general_ci; DELETE FROM password_change_challenges WHERE role = 'canteen' AND account_source = 'canteens' AND user_id COLLATE utf8mb4_general_ci = OLD.canteen_id COLLATE utf8mb4_general_ci; END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `cashiers`
--

CREATE TABLE `cashiers` (
  `cashier_id` varchar(20) NOT NULL,
  `Fname` varchar(100) NOT NULL,
  `username` varchar(50) NOT NULL,
  `password` varchar(255) NOT NULL,
  `pin` varchar(255) DEFAULT NULL,
  `canteen_id` varchar(20) DEFAULT NULL,
  `balance` decimal(10,2) NOT NULL DEFAULT 0.00,
  `profile_photo` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `cashiers`
--

INSERT INTO `cashiers` (`cashier_id`, `Fname`, `username`, `password`, `pin`, `canteen_id`, `balance`, `profile_photo`) VALUES
('CASH001', 'Cashier One', 'cashier1', 'cash123', 123456, 'C4001', 235.00, NULL),
('ZZSEC_CASHIER', 'Security Cashier', 'zzsec_cashier', '$2y$10$2ygCmuwzJWrzxPEu99EFCOBjCmb.lj2goLBifu4KBJBB1C2eVexDO', NULL, NULL, 0.00, NULL);

--
-- Triggers `cashiers`
--
DELIMITER $$
CREATE TRIGGER `edupocket_cashiers_auth_management_delete` AFTER DELETE ON `cashiers` FOR EACH ROW BEGIN DELETE FROM password_change_authenticators WHERE role = 'cashier' AND account_source = 'cashiers' AND user_id COLLATE utf8mb4_general_ci = OLD.cashier_id COLLATE utf8mb4_general_ci; DELETE FROM authenticator_management_challenges WHERE role = 'cashier' AND account_source = 'cashiers' AND user_id COLLATE utf8mb4_general_ci = OLD.cashier_id COLLATE utf8mb4_general_ci; DELETE FROM authenticator_management_events WHERE role = 'cashier' AND account_source = 'cashiers' AND user_id COLLATE utf8mb4_general_ci = OLD.cashier_id COLLATE utf8mb4_general_ci; END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_cashiers_auth_management_identity_update` AFTER UPDATE ON `cashiers` FOR EACH ROW BEGIN IF NOT (OLD.cashier_id <=> NEW.cashier_id) THEN DELETE FROM password_change_authenticators WHERE role = 'cashier' AND account_source = 'cashiers' AND user_id COLLATE utf8mb4_general_ci = OLD.cashier_id COLLATE utf8mb4_general_ci; DELETE FROM authenticator_management_challenges WHERE role = 'cashier' AND account_source = 'cashiers' AND user_id COLLATE utf8mb4_general_ci = OLD.cashier_id COLLATE utf8mb4_general_ci; DELETE FROM authenticator_management_events WHERE role = 'cashier' AND account_source = 'cashiers' AND user_id COLLATE utf8mb4_general_ci = OLD.cashier_id COLLATE utf8mb4_general_ci; END IF; END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_cashiers_login_otp_delete` AFTER DELETE ON `cashiers` FOR EACH ROW BEGIN
    DELETE FROM login_otp_challenges
    WHERE account_source = 'cashiers'
      AND BINARY user_id = BINARY OLD.cashier_id;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_cashiers_login_otp_identity_update` AFTER UPDATE ON `cashiers` FOR EACH ROW BEGIN
    IF NOT (OLD.cashier_id <=> NEW.cashier_id) THEN
        DELETE FROM login_otp_challenges
        WHERE account_source = 'cashiers'
          AND BINARY user_id = BINARY OLD.cashier_id;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_cashiers_password_history` BEFORE UPDATE ON `cashiers` FOR EACH ROW BEGIN
    IF NOT (OLD.password <=> NEW.password) THEN
        IF OLD.password REGEXP '^$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                'cashier', 'cashiers', OLD.cashier_id, OLD.password,
                SHA2(CONCAT('cashier', CHAR(0), 'cashiers', CHAR(0), OLD.cashier_id, CHAR(0), OLD.password), 256)
            );
        END IF;
        IF NEW.password REGEXP '^$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                'cashier', 'cashiers', NEW.cashier_id, NEW.password,
                SHA2(CONCAT('cashier', CHAR(0), 'cashiers', CHAR(0), NEW.cashier_id, CHAR(0), NEW.password), 256)
            );
        END IF;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_cashiers_security_cleanup` AFTER DELETE ON `cashiers` FOR EACH ROW BEGIN DELETE FROM account_verified_emails WHERE role = 'cashier' AND account_source = 'cashiers' AND user_id COLLATE utf8mb4_general_ci = OLD.cashier_id COLLATE utf8mb4_general_ci; DELETE FROM email_verification_challenges WHERE role = 'cashier' AND account_source = 'cashiers' AND user_id COLLATE utf8mb4_general_ci = OLD.cashier_id COLLATE utf8mb4_general_ci; DELETE FROM password_change_authenticators WHERE role = 'cashier' AND account_source = 'cashiers' AND user_id COLLATE utf8mb4_general_ci = OLD.cashier_id COLLATE utf8mb4_general_ci; DELETE FROM password_change_challenges WHERE role = 'cashier' AND account_source = 'cashiers' AND user_id COLLATE utf8mb4_general_ci = OLD.cashier_id COLLATE utf8mb4_general_ci; END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `email_verification_challenges`
--

CREATE TABLE `email_verification_challenges` (
  `challenge_id` bigint(20) UNSIGNED NOT NULL,
  `challenge_token_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `account_fingerprint` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `stage` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `proposed_email_encrypted` text CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `proposed_email_masked` varchar(254) NOT NULL,
  `proposed_email_fingerprint` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `prior_email_fingerprint` char(64) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `otp_destination_encrypted` text CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `otp_destination_masked` varchar(254) NOT NULL,
  `otp_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `otp_expires_at` datetime(6) NOT NULL,
  `failed_attempts` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `resend_count` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `last_sent_at` datetime(6) NOT NULL,
  `expires_at` datetime(6) NOT NULL,
  `request_ip_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `status` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'pending',
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `verified_at` datetime(6) DEFAULT NULL,
  `updated_at` datetime(6) NOT NULL DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `email_verification_rate_limits`
--

CREATE TABLE `email_verification_rate_limits` (
  `scope` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `scope_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `window_started_at` datetime(6) NOT NULL,
  `request_count` smallint(5) UNSIGNED NOT NULL,
  `updated_at` datetime(6) NOT NULL DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `login_otp_challenges`
--

CREATE TABLE `login_otp_challenges` (
  `challenge_id` bigint(20) UNSIGNED NOT NULL,
  `challenge_token_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `method` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_fingerprint` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `device_id_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `request_ip_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `otp_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `otp_expires_at` datetime(6) DEFAULT NULL,
  `destination_masked` varchar(254) DEFAULT NULL,
  `failed_attempts` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `resend_count` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `last_sent_at` datetime(6) DEFAULT NULL,
  `expires_at` datetime(6) NOT NULL,
  `status` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'pending',
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `verified_at` datetime(6) DEFAULT NULL,
  `updated_at` datetime(6) NOT NULL DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `parents`
--

CREATE TABLE `parents` (
  `parent_id` varchar(20) NOT NULL,
  `Fname` varchar(100) NOT NULL,
  `first_name` varchar(50) NOT NULL,
  `middle_name` varchar(50) DEFAULT NULL,
  `last_name` varchar(50) NOT NULL,
  `suffix` varchar(10) DEFAULT NULL,
  `Password` varchar(255) NOT NULL,
  `pin` varchar(255) DEFAULT NULL,
  `email` varchar(100) DEFAULT NULL,
  `linked_student_num` varchar(20) DEFAULT NULL,
  `profile_photo` varchar(255) DEFAULT NULL,
  `password_changed` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Triggers `parents`
--
DELIMITER $$
CREATE TRIGGER `edupocket_parents_auth_management_delete` AFTER DELETE ON `parents` FOR EACH ROW BEGIN DELETE FROM password_change_authenticators WHERE role = 'parent' AND account_source = 'parents' AND user_id COLLATE utf8mb4_general_ci = OLD.parent_id COLLATE utf8mb4_general_ci; DELETE FROM authenticator_management_challenges WHERE role = 'parent' AND account_source = 'parents' AND user_id COLLATE utf8mb4_general_ci = OLD.parent_id COLLATE utf8mb4_general_ci; DELETE FROM authenticator_management_events WHERE role = 'parent' AND account_source = 'parents' AND user_id COLLATE utf8mb4_general_ci = OLD.parent_id COLLATE utf8mb4_general_ci; END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_parents_auth_management_identity_update` AFTER UPDATE ON `parents` FOR EACH ROW BEGIN IF NOT (OLD.parent_id <=> NEW.parent_id) THEN DELETE FROM password_change_authenticators WHERE role = 'parent' AND account_source = 'parents' AND user_id COLLATE utf8mb4_general_ci = OLD.parent_id COLLATE utf8mb4_general_ci; DELETE FROM authenticator_management_challenges WHERE role = 'parent' AND account_source = 'parents' AND user_id COLLATE utf8mb4_general_ci = OLD.parent_id COLLATE utf8mb4_general_ci; DELETE FROM authenticator_management_events WHERE role = 'parent' AND account_source = 'parents' AND user_id COLLATE utf8mb4_general_ci = OLD.parent_id COLLATE utf8mb4_general_ci; END IF; END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_parents_login_otp_delete` AFTER DELETE ON `parents` FOR EACH ROW BEGIN
    DELETE FROM login_otp_challenges
    WHERE account_source = 'parents'
      AND BINARY user_id = BINARY OLD.parent_id;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_parents_login_otp_identity_update` AFTER UPDATE ON `parents` FOR EACH ROW BEGIN
    IF NOT (OLD.parent_id <=> NEW.parent_id) THEN
        DELETE FROM login_otp_challenges
        WHERE account_source = 'parents'
          AND BINARY user_id = BINARY OLD.parent_id;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_parents_password_history` BEFORE UPDATE ON `parents` FOR EACH ROW BEGIN
    IF NOT (OLD.Password <=> NEW.Password) THEN
        IF OLD.Password REGEXP '^$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                'parent', 'parents', OLD.parent_id, OLD.Password,
                SHA2(CONCAT('parent', CHAR(0), 'parents', CHAR(0), OLD.parent_id, CHAR(0), OLD.Password), 256)
            );
        END IF;
        IF NEW.Password REGEXP '^$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                'parent', 'parents', NEW.parent_id, NEW.Password,
                SHA2(CONCAT('parent', CHAR(0), 'parents', CHAR(0), NEW.parent_id, CHAR(0), NEW.Password), 256)
            );
        END IF;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_parents_security_cleanup` AFTER DELETE ON `parents` FOR EACH ROW BEGIN DELETE FROM account_verified_emails WHERE role = 'parent' AND account_source = 'parents' AND user_id COLLATE utf8mb4_general_ci = OLD.parent_id COLLATE utf8mb4_general_ci; DELETE FROM email_verification_challenges WHERE role = 'parent' AND account_source = 'parents' AND user_id COLLATE utf8mb4_general_ci = OLD.parent_id COLLATE utf8mb4_general_ci; DELETE FROM password_change_authenticators WHERE role = 'parent' AND account_source = 'parents' AND user_id COLLATE utf8mb4_general_ci = OLD.parent_id COLLATE utf8mb4_general_ci; DELETE FROM password_change_challenges WHERE role = 'parent' AND account_source = 'parents' AND user_id COLLATE utf8mb4_general_ci = OLD.parent_id COLLATE utf8mb4_general_ci; END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `parent_student_link`
--

CREATE TABLE `parent_student_link` (
  `id` int(11) NOT NULL,
  `parent_id` varchar(20) NOT NULL,
  `student_num` varchar(20) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `password_change_authenticators`
--

CREATE TABLE `password_change_authenticators` (
  `role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `totp_secret_encrypted` text CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `enrolled_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `last_verified_at` datetime(6) DEFAULT NULL,
  `last_used_step` bigint(20) UNSIGNED DEFAULT NULL,
  `updated_at` datetime(6) NOT NULL DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `password_change_challenges`
--

CREATE TABLE `password_change_challenges` (
  `challenge_id` bigint(20) UNSIGNED NOT NULL,
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
  `failed_attempts` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `resend_count` tinyint(3) UNSIGNED NOT NULL DEFAULT 0,
  `last_sent_at` datetime(6) DEFAULT NULL,
  `expires_at` datetime(6) NOT NULL,
  `status` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'pending',
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `verified_at` datetime(6) DEFAULT NULL,
  `updated_at` datetime(6) NOT NULL DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `password_history`
--

CREATE TABLE `password_history` (
  `history_id` bigint(20) UNSIGNED NOT NULL,
  `role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `user_id` varchar(191) NOT NULL,
  `password_hash` varchar(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `password_fingerprint` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `recorded_at` datetime(6) NOT NULL DEFAULT current_timestamp(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `pending_payments`
--

CREATE TABLE `pending_payments` (
  `id` int(11) NOT NULL,
  `checkout_id` varchar(100) DEFAULT NULL,
  `callback_token_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `parent_id` varchar(50) DEFAULT NULL,
  `student_num` varchar(50) DEFAULT NULL,
  `amount` decimal(10,2) DEFAULT NULL,
  `method` varchar(50) DEFAULT NULL,
  `status` varchar(20) NOT NULL DEFAULT 'pending',
  `transaction_id` int(11) DEFAULT NULL,
  `provider_payment_id` varchar(100) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `completed_at` datetime(6) DEFAULT NULL,
  `created_at` timestamp NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `pos_carts`
--

CREATE TABLE `pos_carts` (
  `cart_id` int(11) NOT NULL,
  `canteen_id` varchar(20) NOT NULL,
  `cashier_id` varchar(20) NOT NULL,
  `status` enum('open','checked_out') NOT NULL DEFAULT 'open',
  `created_at` datetime NOT NULL DEFAULT current_timestamp(),
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `pos_cart_items`
--

CREATE TABLE `pos_cart_items` (
  `cart_item_id` int(11) NOT NULL,
  `cart_id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL,
  `quantity` int(11) NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `notes` varchar(255) DEFAULT NULL,
  `updated_at` datetime NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `products`
--

CREATE TABLE `products` (
  `product_id` int(11) NOT NULL,
  `canteen_id` varchar(20) DEFAULT NULL,
  `name` varchar(100) NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `stock_qty` int(11) NOT NULL DEFAULT 0,
  `category` varchar(50) NOT NULL DEFAULT 'Uncategorized',
  `is_active` tinyint(1) NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `receipt_print_tokens`
--

CREATE TABLE `receipt_print_tokens` (
  `token_id` bigint(20) UNSIGNED NOT NULL,
  `token_hash` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `transaction_id` int(11) NOT NULL,
  `session_id` bigint(20) UNSIGNED DEFAULT NULL,
  `viewer_role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `viewer_account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `viewer_user_id` varchar(191) NOT NULL,
  `authorization_context` varchar(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `issued_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `expires_at` datetime(6) NOT NULL,
  `consumed_at` datetime(6) DEFAULT NULL,
  `revoked_at` datetime(6) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `students`
--

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
  `failed_attempts` int(11) NOT NULL DEFAULT 0,
  `is_locked` tinyint(1) NOT NULL DEFAULT 0,
  `is_frozen` tinyint(1) NOT NULL DEFAULT 0,
  `password_changed` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Triggers `students`
--
DELIMITER $$
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_students_auth_management_delete`
AFTER DELETE ON `students`
FOR EACH ROW
BEGIN
    DELETE FROM password_change_authenticators
    WHERE role = 'student'
      AND account_source = 'students'
      AND user_id COLLATE utf8mb4_general_ci =
          OLD.student_num COLLATE utf8mb4_general_ci;

    DELETE FROM authenticator_management_challenges
    WHERE role = 'student'
      AND account_source = 'students'
      AND user_id COLLATE utf8mb4_general_ci =
          OLD.student_num COLLATE utf8mb4_general_ci;

    DELETE FROM authenticator_management_events
    WHERE role = 'student'
      AND account_source = 'students'
      AND user_id COLLATE utf8mb4_general_ci =
          OLD.student_num COLLATE utf8mb4_general_ci;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_students_login_otp_delete`
AFTER DELETE ON `students`
FOR EACH ROW
BEGIN
    DELETE FROM login_otp_challenges
    WHERE account_source = 'students'
      AND BINARY user_id = BINARY OLD.student_num;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_students_login_otp_identity_update` AFTER UPDATE ON `students` FOR EACH ROW BEGIN
    IF NOT (OLD.student_num <=> NEW.student_num) THEN
        DELETE FROM login_otp_challenges
        WHERE account_source = 'students'
          AND BINARY user_id = BINARY OLD.student_num;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_students_password_history` BEFORE UPDATE ON `students` FOR EACH ROW BEGIN
    IF NOT (OLD.Password <=> NEW.Password) THEN
        IF OLD.Password REGEXP '^$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                'student', 'students', OLD.student_num, OLD.Password,
                SHA2(CONCAT('student', CHAR(0), 'students', CHAR(0), OLD.student_num, CHAR(0), OLD.Password), 256)
            );
        END IF;
        IF NEW.Password REGEXP '^$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                'student', 'students', NEW.student_num, NEW.Password,
                SHA2(CONCAT('student', CHAR(0), 'students', CHAR(0), NEW.student_num, CHAR(0), NEW.Password), 256)
            );
        END IF;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `edupocket_students_security_cleanup`
AFTER DELETE ON `students`
FOR EACH ROW
BEGIN
    DELETE FROM account_verified_emails
    WHERE role = 'student'
      AND account_source = 'students'
      AND user_id COLLATE utf8mb4_general_ci =
          OLD.student_num COLLATE utf8mb4_general_ci;

    DELETE FROM email_verification_challenges
    WHERE role = 'student' 
      AND account_source = 'students'
      AND user_id COLLATE utf8mb4_general_ci =
          OLD.student_num COLLATE utf8mb4_general_ci;

    DELETE FROM password_change_authenticators
    WHERE role = 'student'
      AND account_source = 'students'
      AND user_id COLLATE utf8mb4_general_ci =
          OLD.student_num COLLATE utf8mb4_general_ci;

    DELETE FROM password_change_challenges
    WHERE role = 'student'
      AND account_source = 'students'
      AND user_id COLLATE utf8mb4_general_ci =
          OLD.student_num COLLATE utf8mb4_general_ci;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `student_transfers`
--

CREATE TABLE `student_transfers` (
  `transfer_id` bigint(20) UNSIGNED NOT NULL,
  `client_request_id` char(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `request_fingerprint` char(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `sender_student_num` varchar(20) NOT NULL,
  `recipient_student_num` varchar(20) NOT NULL,
  `sender_name_snapshot` varchar(191) NOT NULL,
  `recipient_name_snapshot` varchar(191) NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `currency` char(3) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'PHP',
  `status` enum('pending','completed') NOT NULL DEFAULT 'pending',
  `sender_transaction_id` int(11) DEFAULT NULL,
  `recipient_transaction_id` int(11) DEFAULT NULL,
  `sender_balance_after` decimal(10,2) DEFAULT NULL,
  `recipient_balance_after` decimal(10,2) DEFAULT NULL,
  `session_id` bigint(20) UNSIGNED DEFAULT NULL,
  `created_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `completed_at` datetime(6) DEFAULT NULL,
  `updated_at` datetime(6) NOT NULL DEFAULT current_timestamp(6) ON UPDATE current_timestamp(6)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- --------------------------------------------------------

--
-- Table structure for table `topups`
--

CREATE TABLE `topups` (
  `topup_id` int(11) NOT NULL,
  `transaction_id` int(11) DEFAULT NULL,
  `parent_id` varchar(20) DEFAULT NULL,
  `student_num` varchar(20) NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `method` enum('Bank','GCash','Maya','Over-the-counter') NOT NULL,
  `status` enum('Pending','Completed') NOT NULL DEFAULT 'Pending',
  `date_time` datetime NOT NULL DEFAULT current_timestamp()
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `transactions`
--

CREATE TABLE `transactions` (
  `transaction_id` int(11) NOT NULL,
  `student_num` varchar(20) NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `transaction_type` enum('payment','top-up','transfer-out','transfer-in') NOT NULL,
  `description` varchar(255) DEFAULT NULL,
  `date_time` datetime NOT NULL DEFAULT current_timestamp(),
  `date_created` datetime NOT NULL DEFAULT current_timestamp(),
  `canteen_id` varchar(20) DEFAULT NULL,
  `cashier_id` varchar(20) DEFAULT NULL,
  `processor_role` varchar(20) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `processor_account_source` varchar(32) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `processor_id` varchar(191) DEFAULT NULL,
  `bill_payment_id` int(11) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Triggers `transactions`
--
DELIMITER $$
CREATE TRIGGER `edupocket_transaction_artifacts` AFTER INSERT ON `transactions` FOR EACH ROW BEGIN
    DECLARE notification_title VARCHAR(120);
    DECLARE notification_body VARCHAR(500);
    DECLARE receipt_student_name VARCHAR(191);
    DECLARE receipt_processor_role VARCHAR(20);
    DECLARE receipt_processor_account_source VARCHAR(32);
    DECLARE receipt_processor_id VARCHAR(191);
    DECLARE receipt_processor_name VARCHAR(191);
    DECLARE receipt_cashier_matches INT DEFAULT 0;
    DECLARE receipt_admin_cashier_matches INT DEFAULT 0;

    SET notification_title = CASE
        WHEN NEW.transaction_type = 'top-up' THEN 'Wallet top-up completed'
        WHEN NEW.transaction_type = 'transfer-out' THEN 'Fund transfer sent'
        WHEN NEW.transaction_type = 'transfer-in' THEN 'Fund transfer received'
        ELSE 'Payment completed'
    END;
    SET notification_body = CONCAT(
        'PHP ',
        FORMAT(NEW.amount, 2),
        CASE
            WHEN NEW.transaction_type = 'top-up'
                THEN ' was added to the student wallet.'
            WHEN NEW.transaction_type = 'transfer-out'
                THEN ' was transferred from the student wallet.'
            WHEN NEW.transaction_type = 'transfer-in'
                THEN ' was received in the student wallet.'
            ELSE CONCAT(
                ' was paid for ',
                COALESCE(NULLIF(NEW.description, ''), 'a purchase'),
                '.'
            )
        END
    );

    SELECT COALESCE(NULLIF(TRIM(MAX(s.Fname)), ''), NEW.student_num)
      INTO receipt_student_name
    FROM students s
    WHERE s.student_num = NEW.student_num;

    SET receipt_processor_role = LOWER(NULLIF(TRIM(NEW.processor_role), ''));
    SET receipt_processor_account_source = LOWER(
        NULLIF(TRIM(NEW.processor_account_source), '')
    );
    SET receipt_processor_id = NULLIF(TRIM(NEW.processor_id), '');

    IF receipt_processor_role IS NULL
       OR receipt_processor_account_source IS NULL
       OR receipt_processor_id IS NULL THEN
        IF NULLIF(TRIM(NEW.canteen_id), '') IS NOT NULL THEN
            SET receipt_processor_role = 'canteen';
            SET receipt_processor_account_source = 'canteens';
            SET receipt_processor_id = NEW.canteen_id;
        ELSEIF NULLIF(TRIM(NEW.cashier_id), '') IS NOT NULL THEN
            SET receipt_processor_role = 'cashier';
            SET receipt_processor_id = NEW.cashier_id;
            SELECT COUNT(*) INTO receipt_cashier_matches
            FROM cashiers c
            WHERE BINARY c.cashier_id = BINARY NEW.cashier_id;
            SELECT COUNT(*) INTO receipt_admin_cashier_matches
            FROM admins a
            WHERE BINARY a.admin_id = BINARY NEW.cashier_id
              AND LOWER(COALESCE(a.role, '')) = 'cashier';
            SET receipt_processor_account_source = CASE
                WHEN receipt_cashier_matches = 1
                 AND receipt_admin_cashier_matches = 0 THEN 'cashiers'
                WHEN receipt_cashier_matches = 0
                 AND receipt_admin_cashier_matches = 1 THEN 'admins'
                ELSE NULL
            END;
        END IF;
    END IF;

    SET receipt_processor_name = CASE
        WHEN receipt_processor_role = 'student'
         AND receipt_processor_account_source = 'students' THEN (
            SELECT NULLIF(TRIM(s.Fname), '')
            FROM students s
            WHERE BINARY s.student_num = BINARY receipt_processor_id
            LIMIT 1
        )
        WHEN receipt_processor_role = 'parent'
         AND receipt_processor_account_source = 'parents' THEN (
            SELECT NULLIF(TRIM(p.Fname), '')
            FROM parents p
            WHERE BINARY p.parent_id = BINARY receipt_processor_id
            LIMIT 1
        )
        WHEN receipt_processor_role = 'canteen'
         AND receipt_processor_account_source = 'canteens' THEN (
            SELECT NULLIF(TRIM(c.Fname), '')
            FROM canteens c
            WHERE BINARY c.canteen_id = BINARY receipt_processor_id
            LIMIT 1
        )
        WHEN receipt_processor_role = 'cashier'
         AND receipt_processor_account_source = 'cashiers' THEN (
                SELECT NULLIF(TRIM(c.Fname), '')
                FROM cashiers c
                WHERE BINARY c.cashier_id = BINARY receipt_processor_id
                LIMIT 1
        )
        WHEN receipt_processor_role = 'cashier'
         AND receipt_processor_account_source = 'admins' THEN (
                SELECT NULLIF(TRIM(a.Fname), '')
                FROM admins a
                WHERE BINARY a.admin_id = BINARY receipt_processor_id
                  AND LOWER(COALESCE(a.role, '')) = 'cashier'
                LIMIT 1
        )
        ELSE NULL
    END;

    INSERT IGNORE INTO transaction_receipts
        (transaction_id, receipt_number, issued_at, transaction_type,
         description_snapshot, student_num_snapshot, student_name_snapshot,
         canteen_id_snapshot, canteen_name_snapshot, cashier_id_snapshot,
         cashier_name_snapshot, processor_role_snapshot,
         processor_account_source_snapshot, processor_id_snapshot,
         processor_name_snapshot, total_amount, legacy_backfilled)
    SELECT
        NEW.transaction_id,
        CONCAT(
            'EP-',
            DATE_FORMAT(COALESCE(NEW.date_time, NEW.date_created, NOW()), '%Y%m%d'),
            '-',
            LPAD(NEW.transaction_id, 8, '0')
        ),
        COALESCE(NEW.date_time, NEW.date_created, NOW()),
        NEW.transaction_type,
        NEW.description,
        NEW.student_num,
        receipt_student_name,
        NEW.canteen_id,
        c.Fname,
        NEW.cashier_id,
        COALESCE(ch.Fname, a.Fname),
        receipt_processor_role,
        receipt_processor_account_source,
        receipt_processor_id,
        receipt_processor_name,
        NEW.amount,
        0
    FROM (SELECT 1) seed
    LEFT JOIN canteens c ON c.canteen_id = NEW.canteen_id
    LEFT JOIN cashiers ch ON ch.cashier_id = NEW.cashier_id
    LEFT JOIN admins a ON a.admin_id = NEW.cashier_id
        AND LOWER(COALESCE(a.role, '')) = 'cashier';

    INSERT IGNORE INTO account_notifications
        (recipient_role, account_source, user_id, transaction_id, title, body)
    VALUES
        ('student', 'students', NEW.student_num, NEW.transaction_id,
         notification_title, notification_body);

    INSERT IGNORE INTO account_notifications
        (recipient_role, account_source, user_id, transaction_id, title, body)
    SELECT 'parent', 'parents', linked.parent_id, NEW.transaction_id,
           notification_title, notification_body
    FROM (
        SELECT psl.parent_id
        FROM parent_student_link psl
        WHERE psl.student_num = NEW.student_num
        UNION
        SELECT p.parent_id
        FROM parents p
        WHERE p.linked_student_num = NEW.student_num
    ) linked;

    IF NEW.canteen_id IS NOT NULL AND TRIM(NEW.canteen_id) <> '' THEN
        INSERT IGNORE INTO account_notifications
            (recipient_role, account_source, user_id, transaction_id, title, body)
        VALUES
            ('canteen', 'canteens', NEW.canteen_id, NEW.transaction_id,
             notification_title, notification_body);
    END IF;

    IF NEW.cashier_id IS NOT NULL AND TRIM(NEW.cashier_id) <> '' THEN
        INSERT IGNORE INTO account_notifications
            (recipient_role, account_source, user_id, transaction_id, title, body)
        SELECT 'cashier', 'cashiers', c.cashier_id, NEW.transaction_id,
               notification_title, notification_body
        FROM cashiers c
        WHERE c.cashier_id = NEW.cashier_id;

        INSERT IGNORE INTO account_notifications
            (recipient_role, account_source, user_id, transaction_id, title, body)
        SELECT 'cashier', 'admins', a.admin_id, NEW.transaction_id,
               notification_title, notification_body
        FROM admins a
        WHERE a.admin_id = NEW.cashier_id
          AND LOWER(COALESCE(a.role, '')) = 'cashier';
    END IF;

    INSERT IGNORE INTO account_notifications
        (recipient_role, account_source, user_id, transaction_id, title, body)
    SELECT 'admin', 'admins', a.admin_id, NEW.transaction_id,
           notification_title, notification_body
    FROM admins a
    WHERE LOWER(COALESCE(a.role, '')) <> 'cashier';
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `transaction_items`
--

CREATE TABLE `transaction_items` (
  `id` int(11) NOT NULL,
  `transaction_id` int(11) NOT NULL,
  `product_id` int(11) NOT NULL,
  `item_name` varchar(191) DEFAULT NULL,
  `quantity` int(11) NOT NULL,
  `price` decimal(10,2) NOT NULL,
  `notes` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

-- --------------------------------------------------------

--
-- Table structure for table `transaction_receipts`
--

CREATE TABLE `transaction_receipts` (
  `receipt_id` bigint(20) UNSIGNED NOT NULL,
  `transaction_id` int(11) NOT NULL,
  `receipt_number` varchar(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
  `issued_at` datetime(6) NOT NULL DEFAULT current_timestamp(6),
  `status` varchar(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'issued',
  `currency` char(3) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'PHP',
  `transaction_type` varchar(20) NOT NULL,
  `description_snapshot` varchar(255) DEFAULT NULL,
  `student_num_snapshot` varchar(20) NOT NULL,
  `student_name_snapshot` varchar(191) NOT NULL,
  `canteen_id_snapshot` varchar(20) DEFAULT NULL,
  `canteen_name_snapshot` varchar(191) DEFAULT NULL,
  `cashier_id_snapshot` varchar(20) DEFAULT NULL,
  `cashier_name_snapshot` varchar(191) DEFAULT NULL,
  `processor_role_snapshot` varchar(20) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `processor_account_source_snapshot` varchar(32) CHARACTER SET ascii COLLATE ascii_bin DEFAULT NULL,
  `processor_id_snapshot` varchar(191) DEFAULT NULL,
  `processor_name_snapshot` varchar(191) DEFAULT NULL,
  `total_amount` decimal(10,2) NOT NULL,
  `legacy_backfilled` tinyint(1) NOT NULL DEFAULT 0
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `account_notifications`
--
ALTER TABLE `account_notifications`
  ADD PRIMARY KEY (`notification_id`),
  ADD UNIQUE KEY `uq_account_notification_transaction` (`recipient_role`,`account_source`,`user_id`,`transaction_id`),
  ADD KEY `ix_account_notification_delivery` (`recipient_role`,`user_id`,`notification_id`),
  ADD KEY `fk_account_notification_transaction` (`transaction_id`);

--
-- Indexes for table `account_verified_emails`
--
ALTER TABLE `account_verified_emails`
  ADD PRIMARY KEY (`role`,`account_source`,`user_id`),
  ADD KEY `ix_account_verified_email_fingerprint` (`email_fingerprint`);

--
-- Indexes for table `active_sessions`
--
ALTER TABLE `active_sessions`
  ADD PRIMARY KEY (`session_id`),
  ADD UNIQUE KEY `uq_active_sessions_user` (`user_id`,`user_role`),
  ADD UNIQUE KEY `uq_active_sessions_token` (`session_token`);

--
-- Indexes for table `admins`
--
ALTER TABLE `admins`
  ADD PRIMARY KEY (`admin_id`),
  ADD UNIQUE KEY `uq_admins_username` (`username`),
  ADD KEY `idx_admins_canteen_id` (`canteen_id`);

--
-- Indexes for table `app_activity_events`
--
ALTER TABLE `app_activity_events`
  ADD PRIMARY KEY (`event_id`),
  ADD KEY `ix_app_activity_account` (`role`,`account_source`,`user_id`,`created_at`),
  ADD KEY `ix_app_activity_session` (`session_id`,`created_at`),
  ADD KEY `ix_app_activity_event` (`event_name`,`created_at`);

--
-- Indexes for table `app_sessions`
--
ALTER TABLE `app_sessions`
  ADD PRIMARY KEY (`session_id`),
  ADD UNIQUE KEY `uq_app_session_token_hash` (`token_hash`),
  ADD KEY `ix_app_session_account` (`role`,`account_source`,`user_id`,`issued_at`),
  ADD KEY `ix_app_session_expiry` (`revoked_at`,`expires_at`),
  ADD KEY `ix_app_session_replacement` (`replaced_by_session_id`);

--
-- Indexes for table `app_session_accounts`
--
ALTER TABLE `app_session_accounts`
  ADD PRIMARY KEY (`role`,`account_source`,`user_id`),
  ADD UNIQUE KEY `uq_app_session_account_current` (`current_session_id`);

--
-- Indexes for table `app_settings`
--
ALTER TABLE `app_settings`
  ADD PRIMARY KEY (`setting_id`),
  ADD UNIQUE KEY `uq_app_settings_key` (`setting_key`);

--
-- Indexes for table `authenticator_management_challenges`
--
ALTER TABLE `authenticator_management_challenges`
  ADD PRIMARY KEY (`challenge_id`),
  ADD UNIQUE KEY `uq_auth_management_challenge_token` (`challenge_token_hash`),
  ADD KEY `ix_auth_management_challenge_account` (`role`,`account_source`,`user_id`,`status`),
  ADD KEY `ix_auth_management_challenge_expiry` (`status`,`expires_at`),
  ADD KEY `ix_auth_management_challenge_ip` (`request_ip_hash`,`created_at`);

--
-- Indexes for table `authenticator_management_events`
--
ALTER TABLE `authenticator_management_events`
  ADD PRIMARY KEY (`event_id`),
  ADD UNIQUE KEY `uq_auth_management_event_challenge` (`challenge_id`),
  ADD KEY `ix_auth_management_event_account` (`role`,`account_source`,`user_id`,`created_at`);

--
-- Indexes for table `authenticator_management_rate_limits`
--
ALTER TABLE `authenticator_management_rate_limits`
  ADD PRIMARY KEY (`scope`,`scope_hash`);

--
-- Indexes for table `backend_audit_log`
--
ALTER TABLE `backend_audit_log`
  ADD PRIMARY KEY (`audit_id`),
  ADD UNIQUE KEY `uq_backend_audit_request` (`request_id`),
  ADD KEY `ix_backend_audit_account` (`role`,`account_source`,`user_id`,`created_at`),
  ADD KEY `ix_backend_audit_session` (`session_id`,`created_at`),
  ADD KEY `ix_backend_audit_route` (`route`,`created_at`),
  ADD KEY `ix_backend_audit_outcome` (`outcome`,`response_status`,`created_at`),
  ADD KEY `ix_backend_audit_created` (`created_at`);

--
-- Indexes for table `bill_payments`
--
ALTER TABLE `bill_payments`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_bill_payments_cashier_id` (`cashier_id`);

--
-- Indexes for table `canteens`
--
ALTER TABLE `canteens`
  ADD PRIMARY KEY (`canteen_id`);

--
-- Indexes for table `cashiers`
--
ALTER TABLE `cashiers`
  ADD PRIMARY KEY (`cashier_id`),
  ADD UNIQUE KEY `uq_cashiers_username` (`username`),
  ADD KEY `idx_cashiers_canteen_id` (`canteen_id`);

--
-- Indexes for table `email_verification_challenges`
--
ALTER TABLE `email_verification_challenges`
  ADD PRIMARY KEY (`challenge_id`),
  ADD UNIQUE KEY `uq_email_verification_challenge_token` (`challenge_token_hash`),
  ADD KEY `ix_email_verification_account_history` (`role`,`account_source`,`user_id`,`created_at`),
  ADD KEY `ix_email_verification_pending` (`role`,`account_source`,`user_id`,`status`),
  ADD KEY `ix_email_verification_expiry` (`status`,`expires_at`),
  ADD KEY `ix_email_verification_ip_history` (`request_ip_hash`,`created_at`);

--
-- Indexes for table `email_verification_rate_limits`
--
ALTER TABLE `email_verification_rate_limits`
  ADD PRIMARY KEY (`scope`,`scope_hash`);

--
-- Indexes for table `login_otp_challenges`
--
ALTER TABLE `login_otp_challenges`
  ADD PRIMARY KEY (`challenge_id`),
  ADD UNIQUE KEY `uq_login_otp_token` (`challenge_token_hash`),
  ADD KEY `ix_login_otp_account` (`role`,`account_source`,`user_id`,`status`),
  ADD KEY `ix_login_otp_account_created` (`role`,`account_source`,`user_id`,`created_at`),
  ADD KEY `ix_login_otp_ip_created` (`request_ip_hash`,`created_at`),
  ADD KEY `ix_login_otp_expiry` (`status`,`expires_at`);

--
-- Indexes for table `parents`
--
ALTER TABLE `parents`
  ADD PRIMARY KEY (`parent_id`),
  ADD KEY `idx_parents_linked_student` (`linked_student_num`);

--
-- Indexes for table `parent_student_link`
--
ALTER TABLE `parent_student_link`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_parent_student` (`parent_id`,`student_num`),
  ADD KEY `idx_link_student_num` (`student_num`);

--
-- Indexes for table `password_change_authenticators`
--
ALTER TABLE `password_change_authenticators`
  ADD PRIMARY KEY (`role`,`account_source`,`user_id`);

--
-- Indexes for table `password_change_challenges`
--
ALTER TABLE `password_change_challenges`
  ADD PRIMARY KEY (`challenge_id`),
  ADD UNIQUE KEY `uq_password_change_challenge_token` (`challenge_token_hash`),
  ADD KEY `ix_password_change_challenge_account` (`role`,`account_source`,`user_id`,`status`),
  ADD KEY `ix_password_change_challenge_expiry` (`status`,`expires_at`);

--
-- Indexes for table `password_history`
--
ALTER TABLE `password_history`
  ADD PRIMARY KEY (`history_id`),
  ADD UNIQUE KEY `uq_password_history_exact_credential` (`role`,`account_source`,`user_id`,`password_fingerprint`),
  ADD KEY `ix_password_history_account` (`role`,`account_source`,`user_id`,`recorded_at`);

--
-- Indexes for table `pending_payments`
--
ALTER TABLE `pending_payments`
  ADD PRIMARY KEY (`id`),
  ADD UNIQUE KEY `uq_pending_payments_checkout_id` (`checkout_id`),
  ADD UNIQUE KEY `uq_pending_payments_callback_token` (`callback_token_hash`),
  ADD UNIQUE KEY `uq_pending_payments_provider_payment` (`provider_payment_id`),
  ADD KEY `idx_pending_payments_parent_id` (`parent_id`),
  ADD KEY `idx_pending_payments_student_num` (`student_num`);

--
-- Indexes for table `pos_carts`
--
ALTER TABLE `pos_carts`
  ADD PRIMARY KEY (`cart_id`),
  ADD KEY `idx_pos_carts_canteen_id` (`canteen_id`),
  ADD KEY `idx_pos_carts_cashier_id` (`cashier_id`);

--
-- Indexes for table `pos_cart_items`
--
ALTER TABLE `pos_cart_items`
  ADD PRIMARY KEY (`cart_item_id`),
  ADD UNIQUE KEY `uq_pos_cart_product` (`cart_id`,`product_id`),
  ADD KEY `idx_pos_cart_items_product_id` (`product_id`);

--
-- Indexes for table `products`
--
ALTER TABLE `products`
  ADD PRIMARY KEY (`product_id`),
  ADD KEY `idx_products_canteen_id` (`canteen_id`),
  ADD KEY `ix_products_catalog` (`canteen_id`,`is_active`,`category`,`name`);

--
-- Indexes for table `receipt_print_tokens`
--
ALTER TABLE `receipt_print_tokens`
  ADD PRIMARY KEY (`token_id`),
  ADD UNIQUE KEY `uq_receipt_print_token_hash` (`token_hash`),
  ADD KEY `ix_receipt_print_token_expiry` (`expires_at`,`consumed_at`,`revoked_at`),
  ADD KEY `ix_receipt_print_token_transaction` (`transaction_id`,`issued_at`),
  ADD KEY `ix_receipt_print_token_session` (`session_id`,`issued_at`);

--
-- Indexes for table `students`
--
ALTER TABLE `students`
  ADD PRIMARY KEY (`student_num`),
  ADD UNIQUE KEY `uq_students_qr_code` (`qr_code`),
  ADD KEY `idx_students_parent_id` (`parent_id`);

--
-- Indexes for table `student_transfers`
--
ALTER TABLE `student_transfers`
  ADD PRIMARY KEY (`transfer_id`),
  ADD UNIQUE KEY `uq_student_transfer_request` (`sender_student_num`,`client_request_id`),
  ADD UNIQUE KEY `uq_student_transfer_sender_transaction` (`sender_transaction_id`),
  ADD UNIQUE KEY `uq_student_transfer_recipient_transaction` (`recipient_transaction_id`),
  ADD KEY `ix_student_transfer_sender` (`sender_student_num`,`created_at`),
  ADD KEY `ix_student_transfer_recipient` (`recipient_student_num`,`created_at`),
  ADD KEY `ix_student_transfer_status` (`status`,`created_at`),
  ADD KEY `ix_student_transfer_session` (`session_id`);

--
-- Indexes for table `topups`
--
ALTER TABLE `topups`
  ADD PRIMARY KEY (`topup_id`),
  ADD UNIQUE KEY `uq_topups_transaction` (`transaction_id`),
  ADD KEY `idx_topups_parent_id` (`parent_id`),
  ADD KEY `idx_topups_student_num` (`student_num`);

--
-- Indexes for table `transactions`
--
ALTER TABLE `transactions`
  ADD PRIMARY KEY (`transaction_id`),
  ADD KEY `idx_transactions_student_num` (`student_num`),
  ADD KEY `idx_transactions_canteen_id` (`canteen_id`),
  ADD KEY `idx_transactions_cashier_id` (`cashier_id`),
  ADD KEY `idx_transactions_bill_payment_id` (`bill_payment_id`),
  ADD KEY `ix_transactions_processor` (`processor_role`,`processor_id`),
  ADD KEY `ix_transactions_processor_source` (`processor_account_source`,`processor_id`);

--
-- Indexes for table `transaction_items`
--
ALTER TABLE `transaction_items`
  ADD PRIMARY KEY (`id`),
  ADD KEY `idx_transaction_items_transaction_id` (`transaction_id`),
  ADD KEY `idx_transaction_items_product_id` (`product_id`);

--
-- Indexes for table `transaction_receipts`
--
ALTER TABLE `transaction_receipts`
  ADD PRIMARY KEY (`receipt_id`),
  ADD UNIQUE KEY `uq_transaction_receipt_transaction` (`transaction_id`),
  ADD UNIQUE KEY `uq_transaction_receipt_number` (`receipt_number`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `account_notifications`
--
ALTER TABLE `account_notifications`
  MODIFY `notification_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `active_sessions`
--
ALTER TABLE `active_sessions`
  MODIFY `session_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `app_activity_events`
--
ALTER TABLE `app_activity_events`
  MODIFY `event_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `app_sessions`
--
ALTER TABLE `app_sessions`
  MODIFY `session_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `app_settings`
--
ALTER TABLE `app_settings`
  MODIFY `setting_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `authenticator_management_challenges`
--
ALTER TABLE `authenticator_management_challenges`
  MODIFY `challenge_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `authenticator_management_events`
--
ALTER TABLE `authenticator_management_events`
  MODIFY `event_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `backend_audit_log`
--
ALTER TABLE `backend_audit_log`
  MODIFY `audit_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `bill_payments`
--
ALTER TABLE `bill_payments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `email_verification_challenges`
--
ALTER TABLE `email_verification_challenges`
  MODIFY `challenge_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `login_otp_challenges`
--
ALTER TABLE `login_otp_challenges`
  MODIFY `challenge_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `parent_student_link`
--
ALTER TABLE `parent_student_link`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `password_change_challenges`
--
ALTER TABLE `password_change_challenges`
  MODIFY `challenge_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `password_history`
--
ALTER TABLE `password_history`
  MODIFY `history_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `pending_payments`
--
ALTER TABLE `pending_payments`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `pos_carts`
--
ALTER TABLE `pos_carts`
  MODIFY `cart_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `pos_cart_items`
--
ALTER TABLE `pos_cart_items`
  MODIFY `cart_item_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `products`
--
ALTER TABLE `products`
  MODIFY `product_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `receipt_print_tokens`
--
ALTER TABLE `receipt_print_tokens`
  MODIFY `token_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `student_transfers`
--
ALTER TABLE `student_transfers`
  MODIFY `transfer_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `topups`
--
ALTER TABLE `topups`
  MODIFY `topup_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `transactions`
--
ALTER TABLE `transactions`
  MODIFY `transaction_id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `transaction_items`
--
ALTER TABLE `transaction_items`
  MODIFY `id` int(11) NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `transaction_receipts`
--
ALTER TABLE `transaction_receipts`
  MODIFY `receipt_id` bigint(20) UNSIGNED NOT NULL AUTO_INCREMENT;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `account_notifications`
--
ALTER TABLE `account_notifications`
  ADD CONSTRAINT `fk_account_notification_transaction` FOREIGN KEY (`transaction_id`) REFERENCES `transactions` (`transaction_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `admins`
--
ALTER TABLE `admins`
  ADD CONSTRAINT `fk_admins_canteen` FOREIGN KEY (`canteen_id`) REFERENCES `canteens` (`canteen_id`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Constraints for table `app_activity_events`
--
ALTER TABLE `app_activity_events`
  ADD CONSTRAINT `fk_app_activity_session` FOREIGN KEY (`session_id`) REFERENCES `app_sessions` (`session_id`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Constraints for table `bill_payments`
--
ALTER TABLE `bill_payments`
  ADD CONSTRAINT `fk_bill_payments_cashier` FOREIGN KEY (`cashier_id`) REFERENCES `cashiers` (`cashier_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `cashiers`
--
ALTER TABLE `cashiers`
  ADD CONSTRAINT `fk_cashiers_canteen` FOREIGN KEY (`canteen_id`) REFERENCES `canteens` (`canteen_id`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Constraints for table `parents`
--
ALTER TABLE `parents`
  ADD CONSTRAINT `fk_parents_linked_student` FOREIGN KEY (`linked_student_num`) REFERENCES `students` (`student_num`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Constraints for table `parent_student_link`
--
ALTER TABLE `parent_student_link`
  ADD CONSTRAINT `fk_link_parent` FOREIGN KEY (`parent_id`) REFERENCES `parents` (`parent_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_link_student` FOREIGN KEY (`student_num`) REFERENCES `students` (`student_num`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `pos_carts`
--
ALTER TABLE `pos_carts`
  ADD CONSTRAINT `fk_pos_carts_canteen` FOREIGN KEY (`canteen_id`) REFERENCES `canteens` (`canteen_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `pos_cart_items`
--
ALTER TABLE `pos_cart_items`
  ADD CONSTRAINT `fk_pos_cart_items_cart` FOREIGN KEY (`cart_id`) REFERENCES `pos_carts` (`cart_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_pos_cart_items_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`) ON UPDATE CASCADE;

--
-- Constraints for table `products`
--
ALTER TABLE `products`
  ADD CONSTRAINT `fk_products_canteen` FOREIGN KEY (`canteen_id`) REFERENCES `canteens` (`canteen_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `receipt_print_tokens`
--
ALTER TABLE `receipt_print_tokens`
  ADD CONSTRAINT `fk_receipt_print_token_session` FOREIGN KEY (`session_id`) REFERENCES `app_sessions` (`session_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_receipt_print_token_transaction` FOREIGN KEY (`transaction_id`) REFERENCES `transactions` (`transaction_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `student_transfers`
--
ALTER TABLE `student_transfers`
  ADD CONSTRAINT `fk_student_transfer_recipient_transaction` FOREIGN KEY (`recipient_transaction_id`) REFERENCES `transactions` (`transaction_id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_student_transfer_sender_transaction` FOREIGN KEY (`sender_transaction_id`) REFERENCES `transactions` (`transaction_id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_student_transfer_session` FOREIGN KEY (`session_id`) REFERENCES `app_sessions` (`session_id`) ON DELETE SET NULL ON UPDATE CASCADE;

--
-- Constraints for table `topups`
--
ALTER TABLE `topups`
  ADD CONSTRAINT `fk_topups_parent` FOREIGN KEY (`parent_id`) REFERENCES `parents` (`parent_id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_topups_student` FOREIGN KEY (`student_num`) REFERENCES `students` (`student_num`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `transactions`
--
ALTER TABLE `transactions`
  ADD CONSTRAINT `fk_transactions_bill_payment` FOREIGN KEY (`bill_payment_id`) REFERENCES `bill_payments` (`id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_transactions_canteen` FOREIGN KEY (`canteen_id`) REFERENCES `canteens` (`canteen_id`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_transactions_student` FOREIGN KEY (`student_num`) REFERENCES `students` (`student_num`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `transaction_items`
--
ALTER TABLE `transaction_items`
  ADD CONSTRAINT `fk_transaction_items_product` FOREIGN KEY (`product_id`) REFERENCES `products` (`product_id`) ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_transaction_items_transaction` FOREIGN KEY (`transaction_id`) REFERENCES `transactions` (`transaction_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `transaction_receipts`
--
ALTER TABLE `transaction_receipts`
  ADD CONSTRAINT `fk_transaction_receipt_transaction` FOREIGN KEY (`transaction_id`) REFERENCES `transactions` (`transaction_id`) ON DELETE CASCADE ON UPDATE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;

ALTER TABLE canteens
ADD COLUMN password_changed TINYINT(1) NOT NULL DEFAULT 0;

ALTER TABLE cashiers
ADD COLUMN password_changed TINYINT(1) NOT NULL DEFAULT 0;
