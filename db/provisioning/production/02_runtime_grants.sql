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
