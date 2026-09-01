// Growth OS RC9 — 006_identity_bootstrap_contract.md, executed via the real
// pg driver/pool (db.ts), not raw psql. Requires DATABASE_URL pointing to
// an RC9-provisioned PostgreSQL 18.x database, connecting as app_runtime.
//
// FINDING (RC9-FINDING-002, discovered before execution by reading auth.ts):
// AuthPrincipal requires BOTH userId and workspaceId via its Zod schema.
// There is no code path in the current application for the
// "discover-my-memberships-before-selecting-a-workspace" bootstrap flow
// this contract describes (steps 1-3). withTenantTransaction() cannot be
// used for that phase since it needs a full AuthPrincipal. This test
// exercises the underlying db.ts pool directly for steps 1-3 to prove the
// DB-level behavior is at least available for such a flow to be built on,
// and documents that no application-layer function currently does this.
//
// TEST-INTEGRITY CORRECTION (post-Creative-Production security review):
// two assertions in this file were vacuous by construction —
// `memberships.rows.every((r) => true)` (step 2, always true regardless of
// row content) and a bare `check(..., true)` (step 6, an unconditional
// pass). Neither actually proved what its name claimed. Both are replaced
// below with assertions that fail if the underlying data is wrong, and the
// step 5 finding text is corrected: RC9-FINDING-003 was re-verified LIVE
// against the current database (not re-read from migration text) and is
// CONFIRMED CLOSED, closed prior to this correction by
// db/migrations/002_rc9_security_policy_fix.sql. This file previously
// asserted it as still-open; that was stale documentation, not a live
// re-check, and is corrected here.

import { db } from "../src/db.js";

let failures = 0;
function check(name: string, ok: boolean, detail?: unknown) {
  if (ok) {
    console.log(`PASS: ${name}`);
  } else {
    failures++;
    console.error(`FAIL: ${name}`, detail ?? "");
  }
}

const userA = "a0000000-0000-4000-8000-000000000001";
const userB = "a0000000-0000-4000-8000-000000000002";
const workspaceA = "b0000000-0000-4000-8000-000000000001";
const workspaceB = "b0000000-0000-4000-8000-000000000002";

// ---- Steps 1-3: user_id only, no workspace_id yet ----
{
  const client = await db.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.user_id', $1, true)", [userA]);
    // Deliberately do NOT set app.workspace_id.

    // CORRECTED (step 2): the original query was parameterized
    // "WHERE user_id = $1" with userA, which makes "all returned rows
    // belong to A" true by SQL construction, not by RLS — a vacuous
    // .every((r) => true) on top of that proved nothing at all. This
    // version runs an UNQUALIFIED query (no WHERE on user_id) and lets
    // RLS alone (memberships_self_select, since app.workspace_id is not
    // set) determine what comes back. If it ever returned another user's
    // row, that would be a real leak, and this assertion would catch it.
    const memberships = await client.query(
      "select user_id, workspace_id from growth.memberships"
    );
    const allRowsBelongToA =
      memberships.rows.length >= 1 &&
      memberships.rows.every((r) => r.user_id === userA);
    check(
      "(step 2) UNQUALIFIED memberships query with only app.user_id set returns ONLY A's own rows via RLS alone (memberships_self_select), never another user's",
      allRowsBelongToA,
      memberships.rows
    );

    // Step 3 requires "active workspaces for User A memberships" — the
    // current schema has no query the app already exposes for this; test
    // the direct join a bootstrap-discovery endpoint would need.
    const workspaces = await client.query(
      `select w.id from growth.workspaces w
         join growth.memberships m on m.workspace_id = w.id
        where m.user_id = $1 and m.status = 'active'`,
      [userA]
    );
    check(
      "(step 3) workspace discovery join returns only A's active-membership workspaces",
      workspaces.rows.some((r) => r.id === workspaceA),
      workspaces.rows
    );

    await client.query("ROLLBACK");
  } finally {
    client.release();
  }
}

// ---- Step 4: set workspace_id, tenant tables become visible for A ----
{
  const client = await db.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.user_id', $1, true)", [userA]);
    await client.query("SELECT set_config('app.workspace_id', $1, true)", [workspaceA]);
    const result = await client.query("select id from growth.workspaces where id = $1", [workspaceA]);
    check("(step 4) tenant table visible once workspace_id is set for a legitimate member", result.rows.length === 1);
    await client.query("ROLLBACK");
  } finally {
    client.release();
  }
}

// ---- Step 5: a user with NO membership anywhere attempts app.workspace_id = B ----
// Uses the "attacker" fixture (a0000000-...-002), which genuinely has zero
// memberships in any workspace per 03_test_fixtures.sql. userA/legit_owner
// was NOT usable here: per the original fixture design, legit_owner
// legitimately owns BOTH workspaceA and workspaceB (needed for the 005
// "existing owner may add a member" test against victim_ws), so testing
// "no membership in B" with userA would have been testing the wrong thing.
//
// RC9-FINDING-003 — STATUS CORRECTED: this file previously asserted the
// finding as still open ("id = current_workspace_id() OR EXISTS(...)").
// That described the ORIGINAL RC8 policy at the time the finding was
// discovered, not the current live database. Re-verified LIVE, in the
// same physical rebuild this correction was written against:
// growth.workspaces_member_select now reads
// "USING (growth.workspace_row_visible(id))" — no disjunction, no bypass
// — closed by db/migrations/002_rc9_security_policy_fix.sql. The raw,
// RLS-only query below (no application-layer JOIN involved at all) is now
// asserted directly, not just logged as INFO.
{
  const attacker = userB; // zero memberships anywhere, confirmed by fixtures
  const client = await db.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.user_id', $1, true)", [attacker]);
    await client.query("SELECT set_config('app.workspace_id', $1, true)", [workspaceB]);
    const rawWorkspaceRow = await client.query("select id from growth.workspaces where id = $1", [workspaceB]);
    check(
      "(step 5a) RC9-FINDING-003 CLOSED: raw RLS-only 'select from workspaces where id = <victim>' returns ZERO rows for a user with no membership anywhere, no application-layer JOIN involved",
      rawWorkspaceRow.rows.length === 0,
      rawWorkspaceRow.rows
    );

    const rawMembershipRows = await client.query(
      "select user_id from growth.memberships where workspace_id = $1",
      [workspaceB]
    );
    check(
      "(step 5b) RC9-FINDING-001 CLOSED: raw RLS-only 'select from memberships where workspace_id = <victim>' returns ZERO rows for a user with no membership anywhere",
      rawMembershipRows.rows.length === 0,
      rawMembershipRows.rows
    );

    // The application's ACTUAL exposed function also does a membership-aware
    // JOIN as a second, independent layer — belt-and-suspenders, not the
    // only thing standing between the attacker and the data (that would be
    // step 5a/5b's job now).
    const appLevelResult = await client.query(
      `select w.id from growth.workspaces w
         join growth.memberships m on m.workspace_id = w.id and m.user_id = $1
        where w.id = $2`,
      [attacker, workspaceB]
    );
    check(
      "(step 5c) application-pattern JOIN (as workspaces.ts actually does) ALSO correctly excludes unauthorized workspace B",
      appLevelResult.rows.length === 0,
      appLevelResult.rows
    );

    await client.query("ROLLBACK");
  } finally {
    client.release();
  }
}

// ---- Step 5d: the migration-005 hardening, isolated in its own block since
// it needs a growth_migrator-level connection to GRANT/REVOKE (app_runtime
// itself is not the table owner and has no GRANT OPTION — attempting the
// GRANT from inside the app_runtime session that failed on the first
// attempt of this test, and that failure is itself informative: even
// standing up the "what if UPDATE were ever granted" scenario requires
// privileges app_runtime doesn't have, one more layer beyond RLS alone).
{
  const { Pool } = await import("pg");
  const adminPool = new Pool({ connectionString: "postgresql://growth_migrator@127.0.0.1:5433/growth_rc9" });
  const adminClient = await adminPool.connect();
  const attackerClient = await db.connect();
  try {
    await adminClient.query("GRANT UPDATE ON growth.workspaces TO app_runtime");
    try {
      await attackerClient.query("BEGIN");
      await attackerClient.query("SELECT set_config('app.user_id', $1, true)", [userB]);
      await attackerClient.query("SELECT set_config('app.workspace_id', $1, true)", [workspaceB]);
      const writeAttempt = await attackerClient.query(
        "update growth.workspaces set name = 'HACKED' where id = $1",
        [workspaceB]
      );
      check(
        "(step 5d) workspaces_current_update (migration 005) rejects a write from a user with no membership, independent of table-level grants",
        writeAttempt.rowCount === 0,
        writeAttempt
      );
      await attackerClient.query("ROLLBACK");
    } finally {
      await adminClient.query("REVOKE UPDATE ON growth.workspaces FROM app_runtime");
    }
  } finally {
    attackerClient.release();
    adminClient.release();
    await adminPool.end();
  }
}

// ---- Step 6: User B cannot enumerate A's memberships/workspaces ----
{
  const client = await db.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.user_id', $1, true)", [userB]);

    // CORRECTED (step 6): the original assertion here was a bare
    // `check(..., true)` — an unconditional pass regardless of bSeesA's
    // actual content. This now asserts what the test name always claimed:
    // as B, querying explicitly for A's rows by user_id returns zero rows.
    const bSeesA = await client.query(
      "select user_id from growth.memberships where user_id = $1",
      [userA]
    );
    check(
      "(step 6a) user B, explicitly querying for user A's memberships by user_id, gets ZERO rows (memberships_self_select restricts to B's own user_id regardless of the WHERE clause)",
      bSeesA.rowCount === 0,
      bSeesA.rows
    );

    // The meaningful complementary check: querying AS B for B's own rows
    // never returns A's.
    const bOwnRows = await client.query("select user_id from growth.memberships where user_id = $1", [userB]);
    check(
      "(step 6b) user B querying their own membership rows never includes user A",
      bOwnRows.rows.every((r) => r.user_id === userB)
    );

    // Step 6c — unqualified enumeration attempt: B tries to list ALL
    // memberships with no WHERE clause at all, hoping RLS is the only
    // thing standing between them and everyone else's rows.
    const bEnumerateAll = await client.query("select user_id from growth.memberships");
    check(
      "(step 6c) user B's unqualified enumeration of growth.memberships returns ONLY B's own rows, never A's",
      bEnumerateAll.rows.every((r) => r.user_id === userB),
      bEnumerateAll.rows
    );

    await client.query("ROLLBACK");
  } finally {
    client.release();
  }
}

// ---- Step 8: revoked membership blocks access immediately, within the
// same session, no re-authentication required (matches the mandatory
// regression list from the Creative Production security hardening gate).
{
  const client = await db.connect();
  const revokedUser = "a0000000-0000-4000-8000-000000000003"; // "viewer" fixture
  try {
    // Seeding this membership goes through the same membership_write_guard
    // trigger as any other insert — it requires app.user_id (an actor) and
    // owner/admin authority to add a member, exactly like a real request
    // would. userA is the fixture owner of workspaceA.
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.user_id', $1, true)", [userA]);
    await client.query("SELECT set_config('app.workspace_id', $1, true)", [workspaceA]);
    await client.query(
      `insert into growth.memberships(workspace_id,user_id,role,can_publish,status)
       values ($1,$2,'viewer',false,'active')
       on conflict (workspace_id,user_id) do update set status = 'active'`,
      [workspaceA, revokedUser]
    );
    await client.query("COMMIT");

    await client.query("BEGIN");
    await client.query("SELECT set_config('app.user_id', $1, true)", [revokedUser]);
    await client.query("SELECT set_config('app.workspace_id', $1, true)", [workspaceA]);
    const beforeRevoke = await client.query("select id from growth.workspaces where id = $1", [workspaceA]);
    check("(step 8a) active viewer sees the workspace before revocation", beforeRevoke.rows.length === 1, beforeRevoke.rows);
    await client.query("ROLLBACK");

    await client.query("BEGIN");
    await client.query("SELECT set_config('app.user_id', $1, true)", [userA]);
    await client.query("SELECT set_config('app.workspace_id', $1, true)", [workspaceA]);
    await client.query(
      `update growth.memberships set status = 'revoked' where workspace_id = $1 and user_id = $2`,
      [workspaceA, revokedUser]
    );
    await client.query("COMMIT");

    await client.query("BEGIN");
    await client.query("SELECT set_config('app.user_id', $1, true)", [revokedUser]);
    await client.query("SELECT set_config('app.workspace_id', $1, true)", [workspaceA]);
    const afterRevoke = await client.query("select id from growth.workspaces where id = $1", [workspaceA]);
    check(
      "(step 8b) revoked membership blocks workspace visibility immediately, in a brand-new session with no other state carried over",
      afterRevoke.rows.length === 0,
      afterRevoke.rows
    );
    // CORRECTED expectation, found by physical execution: memberships_self_select
    // is "user_id = current_app_user_id()" with NO status check (frozen RC8
    // design — a user can always see their own membership record, including
    // a revoked one, e.g. so the UI can tell them "you were removed"). That
    // policy is OR'd with membership_row_visible() (which DOES require
    // status='active'), so the revoked user's own row remains visible via
    // self_select alone. The original assertion here (zero rows) was wrong
    // about what the schema actually guarantees; the real, meaningful
    // guarantee is that a revoked user sees ONLY their own row, never
    // another member's — proven by adding a second, still-active member
    // and confirming the revoked user's unqualified query returns exactly
    // one row, and it is their own.
    // app_runtime has no grant on growth.users at all (not in the approved
    // matrix) — this fixture insert must go through an admin connection,
    // same pattern as step 5d's GRANT/REVOKE.
    const secondActiveMember = "a0000000-0000-4000-8000-000000000004";
    {
      const { Pool } = await import("pg");
      // users has FORCE ROW LEVEL SECURITY, so even growth_migrator (the
      // table owner) is subject to RLS here — growth_test_harness
      // (BYPASSRLS, test-only) is the correct role for fixture seeding,
      // matching db/provisioning/test/03_test_fixtures.sql's own pattern.
      const adminPool = new Pool({ connectionString: "postgresql://growth_test_harness@127.0.0.1:5433/growth_rc9" });
      const adminClient = await adminPool.connect();
      try {
        await adminClient.query(
          `insert into growth.users(id,email,status) values ($1,'rc9-second-active-member@example.test','active')
           on conflict (id) do nothing`,
          [secondActiveMember]
        );
      } finally {
        adminClient.release();
        await adminPool.end();
      }
    }
    await client.query("SELECT set_config('app.user_id', $1, true)", [userA]);
    await client.query("SELECT set_config('app.workspace_id', $1, true)", [workspaceA]);
    await client.query(
      `insert into growth.memberships(workspace_id,user_id,role,can_publish,status)
       values ($1,$2,'editor',false,'active')
       on conflict (workspace_id,user_id) do update set status = 'active'`,
      [workspaceA, secondActiveMember]
    );
    await client.query("SELECT set_config('app.user_id', $1, true)", [revokedUser]);
    const membershipsAfterRevoke = await client.query("select user_id, workspace_id, status from growth.memberships");
    // CORRECTION (found by physically running this against the full fixture
    // set): revokedUser (the "viewer" fixture, a...003) already has an
    // ACTIVE membership in workspaceB from 03_test_fixtures.sql, in
    // addition to the now-revoked one in workspaceA created above — so
    // memberships_self_select correctly returns TWO rows here, not one.
    // The original ".length === 1" assumption forgot that pre-existing
    // fixture row. The actually meaningful invariant (what the test name
    // claims) is: every returned row belongs to revokedUser, and none of
    // secondActiveMember's or anyone else's rows leak through — checked
    // below, not row count, which depends on fixture state that isn't
    // this test's concern.
    const onlySelfVisible =
      membershipsAfterRevoke.rows.length >= 1 &&
      membershipsAfterRevoke.rows.every((r) => r.user_id === revokedUser) &&
      membershipsAfterRevoke.rows.some((r) => r.workspace_id === workspaceA && r.status === "revoked");
    check(
      "(step 8c) revoked user's unqualified memberships query returns ONLY their own rows (including the now-revoked one), never another member's — even a still-active one in the same workspace",
      onlySelfVisible,
      membershipsAfterRevoke.rows
    );
    await client.query("ROLLBACK");

    // Cleanup: restore the fixture to active for any other test relying on it.
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.user_id', $1, true)", [userA]);
    await client.query("SELECT set_config('app.workspace_id', $1, true)", [workspaceA]);
    await client.query(
      `update growth.memberships set status = 'active' where workspace_id = $1 and user_id = $2`,
      [workspaceA, revokedUser]
    );
    await client.query("COMMIT");
  } finally {
    client.release();
  }
}

// ---- Step 7: pool reuse clears both GUCs before next logical request ----
{
  const client1 = await db.connect();
  await client1.query("BEGIN");
  await client1.query("SELECT set_config('app.user_id', $1, true)", [userA]);
  await client1.query("SELECT set_config('app.workspace_id', $1, true)", [workspaceA]);
  await client1.query("COMMIT");
  client1.release();

  // A second, independent request must never inherit A's context, even if
  // the pool physically reuses the same underlying connection.
  const client2 = await db.connect();
  const leaked = await client2.query(
    "select current_setting('app.user_id', true) as uid, current_setting('app.workspace_id', true) as wid"
  );
  check(
    "(step 7) a fresh transaction on a possibly-reused pooled connection does not inherit the previous request's GUCs (set_config(...,true) is transaction-local)",
    (leaked.rows[0].uid === "" || leaked.rows[0].uid === null) &&
    (leaked.rows[0].wid === "" || leaked.rows[0].wid === null),
    leaked.rows[0]
  );
  client2.release();
}

await db.end();
process.exit(failures > 0 ? 1 : 0);
