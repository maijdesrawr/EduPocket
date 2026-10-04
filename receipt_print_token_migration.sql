
CREATE TABLE IF NOT EXISTS receipt_print_tokens (
    token_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    token_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    transaction_id INT NOT NULL,
    session_id BIGINT UNSIGNED NULL,
    viewer_role VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    viewer_account_source VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    viewer_user_id VARCHAR(191) NOT NULL,
    authorization_context VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    issued_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    expires_at DATETIME(6) NOT NULL,
    consumed_at DATETIME(6) NULL,
    revoked_at DATETIME(6) NULL,
    PRIMARY KEY (token_id),
    UNIQUE KEY uq_receipt_print_token_hash (token_hash),
    KEY ix_receipt_print_token_expiry (expires_at, consumed_at, revoked_at),
    KEY ix_receipt_print_token_transaction (transaction_id, issued_at),
    KEY ix_receipt_print_token_session (session_id, issued_at),
    CONSTRAINT fk_receipt_print_token_transaction
        FOREIGN KEY (transaction_id) REFERENCES transactions (transaction_id)
        ON DELETE CASCADE ON UPDATE CASCADE,
    CONSTRAINT fk_receipt_print_token_session
        FOREIGN KEY (session_id) REFERENCES app_sessions (session_id)
        ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
