

CREATE TABLE IF NOT EXISTS password_history (
    history_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    role VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_source VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    user_id VARCHAR(191) NOT NULL,
    password_hash VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    password_fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    recorded_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (history_id),
    UNIQUE KEY uq_password_history_exact_credential
        (role, account_source, user_id, password_fingerprint),
    KEY ix_password_history_account (role, account_source, user_id, recorded_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS password_change_authenticators (
    role VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_source VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    user_id VARCHAR(191) NOT NULL,
    totp_secret_encrypted TEXT CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    enrolled_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    last_verified_at DATETIME(6) NULL,
    last_used_step BIGINT UNSIGNED NULL,
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (role, account_source, user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS password_change_challenges (
    challenge_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    challenge_token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    role VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_source VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    user_id VARCHAR(191) NOT NULL,
    method VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    new_password_hash VARCHAR(255) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    otp_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    otp_expires_at DATETIME(6) NULL,
    destination_encrypted TEXT CHARACTER SET ascii COLLATE ascii_bin NULL,
    destination_masked VARCHAR(320) NULL,
    pending_totp_secret_encrypted TEXT CHARACTER SET ascii COLLATE ascii_bin NULL,
    requires_totp_setup TINYINT(1) NOT NULL DEFAULT 0,
    failed_attempts TINYINT UNSIGNED NOT NULL DEFAULT 0,
    resend_count TINYINT UNSIGNED NOT NULL DEFAULT 0,
    last_sent_at DATETIME(6) NULL,
    expires_at DATETIME(6) NOT NULL,
    status VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'pending',
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    verified_at DATETIME(6) NULL,
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (challenge_id),
    UNIQUE KEY uq_password_change_challenge_token (challenge_token_hash),
    KEY ix_password_change_challenge_account
        (role, account_source, user_id, status),
    KEY ix_password_change_challenge_expiry (status, expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO password_history
    (role, account_source, user_id, password_hash, password_fingerprint)
SELECT
    'student',
    'students',
    student_num,
    Password,
    SHA2(CONCAT('student', CHAR(0), 'students', CHAR(0), student_num, CHAR(0), Password), 256)
FROM students
WHERE Password REGEXP '^\\$(2[abxy]|argon2)';

INSERT IGNORE INTO password_history
    (role, account_source, user_id, password_hash, password_fingerprint)
SELECT
    'parent',
    'parents',
    parent_id,
    Password,
    SHA2(CONCAT('parent', CHAR(0), 'parents', CHAR(0), parent_id, CHAR(0), Password), 256)
FROM parents
WHERE Password REGEXP '^\\$(2[abxy]|argon2)';

INSERT IGNORE INTO password_history
    (role, account_source, user_id, password_hash, password_fingerprint)
SELECT
    CASE WHEN LOWER(COALESCE(role, '')) = 'cashier' THEN 'cashier' ELSE 'admin' END,
    'admins',
    admin_id,
    password,
    SHA2(CONCAT(
        CASE WHEN LOWER(COALESCE(role, '')) = 'cashier' THEN 'cashier' ELSE 'admin' END,
        CHAR(0), 'admins', CHAR(0), admin_id, CHAR(0), password
    ), 256)
FROM admins
WHERE password REGEXP '^\\$(2[abxy]|argon2)';

INSERT IGNORE INTO password_history
    (role, account_source, user_id, password_hash, password_fingerprint)
SELECT
    'cashier',
    'cashiers',
    cashier_id,
    password,
    SHA2(CONCAT('cashier', CHAR(0), 'cashiers', CHAR(0), cashier_id, CHAR(0), password), 256)
FROM cashiers
WHERE password REGEXP '^\\$(2[abxy]|argon2)';

INSERT IGNORE INTO password_history
    (role, account_source, user_id, password_hash, password_fingerprint)
SELECT
    'canteen',
    'canteens',
    canteen_id,
    Password,
    SHA2(CONCAT('canteen', CHAR(0), 'canteens', CHAR(0), canteen_id, CHAR(0), Password), 256)
FROM canteens
WHERE Password REGEXP '^\\$(2[abxy]|argon2)';

DELIMITER $$

DROP TRIGGER IF EXISTS edupocket_students_password_history$$
CREATE TRIGGER edupocket_students_password_history
BEFORE UPDATE ON students
FOR EACH ROW
BEGIN
    IF NOT (OLD.Password <=> NEW.Password) THEN
        IF OLD.Password REGEXP '^\\$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                'student', 'students', OLD.student_num, OLD.Password,
                SHA2(CONCAT('student', CHAR(0), 'students', CHAR(0), OLD.student_num, CHAR(0), OLD.Password), 256)
            );
        END IF;
        IF NEW.Password REGEXP '^\\$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                'student', 'students', NEW.student_num, NEW.Password,
                SHA2(CONCAT('student', CHAR(0), 'students', CHAR(0), NEW.student_num, CHAR(0), NEW.Password), 256)
            );
        END IF;
    END IF;
END$$

DROP TRIGGER IF EXISTS edupocket_parents_password_history$$
CREATE TRIGGER edupocket_parents_password_history
BEFORE UPDATE ON parents
FOR EACH ROW
BEGIN
    IF NOT (OLD.Password <=> NEW.Password) THEN
        IF OLD.Password REGEXP '^\\$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                'parent', 'parents', OLD.parent_id, OLD.Password,
                SHA2(CONCAT('parent', CHAR(0), 'parents', CHAR(0), OLD.parent_id, CHAR(0), OLD.Password), 256)
            );
        END IF;
        IF NEW.Password REGEXP '^\\$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                'parent', 'parents', NEW.parent_id, NEW.Password,
                SHA2(CONCAT('parent', CHAR(0), 'parents', CHAR(0), NEW.parent_id, CHAR(0), NEW.Password), 256)
            );
        END IF;
    END IF;
END$$

DROP TRIGGER IF EXISTS edupocket_admins_password_history$$
CREATE TRIGGER edupocket_admins_password_history
BEFORE UPDATE ON admins
FOR EACH ROW
BEGIN
    IF NOT (OLD.password <=> NEW.password) THEN
        IF OLD.password REGEXP '^\\$(2[abxy]|argon2)' THEN
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
        IF NEW.password REGEXP '^\\$(2[abxy]|argon2)' THEN
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
END$$

DROP TRIGGER IF EXISTS edupocket_cashiers_password_history$$
CREATE TRIGGER edupocket_cashiers_password_history
BEFORE UPDATE ON cashiers
FOR EACH ROW
BEGIN
    IF NOT (OLD.password <=> NEW.password) THEN
        IF OLD.password REGEXP '^\\$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                'cashier', 'cashiers', OLD.cashier_id, OLD.password,
                SHA2(CONCAT('cashier', CHAR(0), 'cashiers', CHAR(0), OLD.cashier_id, CHAR(0), OLD.password), 256)
            );
        END IF;
        IF NEW.password REGEXP '^\\$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                'cashier', 'cashiers', NEW.cashier_id, NEW.password,
                SHA2(CONCAT('cashier', CHAR(0), 'cashiers', CHAR(0), NEW.cashier_id, CHAR(0), NEW.password), 256)
            );
        END IF;
    END IF;
END$$

DROP TRIGGER IF EXISTS edupocket_canteens_password_history$$
CREATE TRIGGER edupocket_canteens_password_history
BEFORE UPDATE ON canteens
FOR EACH ROW
BEGIN
    IF NOT (OLD.Password <=> NEW.Password) THEN
        IF OLD.Password REGEXP '^\\$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                'canteen', 'canteens', OLD.canteen_id, OLD.Password,
                SHA2(CONCAT('canteen', CHAR(0), 'canteens', CHAR(0), OLD.canteen_id, CHAR(0), OLD.Password), 256)
            );
        END IF;
        IF NEW.Password REGEXP '^\\$(2[abxy]|argon2)' THEN
            INSERT IGNORE INTO password_history
                (role, account_source, user_id, password_hash, password_fingerprint)
            VALUES (
                'canteen', 'canteens', NEW.canteen_id, NEW.Password,
                SHA2(CONCAT('canteen', CHAR(0), 'canteens', CHAR(0), NEW.canteen_id, CHAR(0), NEW.Password), 256)
            );
        END IF;
    END IF;
END$$

DELIMITER ;
