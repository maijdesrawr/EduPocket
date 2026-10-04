CREATE TABLE IF NOT EXISTS backend_audit_log (
    audit_id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    request_id CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    session_id BIGINT UNSIGNED NULL,
    actor_authenticated TINYINT(1) NOT NULL DEFAULT 0,
    role VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NULL,
    account_source VARCHAR(32) CHARACTER SET ascii COLLATE ascii_bin NULL,
    user_id VARCHAR(191) NULL,
    route VARCHAR(255) NOT NULL,
    request_method VARCHAR(12) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    response_status SMALLINT UNSIGNED NOT NULL,
    outcome VARCHAR(20) CHARACTER SET ascii COLLATE ascii_bin NOT NULL,
    metadata_json LONGTEXT CHARACTER SET utf8mb4 COLLATE utf8mb4_bin NOT NULL,
    request_ip_hash CHAR(64) CHARACTER SET ascii COLLATE ascii_bin NULL,
    user_agent VARCHAR(255) NULL,
    started_at DATETIME(6) NOT NULL,
    completed_at DATETIME(6) NOT NULL,
    duration_ms INT UNSIGNED NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (audit_id),
    UNIQUE KEY uq_backend_audit_request (request_id),
    KEY ix_backend_audit_account (role, account_source, user_id, created_at),
    KEY ix_backend_audit_session (session_id, created_at),
    KEY ix_backend_audit_route (route, created_at),
    KEY ix_backend_audit_outcome (outcome, response_status, created_at),
    KEY ix_backend_audit_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

DROP TRIGGER IF EXISTS edupocket_backend_audit_no_update;
CREATE TRIGGER edupocket_backend_audit_no_update
BEFORE UPDATE ON backend_audit_log
FOR EACH ROW
SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'EduPocket backend audit rows are append-only';

DROP TRIGGER IF EXISTS edupocket_backend_audit_no_delete;
CREATE TRIGGER edupocket_backend_audit_no_delete
BEFORE DELETE ON backend_audit_log
FOR EACH ROW
SIGNAL SQLSTATE '45000'
    SET MESSAGE_TEXT = 'EduPocket backend audit rows are append-only';
