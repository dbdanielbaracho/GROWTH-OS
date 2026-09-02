# Growth OS — RC9 DDL + Runtime Security Freeze Record

**RC9 DDL + RUNTIME SECURITY FREEZE: APPROVED**

This record closes the RC9 review cycle. From this point, any change to
schema, RLS, roles, grants, membership security, concurrency contracts, or
any function covered by this freeze requires a new change record and a
version subsequent to RC9 — this freeze is not silently reopened.

## Baseline preserved

- **RC8 schema SHA-256** (unchanged, `db/migrations/001_initial_schema.sql`):
  `b2bf18fc540bb08a0e0c17c911d91e91e9eda9d7504fa8120d5f9374eeb48b76`
- **RC9 frozen local commit**: `33729648a8693ae0c825d8b91fe86a79cd77912c`
- **Branch**: `feat/rc9-runtime-security-freeze`

## Final Execution Gate — physical results

| Gate | Result |
|---|---|
| PostgreSQL version | 18.4, real, physical (not substituted with PG16) |
| Clean rebuild | YES — zero residual cluster-wide roles confirmed before rebuild; all 8 provisioning stages green |
| SQL test suite | 16/16 PASS, single sequential pass, real exit codes verified per file |
| Application integration (real driver/pool) | 7/7 PASS (`apps/api/rc9-integration/identity-bootstrap.mts`) |
| Concurrency C1–C4 | PASS — all four, two real concurrent `psql` sessions per scenario |
| RC9-FINDING-001 | **CLOSED — PHYSICALLY VERIFIED** |
| RC9-FINDING-003 | **CLOSED — PHYSICALLY VERIFIED** |
| Security blockers | 0 |
| Correctness blockers | 0 |
| Concurrency blockers | 0 |
| Test coverage gaps | 0 |
| RC8 baseline hash | preserved, unchanged |
| Working tree | clean |

## What RC9 delivered over RC8

- Production/test role provisioning (`growth_migrator`, `app_runtime`,
  `growth_test_harness`, `growth_rls_helper`), least-privilege grants
  proven necessary by physical removal, not assumed.
- Complete runtime grant matrix across all 42 tables, fail-closed default.
- RC9-FINDING-001/003 closed: `memberships_workspace_select` and
  `workspaces_member_select` now require genuine active membership, not
  workspace_id alone — closing a real cross-tenant read confirmed by
  isolated physical reproduction.
- Two second-order regressions discovered and fixed by physical execution
  (not anticipated in design): `can_bootstrap_first_membership`'s
  emptiness check and `membership_write_guard`'s own duplicate emptiness
  check were both transitively affected by the RLS tightening above;
  fixed with a dedicated, narrowly-scoped `growth_rls_helper` role and
  `workspace_has_any_membership()`.
- Full physical coverage: identity/bootstrap, jobs concurrency (items 1–4;
  item 5 explicitly out of scope — no worker role exists in the codebase),
  lineage/temporal guards L1 and T1 (complete, a–d and a–f respectively),
  membership concurrency C1–C4, pool partial-context safety (R6),
  privilege-escalation resistance for the security helper, and the
  third-party-owner-visibility coverage gap closed in the final round.

## Known, deliberately open items (not RC9 blockers)

- `provider_usage`/`audit_events` nullable `workspace_id`: classified
  `INTENTIONAL BUT UNIMPLEMENTED` — the "system-role contract" referenced
  by the RC8 regression suite is not delivered anywhere in the codebase.
  Tracked separately; does not block this freeze since no approved grant
  touches either table.
- `RC9-FINDING-002` (no application code path for discover-memberships-
  before-selecting-workspace bootstrap flow): `LOW` severity, application
  feature gap, not a security leak, does not block this freeze.

## Remote status

**Push remains pending, exclusively due to authentication.** No
persistent GitHub credential, `gh auth` session, or OAuth device-flow
completion is available in this environment (the device-flow code display
and completion-check cannot be bridged across tool-call boundaries here).
The branch and all 24 commits exist only locally until authentication is
resolved through a channel outside this environment. This is an
operational pendency, separate from and not a reflection on the technical
freeze decision above.
