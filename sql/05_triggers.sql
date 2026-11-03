-- =============================================================================
-- File: 05_triggers.sql
-- Description: Synchronize vehicle status upon leasing contract lifecycle events
-- =============================================================================

CREATE OR REPLACE TRIGGER trg_sync_vehicle_status
AFTER INSERT OR UPDATE OF contract_status ON leasing_contracts
FOR EACH ROW
BEGIN
    IF INSERTING AND :NEW.contract_status = 'ACTIVE' THEN
        UPDATE fleet_vehicles
           SET status = 'LEASED'
         WHERE vehicle_id = :NEW.vehicle_id;

    ELSIF UPDATING AND :NEW.contract_status IN ('CLOSED', 'CANCELLED') THEN
        UPDATE fleet_vehicles
           SET status = 'AVAILABLE'
         WHERE vehicle_id = :NEW.vehicle_id;
    END IF;
END trg_sync_vehicle_status;
/