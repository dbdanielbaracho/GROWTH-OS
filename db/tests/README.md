# Growth OS DDL v1 RC8 Cross-Review Gate

Target: PostgreSQL 18.6 for this review, then the exact PostgreSQL 18.x patch/build deployed for Release 1.

## Environment isolation

- Never run the full stateful SQL/Node suite against the project's permanent application database.
- Maintain a dedicated Railway validation PostgreSQL **service/cluster** for `growth_os_test`. A separate database inside the production PostgreSQL server is **not** sufficient because PostgreSQL roles and memberships are cluster-global.
- The validation cluster must use credentials generated specifically for validation. Production database credentials must never be copied into the validation cluster.
- `growth_test_harness` and every other test-only role/provisioning object may exist only on the validation PostgreSQL cluster. They must never exist on the production PostgreSQL cluster.
- `node-integration-tests`, migration/test runners and any other stateful validation tooling must target the validation PostgreSQL cluster explicitly. They must not fall back to the production database when validation configuration is absent.
- `growth_os_test` is a long-lived validation environment, but its data is restored to an empty baseline before every complete suite run.
- A complete run means: clean validation database, migrations 001-005, production provisioning required by those migrations, Identity helper-role provisioning (`05_identity_roles.sql`), migrations 006-008 in order, **test provisioning only after all schema/security migrations are present**, `000_validation_database_is_empty.sql`, fixtures, SQL tests in order, concurrency scenarios, then Node integrations.
- Test provisioning must run after the latest schema/security migration. `01_test_roles.sql` grants the test harness access to `ALL TABLES IN SCHEMA growth` as they exist at grant time; running it before a later migration creates new tables outside the harness grant and produces false test-environment failures such as SQLSTATE `42501`.
- Do not fix a test-harness privilege gap by widening `app_runtime` production privileges. Test-only access belongs to `growth_test_harness` and must never be introduced into `db/provisioning/production/`.
- Do not rerun an arbitrary stateful subset after the database has accumulated fixtures and classify fixture collisions as product regressions.
- Test `000_production_provisioning_excludes_test_roles.sql` must run on a PostgreSQL cluster that has received production-only provisioning and no test-role provisioning. Roles are cluster-global, so this proof is invalid if production and validation share a PostgreSQL server.
- `009_membership_authorization_matrix.sql` uses unique per-run identities and may be rerun independently; this is intentional because it is the focused authorization matrix.

## Production-cluster exclusion gate

Before a production database change is frozen or released, prove on the production PostgreSQL cluster that:

1. no test-only role such as `growth_test_harness` exists;
2. no test provisioning has been applied;
3. application/migrator/helper role boundaries match the reviewed production provisioning;
4. no validation runner or test credential points to the production database.

If a legacy test role is discovered on a production cluster, do not repair it ad hoc. Contain it first, move validation to a separate cluster, then use the reviewed scripts under `db/remediation/` to remove database-level dependencies and finally drop the cluster-global role. Any unexpected ownership, membership or dependency is a stop condition.

## Mandatory sequence
1. Restore the dedicated Railway validation database `growth_os_test` on its separate validation PostgreSQL service/cluster to an empty baseline.
2. Apply ordered schema migrations `001` through `005` with `ON_ERROR_STOP=1`.
3. Apply the matching production provisioning, including `db/provisioning/production/05_identity_roles.sql` before Identity v1 migration 006.
4. Apply `db/migrations/006_identity_v1.sql` and confirm `COMMIT`.
5. Apply `db/migrations/007_public_execute_least_privilege.sql` as `growth_migrator` and confirm `COMMIT`.
6. Apply `db/migrations/008_opportunity_radar_evidence_read.sql` as `growth_migrator` and confirm `COMMIT`.
7. Only now run `db/provisioning/test/01_test_roles.sql` and the remaining test provisioning so `growth_test_harness` receives privileges over every table created by the current schema.
8. Run `000_validation_database_is_empty.sql` before loading any fixture.
9. Load the versioned test fixtures.
10. Run the existing SQL regression suite `001` through `022` in its documented order, including its real-concurrency scenarios.
11. Run `023_identity_v1_schema_security.sql` and `024_identity_v1_flow.sql`.
12. Execute the Identity invitation-accept race with two real PostgreSQL sessions, then run `025_identity_v1_invitation_concurrency.sql` as the final-state assertion.
13. Run `026_public_execute_least_privilege.sql` and require the exact Issue #17 grant matrix: zero PUBLIC EXECUTE on all 16 reviewed functions, explicit runtime/helper access only where documented.
14. Run `027_opportunity_radar_evidence_read.sql` and require SELECT-only runtime access to `opportunity_evidence` and `insight_evidence`, continued RLS+FORCE, and no new runtime access to `feed_cards`.
15. Execute identity/application integration and pool-reset tests with the actual application driver/pool when that layer exists.
16. Run `apps/api/integration-tests/opportunity-radar.integration.mts` with `DATABASE_URL` bound to app_runtime and `MIGRATOR_DATABASE_URL` bound to growth_migrator on the isolated validation cluster.
17. Record exact PG version/build, schema checksum or migration SHA, command, timestamps and PASS/FAIL/NOT EXECUTED for every gate.

No test may be marked PASS from deduction alone.

Hosted runs of `012_rc9_security_helper_hardening.sql` must provide
`APP_RUNTIME_DATABASE_URL`, `MIGRATOR_DATABASE_URL`, and `ADMIN_DATABASE_URL`.
The test never assumes a local host, fixed port, database name, or shared password.

RC8: execute `011_rc8_six_fail_regressions.md` before structural-freeze consideration.
