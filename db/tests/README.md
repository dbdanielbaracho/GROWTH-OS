# Growth OS DDL v1 RC8 Cross-Review Gate

Target: PostgreSQL 18.6 for this review, then the exact PostgreSQL 18.x patch/build deployed for Release 1.

## Environment isolation

- Never run the full stateful SQL/Node suite against the project's permanent application database.
- Maintain a dedicated Railway validation database (`growth_os_test`). It is a long-lived environment, but its data is restored to an empty baseline before every complete suite run.
- A complete run means: clean database, migrations 001-005, production provisioning, test provisioning, `000_validation_database_is_empty.sql`, fixtures, SQL tests in order, concurrency scenarios, then Node integrations.
- Do not rerun an arbitrary stateful subset after the database has accumulated fixtures and classify fixture collisions as product regressions.
- Test `000_production_provisioning_excludes_test_roles.sql` requires a separate PostgreSQL cluster because roles are cluster-global. Run it after production-only provisioning and before any test-role provisioning on that isolated cluster.
- `009_membership_authorization_matrix.sql` uses unique per-run identities and may be rerun independently; this is intentional because it is the focused authorization matrix.

## Mandatory sequence
1. Restore the dedicated test database to an empty baseline -> apply `001_initial_schema.sql` with `ON_ERROR_STOP=1`.
2. Run `000_validation_database_is_empty.sql` before loading any fixture.
3. Load the versioned test fixtures.
4. Run `001_catalog_invariants.sql` (dynamic, not a hard-coded tenant table list).
5. Provision actual runtime role and run `002_runtime_role_gate.sql`.
6. Run `003_trigger_integrity.sql`.
7. Run `005_rc3_integrity.sql` and `005_membership_privilege_escalation.sql`.
8. Run `009_membership_authorization_matrix.sql`.
9. Execute the four real-concurrency scenarios in `010_membership_concurrency_contract.md`.
10. Only after membership authorization is green, resume lineage/temporal and the remaining concurrency/deletion/late-metric/AI-routing suite.
11. Execute identity bootstrap and pool reset with the actual application driver/pool when that layer exists.
12. Record exact PG version/build, schema checksum, command, timestamps and PASS/FAIL/NOT EXECUTED.

No test may be marked PASS from deduction alone.

Hosted runs of `012_rc9_security_helper_hardening.sql` must provide
`APP_RUNTIME_DATABASE_URL`, `MIGRATOR_DATABASE_URL`, and `ADMIN_DATABASE_URL`.
The test never assumes a local host, fixed port, database name, or shared password.

RC8: execute `011_rc8_six_fail_regressions.md` before structural-freeze consideration.
