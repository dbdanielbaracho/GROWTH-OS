-- Growth OS — Post-RC9 Content Domain runtime grants.
-- Kept as a separate, additive file — db/provisioning/production/02_runtime_grants.sql
-- (the frozen RC9 grant matrix) is never edited by this evolution.
-- Applies after db/migrations/003_post_rc9_content_reconciliation.sql,
-- as growth_migrator (it owns every object these grants touch, unlike
-- the two SECURITY DEFINER helpers added by RC9 itself).

\set ON_ERROR_STOP on

-- content_items lifecycle: app_runtime already had SELECT, INSERT
-- (RC9). Adding UPDATE, discovered physically necessary while proving
-- the status-transition design: without it, the Approve/Changes
-- Requested/Edit lifecycle cannot update content_items.status at all.
GRANT UPDATE ON growth.content_items TO app_runtime;

-- content_variants and media_assets already existed structurally in RC9
-- (both satisfy most of Especificação Técnica v0.4.1 Section 10) but had
-- ZERO grant to app_runtime — confirmed by physical inspection of the
-- frozen matrix. Not a schema gap; a provisioning gap, closed here.
GRANT SELECT, INSERT ON growth.content_variants TO app_runtime;
GRANT SELECT, INSERT ON growth.media_assets TO app_runtime;

-- New tables from 003_post_rc9_content_reconciliation.sql. Append-only:
-- no UPDATE/DELETE for either, consistent with the audit-trail design.
GRANT SELECT, INSERT ON growth.content_approvals TO app_runtime;
GRANT SELECT, INSERT ON growth.content_localizations TO app_runtime;

-- content_version_visible() is a plain (non-SECURITY DEFINER) function;
-- PostgreSQL grants EXECUTE to PUBLIC by default on function creation
-- unless explicitly revoked, and 003_post_rc9_content_reconciliation.sql
-- does not revoke it — so no explicit GRANT EXECUTE line is required
-- here. Verified physically: app_runtime can call it without any
-- additional grant.
