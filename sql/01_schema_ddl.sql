-- =============================================================================
-- File: 01_schema_ddl.sql
-- Description: Core database schema for Fleet & Leasing Management Engine
-- Target: Oracle Database 19c+
-- =============================================================================

-- 1. Fleet Vehicles Table
CREATE TABLE fleet_vehicles (
    vehicle_id      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vin             VARCHAR2(17) NOT NULL UNIQUE,
    license_plate   VARCHAR2(15) NOT NULL UNIQUE,
    brand           VARCHAR2(50) DEFAULT 'TOYOTA' NOT NULL,
    model_name      VARCHAR2(50) NOT NULL,
    current_mileage NUMBER(10) DEFAULT 0 NOT NULL,
    status          VARCHAR2(20) DEFAULT 'AVAILABLE' NOT NULL,
    created_at      TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT chk_vehicle_status CHECK (status IN ('AVAILABLE', 'LEASED', 'MAINTENANCE', 'RETIRED')),
    CONSTRAINT chk_vehicle_mileage CHECK (current_mileage >= 0)
);

-- 2. Leasing Contracts Table
CREATE TABLE leasing_contracts (
    contract_id         NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    vehicle_id          NUMBER NOT NULL,
    customer_tax_id     VARCHAR2(20) NOT NULL,
    customer_name       VARCHAR2(100) NOT NULL,
    start_date          DATE NOT NULL,
    end_date            DATE NOT NULL,
    base_monthly_fee    NUMBER(10, 2) NOT NULL,
    allowed_km_per_year NUMBER(10) NOT NULL,
    extra_km_rate       NUMBER(6, 4) DEFAULT 0.0850 NOT NULL,
    initial_mileage     NUMBER(10) NOT NULL,
    contract_status     VARCHAR2(20) DEFAULT 'ACTIVE' NOT NULL,
    CONSTRAINT fk_contract_vehicle FOREIGN KEY (vehicle_id) REFERENCES fleet_vehicles(vehicle_id),
    CONSTRAINT chk_contract_status CHECK (contract_status IN ('ACTIVE', 'CLOSED', 'CANCELLED', 'DEFAULTED')),
    CONSTRAINT chk_contract_dates  CHECK (end_date > start_date)
);

CREATE INDEX idx_contracts_status_veh ON leasing_contracts(contract_status, vehicle_id);

-- 3. Monthly Billing Invoices Table
CREATE TABLE leasing_invoices (
    invoice_id      NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    contract_id     NUMBER NOT NULL,
    billing_period  VARCHAR2(7) NOT NULL, -- Format: YYYY-MM
    base_amount     NUMBER(10, 2) NOT NULL,
    mileage_penalty NUMBER(10, 2) DEFAULT 0 NOT NULL,
    total_amount    NUMBER(10, 2) NOT NULL,
    issued_at       TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
    CONSTRAINT fk_invoice_contract FOREIGN KEY (contract_id) REFERENCES leasing_contracts(contract_id),
    CONSTRAINT uq_contract_period UNIQUE (contract_id, billing_period)
);

-- 4. System Error & Audit Log Table
CREATE TABLE system_error_log (
    log_id          NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    module_name     VARCHAR2(100) NOT NULL,
    error_code      NUMBER NOT NULL,
    error_message   VARCHAR2(4000) NOT NULL,
    backtrace       VARCHAR2(4000),
    context_info    VARCHAR2(1000),
    logged_at       TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
);