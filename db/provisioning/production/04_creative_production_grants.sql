-- Growth OS — Creative Production runtime grants.
-- Applied strictly AFTER db/migrations/004_creative_production.sql —
-- RLS and policies must already exist before app_runtime gets any
-- access. This is the physical enforcement of the v0.5.2 requirement:
-- "nenhuma tabela nova pode depender de 'sem grant ainda' como
-- mecanismo de segurança" — RLS is the mechanism; grants come after and
-- rely on it, never the other way around.

\set ON_ERROR_STOP on

GRANT SELECT, INSERT ON growth.creative_requests TO app_runtime;
GRANT SELECT, INSERT, UPDATE ON growth.creative_generations TO app_runtime;
-- No DELETE: retries create new rows (append-only-ish history per
-- creative_request), matching the pattern already established for
-- content_approvals.

GRANT SELECT, INSERT ON growth.media_asset_lineage TO app_runtime;
-- No UPDATE/DELETE: lineage edges are immutable once created — the
-- composition history of an asset should not be silently rewritten.

-- media_assets already had SELECT, INSERT from Post-RC9 Content; the new
-- columns (content_version_id, creative_generation_id, purpose) ride on
-- those existing grants, no new GRANT line needed for them.
