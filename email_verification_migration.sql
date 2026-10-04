
CREATE TABLE IF NOT EXISTS account_verified_emails (
    role VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_source VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    user_id VARCHAR(191) NOT NULL,
    email_encrypted TEXT CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    email_masked VARCHAR(254) NOT NULL,
    email_fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    verified_at DATETIME(6) NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (role, account_source, user_id),
    KEY ix_account_verified_email_fingerprint (email_fingerprint)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS email_verification_challenges (
    challenge_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    challenge_token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    role VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_source VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    user_id VARCHAR(191) NOT NULL,
    account_fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    stage VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    proposed_email_encrypted TEXT CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    proposed_email_masked VARCHAR(254) NOT NULL,
    proposed_email_fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    prior_email_fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    otp_destination_encrypted TEXT CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    otp_destination_masked VARCHAR(254) NOT NULL,
    otp_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    otp_expires_at DATETIME(6) NOT NULL,
    failed_attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
    resend_count TINYINT UNSIGNED NOT NULL DEFAULT 0,
    last_sent_at DATETIME(6) NOT NULL,
    expires_at DATETIME(6) NOT NULL,
    request_ip_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    status VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'pending',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    verified_at DATETIME(6) NULL,
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (challenge_id),
    UNIQUE KEY uq_email_verification_challenge_token (challenge_token_hash),
    KEY ix_email_verification_account_history
        (role, account_source, user_id, created_at),
    KEY ix_email_verification_pending
        (role, account_source, user_id, status),
    KEY ix_email_verification_expiry (status, expires_at),
    KEY ix_email_verification_ip_history (request_ip_hash, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS email_verification_rate_limits (
    scope VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    scope_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    window_started_at DATETIME(6) NOT NULL,
    request_count SMALLINT UNSIGNED NOT NULL,
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (scope, scope_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$

DROP TRIGGER IF EXISTS edupocket_students_security_cleanup$$
CREATE TRIGGER edupocket_students_security_cleanup
AFTER DELETE ON students
FOR EACH ROW
BEGIN
    DELETE FROM account_verified_emails
    WHERE role = 'student' AND account_source = 'students'
      AND user_id = OLD.student_num;
    DELETE FROM email_verification_challenges
    WHERE role = 'student' AND account_source = 'students'
      AND user_id = OLD.student_num;
    DELETE FROM password_change_authenticators
    WHERE role = 'student' AND account_source = 'students'
      AND user_id = OLD.student_num;
    DELETE FROM password_change_challenges
    WHERE role = 'student' AND account_source = 'students'
      AND user_id = OLD.student_num;
END$$

DROP TRIGGER IF EXISTS edupocket_parents_security_cleanup$$
CREATE TRIGGER edupocket_parents_security_cleanup
AFTER DELETE ON parents
FOR EACH ROW
BEGIN
    DELETE FROM account_verified_emails
    WHERE role = 'parent' AND account_source = 'parents'
      AND user_id = OLD.parent_id;
    DELETE FROM email_verification_challenges
    WHERE role = 'parent' AND account_source = 'parents'
      AND user_id = OLD.parent_id;
    DELETE FROM password_change_authenticators
    WHERE role = 'parent' AND account_source = 'parents'
      AND user_id = OLD.parent_id;
    DELETE FROM password_change_challenges
    WHERE role = 'parent' AND account_source = 'parents'
      AND user_id = OLD.parent_id;
END$$

DROP TRIGGER IF EXISTS edupocket_admins_security_cleanup$$
CREATE TRIGGER edupocket_admins_security_cleanup
AFTER DELETE ON admins
FOR EACH ROW
BEGIN
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
END$$

DROP TRIGGER IF EXISTS edupocket_cashiers_security_cleanup$$
CREATE TRIGGER edupocket_cashiers_security_cleanup
AFTER DELETE ON cashiers
FOR EACH ROW
BEGIN
    DELETE FROM account_verified_emails
    WHERE role = 'cashier' AND account_source = 'cashiers'
      AND user_id = OLD.cashier_id;
    DELETE FROM email_verification_challenges
    WHERE role = 'cashier' AND account_source = 'cashiers'
      AND user_id = OLD.cashier_id;
    DELETE FROM password_change_authenticators
    WHERE role = 'cashier' AND account_source = 'cashiers'
      AND user_id = OLD.cashier_id;
    DELETE FROM password_change_challenges
    WHERE role = 'cashier' AND account_source = 'cashiers'
      AND user_id = OLD.cashier_id;
END$$

DROP TRIGGER IF EXISTS edupocket_canteens_security_cleanup$$
CREATE TRIGGER edupocket_canteens_security_cleanup
AFTER DELETE ON canteens
FOR EACH ROW
BEGIN
    DELETE FROM account_verified_emails
    WHERE role = 'canteen' AND account_source = 'canteens'
      AND user_id = OLD.canteen_id;
    DELETE FROM email_verification_challenges
    WHERE role = 'canteen' AND account_source = 'canteens'
      AND user_id = OLD.canteen_id;
    DELETE FROM password_change_authenticators
    WHERE role = 'canteen' AND account_source = 'canteens'
      AND user_id = OLD.canteen_id;
    DELETE FROM password_change_challenges
    WHERE role = 'canteen' AND account_source = 'canteens'
      AND user_id = OLD.canteen_id;
END$$

DELIMITER ;
