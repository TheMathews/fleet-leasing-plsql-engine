-- =============================================================================
-- File: 03_pkg_leasing_engine.pks
-- Description: Package Specification for Fleet Billing & Contract Operations
-- =============================================================================

CREATE OR REPLACE PACKAGE pkg_leasing_engine AS

    -- Custom Exception for Business Rule Violations
    e_invalid_mileage EXCEPTION;
    PRAGMA EXCEPTION_INIT(e_invalid_mileage, -20001);

    -- Bulk processing batch limit constant
    c_batch_limit CONSTANT PLS_INTEGER := 500;

    -- Deterministic function to calculate over-mileage fee
    FUNCTION fn_calc_mileage_penalty (
        p_initial_km      IN NUMBER,
        p_current_km      IN NUMBER,
        p_allowed_km      IN NUMBER,
        p_extra_km_rate   IN NUMBER
    ) RETURN NUMBER DETERMINISTIC;

    -- Update vehicle odometer and validate against rollback tampering
    PROCEDURE prc_update_odometer (
        p_vehicle_id  IN fleet_vehicles.vehicle_id%TYPE,
        p_new_mileage IN fleet_vehicles.current_mileage%TYPE
    );

    -- High-performance batch billing using BULK COLLECT and FORALL
    PROCEDURE prc_run_monthly_billing (
        p_billing_period IN VARCHAR2, -- Expected: 'YYYY-MM'
        p_processed_out  OUT PLS_INTEGER,
        p_failed_out     OUT PLS_INTEGER
    );

    -- Analytical reporting using SYS_REFCURSOR and Window Functions
    PROCEDURE prc_get_fleet_utilization_report (
        p_brand_filter IN VARCHAR2 DEFAULT NULL,
        p_report_rc    OUT SYS_REFCURSOR
    );

END pkg_leasing_engine;
/