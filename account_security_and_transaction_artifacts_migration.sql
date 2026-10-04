
ALTER TABLE parents
    ADD COLUMN IF NOT EXISTS pin VARCHAR(255) NULL AFTER Password;

ALTER TABLE admins
    ADD COLUMN IF NOT EXISTS pin VARCHAR(255) NULL AFTER password;

ALTER TABLE cashiers
    ADD COLUMN IF NOT EXISTS pin VARCHAR(255) NULL AFTER password;

ALTER TABLE canteens
    ADD COLUMN IF NOT EXISTS pin VARCHAR(255) NULL AFTER Password;

ALTER TABLE transaction_items
    ADD COLUMN IF NOT EXISTS item_name VARCHAR(191) NULL AFTER product_id;

ALTER TABLE transactions
    ADD COLUMN IF NOT EXISTS processor_role VARCHAR(20)
        CHARACTER SET ascii COLLATE ascii_bin NULL AFTER cashier_id,
    ADD COLUMN IF NOT EXISTS processor_account_source VARCHAR(32)
        CHARACTER SET ascii COLLATE ascii_bin NULL AFTER processor_role,
    ADD COLUMN IF NOT EXISTS processor_id VARCHAR(191)
        NULL AFTER processor_account_source;

CREATE INDEX IF NOT EXISTS ix_transactions_processor
    ON transactions (processor_role, processor_id);

CREATE INDEX IF NOT EXISTS ix_transactions_processor_source
    ON transactions (processor_account_source, processor_id);

ALTER TABLE topups
    ADD COLUMN IF NOT EXISTS transaction_id INT NULL AFTER topup_id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_topups_transaction
    ON topups (transaction_id);

ALTER TABLE pending_payments
    ADD COLUMN IF NOT EXISTS callback_token_hash CHAR(64)
        CHARACTER SET ascii COLLATE ascii_bin NULL AFTER checkout_id,
    ADD COLUMN IF NOT EXISTS transaction_id INT NULL AFTER status,
    ADD COLUMN IF NOT EXISTS provider_payment_id VARCHAR(100)
        CHARACTER SET ascii COLLATE ascii_bin NULL AFTER transaction_id,
    ADD COLUMN IF NOT EXISTS completed_at DATETIME(6) NULL AFTER provider_payment_id;

ALTER TABLE pending_payments
    MODIFY COLUMN provider_payment_id VARCHAR(100)
        CHARACTER SET ascii COLLATE ascii_bin NULL AFTER transaction_id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_pending_payments_callback_token
    ON pending_payments (callback_token_hash);

CREATE UNIQUE INDEX IF NOT EXISTS uq_pending_payments_provider_payment
    ON pending_payments (provider_payment_id);

UPDATE transaction_items ti
LEFT JOIN products p ON p.product_id = ti.product_id
SET ti.item_name = COALESCE(NULLIF(ti.item_name, ''), p.name, CONCAT('Product #', ti.product_id))
WHERE ti.item_name IS NULL OR ti.item_name = '';

CREATE TABLE IF NOT EXISTS login_otp_challenges (
    challenge_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    challenge_token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    role VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_source VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    user_id VARCHAR(191) NOT NULL,
    method VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    device_id_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    request_ip_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    otp_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    otp_expires_at DATETIME(6) NULL,
    destination_masked VARCHAR(254) NULL,
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
    UNIQUE KEY uq_login_otp_token (challenge_token_hash),
    KEY ix_login_otp_account (role, account_source, user_id, status),
    KEY ix_login_otp_account_created (role, account_source, user_id, created_at),
    KEY ix_login_otp_ip_created (request_ip_hash, created_at),
    KEY ix_login_otp_expiry (status, expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE login_otp_challenges
    ADD COLUMN IF NOT EXISTS request_ip_hash CHAR(64)
        CHARACTER SET ascii COLLATE ascii_bin NULL AFTER account_fingerprint;

ALTER TABLE login_otp_challenges
    ADD COLUMN IF NOT EXISTS device_id_hash CHAR(64)
        CHARACTER SET ascii COLLATE ascii_bin NULL AFTER account_fingerprint;

UPDATE login_otp_challenges
SET status = 'cancelled'
WHERE status = 'pending'
  AND (device_id_hash IS NULL OR device_id_hash = '');

CREATE INDEX IF NOT EXISTS ix_login_otp_account_created
    ON login_otp_challenges (role, account_source, user_id, created_at);

CREATE INDEX IF NOT EXISTS ix_login_otp_ip_created
    ON login_otp_challenges (request_ip_hash, created_at);


CREATE TABLE IF NOT EXISTS app_sessions (
    session_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    role VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_source VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    user_id VARCHAR(191) NOT NULL,
    device_id_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    request_ip_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    user_agent VARCHAR(255) NULL,
    issued_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    last_seen_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    expires_at DATETIME(6) NOT NULL,
    revoked_at DATETIME(6) NULL,
    revocation_reason VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NULL,
    replaced_by_session_id BIGINT UNSIGNED NULL,
    PRIMARY KEY (session_id),
    UNIQUE KEY uq_app_session_token_hash (token_hash),
    KEY ix_app_session_account
        (role, account_source, user_id, issued_at),
    KEY ix_app_session_expiry (revoked_at, expires_at),
    KEY ix_app_session_replacement (replaced_by_session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE INDEX IF NOT EXISTS ix_app_session_idle_expiry
    ON app_sessions (revoked_at, last_seen_at);

CREATE TABLE IF NOT EXISTS app_session_accounts (
    role VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_source VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    user_id VARCHAR(191) NOT NULL,
    current_session_id BIGINT UNSIGNED NULL,
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (role, account_source, user_id),
    UNIQUE KEY uq_app_session_account_current (current_session_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS app_activity_events (
    event_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    session_id BIGINT UNSIGNED NULL,
    role VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_source VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    user_id VARCHAR(191) NOT NULL,
    event_name VARCHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    event_source VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL
        DEFAULT 'client',
    event_status VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL
        DEFAULT 'success',
    route VARCHAR(191) NULL,
    metadata_json LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NULL,
    request_ip_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    user_agent VARCHAR(255) NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (event_id),
    KEY ix_app_activity_account
        (role, account_source, user_id, created_at),
    KEY ix_app_activity_session (session_id, created_at),
    KEY ix_app_activity_event (event_name, created_at),
    CONSTRAINT fk_app_activity_session
        FOREIGN KEY (session_id) REFERENCES app_sessions (session_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS transaction_receipts (
    receipt_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    transaction_id INT NOT NULL,
    receipt_number VARCHAR(40) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    issued_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    status VARCHAR(16) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'issued',
    currency CHAR(3) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'PHP',
    transaction_type VARCHAR(20) NOT NULL,
    description_snapshot VARCHAR(255) NULL,
    student_num_snapshot VARCHAR(20) NOT NULL,
    student_name_snapshot VARCHAR(191) NOT NULL,
    canteen_id_snapshot VARCHAR(20) NULL,
    canteen_name_snapshot VARCHAR(191) NULL,
    cashier_id_snapshot VARCHAR(20) NULL,
    cashier_name_snapshot VARCHAR(191) NULL,
    processor_role_snapshot VARCHAR(20)
        CHARACTER SET ascii COLLATE ascii_bin NULL,
    processor_account_source_snapshot VARCHAR(32)
        CHARACTER SET ascii COLLATE ascii_bin NULL,
    processor_id_snapshot VARCHAR(191) NULL,
    processor_name_snapshot VARCHAR(191) NULL,
    total_amount DECIMAL(10,2) NOT NULL,
    legacy_backfilled TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (receipt_id),
    UNIQUE KEY uq_transaction_receipt_transaction (transaction_id),
    UNIQUE KEY uq_transaction_receipt_number (receipt_number),
    CONSTRAINT fk_transaction_receipt_transaction
        FOREIGN KEY (transaction_id) REFERENCES transactions (transaction_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE transaction_receipts
    ADD COLUMN IF NOT EXISTS processor_role_snapshot VARCHAR(20)
        CHARACTER SET ascii COLLATE ascii_bin NULL AFTER cashier_name_snapshot,
    ADD COLUMN IF NOT EXISTS processor_account_source_snapshot VARCHAR(32)
        CHARACTER SET ascii COLLATE ascii_bin NULL AFTER processor_role_snapshot,
    ADD COLUMN IF NOT EXISTS processor_id_snapshot VARCHAR(191)
        NULL AFTER processor_account_source_snapshot,
    ADD COLUMN IF NOT EXISTS processor_name_snapshot VARCHAR(191)
        NULL AFTER processor_id_snapshot;

CREATE TABLE IF NOT EXISTS account_notifications (
    notification_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    recipient_role VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    account_source VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    user_id VARCHAR(191) NOT NULL,
    transaction_id INT NOT NULL,
    title VARCHAR(120) NOT NULL,
    body VARCHAR(500) NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    read_at DATETIME(6) NULL,
    PRIMARY KEY (notification_id),
    UNIQUE KEY uq_account_notification_transaction
        (recipient_role, account_source, user_id, transaction_id),
    KEY ix_account_notification_delivery
        (recipient_role, user_id, notification_id),
    CONSTRAINT fk_account_notification_transaction
        FOREIGN KEY (transaction_id) REFERENCES transactions (transaction_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

INSERT IGNORE INTO transaction_receipts
    (transaction_id, receipt_number, issued_at, transaction_type,
     description_snapshot, student_num_snapshot, student_name_snapshot,
     canteen_id_snapshot, canteen_name_snapshot, cashier_id_snapshot,
     cashier_name_snapshot, processor_role_snapshot,
     processor_account_source_snapshot, processor_id_snapshot,
     processor_name_snapshot, total_amount, legacy_backfilled)
SELECT
    t.transaction_id,
    CONCAT(
        'EP-',
        DATE_FORMAT(COALESCE(date_time, date_created, NOW()), '%Y%m%d'),
        '-',
        LPAD(t.transaction_id, 8, '0')
    ),
    COALESCE(t.date_time, t.date_created, NOW()),
    t.transaction_type,
    t.description,
    t.student_num,
    COALESCE(s.Fname, t.student_num),
    t.canteen_id,
    c.Fname,
    t.cashier_id,
    COALESCE(ch.Fname, a.Fname),
    t.processor_role,
    t.processor_account_source,
    t.processor_id,
    CASE
        WHEN t.processor_role = 'student'
         AND t.processor_account_source = 'students' THEN ps.Fname
        WHEN t.processor_role = 'parent'
         AND t.processor_account_source = 'parents' THEN pp.Fname
        WHEN t.processor_role = 'canteen'
         AND t.processor_account_source = 'canteens' THEN pc.Fname
        WHEN t.processor_role = 'cashier'
         AND t.processor_account_source = 'cashiers' THEN pch.Fname
        WHEN t.processor_role = 'cashier'
         AND t.processor_account_source = 'admins' THEN pa.Fname
        ELSE NULL
    END,
    t.amount,
    1
FROM transactions t
LEFT JOIN students s ON s.student_num = t.student_num
LEFT JOIN canteens c ON c.canteen_id = t.canteen_id
LEFT JOIN cashiers ch ON ch.cashier_id = t.cashier_id
LEFT JOIN admins a ON a.admin_id = t.cashier_id
    AND LOWER(COALESCE(a.role, '')) = 'cashier'
LEFT JOIN students ps
  ON t.processor_role = 'student'
 AND t.processor_account_source = 'students'
 AND BINARY ps.student_num = BINARY t.processor_id
LEFT JOIN parents pp
  ON t.processor_role = 'parent'
 AND t.processor_account_source = 'parents'
 AND BINARY pp.parent_id = BINARY t.processor_id
LEFT JOIN canteens pc
  ON t.processor_role = 'canteen'
 AND t.processor_account_source = 'canteens'
 AND BINARY pc.canteen_id = BINARY t.processor_id
LEFT JOIN cashiers pch
  ON t.processor_role = 'cashier'
 AND t.processor_account_source = 'cashiers'
 AND BINARY pch.cashier_id = BINARY t.processor_id
LEFT JOIN admins pa
  ON t.processor_role = 'cashier'
 AND t.processor_account_source = 'admins'
 AND BINARY pa.admin_id = BINARY t.processor_id
 AND LOWER(COALESCE(pa.role, '')) = 'cashier';

DELIMITER $$

DROP TRIGGER IF EXISTS edupocket_transaction_artifacts$$
CREATE TRIGGER edupocket_transaction_artifacts
AFTER INSERT ON transactions
FOR EACH ROW
BEGIN
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
END$$

DROP TRIGGER IF EXISTS edupocket_students_login_otp_delete$$
CREATE TRIGGER edupocket_students_login_otp_delete
AFTER DELETE ON students
FOR EACH ROW
BEGIN
    DELETE FROM login_otp_challenges
    WHERE account_source = 'students'
      AND BINARY user_id = BINARY OLD.student_num;
END$$

DROP TRIGGER IF EXISTS edupocket_students_login_otp_identity_update$$
CREATE TRIGGER edupocket_students_login_otp_identity_update
AFTER UPDATE ON students
FOR EACH ROW
BEGIN
    IF NOT (OLD.student_num <=> NEW.student_num) THEN
        DELETE FROM login_otp_challenges
        WHERE account_source = 'students'
          AND BINARY user_id = BINARY OLD.student_num;
    END IF;
END$$

DROP TRIGGER IF EXISTS edupocket_parents_login_otp_delete$$
CREATE TRIGGER edupocket_parents_login_otp_delete
AFTER DELETE ON parents
FOR EACH ROW
BEGIN
    DELETE FROM login_otp_challenges
    WHERE account_source = 'parents'
      AND BINARY user_id = BINARY OLD.parent_id;
END$$

DROP TRIGGER IF EXISTS edupocket_parents_login_otp_identity_update$$
CREATE TRIGGER edupocket_parents_login_otp_identity_update
AFTER UPDATE ON parents
FOR EACH ROW
BEGIN
    IF NOT (OLD.parent_id <=> NEW.parent_id) THEN
        DELETE FROM login_otp_challenges
        WHERE account_source = 'parents'
          AND BINARY user_id = BINARY OLD.parent_id;
    END IF;
END$$

DROP TRIGGER IF EXISTS edupocket_admins_login_otp_delete$$
CREATE TRIGGER edupocket_admins_login_otp_delete
AFTER DELETE ON admins
FOR EACH ROW
BEGIN
    DELETE FROM login_otp_challenges
    WHERE account_source = 'admins'
      AND BINARY user_id = BINARY OLD.admin_id;
END$$

DROP TRIGGER IF EXISTS edupocket_admins_login_otp_identity_update$$
CREATE TRIGGER edupocket_admins_login_otp_identity_update
AFTER UPDATE ON admins
FOR EACH ROW
BEGIN
    IF NOT (OLD.admin_id <=> NEW.admin_id)
       OR NOT (LOWER(COALESCE(OLD.role, '')) <=> LOWER(COALESCE(NEW.role, ''))) THEN
        DELETE FROM login_otp_challenges
        WHERE account_source = 'admins'
          AND BINARY user_id = BINARY OLD.admin_id;
    END IF;
END$$

DROP TRIGGER IF EXISTS edupocket_cashiers_login_otp_delete$$
CREATE TRIGGER edupocket_cashiers_login_otp_delete
AFTER DELETE ON cashiers
FOR EACH ROW
BEGIN
    DELETE FROM login_otp_challenges
    WHERE account_source = 'cashiers'
      AND BINARY user_id = BINARY OLD.cashier_id;
END$$

DROP TRIGGER IF EXISTS edupocket_cashiers_login_otp_identity_update$$
CREATE TRIGGER edupocket_cashiers_login_otp_identity_update
AFTER UPDATE ON cashiers
FOR EACH ROW
BEGIN
    IF NOT (OLD.cashier_id <=> NEW.cashier_id) THEN
        DELETE FROM login_otp_challenges
        WHERE account_source = 'cashiers'
          AND BINARY user_id = BINARY OLD.cashier_id;
    END IF;
END$$

DROP TRIGGER IF EXISTS edupocket_canteens_login_otp_delete$$
CREATE TRIGGER edupocket_canteens_login_otp_delete
AFTER DELETE ON canteens
FOR EACH ROW
BEGIN
    DELETE FROM login_otp_challenges
    WHERE account_source = 'canteens'
      AND BINARY user_id = BINARY OLD.canteen_id;
END$$

DROP TRIGGER IF EXISTS edupocket_canteens_login_otp_identity_update$$
CREATE TRIGGER edupocket_canteens_login_otp_identity_update
AFTER UPDATE ON canteens
FOR EACH ROW
BEGIN
    IF NOT (OLD.canteen_id <=> NEW.canteen_id) THEN
        DELETE FROM login_otp_challenges
        WHERE account_source = 'canteens'
          AND BINARY user_id = BINARY OLD.canteen_id;
    END IF;
END$$

DELIMITER ;
