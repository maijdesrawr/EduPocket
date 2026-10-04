USE centraldb;

ALTER TABLE transactions
    MODIFY COLUMN transaction_type
        ENUM('payment', 'top-up', 'transfer-out', 'transfer-in') NOT NULL;

CREATE TABLE IF NOT EXISTS student_transfers (
    transfer_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    client_request_id CHAR(36) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    request_fingerprint CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    sender_student_num VARCHAR(20) NOT NULL,
    recipient_student_num VARCHAR(20) NOT NULL,
    sender_name_snapshot VARCHAR(191) NOT NULL,
    recipient_name_snapshot VARCHAR(191) NOT NULL,
    amount DECIMAL(10,2) NOT NULL,
    currency CHAR(3) CHARACTER SET ascii COLLATE ascii_bin NOT NULL DEFAULT 'PHP',
    status ENUM('pending', 'completed') NOT NULL DEFAULT 'pending',
    sender_transaction_id INT NULL,
    recipient_transaction_id INT NULL,
    sender_balance_after DECIMAL(10,2) NULL,
    recipient_balance_after DECIMAL(10,2) NULL,
    session_id BIGINT UNSIGNED NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    completed_at DATETIME(6) NULL,
    updated_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6)
        ON UPDATE CURRENT_TIMESTAMP(6),
    PRIMARY KEY (transfer_id),
    UNIQUE KEY uq_student_transfer_request
        (sender_student_num, client_request_id),
    UNIQUE KEY uq_student_transfer_sender_transaction (sender_transaction_id),
    UNIQUE KEY uq_student_transfer_recipient_transaction (recipient_transaction_id),
    KEY ix_student_transfer_sender (sender_student_num, created_at),
    KEY ix_student_transfer_recipient (recipient_student_num, created_at),
    KEY ix_student_transfer_status (status, created_at),
    KEY ix_student_transfer_session (session_id),
    CONSTRAINT ck_student_transfer_distinct_accounts
        CHECK (sender_student_num <> recipient_student_num),
    CONSTRAINT ck_student_transfer_positive_amount
        CHECK (amount >= 1.00 AND amount <= 50000.00),
    CONSTRAINT fk_student_transfer_sender_transaction
        FOREIGN KEY (sender_transaction_id) REFERENCES transactions (transaction_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_student_transfer_recipient_transaction
        FOREIGN KEY (recipient_transaction_id) REFERENCES transactions (transaction_id)
        ON DELETE SET NULL ON UPDATE CASCADE,
    CONSTRAINT fk_student_transfer_session
        FOREIGN KEY (session_id) REFERENCES app_sessions (session_id)
        ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

ALTER TABLE student_transfers
    DROP CONSTRAINT ck_student_transfer_positive_amount;

ALTER TABLE student_transfers
    ADD CONSTRAINT ck_student_transfer_positive_amount
        CHECK (amount >= 1.00 AND amount <= 50000.00);
