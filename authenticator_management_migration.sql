
CREATE TABLE IF NOT EXISTS authenticator_management_challenges (
    challenge_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    challenge_token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    action VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    role VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_source VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    user_id VARCHAR(191) NOT NULL,
    account_fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    pending_totp_secret_encrypted TEXT CHARACTER SET ascii COLLATE ascii_bin NULL,
    expected_authenticator_fingerprint CHAR(64)
        CHARACTER SET ascii COLLATE ascii_bin NULL,
    failed_attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
    expires_at DATETIME(6) NOT NULL,
    request_ip_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    status VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'pending',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    verified_at DATETIME(6) NULL,
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (challenge_id),
    UNIQUE KEY uq_auth_management_challenge_token (challenge_token_hash),
    KEY ix_auth_management_challenge_account
        (role, account_source, user_id, status),
    KEY ix_auth_management_challenge_expiry (status, expires_at),
    KEY ix_auth_management_challenge_ip (request_ip_hash, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS authenticator_management_rate_limits (
    scope VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    scope_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    window_started_at DATETIME(6) NOT NULL,
    request_count SMALLINT UNSIGNED NOT NULL,
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (scope, scope_hash)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS authenticator_management_events (
    event_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    challenge_id BIGINT UNSIGNED NOT NULL,
    role VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_source VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    user_id VARCHAR(191) NOT NULL,
    event_type VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    request_ip_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (event_id),
    UNIQUE KEY uq_auth_management_event_challenge (challenge_id),
    KEY ix_auth_management_event_account
        (role, account_source, user_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DELIMITER $$

DROP TRIGGER IF EXISTS edupocket_students_auth_management_delete$$
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

DROP TRIGGER IF EXISTS edupocket_students_auth_management_identity_update$$
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

DROP TRIGGER IF EXISTS edupocket_parents_auth_management_delete$$
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

DROP TRIGGER IF EXISTS edupocket_parents_auth_management_identity_update$$
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

DROP TRIGGER IF EXISTS edupocket_admins_auth_management_delete$$
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

DROP TRIGGER IF EXISTS edupocket_admins_auth_management_identity_update$$
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

DROP TRIGGER IF EXISTS edupocket_cashiers_auth_management_delete$$
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

DROP TRIGGER IF EXISTS edupocket_cashiers_auth_management_identity_update$$
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

DROP TRIGGER IF EXISTS edupocket_canteens_auth_management_delete$$
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

DROP TRIGGER IF EXISTS edupocket_canteens_auth_management_identity_update$$
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
