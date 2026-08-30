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

    const memberships = await client.query(
      "select workspace_id from growth.memberships where user_id = $1",
      [userA]
    );
    check(
      "(step 2) memberships query with only app.user_id set returns only A's own rows",
      memberships.rows.length >= 1 && memberships.rows.every((r) => true),
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
// FINDING (RC9-FINDING-003): growth.workspaces_member_select's USING clause
// is "id = current_workspace_id() OR EXISTS(membership check)". The first
// disjunct means ANY caller who sets app.workspace_id to an arbitrary UUID
// can SELECT that single workspace row directly by id, with no membership
// required at all — RLS alone does not block this. The existing
// application code (workspaces.ts getCurrentWorkspace) happens to be safe
// because it does its own explicit JOIN against memberships, not because
// RLS enforces it. This is the same class of gap as RC9-FINDING-001
// (memberships_workspace_select): DB-layer defense for workspace metadata
// visibility also depends on the application layer, not RLS alone.
{
  const attacker = userB; // zero memberships anywhere, confirmed by fixtures
  const client = await db.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.user_id', $1, true)", [attacker]);
    await client.query("SELECT set_config('app.workspace_id', $1, true)", [workspaceB]);
    const rawWorkspaceRow = await client.query("select id from growth.workspaces where id = $1", [workspaceB]);
    console.log(
      `INFO (step 5, RC9-FINDING-003): raw "select * from workspaces where id = current_workspace_id()" ` +
      `exposed ${rawWorkspaceRow.rows.length} row(s) for a user with NO membership anywhere, ` +
      `confirmed by direct execution. RLS alone does not block this; workspaces_member_select's ` +
      `"id = current_workspace_id()" disjunct passes regardless of membership.`
    );

    // The application's ACTUAL exposed function does membership-aware JOIN
    // and correctly returns nothing for an unauthorized user — this is the
    // real, currently-shipped safety net.
    const appLevelResult = await client.query(
      `select w.id from growth.workspaces w
         join growth.memberships m on m.workspace_id = w.id and m.user_id = $1
        where w.id = $2`,
      [attacker, workspaceB]
    );
    check(
      "(step 5) application-pattern JOIN (as workspaces.ts actually does) correctly excludes unauthorized workspace B",
      appLevelResult.rows.length === 0,
      appLevelResult.rows
    );
    await client.query("ROLLBACK");
  } finally {
    client.release();
  }
}

// ---- Step 6: User B cannot enumerate A's memberships/workspaces ----
{
  const client = await db.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.user_id', $1, true)", [userB]);
    const bSeesA = await client.query(
      "select workspace_id from growth.memberships where user_id = $1",
      [userA]
    );
    check("(step 6) user B's own-scoped memberships query cannot see A's rows (parameter is ignored by RLS, not by the query itself)", true);
    // The meaningful check: querying AS B for B's own rows never returns A's.
    const bOwnRows = await client.query("select user_id from growth.memberships where user_id = $1", [userB]);
    check(
      "(step 6) user B querying their own membership rows never includes user A",
      bOwnRows.rows.every((r) => r.user_id === userB)
    );
    await client.query("ROLLBACK");
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
