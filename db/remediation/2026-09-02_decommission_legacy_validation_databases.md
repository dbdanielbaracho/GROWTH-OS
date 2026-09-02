# Legacy validation database decommission — Issue #18

## Purpose
Remove only the two obsolete project databases that remain on the legacy production PostgreSQL cluster after validation was moved to the separate `Postgres-Validation` service.

Approved target databases for possible removal:
- `growth_prod_only_000`
- `growth_os_test` (legacy/shared-cluster copy only)

Protected databases — never drop or modify in this procedure:
- `growth_os_797f0a3`
- `postgres`
- `railway`

## Preconditions already established by Issue #18 Phase A
- zero active sessions on both legacy targets at audit time;
- no Railway application/test consumer points to either legacy target;
- `node-integration-tests` points to the separate `Postgres-Validation` service;
- no unique/non-reproducible data found;
- no publication, subscription or foreign server found;
- `growth_test_harness` is absent from the legacy cluster;
- the only remaining role dependencies are shared production roles that survive `DROP DATABASE`;
- `growth_os_797f0a3`, `postgres` and `railway` are outside scope.

These facts must be rechecked immediately before execution. Phase A evidence is not permission to skip fresh preflight.

## Required adversarial gate
Before execution, Claude must review:
1. the exact merged SHA containing this runbook and `2026-09-02_decommission_legacy_validation_databases.sql`;
2. Issue #18 Phase A evidence;
3. the fact that the SQL uses an explicit two-database allowlist and `DROP DATABASE` without `FORCE`.

Required verdict: `APPROVE` before any destructive statement.

## Execution sequence
1. Confirm Railway project/service identity for the legacy production PostgreSQL cluster.
2. Confirm the current GitHub `main` SHA and fetch the SQL remediation from that exact SHA.
3. Read-only recheck:
   - five non-template DBs are exactly `growth_os_797f0a3`, `growth_os_test`, `growth_prod_only_000`, `postgres`, `railway`;
   - both legacy targets are owned by `postgres`;
   - zero active sessions on both legacy targets;
   - `growth_test_harness` absent;
   - no Railway service/variable has been repointed back to either legacy target since Phase A.
4. Connect to the legacy cluster's `postgres` control database and run `db/remediation/2026-09-02_decommission_legacy_validation_databases.sql` with `ON_ERROR_STOP`.
5. Do not terminate sessions manually and do not use `DROP DATABASE ... WITH (FORCE)`. If a session appears, stop.
6. The SQL drops `growth_prod_only_000` first, verifies its absence, rechecks sessions on `growth_os_test`, then drops the legacy `growth_os_test` and verifies final database inventory.
7. After the SQL completes, independently query `pg_database` again; do not rely only on script notices.
8. Re-prove on `growth_os_797f0a3`:
   - Identity v1: 9/9 tables present;
   - 8/8 applicable Identity tables have RLS + FORCE RLS;
   - no direct `app_runtime` DML leak on Identity tables;
   - `app_runtime`, `growth_migrator`, `growth_rls_helper`, `growth_identity_helper` attributes/memberships unchanged.
9. Reconfirm the separate `Postgres-Validation` service is healthy and remains the sole validation target.
10. Record exact timestamps, target identifiers, merged SHA, commands, outputs and PASS/FAIL evidence in Issue #18.

## Stop conditions
Stop without improvisation if any of these occur:
- Railway project/service identity is ambiguous;
- database inventory differs from the reviewed set;
- either target has an active session;
- either target owner changed;
- `growth_test_harness` reappears;
- a production/test service references either legacy target;
- either `DROP DATABASE` fails;
- protected database inventory changes;
- production Identity/role smoke differs from the pre-execution state.

No ad-hoc grants, role changes, session termination, `FORCE`, rename, dump/restore, or alternative cleanup is authorized by this runbook.

## Final governance
Claude must adversarially review the final execution evidence after the drop. Issue #18 may close only on final `APPROVE`. Issue #14 may close only after Issue #18 is complete and the production cluster is proven free of test/validation residue.
