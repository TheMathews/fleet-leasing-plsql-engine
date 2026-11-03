-- =============================================================================
-- File: 06_test_execution.sql
-- Description: Seed sample fleet data and execute billing & reporting tests
-- =============================================================================
SET SERVEROUTPUT ON SIZE UNLIMITED;

DECLARE
    v_veh_id_1   NUMBER;
    v_veh_id_2   NUMBER;
    v_processed  PLS_INTEGER;
    v_failed     PLS_INTEGER;
BEGIN
    -- 1. Insert sample vehicles
    INSERT INTO fleet_vehicles (vin, license_plate, brand, model_name, current_mileage)
    VALUES ('JT111111111111111', '1234-MNP', 'TOYOTA', 'COROLLA HYBRID', 15000)
    RETURNING vehicle_id INTO v_veh_id_1;

    INSERT INTO fleet_vehicles (vin, license_plate, brand, model_name, current_mileage)
    VALUES ('JT222222222222222', '5678-MNR', 'TOYOTA', 'RAV4 PLUG-IN', 28000)
    RETURNING vehicle_id INTO v_veh_id_2;

    -- 2. Create active leasing contracts
    INSERT INTO leasing_contracts (
        vehicle_id, customer_tax_id, customer_name, start_date, end_date,
        base_monthly_fee, allowed_km_per_year, extra_km_rate, initial_mileage
    ) VALUES (
        v_veh_id_1, 'B12345678', 'Tech Logistics SL', ADD_MONTHS(SYSDATE, -12), ADD_MONTHS(SYSDATE, 24),
        420.00, 20000, 0.0800, 5000
    );

    INSERT INTO leasing_contracts (
        vehicle_id, customer_tax_id, customer_name, start_date, end_date,
        base_monthly_fee, allowed_km_per_year, extra_km_rate, initial_mileage
    ) VALUES (
        v_veh_id_2, 'B87654321', 'Madrid Consulting Group', ADD_MONTHS(SYSDATE, -12), ADD_MONTHS(SYSDATE, 24),
        650.00, 15000, 0.1000, 2000 -- Exceeded mileage: driven 26,000 km vs 15,000 allowed
    );

    COMMIT;

    -- 3. Update odometer via package API
    pkg_leasing_engine.prc_update_odometer(p_vehicle_id => v_veh_id_1, p_new_mileage => 18500);

    -- 4. Execute Monthly Batch Billing
    pkg_leasing_engine.prc_run_monthly_billing(
        p_billing_period => TO_CHAR(SYSDATE, 'YYYY-MM'),
        p_processed_out  => v_processed,
        p_failed_out     => v_failed
    );

    DBMS_OUTPUT.PUT_LINE('Batch Run Complete -> Processed: ' || v_processed || ' | Failed: ' || v_failed);
END;
/