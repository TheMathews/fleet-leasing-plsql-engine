-- =============================================================================
-- File: 02_audit_logger.sql
-- Description: Autonomous error logging procedure to persist exceptions
--              even when the main transaction rolls back.
-- =============================================================================

CREATE OR REPLACE PROCEDURE prc_log_error (
    p_module_name  IN VARCHAR2,
    p_error_code   IN NUMBER,
    p_error_msg    IN VARCHAR2,
    p_context_info IN VARCHAR2 DEFAULT NULL
) IS
    PRAGMA AUTONOMOUS_TRANSACTION;
BEGIN
    INSERT INTO system_error_log (
        module_name,
        error_code,
        error_message,
        backtrace,
        context_info
    ) VALUES (
        p_module_name,
        p_error_code,
        SUBSTR(p_error_msg, 1, 4000),
        SUBSTR(DBMS_UTILITY.FORMAT_ERROR_BACKTRACE, 1, 4000),
        SUBSTR(p_context_info, 1, 1000)
    );
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK; -- Never let the logger crash the caller
END prc_log_error;
/