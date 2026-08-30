-- Growth OS RC9 — app_runtime grants.
-- Every GRANT below corresponds to exactly one YES cell in the
-- RC9 Complete Runtime Grant Matrix. No GRANT ALL. No ALTER DEFAULT
-- PRIVILEGES. Every new table added by a future migration must add its
-- own explicit grant line here after individual review — silent expansion
-- of app_runtime's surface is deliberately not automated.

\set ON_ERROR_STOP on

GRANT USAGE ON SCHEMA growth TO app_runtime;

GRANT SELECT ON growth.workspaces TO app_runtime;

GRANT SELECT, INSERT, UPDATE, DELETE ON growth.memberships TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.can_manage_memberships(uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.can_bootstrap_first_membership(uuid,uuid,text,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.tenant_context_valid(uuid) TO app_runtime;

GRANT SELECT, INSERT ON growth.content_items TO app_runtime;
GRANT SELECT, INSERT ON growth.content_versions TO app_runtime;

-- CORRECTION discovered by physical execution against PG18 (not by design
-- review): growth.content_items_workspace_isolation and
-- growth.content_versions_workspace_isolation both internally reference
-- growth.deletion_tombstones inside their USING clause (tombstone
-- exclusion). PostgreSQL RLS policies evaluate with the CALLING role's
-- privileges, so app_runtime needs SELECT on deletion_tombstones purely as
-- a transitive dependency of evaluating those two policies — no
-- application code queries deletion_tombstones directly. Without this
-- grant, app_runtime cannot read content_items/content_versions AT ALL,
-- which would have silently broken PR #6's entire content-authoring
-- feature in production. The original approved matrix marked
-- deletion_tombstones as NO RUNTIME ACCESS on the (incorrect) assumption
-- that "no route touches it" was sufficient; it does not account for
-- transitive RLS policy dependencies. This is the only cell in the
-- approved matrix changed since design approval, and it is additive
-- (SELECT only, not write) and minimal (exactly the dependency required).
GRANT SELECT ON growth.deletion_tombstones TO app_runtime;

GRANT SELECT ON growth.insights TO app_runtime;
GRANT SELECT ON growth.opportunities TO app_runtime;

-- Everything else: NO RUNTIME ACCESS by design. This includes growth.jobs
-- (explicit RC8 contract — internal, cross-tenant claimable, no runtime
-- privilege), the four global/structural tables with no workspace_id
-- (capabilities, ai_provider_policies, ai_data_routing_allowlist), and
-- aggregate_intelligence.cohort_statistics (deliberately tenant-free).
-- Every remaining growth.* table has RLS from the generic tenant-isolation
-- loop but zero grant, by the fail-closed default: NO RUNTIME ACCESS
-- until a route exercises it and a reviewer adds an explicit line here.
