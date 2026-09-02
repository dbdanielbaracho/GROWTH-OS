-- Growth OS RC9 — Security Policy Fix (forward migration, RC8-immutable).
--
-- EXECUTION IDENTITY: this file MUST be applied by the same administrative
-- bootstrap identity that runs db/provisioning/production/01_roles.sql
-- (the provider's native superuser/master-user in production, or a local
-- superuser in disposable test environments) — NOT by growth_migrator.
-- This was discovered by physical execution, not anticipated in design:
-- ALTER FUNCTION ... OWNER TO growth_rls_helper requires the executing
-- role to be able to SET ROLE to the target role. growth_migrator cannot
-- SET ROLE growth_rls_helper (verified in the hardening round of this
-- exercise) — which is exactly the isolation property this fix depends
-- on. That isolation is what makes growth_migrator unable to install its
-- own privilege escalation path, which is correct: a migration that
-- establishes a new privilege-separation boundary legitimately needs more
-- authority than the role being separated from, and requiring the
-- administrative identity for this one file (while every other migration
-- continues to run as growth_migrator) is the correct reflection of that
-- boundary, not a limitation to work around.
--
-- This file is a FORWARD migration. It never modifies
-- db/migrations/001_initial_schema.sql, whose SHA-256
-- (b2bf18fc540bb08a0e0c17c911d91e91e9eda9d7504fa8120d5f9374eeb48b76)
-- remains the frozen RC8 canonical baseline.
--
-- Closes RC9-FINDING-001 (growth.memberships_workspace_select) and
-- RC9-FINDING-003 (growth.workspaces_member_select): both policies
-- previously granted SELECT visibility based on app.workspace_id alone,
-- without independently verifying that app.user_id holds an active
-- membership in that workspace. Physically confirmed to allow cross-tenant
-- reads before this fix.
--
-- Design history (all physically tested against disposable PostgreSQL 18.4
-- environments before being applied here, never guessed):
--   Option A (calling growth.tenant_context_valid() directly from inside
--   memberships_workspace_select) was tested and PROVEN UNSAFE: it causes
--   real infinite recursion ("stack depth limit exceeded") for legitimate
--   same-tenant users, because tenant_context_valid() is SECURITY DEFINER
--   owned by growth_migrator, growth_migrator owns growth.memberships,
--   growth.memberships has FORCE ROW LEVEL SECURITY, and the function's
--   internal query against memberships re-triggers the very policy that
--   invoked it.
--   Option B (this file): a dedicated, narrowly-scoped role
--   (growth_rls_helper) with a real BYPASSRLS attribute owns two new,
--   minimal SECURITY DEFINER functions. BYPASSRLS unconditionally bypasses
--   RLS regardless of FORCE ROW LEVEL SECURITY or table ownership, which
--   breaks the recursion structurally. growth_rls_helper has zero
--   memberships, cannot be SET ROLE'd or SET SESSION AUTHORIZATION'd by
--   any application role (physically verified), and its functions cannot
--   be modified by growth_migrator despite growth_migrator owning the
--   schema (function ownership is separate from schema ownership in
--   PostgreSQL; physically verified).

\set ON_ERROR_STOP on
SET search_path = growth, public;

-- growth_rls_helper needs base table access in addition to BYPASSRLS:
-- BYPASSRLS only skips RLS *policy* evaluation, it does not substitute for
-- the underlying table-level GRANT, which PostgreSQL still checks as a
-- separate layer (proven physically in an earlier round of this same
-- hardening exercise).
GRANT USAGE ON SCHEMA growth TO growth_rls_helper;
GRANT SELECT ON growth.memberships TO growth_rls_helper;

-- ============================================================
-- membership_row_visible: closes RC9-FINDING-001.
-- ============================================================
CREATE OR REPLACE FUNCTION growth.membership_row_visible(p_workspace_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
  SELECT
    growth.current_app_user_id() IS NOT NULL
    AND p_workspace_id = growth.current_workspace_id()
    AND EXISTS (
      SELECT 1
      FROM growth.memberships m
      WHERE m.workspace_id = p_workspace_id
        AND m.user_id = growth.current_app_user_id()
        AND m.status = 'active'
    );
$$;

ALTER FUNCTION growth.membership_row_visible(uuid) OWNER TO growth_rls_helper;
REVOKE ALL ON FUNCTION growth.membership_row_visible(uuid) FROM PUBLIC;
-- EXECUTE grants issued in db/provisioning/production/02_runtime_grants.sql,
-- not here, to keep all runtime privilege decisions in one auditable file.

DROP POLICY memberships_workspace_select ON growth.memberships;
CREATE POLICY memberships_workspace_select ON growth.memberships FOR SELECT
  USING (growth.membership_row_visible(workspace_id));

-- ============================================================
-- SECOND-ORDER FIX (discovered by physical execution of
-- db/tests/009_membership_authorization_matrix.sql after the fix above,
-- not anticipated in design): can_bootstrap_first_membership() determines
-- "is this workspace genuinely empty of any membership" via
-- NOT EXISTS (SELECT 1 FROM growth.memberships WHERE workspace_id = ...).
-- That query is a SECURITY DEFINER query against a FORCE-RLS table, so it
-- is itself subject to memberships_workspace_select — which the fix above
-- correctly tightened to require the CALLER's own active membership. An
-- outsider with zero memberships anywhere now sees zero rows via that
-- policy, so the emptiness check incorrectly concluded "workspace is
-- empty" even when it genuinely has four members, allowing the outsider
-- to self-bootstrap as owner into a non-empty workspace. Physically
-- reproduced: db/tests/009_membership_authorization_matrix.sql's final
-- assertion ("outsider self-created owner membership in non-empty
-- workspace") failed after the first-order fix, on a freshly rebuilt
-- environment, not due to test-state pollution.
--
-- Root cause: "is this workspace empty" is a workspace-wide fact that
-- must be evaluated independent of the caller's own row-level visibility
-- — it is not the same kind of question as "can this caller see this
-- row", which is what memberships_workspace_select now correctly answers.
-- The two questions were incorrectly sharing the same RLS-filtered data
-- source in the original RC8 design; tightening one broke the other.
CREATE OR REPLACE FUNCTION growth.workspace_has_any_membership(p_workspace_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
  SELECT EXISTS (SELECT 1 FROM growth.memberships m WHERE m.workspace_id = p_workspace_id);
$$;

ALTER FUNCTION growth.workspace_has_any_membership(uuid) OWNER TO growth_rls_helper;
REVOKE ALL ON FUNCTION growth.workspace_has_any_membership(uuid) FROM PUBLIC;

-- can_bootstrap_first_membership is a pre-existing RC8 function (defined
-- in 001_initial_schema.sql, already owned by growth_migrator). Replacing
-- it here does not require an ownership transfer growth_migrator cannot
-- perform (unlike the two functions above) — growth_migrator already owns
-- it and may CREATE OR REPLACE its own object. Only its internal
-- emptiness check changes; its external contract (arguments, return type,
-- the caller-must-be-self / role-must-be-owner / status-must-be-active
-- conditions) is unchanged.
CREATE OR REPLACE FUNCTION growth.can_bootstrap_first_membership(
  p_workspace_id uuid,
  p_user_id uuid,
  p_role text,
  p_status text
)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
  SELECT
    p_user_id = growth.current_app_user_id()
    AND p_role = 'owner'
    AND p_status = 'active'
    AND NOT growth.workspace_has_any_membership(p_workspace_id);
$$;

-- ============================================================
-- THIRD-ORDER FIX (discovered by physical execution of concurrency
-- scenario C1 after the second-order fix, not anticipated in design):
-- membership_write_guard() has its OWN, separate, duplicate emptiness
-- check — SELECT count(*) FROM growth.memberships WHERE workspace_id = ws
-- at what was originally lines 1321-1323 of 001_initial_schema.sql — used
-- only to decide whether an INSERT is a "first membership bootstrap"
-- (line 1328's IF membership_count = 0). This is a SEPARATE code path
-- from can_bootstrap_first_membership (called from the RLS WITH CHECK,
-- already fixed above); the trigger runs BEFORE RLS is evaluated and does
-- its own independent pre-check, which the second-order fix did not
-- touch. Same root cause: this SECURITY DEFINER query against a FORCE-RLS
-- table is itself subject to memberships_workspace_select, so a brand
-- new user with no membership yet (exactly the population this check
-- exists to test) always sees zero rows regardless of how many actually
-- exist, letting a second, third, etc. user each independently believe
-- they are "first" and bootstrap as owner.
--
-- Physically reproduced: two real concurrent sessions (C1) both
-- successfully inserted themselves as owner into the same empty-turned-
-- non-empty workspace, serialized by the advisory lock but each still
-- incorrectly evaluating membership_count = 0 for their own turn.
--
-- Every other count query inside this function (the three
-- other_active_owner_count checks, in UPDATE/DELETE) is unaffected: the
-- actor performing those operations is always independently required
-- (by the UPDATE/DELETE RLS policies) to already hold their own active
-- membership, which memberships_self_select always exposes regardless of
-- this fix, and membership_row_visible's EXISTS check then correctly
-- exposes every other row in that same workspace once that gate passes.
-- Only the bootstrap case involves an actor with zero membership by
-- definition, which is the one case that breaks.
--
-- Fix: reuse workspace_has_any_membership (already defined above,
-- growth_rls_helper-owned, genuinely bypasses RLS) instead of a directly
-- RLS-filtered count. Only the emptiness check changes; every other
-- branch of this function (UPDATE demotion protection, DELETE last-owner
-- protection, admin/owner authority checks, immutability checks) is
-- byte-for-byte unchanged from the frozen RC8 definition.
CREATE OR REPLACE FUNCTION growth.membership_write_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  ws uuid;
  actor uuid := growth.current_app_user_id();
  actor_role text;
  is_empty boolean;
  other_active_owner_count integer;
BEGIN
  IF TG_OP = 'DELETE' THEN
    ws := OLD.workspace_id;
  ELSE
    ws := NEW.workspace_id;
  END IF;

  IF actor IS NULL THEN
    RAISE EXCEPTION 'membership mutation requires app.user_id';
  END IF;

  PERFORM growth.membership_workspace_lock(ws);

  SELECT NOT growth.workspace_has_any_membership(ws) INTO is_empty;

  SELECT growth.membership_actor_role(ws) INTO actor_role;

  IF TG_OP = 'INSERT' THEN
    IF is_empty THEN
      IF NEW.user_id <> actor OR NEW.role <> 'owner' OR NEW.status <> 'active' THEN
        RAISE EXCEPTION 'first membership must bootstrap current user as active owner';
      END IF;
      RETURN NEW;
    END IF;

    IF actor_role IS NULL OR actor_role NOT IN ('owner','admin') THEN
      RAISE EXCEPTION 'membership insert requires owner/admin authority';
    END IF;

    -- Admins manage lower-privilege memberships only. Only owners may create owners/admins.
    IF actor_role = 'admin' AND NEW.role IN ('owner','admin') THEN
      RAISE EXCEPTION 'admin cannot create owner/admin membership';
    END IF;

    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.workspace_id <> OLD.workspace_id OR NEW.user_id <> OLD.user_id THEN
      RAISE EXCEPTION 'workspace_id and user_id are immutable on membership update';
    END IF;

    IF actor_role NOT IN ('owner','admin') THEN
      RAISE EXCEPTION 'membership update requires owner/admin authority';
    END IF;

    -- Admin cannot mutate peer/higher privilege and cannot promote anyone to admin/owner.
    IF actor_role = 'admin' AND (OLD.role IN ('owner','admin') OR NEW.role IN ('owner','admin')) THEN
      RAISE EXCEPTION 'admin cannot mutate owner/admin membership or promote to owner/admin';
    END IF;

    -- Never permit a transition that leaves the workspace with zero active owners.
    IF OLD.role = 'owner' AND OLD.status = 'active'
       AND (NEW.role <> 'owner' OR NEW.status <> 'active') THEN
      SELECT count(*) INTO other_active_owner_count
      FROM growth.memberships m
      WHERE m.workspace_id = ws
        AND m.user_id <> OLD.user_id
        AND m.role = 'owner'
        AND m.status = 'active';
      IF other_active_owner_count = 0 THEN
        RAISE EXCEPTION 'cannot demote/revoke the last active owner';
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    -- Self-leave is allowed except for the last active owner.
    IF actor = OLD.user_id THEN
      IF OLD.role = 'owner' AND OLD.status = 'active' THEN
        SELECT count(*) INTO other_active_owner_count
        FROM growth.memberships m
        WHERE m.workspace_id = ws
          AND m.user_id <> OLD.user_id
          AND m.role = 'owner'
          AND m.status = 'active';
        IF other_active_owner_count = 0 THEN
          RAISE EXCEPTION 'last active owner cannot leave workspace';
        END IF;
      END IF;
      RETURN OLD;
    END IF;

    IF actor_role NOT IN ('owner','admin') THEN
      RAISE EXCEPTION 'membership delete requires owner/admin authority or self-leave';
    END IF;

    -- Admin cannot delete owners/admins.
    IF actor_role = 'admin' AND OLD.role IN ('owner','admin') THEN
      RAISE EXCEPTION 'admin cannot delete owner/admin membership';
    END IF;

    IF OLD.role = 'owner' AND OLD.status = 'active' THEN
      SELECT count(*) INTO other_active_owner_count
      FROM growth.memberships m
      WHERE m.workspace_id = ws
        AND m.user_id <> OLD.user_id
        AND m.role = 'owner'
        AND m.status = 'active';
      IF other_active_owner_count = 0 THEN
        RAISE EXCEPTION 'cannot delete the last active owner';
      END IF;
    END IF;

    RETURN OLD;
  END IF;

  RAISE EXCEPTION 'unsupported membership operation %', TG_OP;
END;
$$;

-- ============================================================
-- workspace_row_visible: closes RC9-FINDING-003.
-- ============================================================
CREATE OR REPLACE FUNCTION growth.workspace_row_visible(p_workspace_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM growth.memberships m
    WHERE m.workspace_id = p_workspace_id
      AND m.user_id = growth.current_app_user_id()
      AND m.status = 'active'
  );
$$;

ALTER FUNCTION growth.workspace_row_visible(uuid) OWNER TO growth_rls_helper;
REVOKE ALL ON FUNCTION growth.workspace_row_visible(uuid) FROM PUBLIC;

DROP POLICY workspaces_member_select ON growth.workspaces;
CREATE POLICY workspaces_member_select ON growth.workspaces FOR SELECT
  USING (growth.workspace_row_visible(id));

-- EXECUTE grants issued here, not in db/provisioning/production/02_runtime_grants.sql:
-- growth_migrator does not own these functions and has no GRANT OPTION on
-- them (discovered by physical execution — attempting the grant as
-- growth_migrator fails with "permission denied for function", correctly,
-- since growth_migrator cannot act on growth_rls_helper's objects). Only
-- the administrative identity running this file can issue these grants.
--
-- The two grants below are intentionally asymmetric, each proven
-- necessary/unnecessary by physical removal, not by analogy between them:
--   membership_row_visible: app_runtime needs EXECUTE because SECURITY
--   DEFINER changes the function's internal privileges, not the caller's
--   need to invoke it — removing this grant broke every ordinary SELECT
--   on memberships. growth_migrator ALSO needs EXECUTE here because
--   membership_write_guard() (the INSERT/UPDATE/DELETE trigger on
--   memberships) runs as growth_migrator via its own SECURITY DEFINER and
--   queries memberships internally, triggering the same policy — proven
--   by physically revoking the grant and watching the trigger fail.
--   workspace_row_visible: app_runtime needs EXECUTE (same reasoning as
--   above). growth_migrator does NOT need it — workspaces has no
--   equivalent SECURITY DEFINER trigger querying the table internally;
--   proven by physically revoking growth_migrator's grant and rebuilding
--   the entire pipeline from a clean cluster, which completed with zero
--   errors.
GRANT EXECUTE ON FUNCTION growth.membership_row_visible(uuid) TO app_runtime, growth_migrator;
GRANT EXECUTE ON FUNCTION growth.workspace_row_visible(uuid) TO app_runtime;

-- growth_migrator needs EXECUTE on workspace_has_any_membership because
-- can_bootstrap_first_membership (owned by growth_migrator, SECURITY
-- DEFINER) calls it internally. app_runtime does NOT need direct EXECUTE
-- on it: once execution is inside can_bootstrap_first_membership's
-- SECURITY DEFINER context, further internal calls also execute as
-- growth_migrator, not as the original caller — proven by physical
-- removal/restoration testing, not assumed by analogy with the other two
-- functions above.
GRANT EXECUTE ON FUNCTION growth.workspace_has_any_membership(uuid) TO growth_migrator;
