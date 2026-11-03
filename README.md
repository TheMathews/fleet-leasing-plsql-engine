# Fleet & Leasing PL/SQL Engine (`fleet-leasing-plsql-engine`)

A modular **Oracle 19c PL/SQL** backend engine designed to manage vehicle fleet lifecycles, leasing contracts, odometer validations, and high-throughput monthly billing batches.

## Business Domain Overview
Modern mobility and vehicle subscription platforms require reliable transactional processing for thousands of active contracts. This project demonstrates production-grade database engineering patterns for:
- **Fleet Lifecycle Tracking:** Automated state transitions (`AVAILABLE`, `LEASED`, `MAINTENANCE`, `RETIRED`) synchronized with contract events.
- **Odometer Anti-Tampering:** Concurrency-safe mileage updates using pessimistic row locking (`SELECT ... FOR UPDATE NOWAIT`) and custom business exceptions.
- **High-Volume Batch Billing:** Memory-bounded bulk invoice calculation combining base monthly fees with dynamic over-mileage penalties.
- **Fault-Tolerant Auditing:** Non-blocking error persistence via autonomous transactions.

## Key Oracle PL/SQL Concepts Demonstrated

| Feature / Pattern | Implementation File | Technical Benefit |
| :--- | :--- | :--- |
| **Modular Package Design** | `03_pkg_leasing_engine.pks` / `.pkb` | Encapsulates business logic, separates public API from private implementation, prevents invalidation cascades. |
| **`BULK COLLECT` + `LIMIT`** | `04_pkg_leasing_engine.pkb` | Processes large contract volumes in chunks of 500 rows, keeping PGA memory consumption predictable. |
| **`FORALL ... SAVE EXCEPTIONS`** | `04_pkg_leasing_engine.pkb` | Minimizes SQL/PLSQL context switches and isolates row-level failures via `SQL%BULK_EXCEPTIONS` without aborting the entire batch. |
| **`PRAGMA AUTONOMOUS_TRANSACTION`** | `02_audit_logger.sql` | Commits error diagnostics and stack backtraces (`DBMS_UTILITY.FORMAT_ERROR_BACKTRACE`) independently of main transaction rollbacks. |
| **Window Functions + `SYS_REFCURSOR`** | `04_pkg_leasing_engine.pkb` | Exposes fleet utilization metrics (`AVG() OVER`, `RANK() OVER`) to external backend services. |
| **DETERMINISTIC Functions** | `03_pkg_leasing_engine.pks` | Optimizes repeated penalty calculations within SQL and PL/SQL contexts. |

## Quick Start

Run the scripts sequentially in SQL*Plus, SQLcl, or Oracle SQL Developer (Oracle 19c or higher):

```sql
@sql/01_schema_ddl.sql
@sql/02_audit_logger.sql
@sql/03_pkg_leasing_engine.pks
@sql/04_pkg_leasing_engine.pkb
@sql/05_triggers.sql
@sql/06_test_execution.sql