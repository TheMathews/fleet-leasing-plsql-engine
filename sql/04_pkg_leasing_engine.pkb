-- =============================================================================
-- File: 04_pkg_leasing_engine.pkb
-- Description: Package Body implementing bulk billing and fleet analytics
-- =============================================================================

CREATE OR REPLACE PACKAGE BODY pkg_leasing_engine AS

    -- -------------------------------------------------------------------------
    -- Function: fn_calc_mileage_penalty
    -- -------------------------------------------------------------------------
    FUNCTION fn_calc_mileage_penalty (
        p_initial_km      IN NUMBER,
        p_current_km      IN NUMBER,
        p_allowed_km      IN NUMBER,
        p_extra_km_rate   IN NUMBER
    ) RETURN NUMBER DETERMINISTIC IS
        v_driven_km NUMBER;
        v_excess_km NUMBER;
    BEGIN
        v_driven_km := GREATEST(0, p_current_km - p_initial_km);
        v_excess_km := GREATEST(0, v_driven_km - p_allowed_km);
        RETURN ROUND(v_excess_km * p_extra_km_rate, 2);
    END fn_calc_mileage_penalty;

    -- -------------------------------------------------------------------------
    -- Procedure: prc_update_odometer
    -- -------------------------------------------------------------------------
    PROCEDURE prc_update_odometer (
        p_vehicle_id  IN fleet_vehicles.vehicle_id%TYPE,
        p_new_mileage IN fleet_vehicles.current_mileage%TYPE
    ) IS
        v_current_mileage fleet_vehicles.current_mileage%TYPE;
    BEGIN
        SELECT current_mileage
          INTO v_current_mileage
          FROM fleet_vehicles
         WHERE vehicle_id = p_vehicle_id
           FOR UPDATE NOWAIT;

        IF p_new_mileage < v_current_mileage THEN
            RAISE_APPLICATION_ERROR(
                -20001,
                'New odometer reading (' || p_new_mileage || ') cannot be lower than current reading (' || v_current_mileage || ').'
            );
        END IF;

        UPDATE fleet_vehicles
           SET current_mileage = p_new_mileage
         WHERE vehicle_id = p_vehicle_id;

        COMMIT;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            prc_log_error('pkg_leasing_engine.prc_update_odometer', SQLCODE, 'Vehicle ID not found', 'ID=' || p_vehicle_id);
            RAISE;
        WHEN OTHERS THEN
            ROLLBACK;
            prc_log_error('pkg_leasing_engine.prc_update_odometer', SQLCODE, SQLERRM, 'ID=' || p_vehicle_id);
            RAISE;
    END prc_update_odometer;

    -- -------------------------------------------------------------------------
    -- Procedure: prc_run_monthly_billing
    -- -------------------------------------------------------------------------
    PROCEDURE prc_run_monthly_billing (
        p_billing_period IN VARCHAR2,
        p_processed_out  OUT PLS_INTEGER,
        p_failed_out     OUT PLS_INTEGER
    ) IS
        CURSOR c_active_contracts IS
            SELECT c.contract_id,
                   c.base_monthly_fee,
                   c.initial_mileage,
                   v.current_mileage,
                   c.allowed_km_per_year,
                   c.extra_km_rate
              FROM leasing_contracts c
              JOIN fleet_vehicles v ON v.vehicle_id = c.vehicle_id
             WHERE c.contract_status = 'ACTIVE';

        TYPE t_contract_batch IS TABLE OF c_active_contracts%ROWTYPE INDEX BY PLS_INTEGER;
        TYPE t_invoice_batch  IS TABLE OF leasing_invoices%ROWTYPE INDEX BY PLS_INTEGER;

        l_contracts t_contract_batch;
        l_invoices  t_invoice_batch;

        e_forall_errors EXCEPTION;
        PRAGMA EXCEPTION_INIT(e_forall_errors, -24381);

        v_err_idx  PLS_INTEGER;
        v_err_code NUMBER;
        v_err_msg  VARCHAR2(4000);
    BEGIN
        p_processed_out := 0;
        p_failed_out    := 0;

        OPEN c_active_contracts;
        LOOP
            FETCH c_active_contracts BULK COLLECT INTO l_contracts LIMIT c_batch_limit;
            EXIT WHEN l_contracts.COUNT = 0;

            l_invoices.DELETE;

            -- Transform contract data into invoice records in memory (PGA)
            FOR i IN 1 .. l_contracts.COUNT LOOP
                l_invoices(i).contract_id     := l_contracts(i).contract_id;
                l_invoices(i).billing_period  := p_billing_period;
                l_invoices(i).base_amount     := l_contracts(i).base_monthly_fee;
                l_invoices(i).mileage_penalty := fn_calc_mileage_penalty(
                    p_initial_km    => l_contracts(i).initial_mileage,
                    p_current_km    => l_contracts(i).current_mileage,
                    p_allowed_km    => l_contracts(i).allowed_km_per_year,
                    p_extra_km_rate => l_contracts(i).extra_km_rate
                );
                l_invoices(i).total_amount    := l_invoices(i).base_amount + l_invoices(i).mileage_penalty;
            END LOOP;

            -- Bulk insert with exception handling per row
            BEGIN
                FORALL i IN 1 .. l_invoices.COUNT SAVE EXCEPTIONS
                    INSERT INTO leasing_invoices (
                        contract_id,
                        billing_period,
                        base_amount,
                        mileage_penalty,
                        total_amount
                    ) VALUES (
                        l_invoices(i).contract_id,
                        l_invoices(i).billing_period,
                        l_invoices(i).base_amount,
                        l_invoices(i).mileage_penalty,
                        l_invoices(i).total_amount
                    );

                p_processed_out := p_processed_out + l_invoices.COUNT;

            EXCEPTION
                WHEN e_forall_errors THEN
                    p_failed_out    := p_failed_out + SQL%BULK_EXCEPTIONS.COUNT;
                    p_processed_out := p_processed_out + (l_invoices.COUNT - SQL%BULK_EXCEPTIONS.COUNT);

                    FOR j IN 1 .. SQL%BULK_EXCEPTIONS.COUNT LOOP
                        v_err_idx  := SQL%BULK_EXCEPTIONS(j).ERROR_INDEX;
                        v_err_code := -SQL%BULK_EXCEPTIONS(j).ERROR_CODE;
                        v_err_msg  := SQLERRM(v_err_code);

                        prc_log_error(
                            p_module_name  => 'pkg_leasing_engine.prc_run_monthly_billing',
                            p_error_code   => v_err_code,
                            p_error_msg    => v_err_msg,
                            p_context_info => 'ContractID=' || l_invoices(v_err_idx).contract_id || ', Period=' || p_billing_period
                        );
                    END LOOP;
            END;
        END LOOP;

        CLOSE c_active_contracts;
        COMMIT;

    EXCEPTION
        WHEN OTHERS THEN
            IF c_active_contracts%ISOPEN THEN
                CLOSE c_active_contracts;
            END IF;
            ROLLBACK;
            prc_log_error('pkg_leasing_engine.prc_run_monthly_billing', SQLCODE, SQLERRM, 'Period=' || p_billing_period);
            RAISE;
    END prc_run_monthly_billing;

    -- -------------------------------------------------------------------------
    -- Procedure: prc_get_fleet_utilization_report
    -- -------------------------------------------------------------------------
    PROCEDURE prc_get_fleet_utilization_report (
        p_brand_filter IN VARCHAR2 DEFAULT NULL,
        p_report_rc    OUT SYS_REFCURSOR
    ) IS
    BEGIN
        OPEN p_report_rc FOR
            SELECT v.brand,
                   v.model_name,
                   v.license_plate,
                   v.current_mileage,
                   c.customer_name,
                   c.base_monthly_fee,
                   ROUND(AVG(v.current_mileage) OVER (PARTITION BY v.model_name), 0) AS avg_model_mileage,
                   RANK() OVER (PARTITION BY v.brand ORDER BY v.current_mileage DESC) AS mileage_rank_in_brand
              FROM fleet_vehicles v
              LEFT JOIN leasing_contracts c
                ON c.vehicle_id = v.vehicle_id
               AND c.contract_status = 'ACTIVE'
             WHERE (p_brand_filter IS NULL OR v.brand = UPPER(p_brand_filter))
             ORDER BY v.brand, mileage_rank_in_brand;
    END prc_get_fleet_utilization_report;

END pkg_leasing_engine;
/