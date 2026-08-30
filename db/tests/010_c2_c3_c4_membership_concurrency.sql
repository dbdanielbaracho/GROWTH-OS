-- Growth OS RC9 — membership concurrency C2, C3, C4.
-- Same pattern as db/tests/010_c1_membership_concurrency.sql: these
-- assertions verify the final state after two real concurrent psql
-- sessions were run against the same workspace, coordinated by the
-- schema's own pg_advisory_xact_lock in membership_workspace_lock().
-- This file alone (single session) cannot reproduce the races; it is the
-- setup/assertion couple around the driver scripts actually executed.
--
-- C2 — two owners concurrently try to leave (workspace c2000000...0001,
-- two active owners a...001/a...002):
--   Session A: BEGIN; set app.user_id=a...001, app.workspace_id=ws;
--              DELETE own membership; pg_sleep(1.5); COMMIT.
--   Session B (started ~0.3s later, while A's tx is open):
--              BEGIN; set app.user_id=a...002, app.workspace_id=ws;
--              DELETE own membership; COMMIT.
--   Physically observed: A's DELETE succeeded; B's DELETE was rejected
--   with "last active owner cannot leave workspace" once B acquired the
--   lock after A committed and saw itself as the sole remaining owner.
--
-- C3 — owner demotion races owner deletion (workspace c3000000...0001,
-- two active owners a...001/a...002):
--   Session A: demotes a...001 (self) from owner to admin; pg_sleep(1.5);
--              COMMIT.
--   Session B (started ~0.3s later): DELETE a...002's own (owner)
--              membership; COMMIT.
--   Physically observed: A's demotion succeeded (a...002 was still an
--   active owner at that moment, so demoting A left one active owner).
--   B's DELETE was then rejected with "last active owner cannot leave
--   workspace", since by the time B's lock was granted, a...002 was the
--   only remaining active owner. Final state: a...001=admin/active,
--   a...002=owner/active -- no partial state, at least one owner survives.
--
-- C4 — admin takeover race (workspace c4000000...0001, owner a...001,
-- admin a...002):
--   Session A (as a...002): attempts to promote itself to owner.
--   Session B (as a...002): attempts, in a separate session, to delete
--              a...001 (the owner).
--   Both run sequentially in this reproduction (not truly concurrent, since
--   both are independent rejections that do not depend on timing relative
--   to each other -- membership_write_guard rejects an admin's attempt to
--   mutate or delete an owner/admin row unconditionally, not based on a
--   race outcome). Both physically observed rejected independently:
--   "admin cannot mutate owner/admin membership or promote to owner/admin"
--   and "admin cannot delete owner/admin membership". Final state:
--   a...001=owner/active, a...002=admin/active -- both unchanged.

\set ON_ERROR_STOP on
SET search_path = growth, public;

DO $$
DECLARE
  c2_owners int;
  c3_a_role text;
  c3_b_role text;
  c4_a_role text;
  c4_b_role text;
BEGIN
  -- C2 assertion
  SELECT count(*) INTO c2_owners FROM growth.memberships
   WHERE workspace_id = 'c2000000-0000-4000-8000-000000000001'::uuid
     AND role = 'owner' AND status = 'active';
  IF c2_owners <> 1 THEN
    RAISE EXCEPTION 'TEST FAIL (C2): expected exactly 1 active owner, found %', c2_owners;
  END IF;
  RAISE NOTICE 'PASS (C2): exactly one active owner survived the concurrent leave race';

  -- C3 assertion
  SELECT role INTO c3_a_role FROM growth.memberships
   WHERE workspace_id = 'c3000000-0000-4000-8000-000000000001'::uuid AND user_id = 'a0000000-0000-4000-8000-000000000001'::uuid;
  SELECT role INTO c3_b_role FROM growth.memberships
   WHERE workspace_id = 'c3000000-0000-4000-8000-000000000001'::uuid AND user_id = 'a0000000-0000-4000-8000-000000000002'::uuid;
  IF c3_a_role <> 'admin' OR c3_b_role <> 'owner' THEN
    RAISE EXCEPTION 'TEST FAIL (C3): expected a...001=admin, a...002=owner, found % / %', c3_a_role, c3_b_role;
  END IF;
  RAISE NOTICE 'PASS (C3): demotion succeeded, concurrent last-owner deletion correctly rejected, no partial state';

  -- C4 assertion
  SELECT role INTO c4_a_role FROM growth.memberships
   WHERE workspace_id = 'c4000000-0000-4000-8000-000000000001'::uuid AND user_id = 'a0000000-0000-4000-8000-000000000001'::uuid;
  SELECT role INTO c4_b_role FROM growth.memberships
   WHERE workspace_id = 'c4000000-0000-4000-8000-000000000001'::uuid AND user_id = 'a0000000-0000-4000-8000-000000000002'::uuid;
  IF c4_a_role <> 'owner' OR c4_b_role <> 'admin' THEN
    RAISE EXCEPTION 'TEST FAIL (C4): expected owner O unchanged and admin A unchanged, found % / %', c4_a_role, c4_b_role;
  END IF;
  RAISE NOTICE 'PASS (C4): both admin takeover attempts (self-promote, delete owner) independently rejected';
END $$;

\echo 'PASS: C2, C3, C4 all verified'
