# Growth OS — Test Integrity & Method Hardening Gate

**Status: ACTIVE, forward-only.** This document does not edit or reopen any
frozen document (RC9 Freeze Record, Post-RC9 Content, Creative Production
v0.5.2 Freeze Record, or the Documento Mestre Universal). It is a new
protocol layer, added because a review process found that a defect in a
*test's own logic* — not the schema, not the application — had been
silently reporting PASS, and that the finding which triggered the review
was itself based on stale historical documentation rather than a live
re-check. Both gaps are closed here as permanent, mechanical rules, not as
one-time fixes.

## 1. The evidence-freshness rule

**Historical evidence — a code comment, a past finding record, an older
document — can never by itself prove the current state of a live system.**
It can only ever establish what was true *at the time it was written*.

For any claim about the current state of a database, a security control,
or any other runtime behavior, the required chain is:

```
historical evidence → inspect live/current implementation → execute a
discriminating test against that live implementation → conclusion
```

Skipping either of the middle two steps and going straight from historical
evidence to a conclusion is not permitted, regardless of how authoritative
the historical evidence looks (a named finding ID, a signed-off freeze
record, a prior session's report). This applies symmetrically: a comment
saying a vulnerability is open is not proof it is still open, exactly as a
freeze record saying something was fixed is not proof it is still fixed
after later changes. Both require the same live-inspection-plus-test step
before being restated as a current-state conclusion.

**Origin of this rule:** a security review correctly identified that
`apps/api/rc9-integration/identity-bootstrap.mts` contained a comment
documenting RC9-FINDING-003 as an open bypass in
`growth.workspaces_member_select`. That comment was accurate *when
written* — it described the original RC8 policy. It was reused as evidence
that the bypass was still live, without re-querying `pg_policy` or
re-running the exploit against a current database. It was not: the policy
had already been replaced by `db/migrations/002_rc9_security_policy_fix.sql`
in an earlier round. The corrected process — query `pg_policy` directly for
the live policy definition, then physically execute the described exploit
against a freshly rebuilt database — produced the actual answer (0 rows
leaked) in minutes and cost nothing extra. That is now the required
process, not an optional extra step.

## 2. Full repository audit — classification table

Every occurrence of the requested pattern classes was searched for across
the entire repository (excluding `node_modules`, which is third-party code
outside this project's own test-integrity scope). Each is classified:

- **REAL DEFECT** — the pattern makes a test pass regardless of the actual
  condition. Corrected.
- **LEGITIMATE** — the pattern appears only in a comment (documenting the
  defect for the historical record, or explaining a design decision) or in
  third-party code, never in live, executed test logic.
- **NEEDS HARDENING** — not a false-green defect on its own, but a
  structural weakness (a security-relevant check that can silently not
  run) that should not be allowed to recur.

| Pattern | Location | Classification | Disposition |
|---|---|---|---|
| `.every((r) => true)` | `identity-bootstrap.mts` step 2 (original) | REAL DEFECT | Fixed in the prior round: unqualified query + real per-row identity check |
| `check(..., true)` | `identity-bootstrap.mts` step 6 (original) | REAL DEFECT | Fixed in the prior round: real `rowCount === 0` assertion |
| `.every((r) => true)`, `check(..., true)` | same file, current doc-comments describing the above fixes | LEGITIMATE | Comments only, not scanned by the gate, kept as historical record of the correction |
| `expect(true)` | `node_modules/zod/**` | LEGITIMATE | Third-party library's own test suite, outside this project's scope |
| `SKIP: (3) no fixture opportunity...` | `creative-production.integration.mts`, cross-workspace rejection test | NEEDS HARDENING | A security-relevant assertion could silently not run without failing the suite. Fixed: fixture now guaranteed by `db/provisioning/test/04_creative_production_test_fixtures.sql`; the branch itself now hard-FAILs instead of silently skipping if the fixture is ever absent again |
| `>= 1 && rows.every((r) => r.field === expected)` | `identity-bootstrap.mts` steps 2 and 8c | LEGITIMATE | The `>= 1` guards only against vacuous-true on an empty array; the actual assertion is the per-row identity check (`.every`), and exact row count is intentionally not the invariant being tested (fixture-dependent, documented inline) |
| Empty catch blocks (`catch (e) {}`) | none found | LEGITIMATE (absent) | — |
| Self-comparison tautology (`x === x`) | none found in live code | LEGITIMATE (absent) | — |
| `.skip(`, `xit(`, `xdescribe(`, `.todo(` | none found | LEGITIMATE (absent) | — |
| Tests with zero assertion calls | none found (every `.mts` test file has ≥3 `check()` calls; every `.sql` test file has `RAISE EXCEPTION` and/or explicit `FAIL` echo) | LEGITIMATE (absent) | — |
| Exit-code-masking shell pipelines in committed scripts | none found in `package.json` scripts or `.github/workflows/ci.yml` | LEGITIMATE (absent) | — |
| Concurrency tests that don't run real concurrency | `db/tests/010_c1_*.sql`, `010_c2_c3_c4_*.sql`, `017_post_rc9_approval_concurrency.sql`, `020_creative_production_lineage_concurrency.sql` | LEGITIMATE (by design, documented) | These are deliberately assertion-only files, paired with a documented two-session driver script in their own header comments — not runnable standalone by design. Re-executed with genuine two real concurrent `psql` sessions each, physically, as part of this same gate (see Security Hardening Gate report) |

**Patterns explicitly searched for and not found anywhere in live project
code:** `assert(true)` as a literal condition, `.some(() => false)`,
negative tests whose catch block contains no state-verification (all
`EXCEPTION WHEN OTHERS` blocks in `db/tests/*.sql` capture `SQLSTATE`
and/or `MESSAGE_TEXT` via `GET STACKED DIAGNOSTICS` and assert on it, not
merely "it threw, therefore PASS").

## 3. The automated gate: `db/scripts/test-integrity-gate.mjs`

A static-analysis script, run as the **first** step of CI (before
typecheck, build, or test), scanning every `.mts`/`.ts` file for the
mechanically-detectable false-green pattern classes:

- `check(..., true)` / `assert(true)` / `expect(true)` — literal-true as
  the entire asserted condition.
- `.every((x) => true)` — vacuous predicate, always true regardless of
  array contents.
- `.some((x) => false)` — the inverse vacuous predicate.
- `.skip(`, `.todo(`, `xit(`, `xdescribe(` — a test disabled at the
  framework level.
- `x === x` / `x == x` — a value compared against itself rather than an
  expected value.

Matches inside comments are not flagged (a line is skipped if its trimmed
content starts with `//`, `*`, or `/*`) — this document and the corrected
test file's own explanatory comments about the original defects would
otherwise trigger the gate on their own historical description of the bug.

**This gate does not cover, and does not claim to cover:** catches that
swallow real failures without re-raising or failing the test (requires
understanding control flow, not just pattern matching); negative tests
that catch an exception but don't verify *which* exception or the
resulting state (same limitation); fake concurrency (requires knowing
whether two operations actually overlapped in time, not visible from
source text alone). These remain the responsibility of physical execution
and manual review at each security/correctness gate — documented here so
the gate's coverage boundary is explicit, not implied to be complete.

**Physically proven, both directions, before this gate was committed:**
a synthetic file containing exactly these three defect patterns was
created, the gate correctly failed (exit 1, all three matches reported
with file/line/pattern), the file was deleted, and the gate correctly
passed again (exit 0) — see the Test Integrity & Method Hardening Gate
execution report for the literal commands and output.

## 4. CI wiring

`.github/workflows/ci.yml` runs `node db/scripts/test-integrity-gate.mjs`
as the step immediately after `npm install`, before `Typecheck`, `Build`,
or `Test`. A future PR that reintroduces any of the covered patterns fails
CI before any other step runs, rather than being caught only if a human
happens to read that specific file during review.
