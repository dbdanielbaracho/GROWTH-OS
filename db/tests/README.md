# Growth OS DDL v1 RC8 Cross-Review Gate

Target: PostgreSQL 18.6 for this review, then the exact PostgreSQL 18.x patch/build deployed for Release 1.

## Environment isolation

- Never run the full stateful SQL/Node suite against the project's permanent application database.
- Maintain a dedicated Railway validation database (`growth_os_test`). It is a long-lived environment, but its data is restored to an empty baseline before every complete suite run.
- A complete run means: clean database, migrations 001-005, production provisioning required by those migrations, Identity helper-role provisioning (`05_identity_roles.sql`), migration 006, **test provisioning only after all schema migrations are present**, `000_validation_database_is_empty.sql`, fixtures, SQL tests in order, concurrency scenarios, then Node integrations.
- Test provisioning must run after the latest schema migration. `01_test_roles.sql` grants the test harness access to `ALL TABLES IN SCHEMA growth` as they exist at grant time; running it before a later migration creates new tables leaves those tables outside the harness grant and produces false test-environment failures such as SQLSTATE `42501`.
- Do not fix a test-harness privilege gap by widening `app_runtime` production privileges. Test-only access belongs to `growth_test_harness` and must never be introduced into `db/provisioning/production/`.
- Do not rerun an arbitrary stateful subset after the database has accumulated fixtures and classify fixture collisions as product regressions.
- Test `000_production_provisioning_excludes_test_roles.sql` requires a separate PostgreSQL cluster because roles are cluster-global. Run it after production-only provisioning and before any test-role provisioning on that isolated cluster.
- `009_membership_authorization_matrix.sql` uses unique per-run identities and may be rerun independently; this is intentional because it is the focused authorization matrix.

## Mandatory sequence
1. Restore the dedicated Railway validation database `growth_os_test` to an empty baseline.
2. Apply ordered schema migrations `001` through `005` with `ON_ERROR_STOP=1`.
3. Apply the matching production provisioning, including `db/provisioning/production/05_identity_roles.sql` before Identity v1 migration 006.
4. Apply `db/migrations/006_identity_v1.sql` and confirm `COMMIT`.
5. Only now run `db/provisioning/test/01_test_roles.sql` and the remaining test provisioning so `growth_test_harness` receives privileges over every table created through migration 006.
6. Run `000_validation_database_is_empty.sql` before loading any fixture.
7. Load the versioned test fixtures.
8. Run the existing SQL regression suite `001` through `022` in its documented order, including its real-concurrency scenarios.
9. Run `023_identity_v1_schema_security.sql` and `024_identity_v1_flow.sql`.
10. Execute the Identity invitation-accept race with two real PostgreSQL sessions, then run `025_identity_v1_invitation_concurrency.sql` as the final-state assertion.
11. Execute identity/application integration and pool-reset tests with the actual application driver/pool when that layer exists.
12. Record exact PG version/build, schema checksum or migration SHA, command, timestamps and PASS/FAIL/NOT EXECUTED for every gate.

No test may be marked PASS from deduction alone.

Hosted runs of `012_rc9_security_helper_hardening.sql` must provide
`APP_RUNTIME_DATABASE_URL`, `MIGRATOR_DATABASE_URL`, and `ADMIN_DATABASE_URL`.
The test never assumes a local host, fixed port, database name, or shared password.

RC8: execute `011_rc8_six_fail_regressions.md` before structural-freeze consideration.
