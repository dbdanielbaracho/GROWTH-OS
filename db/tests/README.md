# Growth OS DDL v1 RC8 Cross-Review Gate

Target: PostgreSQL 18.6 for this review, then the exact PostgreSQL 18.x patch/build deployed for Release 1.

## Mandatory sequence
1. Empty DB -> apply `001_initial_schema.sql` with `ON_ERROR_STOP=1`.
2. Run `001_catalog_invariants.sql` (dynamic, not a hard-coded tenant table list).
3. Provision actual runtime role and run `002_runtime_role_gate.sql`.
4. Run `003_trigger_integrity.sql`.
5. Run `005_rc3_integrity.sql` and `005_membership_privilege_escalation.sql`.
6. Run `009_membership_authorization_matrix.sql`.
7. Execute the four real-concurrency scenarios in `010_membership_concurrency_contract.md`.
8. Only after membership authorization is green, resume lineage/temporal and the remaining concurrency/deletion/late-metric/AI-routing suite.
9. Execute identity bootstrap and pool reset with the actual application driver/pool when that layer exists.
10. Record exact PG version/build, schema checksum, command, timestamps and PASS/FAIL/NOT EXECUTED.

No test may be marked PASS from deduction alone.

RC8: execute `011_rc8_six_fail_regressions.md` before structural-freeze consideration.
