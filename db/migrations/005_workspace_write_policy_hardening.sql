-- Growth OS — Workspace write-policy hardening (forward migration).
--
-- Triggered by a systematic RLS audit requested during Creative Production
-- remote-persistence review: every policy in growth.* was queried live
-- from pg_policy and checked for the RC9-FINDING-001/003 class of bug
-- (a disjunction or bare check that grants access via current_workspace_id()
-- alone, without independently verifying real membership).
--
-- RC9-FINDING-001 (memberships_workspace_select) and RC9-FINDING-003
-- (workspaces_member_select) were RE-VERIFIED LIVE against this exact
-- database, not merely re-read from migration text: an attacker with zero
-- memberships anywhere was seated as app_runtime, set app.workspace_id to
-- a workspace it does not belong to, and both
--   SELECT * FROM growth.workspaces WHERE id = <victim>
--   SELECT * FROM growth.memberships WHERE workspace_id = <victim>
-- returned zero rows. Both findings are CONFIRMED ALREADY CLOSED by
-- db/migrations/002_rc9_security_policy_fix.sql (workspace_row_visible(),
-- membership_row_visible()) — this migration does not touch either policy
-- again; doing so would be a no-op dressed up as a fix.
--
-- The audit surfaced ONE additional, structurally similar gap that RC8
-- never closed: workspaces_current_update USING (id = current_workspace_id())
-- has no membership check of its own at all — not even a same-class
-- disjunction, just a bare tenant-id equality. It is NOT currently
-- exploitable: physically confirmed that app_runtime has zero UPDATE grant
-- on growth.workspaces at the table level (has_table_privilege = false),
-- and a live UPDATE attempt as app_runtime with an attacker identity and a
-- victim workspace_id was rejected with 42501 (permission denied for table
-- workspaces) before RLS was ever evaluated. But per this project's own
-- stated principle (Creative Production v0.5.2 freeze record: "RLS is the
-- mechanism; grants come after and rely on it, never the other way
-- around"), a table-level grant being absent today is not a substitute for
-- RLS correctness — a future grant change (e.g. adding UPDATE for a
-- workspace-settings feature) would silently reintroduce a real
-- cross-tenant write. Closed here, proactively, before that ever happens.
--
-- workspaces_current_insert is deliberately LEFT UNCHANGED: it is what
-- lets a brand-new workspace be created at all (the id is fresh; no
-- membership can possibly exist yet for it — membership bootstrap happens
-- in a subsequent INSERT into growth.memberships, gated by its own
-- can_bootstrap_first_membership() check). Adding a membership requirement
-- here would break workspace creation entirely, not harden anything. Its
-- current safety (zero INSERT grant to app_runtime, physically confirmed)
-- is the actual intended control for this policy, not an oversight.

\set ON_ERROR_STOP on
SET search_path = growth, public;

-- can_manage_memberships(uuid) already exists (RC8, growth_migrator-owned,
-- already GRANTed to app_runtime for the memberships policies) — reused
-- here rather than duplicated. An active owner/admin of a workspace may
-- update that workspace's own settings; nobody else may, regardless of
-- what app.workspace_id happens to be set to.
DROP POLICY workspaces_current_update ON growth.workspaces;
CREATE POLICY workspaces_current_update ON growth.workspaces FOR UPDATE
  USING (id = growth.current_workspace_id() AND growth.can_manage_memberships(id))
  WITH CHECK (id = growth.current_workspace_id() AND growth.can_manage_memberships(id));
