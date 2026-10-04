
USE centraldb;

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

ALTER TABLE transaction_receipts
    ADD COLUMN IF NOT EXISTS processor_role_snapshot VARCHAR(20)
        CHARACTER SET ascii COLLATE ascii_bin NULL AFTER cashier_name_snapshot,
    ADD COLUMN IF NOT EXISTS processor_account_source_snapshot VARCHAR(32)
        CHARACTER SET ascii COLLATE ascii_bin NULL AFTER processor_role_snapshot,
    ADD COLUMN IF NOT EXISTS processor_id_snapshot VARCHAR(191)
        NULL AFTER processor_account_source_snapshot,
    ADD COLUMN IF NOT EXISTS processor_name_snapshot VARCHAR(191)
        NULL AFTER processor_id_snapshot;

ALTER TABLE topups
    ADD COLUMN IF NOT EXISTS transaction_id INT NULL AFTER topup_id;

CREATE UNIQUE INDEX IF NOT EXISTS uq_topups_transaction
    ON topups (transaction_id);

UPDATE transactions t
JOIN student_transfers st
  ON t.transaction_id = st.sender_transaction_id
  OR t.transaction_id = st.recipient_transaction_id
SET t.processor_role = 'student',
    t.processor_account_source = 'students',
    t.processor_id = st.sender_student_num
WHERE NULLIF(TRIM(COALESCE(t.processor_role, '')), '') IS NULL
   OR NULLIF(TRIM(COALESCE(t.processor_account_source, '')), '') IS NULL
   OR NULLIF(TRIM(COALESCE(t.processor_id, '')), '') IS NULL;

UPDATE transactions t
JOIN pending_payments pp ON pp.transaction_id = t.transaction_id
SET t.processor_role = 'parent',
    t.processor_account_source = 'parents',
    t.processor_id = pp.parent_id
WHERE t.transaction_type = 'top-up'
  AND NULLIF(TRIM(COALESCE(pp.parent_id, '')), '') IS NOT NULL
  AND (
      NULLIF(TRIM(COALESCE(t.processor_role, '')), '') IS NULL
      OR NULLIF(TRIM(COALESCE(t.processor_account_source, '')), '') IS NULL
      OR NULLIF(TRIM(COALESCE(t.processor_id, '')), '') IS NULL
  );

DROP TEMPORARY TABLE IF EXISTS edupocket_topup_candidate_pairs;
CREATE TEMPORARY TABLE edupocket_topup_candidate_pairs
ENGINE=InnoDB
AS
SELECT
    tu.topup_id,
    t.transaction_id,
    ABS(TIMESTAMPDIFF(
        SECOND,
        tu.date_time,
        COALESCE(t.date_time, t.date_created)
    )) AS time_distance
FROM topups tu
JOIN transactions t
  ON t.transaction_type = 'top-up'
 AND t.student_num = tu.student_num
 AND t.amount = tu.amount
 AND ABS(TIMESTAMPDIFF(
        SECOND,
        tu.date_time,
        COALESCE(t.date_time, t.date_created)
     )) <= 300
LEFT JOIN topups already_linked
  ON already_linked.transaction_id = t.transaction_id
WHERE tu.transaction_id IS NULL
  AND already_linked.topup_id IS NULL;

DROP TEMPORARY TABLE IF EXISTS edupocket_topup_unique_best;
CREATE TEMPORARY TABLE edupocket_topup_unique_best
ENGINE=InnoDB
AS
SELECT pair.topup_id, MIN(pair.transaction_id) AS transaction_id
FROM edupocket_topup_candidate_pairs pair
JOIN (
    SELECT topup_id, MIN(time_distance) AS minimum_distance
    FROM edupocket_topup_candidate_pairs
    GROUP BY topup_id
) nearest
  ON nearest.topup_id = pair.topup_id
 AND nearest.minimum_distance = pair.time_distance
GROUP BY pair.topup_id
HAVING COUNT(*) = 1;

DROP TEMPORARY TABLE IF EXISTS edupocket_transaction_unique_best;
CREATE TEMPORARY TABLE edupocket_transaction_unique_best
ENGINE=InnoDB
AS
SELECT pair.transaction_id, MIN(pair.topup_id) AS topup_id
FROM edupocket_topup_candidate_pairs pair
JOIN (
    SELECT transaction_id, MIN(time_distance) AS minimum_distance
    FROM edupocket_topup_candidate_pairs
    GROUP BY transaction_id
) nearest
  ON nearest.transaction_id = pair.transaction_id
 AND nearest.minimum_distance = pair.time_distance
GROUP BY pair.transaction_id
HAVING COUNT(*) = 1;

UPDATE topups tu
JOIN edupocket_topup_unique_best topup_choice
  ON topup_choice.topup_id = tu.topup_id
JOIN edupocket_transaction_unique_best transaction_choice
  ON transaction_choice.transaction_id = topup_choice.transaction_id
 AND transaction_choice.topup_id = topup_choice.topup_id
SET tu.transaction_id = topup_choice.transaction_id
WHERE tu.transaction_id IS NULL;

DROP TEMPORARY TABLE IF EXISTS edupocket_transaction_unique_best;
DROP TEMPORARY TABLE IF EXISTS edupocket_topup_unique_best;
DROP TEMPORARY TABLE IF EXISTS edupocket_topup_candidate_pairs;

UPDATE transactions t
JOIN topups tu ON tu.transaction_id = t.transaction_id
SET t.processor_role = 'parent',
    t.processor_account_source = 'parents',
    t.processor_id = tu.parent_id
WHERE t.transaction_type = 'top-up'
  AND NULLIF(TRIM(COALESCE(tu.parent_id, '')), '') IS NOT NULL
  AND (
      NULLIF(TRIM(COALESCE(t.processor_role, '')), '') IS NULL
      OR NULLIF(TRIM(COALESCE(t.processor_account_source, '')), '') IS NULL
      OR NULLIF(TRIM(COALESCE(t.processor_id, '')), '') IS NULL
  );

UPDATE transactions t
JOIN canteens c ON c.canteen_id = t.canteen_id
SET t.processor_role = 'canteen',
    t.processor_account_source = 'canteens',
    t.processor_id = t.canteen_id
WHERE NULLIF(TRIM(COALESCE(t.processor_role, '')), '') IS NULL
   OR NULLIF(TRIM(COALESCE(t.processor_account_source, '')), '') IS NULL
   OR NULLIF(TRIM(COALESCE(t.processor_id, '')), '') IS NULL;

UPDATE transactions t
JOIN cashiers c ON BINARY c.cashier_id = BINARY t.cashier_id
JOIN admins a
  ON BINARY a.admin_id = BINARY t.cashier_id
 AND LOWER(COALESCE(a.role, '')) = 'cashier'
SET t.processor_role = NULL,
    t.processor_account_source = NULL,
    t.processor_id = NULL
WHERE t.processor_role = 'cashier'
  AND NULLIF(TRIM(COALESCE(t.processor_account_source, '')), '') IS NULL;

UPDATE transactions t
LEFT JOIN cashiers c ON BINARY c.cashier_id = BINARY t.cashier_id
LEFT JOIN admins a
  ON BINARY a.admin_id = BINARY t.cashier_id
 AND LOWER(COALESCE(a.role, '')) = 'cashier'
SET t.processor_role = 'cashier',
    t.processor_account_source = CASE
        WHEN c.cashier_id IS NOT NULL AND a.admin_id IS NULL THEN 'cashiers'
        WHEN c.cashier_id IS NULL AND a.admin_id IS NOT NULL THEN 'admins'
        ELSE NULL
    END,
    t.processor_id = t.cashier_id
WHERE NULLIF(TRIM(COALESCE(t.cashier_id, '')), '') IS NOT NULL
  AND (
      (c.cashier_id IS NOT NULL AND a.admin_id IS NULL)
      OR (c.cashier_id IS NULL AND a.admin_id IS NOT NULL)
  )
  AND (
      NULLIF(TRIM(COALESCE(t.processor_role, '')), '') IS NULL
      OR NULLIF(TRIM(COALESCE(t.processor_account_source, '')), '') IS NULL
      OR NULLIF(TRIM(COALESCE(t.processor_id, '')), '') IS NULL
  );

UPDATE transaction_receipts r
JOIN transactions t ON t.transaction_id = r.transaction_id
JOIN cashiers c ON BINARY c.cashier_id = BINARY t.cashier_id
JOIN admins a
  ON BINARY a.admin_id = BINARY t.cashier_id
 AND LOWER(COALESCE(a.role, '')) = 'cashier'
SET r.processor_role_snapshot = 'cashier',
    r.processor_account_source_snapshot = NULL,
    r.processor_id_snapshot = t.cashier_id,
    r.processor_name_snapshot = NULL
WHERE NULLIF(TRIM(COALESCE(t.processor_account_source, '')), '') IS NULL;

UPDATE transaction_receipts r
JOIN transactions t ON t.transaction_id = r.transaction_id
LEFT JOIN students ps
  ON t.processor_role = 'student' AND BINARY ps.student_num = BINARY t.processor_id
LEFT JOIN parents pp
  ON t.processor_role = 'parent' AND BINARY pp.parent_id = BINARY t.processor_id
LEFT JOIN canteens pc
  ON t.processor_role = 'canteen' AND BINARY pc.canteen_id = BINARY t.processor_id
LEFT JOIN cashiers pch
  ON t.processor_role = 'cashier'
 AND t.processor_account_source = 'cashiers'
 AND BINARY pch.cashier_id = BINARY t.processor_id
LEFT JOIN admins pa
  ON t.processor_role = 'cashier'
 AND t.processor_account_source = 'admins'
 AND BINARY pa.admin_id = BINARY t.processor_id
 AND LOWER(COALESCE(pa.role, '')) = 'cashier'
LEFT JOIN student_transfers st
  ON t.transaction_id = st.sender_transaction_id
  OR t.transaction_id = st.recipient_transaction_id
SET r.processor_role_snapshot = t.processor_role,
    r.processor_account_source_snapshot = t.processor_account_source,
    r.processor_id_snapshot = t.processor_id,
    r.processor_name_snapshot = CASE
      WHEN NULLIF(TRIM(COALESCE(r.processor_name_snapshot, '')), '') IS NOT NULL
      THEN r.processor_name_snapshot
      ELSE CASE t.processor_role
        WHEN 'student' THEN COALESCE(
            NULLIF(TRIM(ps.Fname), ''),
            NULLIF(TRIM(st.sender_name_snapshot), ''),
            CASE
                WHEN BINARY t.processor_id = BINARY r.student_num_snapshot
                THEN NULLIF(TRIM(r.student_name_snapshot), '')
                ELSE NULL
            END
        )
        WHEN 'parent' THEN NULLIF(TRIM(pp.Fname), '')
        WHEN 'canteen' THEN COALESCE(
            NULLIF(TRIM(pc.Fname), ''),
            NULLIF(TRIM(r.canteen_name_snapshot), '')
        )
        WHEN 'cashier' THEN COALESCE(
            NULLIF(TRIM(pch.Fname), ''),
            NULLIF(TRIM(pa.Fname), '')
        )
        ELSE NULL
      END
    END
WHERE (
      NULLIF(TRIM(COALESCE(r.processor_role_snapshot, '')), '') IS NULL
      OR NULLIF(TRIM(COALESCE(r.processor_account_source_snapshot, '')), '') IS NULL
      OR NULLIF(TRIM(COALESCE(r.processor_id_snapshot, '')), '') IS NULL
      OR NULLIF(TRIM(COALESCE(r.processor_name_snapshot, '')), '') IS NULL
  )
  AND NULLIF(TRIM(COALESCE(t.processor_role, '')), '') IS NOT NULL
  AND NULLIF(TRIM(COALESCE(t.processor_account_source, '')), '') IS NOT NULL
  AND NULLIF(TRIM(COALESCE(t.processor_id, '')), '') IS NOT NULL;

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

DELIMITER ;
