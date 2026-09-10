-- Growth OS — production helper privileges for protected provider/publication reads.
-- Production bootstrap creates canonical tables as the database owner, while
-- provider/publication helpers run as growth_migrator SECURITY DEFINER functions.
-- Grant only the helper's required table privileges; app_runtime remains closed.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_migrator') THEN
    RAISE EXCEPTION '045 requires growth_migrator role';
  END IF;
END $;

CREATE TABLE IF NOT EXISTS growth.production_helper_privileges_045 (
  id boolean PRIMARY KEY DEFAULT true,
  applied_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO growth.production_helper_privileges_045(id)
VALUES (true)
ON CONFLICT (id) DO NOTHING;

GRANT USAGE ON SCHEMA growth TO growth_migrator;

-- Provider status and authorization helpers.
GRANT SELECT ON
  growth.managed_accounts,
  growth.platform_connections,
  growth.social_accounts
TO growth_migrator;

GRANT SELECT, INSERT, UPDATE, DELETE ON
  growth.provider_credentials
TO growth_migrator;

GRANT INSERT, UPDATE ON
  growth.platform_connections,
  growth.social_accounts
TO growth_migrator;

-- Instagram media and metric ingestion helpers.
GRANT SELECT, INSERT, UPDATE ON
  growth.instagram_media,
  growth.metric_observations
TO growth_migrator;

-- Publication status projection and its tenant-scoped helper chain.
GRANT SELECT ON
  growth.publication_intents,
  growth.content_versions,
  growth.content_items
TO growth_migrator;

-- Growth intelligence helpers may materialize factual, insight, and
-- opportunity projections without opening those tables to app_runtime.
GRANT SELECT, INSERT, UPDATE ON
  growth.factual_signals,
  growth.insights,
  growth.opportunities,
  growth.insight_evidence,
  growth.opportunity_evidence
TO growth_migrator;

DO $$
BEGIN
  IF NOT has_table_privilege('growth_migrator', 'growth.managed_accounts', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.platform_connections', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.social_accounts', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.publication_intents', 'SELECT')
     OR NOT has_table_privilege('growth_migrator', 'growth.instagram_media', 'INSERT')
  THEN
    RAISE EXCEPTION '045 helper privilege reconciliation failed';
  END IF;
END $$;

COMMIT;
