-- Growth OS canonical initial schema
-- Candidate for DDL v1.0 freeze
-- Target: PostgreSQL 18.x (final gate must run on the exact deployed patch version)
-- Authority: Growth OS Technical Specification v0.4.1 FROZEN + accepted DDL v0.1-v0.3 findings

BEGIN;

CREATE SCHEMA IF NOT EXISTS growth;
CREATE SCHEMA IF NOT EXISTS aggregate_intelligence;

SET search_path = growth, public;

-- ============================================================
-- 0. Global identity / tenant root
-- ============================================================

CREATE TABLE users (
  id uuid PRIMARY KEY,
  email text NOT NULL,
  status text NOT NULL CHECK (status IN ('active','disabled')),
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX users_email_lower_uq ON users (lower(email));

CREATE TABLE workspaces (
  id uuid PRIMARY KEY,
  name text NOT NULL,
  default_market text NOT NULL,
  default_language text NOT NULL,
  default_timezone text NOT NULL,
  status text NOT NULL CHECK (status IN ('active','suspended','deleting')),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE memberships (
  workspace_id uuid NOT NULL REFERENCES workspaces(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('owner','admin','editor','viewer')),
  can_publish boolean NOT NULL DEFAULT false,
  status text NOT NULL CHECK (status IN ('active','invited','revoked')),
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (workspace_id,user_id)
);

-- ============================================================
-- 1. Managed accounts / authority / consent
-- ============================================================

CREATE TABLE managed_accounts (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  owner_type text NOT NULL CHECK (owner_type IN ('direct','agency_managed')),
  authority_status text NOT NULL CHECK (authority_status IN ('pending','contractually_granted','revoked')),
  contribution_eligibility text NOT NULL CHECK (contribution_eligibility IN ('private_only','eligible_pending_review','eligible')),
  authority_clause_ref text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id)
);

CREATE TABLE authority_history (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL,
  managed_account_id uuid NOT NULL,
  owner_type text NOT NULL CHECK (owner_type IN ('direct','agency_managed')),
  authority_status text NOT NULL CHECK (authority_status IN ('pending','contractually_granted','revoked')),
  contribution_eligibility text NOT NULL CHECK (contribution_eligibility IN ('private_only','eligible_pending_review','eligible')),
  authority_clause_ref text,
  effective_from timestamptz NOT NULL,
  effective_to timestamptz,
  recorded_at timestamptz NOT NULL DEFAULT now(),
  CHECK (effective_to IS NULL OR effective_to > effective_from),
  UNIQUE (workspace_id,id),
  FOREIGN KEY (workspace_id,managed_account_id)
    REFERENCES managed_accounts(workspace_id,id)
);
CREATE UNIQUE INDEX authority_history_one_open
  ON authority_history(managed_account_id)
  WHERE effective_to IS NULL;
CREATE INDEX authority_history_lookup_idx
  ON authority_history(workspace_id,managed_account_id,effective_from DESC);

CREATE TABLE consent_events (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  managed_account_id uuid,
  consent_type text NOT NULL,
  decision text NOT NULL CHECK (decision IN ('granted','denied','revoked')),
  policy_version text NOT NULL,
  effective_at timestamptz NOT NULL,
  actor_user_id uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id),
  FOREIGN KEY (workspace_id,managed_account_id)
    REFERENCES managed_accounts(workspace_id,id)
);

-- ============================================================
-- 2. Platform connections / accounts / capability registry
-- ============================================================

CREATE TABLE platform_connections (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  managed_account_id uuid,
  platform text NOT NULL,
  state text NOT NULL CHECK (state IN ('authorizing','connected','degraded','reauth_required','failed','revoked','disconnected')),
  credential_ciphertext bytea,
  granted_scopes text[] NOT NULL DEFAULT '{}',
  token_expires_at timestamptz,
  last_success_at timestamptz,
  last_failure_at timestamptz,
  error_class text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id),
  FOREIGN KEY (workspace_id,managed_account_id)
    REFERENCES managed_accounts(workspace_id,id)
);

CREATE TABLE social_accounts (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  managed_account_id uuid NOT NULL,
  platform_connection_id uuid NOT NULL,
  platform text NOT NULL,
  provider_account_id text NOT NULL,
  handle text,
  account_type text,
  market text,
  timezone text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id),
  UNIQUE (platform,provider_account_id),
  FOREIGN KEY (workspace_id,managed_account_id)
    REFERENCES managed_accounts(workspace_id,id),
  FOREIGN KEY (workspace_id,platform_connection_id)
    REFERENCES platform_connections(workspace_id,id)
);

CREATE TABLE capabilities (
  id uuid PRIMARY KEY,
  platform text NOT NULL,
  market text NOT NULL,
  account_type text NOT NULL,
  capability text NOT NULL,
  status text NOT NULL CHECK (status IN ('enabled','disabled','degraded','validation_required')),
  required_scopes text[] NOT NULL DEFAULT '{}',
  limits jsonb NOT NULL DEFAULT '{}'::jsonb,
  media_constraints jsonb NOT NULL DEFAULT '{}'::jsonb,
  app_review_status text CHECK (app_review_status IS NULL OR app_review_status IN ('not_submitted','in_review','approved','rejected')),
  provider_api_version text,
  deprecation_at timestamptz,
  sunset_notice_ref text,
  incident_ref text,
  last_incident_at timestamptz,
  validated_at timestamptz,
  evidence_ref text,
  evidence_status text NOT NULL DEFAULT 'unverified',
  adapter_version text,
  kill_switch boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(platform,market,account_type,capability)
);

-- ============================================================
-- 3. Content / versions / assets
-- ============================================================

CREATE TABLE content_items (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  objective text,
  market text NOT NULL,
  language text NOT NULL,
  platform_target text,
  source_type text NOT NULL,
  status text NOT NULL,
  created_by uuid REFERENCES users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id)
);

CREATE TABLE content_versions (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL,
  content_item_id uuid NOT NULL,
  version_no integer NOT NULL CHECK (version_no > 0),
  body text,
  structure_json jsonb NOT NULL DEFAULT '{}'::jsonb,
  ai_provenance jsonb,
  checksum text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id),
  UNIQUE (content_item_id,version_no),
  UNIQUE (content_item_id,checksum),
  FOREIGN KEY (workspace_id,content_item_id)
    REFERENCES content_items(workspace_id,id)
);

CREATE TABLE media_assets (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  storage_ref text NOT NULL,
  mime_type text NOT NULL,
  checksum text NOT NULL,
  rights_status text NOT NULL,
  source_class text NOT NULL,
  bytes bigint CHECK (bytes IS NULL OR bytes >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id),
  UNIQUE (workspace_id,checksum,storage_ref)
);

-- ============================================================
-- 4. Publishing / idempotency / reconciliation
-- ============================================================

CREATE TABLE publication_intents (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  social_account_id uuid NOT NULL,
  content_version_id uuid NOT NULL,
  request_nonce uuid NOT NULL,
  idempotency_key text NOT NULL,
  idempotency_key_source text NOT NULL DEFAULT 'client_persisted_nonce',
  status text NOT NULL CHECK(status IN (
    'ready','scheduled','queued','sending','failed_retryable','retrying',
    'needs_user_action','confirmed','cancelled','superseded'
  )),
  scheduled_for timestamptz,
  supersedes_intent_id uuid,
  provider_content_id text,
  provider_permalink text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (supersedes_intent_id IS NULL OR supersedes_intent_id <> id),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id),
  UNIQUE (workspace_id,idempotency_key),
  UNIQUE (workspace_id,request_nonce),
  UNIQUE (workspace_id,id,social_account_id,content_version_id),
  FOREIGN KEY (workspace_id,social_account_id)
    REFERENCES social_accounts(workspace_id,id),
  FOREIGN KEY (workspace_id,content_version_id)
    REFERENCES content_versions(workspace_id,id),
  FOREIGN KEY (workspace_id,supersedes_intent_id,social_account_id,content_version_id)
    REFERENCES publication_intents(workspace_id,id,social_account_id,content_version_id)
);

CREATE UNIQUE INDEX publication_one_active_per_version_account
ON publication_intents(social_account_id,content_version_id)
WHERE status IN ('ready','scheduled','queued','sending','failed_retryable','retrying','needs_user_action','confirmed');

CREATE INDEX publication_recovery_idx
ON publication_intents(workspace_id,status,scheduled_for,updated_at);

CREATE TABLE publication_attempts (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  publication_intent_id uuid NOT NULL,
  attempt_no integer NOT NULL CHECK(attempt_no > 0),
  request_hash text NOT NULL,
  provider_request_id text,
  result_class text NOT NULL,
  http_status integer,
  provider_content_id text,
  started_at timestamptz NOT NULL,
  provider_responded_at timestamptz,
  persisted_at timestamptz,
  raw_payload_ref text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id),
  UNIQUE (publication_intent_id,attempt_no),
  FOREIGN KEY (workspace_id,publication_intent_id)
    REFERENCES publication_intents(workspace_id,id)
);

CREATE TABLE publication_reconciliation_attempts (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  publication_intent_id uuid NOT NULL,
  attempt_no integer NOT NULL CHECK (attempt_no > 0),
  method text NOT NULL CHECK(method IN ('exact','resumable_status','fuzzy_recent_content','manual')),
  confidence text NOT NULL CHECK(confidence IN ('exact','high','medium','low','none')),
  reconciliation_status text NOT NULL CHECK(reconciliation_status IN ('pending','matched','not_found','ambiguous','escalated')),
  candidate_provider_content_id text,
  evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id),
  UNIQUE (publication_intent_id,attempt_no),
  FOREIGN KEY (workspace_id,publication_intent_id)
    REFERENCES publication_intents(workspace_id,id)
);

-- Advisory lock keys are computed by the application using a versioned SHA-256 -> signed-int64 algorithm.
-- PostgreSQL internal undocumented hash functions are deliberately NOT used.

-- ============================================================
-- 5. Durable jobs / transactional outbox
-- ============================================================

CREATE TABLE outbox_events (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  aggregate_type text NOT NULL,
  aggregate_id uuid NOT NULL,
  event_type text NOT NULL,
  payload jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  leased_until timestamptz,
  processed_at timestamptz,
  attempt_count integer NOT NULL DEFAULT 0,
  UNIQUE (workspace_id,id)
);
CREATE INDEX outbox_claim_idx ON outbox_events(processed_at,leased_until,created_at);

CREATE TABLE jobs (
  id uuid PRIMARY KEY,
  workspace_id uuid REFERENCES workspaces(id),
  job_type text NOT NULL,
  operation_key text NOT NULL,
  payload jsonb NOT NULL,
  state text NOT NULL CHECK(state IN ('queued','leased','retry_wait','done','dead')),
  available_at timestamptz NOT NULL DEFAULT now(),
  leased_until timestamptz,
  attempts integer NOT NULL DEFAULT 0,
  last_error_class text
);

-- jobs is an internal worker-control table. It is intentionally not tenant-RLS-scoped because workers claim across tenants;
-- API runtime access is forbidden by the runtime-role gate. Tenant and global operation keys use separate uniqueness domains.
CREATE UNIQUE INDEX jobs_tenant_operation_uq
  ON jobs(workspace_id,job_type,operation_key)
  WHERE workspace_id IS NOT NULL;
CREATE UNIQUE INDEX jobs_global_operation_uq
  ON jobs(job_type,operation_key)
  WHERE workspace_id IS NULL;
CREATE INDEX jobs_claim_idx ON jobs(state,available_at,leased_until);

-- ============================================================
-- 6. Metrics / baselines
-- ============================================================

CREATE TABLE metric_observations (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  social_account_id uuid NOT NULL,
  content_item_id uuid,
  provider_content_id text NOT NULL,
  metric_name text NOT NULL,
  raw_value numeric NOT NULL,
  unit text,
  observed_at timestamptz NOT NULL,
  provider_effective_at timestamptz,
  source_timezone text,
  provider_api_version text,
  source_schema_version text,
  collection_method text NOT NULL CHECK(collection_method IN ('webhook','polling','backfill','manual_import')),
  raw_payload_ref text,
  adapter_version text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id),
  FOREIGN KEY (workspace_id,social_account_id)
    REFERENCES social_accounts(workspace_id,id),
  FOREIGN KEY (workspace_id,content_item_id)
    REFERENCES content_items(workspace_id,id)
);
CREATE INDEX metric_obs_lookup
ON metric_observations(workspace_id,social_account_id,provider_content_id,metric_name,observed_at DESC);

CREATE TABLE metric_normalized (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  content_item_id uuid NOT NULL,
  metric_key text NOT NULL,
  value numeric NOT NULL,
  unit text,
  window_start timestamptz,
  window_end timestamptz,
  logic_version text NOT NULL,
  computed_at timestamptz NOT NULL DEFAULT now(),
  CHECK (window_end IS NULL OR window_start IS NULL OR window_end >= window_start),
  UNIQUE (workspace_id,id),
  UNIQUE NULLS NOT DISTINCT (content_item_id,metric_key,window_start,window_end,logic_version),
  FOREIGN KEY (workspace_id,content_item_id)
    REFERENCES content_items(workspace_id,id)
);

CREATE TABLE metric_completeness (
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  content_item_id uuid NOT NULL,
  metric_key text NOT NULL,
  available boolean NOT NULL,
  last_checked_at timestamptz NOT NULL,
  reason_unavailable text,
  PRIMARY KEY(workspace_id,content_item_id,metric_key),
  FOREIGN KEY (workspace_id,content_item_id)
    REFERENCES content_items(workspace_id,id)
);

CREATE TABLE baselines (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  social_account_id uuid,
  metric_key text NOT NULL,
  segment_key jsonb NOT NULL DEFAULT '{}'::jsonb,
  window_start timestamptz NOT NULL,
  window_end timestamptz NOT NULL,
  statistic jsonb NOT NULL,
  sample_size integer NOT NULL CHECK(sample_size >= 0),
  logic_version text NOT NULL,
  computed_at timestamptz NOT NULL DEFAULT now(),
  CHECK (window_end > window_start),
  UNIQUE (workspace_id,id),
  FOREIGN KEY (workspace_id,social_account_id)
    REFERENCES social_accounts(workspace_id,id)
);

-- ============================================================
-- 7. Insights / evidence / feed
-- ============================================================

CREATE TABLE insights (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  social_account_id uuid,
  state text NOT NULL CHECK(state IN ('confirmed_account','account_hypothesis','general_practice','insufficient_signal')),
  claim text NOT NULL,
  metric_definition jsonb,
  sample_size integer,
  confidence jsonb,
  logic_version text NOT NULL,
  valid_from timestamptz NOT NULL,
  expires_at timestamptz,
  demoted_from uuid,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (demoted_from IS NULL OR demoted_from <> id),
  UNIQUE (workspace_id,id),
  FOREIGN KEY (workspace_id,social_account_id)
    REFERENCES social_accounts(workspace_id,id),
  FOREIGN KEY (workspace_id,demoted_from)
    REFERENCES insights(workspace_id,id)
);

CREATE TABLE insight_evidence (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  insight_id uuid NOT NULL,
  evidence_type text NOT NULL,
  evidence_ref text NOT NULL,
  source_class text NOT NULL CHECK(source_class IN ('owned','open','licensed','network','general')),
  weight numeric,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id),
  UNIQUE(insight_id,evidence_type,evidence_ref),
  FOREIGN KEY (workspace_id,insight_id)
    REFERENCES insights(workspace_id,id)
);

CREATE TABLE feed_cards (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  social_account_id uuid,
  card_type text NOT NULL,
  schema_version integer NOT NULL CHECK(schema_version > 0),
  priority integer NOT NULL,
  status text NOT NULL CHECK(status IN ('active','acted','dismissed','expired')),
  source_entity_type text,
  source_entity_id uuid,
  payload_snapshot jsonb NOT NULL,
  evidence_snapshot jsonb,
  visible_from timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id),
  FOREIGN KEY (workspace_id,social_account_id)
    REFERENCES social_accounts(workspace_id,id)
);
CREATE INDEX feed_active_idx ON feed_cards(workspace_id,status,priority DESC,visible_from DESC);

CREATE TABLE feed_events (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  feed_card_id uuid NOT NULL,
  user_id uuid REFERENCES users(id),
  event_type text NOT NULL CHECK(event_type IN ('shown','opened','accepted','ignored','dismissed','action_completed')),
  card_snapshot jsonb NOT NULL,
  occurred_at timestamptz NOT NULL DEFAULT now(),
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  UNIQUE (workspace_id,id),
  FOREIGN KEY (workspace_id,feed_card_id)
    REFERENCES feed_cards(workspace_id,id)
);

-- ============================================================
-- 8. Opportunities
-- ============================================================

CREATE TABLE opportunities (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  social_account_id uuid,
  market text NOT NULL,
  platform text NOT NULL,
  status text NOT NULL,
  score numeric,
  confidence jsonb,
  ranking_version text NOT NULL,
  expires_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id),
  FOREIGN KEY (workspace_id,social_account_id)
    REFERENCES social_accounts(workspace_id,id)
);

CREATE TABLE opportunity_evidence (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  opportunity_id uuid NOT NULL,
  source_class text NOT NULL,
  evidence_ref text NOT NULL,
  observed_at timestamptz,
  UNIQUE (workspace_id,id),
  UNIQUE(opportunity_id,source_class,evidence_ref),
  FOREIGN KEY (workspace_id,opportunity_id)
    REFERENCES opportunities(workspace_id,id)
);

-- ============================================================
-- 9. Experiments / multiply / causal instrumentation
-- ============================================================

CREATE TABLE hypotheses (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  question text NOT NULL,
  expected_direction text,
  primary_metric text NOT NULL,
  practical_effect_threshold numeric,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id)
);

CREATE TABLE experiments (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  hypothesis_id uuid NOT NULL,
  design_type text NOT NULL,
  status text NOT NULL,
  eligibility_rule jsonb NOT NULL,
  started_at timestamptz,
  ended_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (ended_at IS NULL OR started_at IS NULL OR ended_at >= started_at),
  UNIQUE (workspace_id,id),
  FOREIGN KEY (workspace_id,hypothesis_id)
    REFERENCES hypotheses(workspace_id,id)
);

CREATE TABLE content_variants (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  source_content_version_id uuid NOT NULL,
  variant_content_version_id uuid NOT NULL,
  hypothesis_id uuid,
  similarity_status text,
  override_by uuid REFERENCES users(id),
  override_reason text,
  override_performance_linked boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (source_content_version_id <> variant_content_version_id),
  UNIQUE (workspace_id,id),
  UNIQUE(source_content_version_id,variant_content_version_id),
  FOREIGN KEY (workspace_id,source_content_version_id)
    REFERENCES content_versions(workspace_id,id),
  FOREIGN KEY (workspace_id,variant_content_version_id)
    REFERENCES content_versions(workspace_id,id),
  FOREIGN KEY (workspace_id,hypothesis_id)
    REFERENCES hypotheses(workspace_id,id)
);

CREATE TABLE exposures (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  experiment_id uuid NOT NULL,
  content_variant_id uuid,
  social_account_id uuid NOT NULL,
  wave_number integer CHECK(wave_number IS NULL OR wave_number > 0),
  multiplication_eligible_at timestamptz NOT NULL,
  assigned_at timestamptz,
  multiplication_released_at timestamptz,
  provider_content_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (assigned_at IS NULL OR assigned_at >= multiplication_eligible_at),
  CHECK (multiplication_released_at IS NULL OR multiplication_released_at >= multiplication_eligible_at),
  UNIQUE (workspace_id,id),
  UNIQUE(experiment_id,social_account_id,content_variant_id),
  FOREIGN KEY (workspace_id,experiment_id)
    REFERENCES experiments(workspace_id,id),
  FOREIGN KEY (workspace_id,content_variant_id)
    REFERENCES content_variants(workspace_id,id),
  FOREIGN KEY (workspace_id,social_account_id)
    REFERENCES social_accounts(workspace_id,id)
);

CREATE TABLE experiment_outcomes (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  exposure_id uuid NOT NULL,
  metric_key text NOT NULL,
  window_start timestamptz NOT NULL,
  window_end timestamptz NOT NULL,
  value numeric,
  completeness text NOT NULL,
  analysis_version text,
  created_at timestamptz NOT NULL DEFAULT now(),
  CHECK (window_end > window_start),
  UNIQUE (workspace_id,id),
  UNIQUE(exposure_id,metric_key,window_start,window_end),
  FOREIGN KEY (workspace_id,exposure_id)
    REFERENCES exposures(workspace_id,id)
);

-- ============================================================
-- 10. Growth Brain memory — NO fixed vector dimension in canonical schema
-- ============================================================

CREATE TABLE memories (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  social_account_id uuid,
  memory_type text NOT NULL CHECK(memory_type IN ('profile','episodic','structured_insight','semantic','prior')),
  source_class text NOT NULL,
  content jsonb NOT NULL,
  sensitivity_class text NOT NULL,
  valid_from timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz,
  logic_version text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id),
  FOREIGN KEY (workspace_id,social_account_id)
    REFERENCES social_accounts(workspace_id,id)
);

CREATE TABLE memory_embeddings (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  memory_id uuid NOT NULL,
  embedding_provider text NOT NULL,
  embedding_model text NOT NULL,
  embedding_dimension integer NOT NULL CHECK(embedding_dimension > 0),
  embedding_storage_ref text,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (workspace_id,id),
  UNIQUE(memory_id,embedding_provider,embedding_model),
  FOREIGN KEY (workspace_id,memory_id)
    REFERENCES memories(workspace_id,id)
);

-- ============================================================
-- 11. AI provider governance / routing / FinOps
-- ============================================================

CREATE TABLE ai_provider_policies (
  id uuid PRIMARY KEY,
  provider text NOT NULL,
  model text NOT NULL,
  modality text NOT NULL CHECK(modality IN ('text','image','video','audio','embedding')),
  region text NOT NULL,
  retention_class text NOT NULL,
  retention_detail text,
  training_use text NOT NULL,
  contract_ref text,
  verified_at timestamptz,
  evidence_status text NOT NULL,
  UNIQUE(provider,model,modality,region),
  UNIQUE(id,provider,model,modality,region)
);

CREATE TABLE ai_data_routing_allowlist (
  id uuid PRIMARY KEY,
  sensitivity_class text NOT NULL,
  purpose text NOT NULL,
  region text NOT NULL,
  modality text NOT NULL,
  provider text NOT NULL,
  model text NOT NULL,
  enabled boolean NOT NULL DEFAULT false,
  policy_id uuid NOT NULL,
  UNIQUE(sensitivity_class,purpose,region,modality,provider,model),
  FOREIGN KEY (policy_id,provider,model,modality,region)
    REFERENCES ai_provider_policies(id,provider,model,modality,region)
);

CREATE TABLE provider_usage (
  id uuid PRIMARY KEY,
  workspace_id uuid REFERENCES workspaces(id),
  provider text NOT NULL,
  capability text NOT NULL,
  model_or_endpoint text,
  request_id text,
  units numeric,
  cost_amount numeric,
  currency text,
  quota_bucket text,
  occurred_at timestamptz NOT NULL DEFAULT now()
);

-- ============================================================
-- 12. Audit
-- ============================================================

CREATE TABLE audit_events (
  id uuid PRIMARY KEY,
  workspace_id uuid REFERENCES workspaces(id),
  actor_user_id uuid REFERENCES users(id),
  event_type text NOT NULL,
  resource_type text,
  resource_id uuid,
  correlation_id uuid,
  metadata jsonb NOT NULL DEFAULT '{}'::jsonb,
  occurred_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX audit_workspace_time_idx ON audit_events(workspace_id,occurred_at DESC);
CREATE INDEX audit_correlation_idx ON audit_events(correlation_id);

-- ============================================================
-- 13. Deletion ledger / tombstones / purge
-- ============================================================

CREATE TABLE deletion_requests (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  requested_by uuid REFERENCES users(id),
  scope text NOT NULL CHECK(scope IN ('workspace','account','content','user')),
  target_id uuid NOT NULL,
  state text NOT NULL CHECK(state IN ('requested','tombstoned','purging','provider_pending','completed','failed')),
  requested_at timestamptz NOT NULL DEFAULT now(),
  tombstoned_at timestamptz,
  completed_at timestamptz,
  manifest_version text NOT NULL,
  UNIQUE (workspace_id,id)
);

CREATE TABLE purge_jobs (
  id uuid PRIMARY KEY,
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  deletion_request_id uuid NOT NULL,
  system_class text NOT NULL CHECK(system_class IN (
    'primary_db','read_replica','object_storage','cdn','search_vector',
    'cache','queue','logs_traces','analytics_warehouse','backup_restore_ledger','external_ai_provider'
  )),
  state text NOT NULL CHECK(state IN ('pending','running','confirmed','limitation_documented','failed')),
  evidence jsonb NOT NULL DEFAULT '{}'::jsonb,
  started_at timestamptz,
  completed_at timestamptz,
  UNIQUE (workspace_id,id),
  UNIQUE(deletion_request_id,system_class),
  FOREIGN KEY (workspace_id,deletion_request_id)
    REFERENCES deletion_requests(workspace_id,id)
);

CREATE TABLE deletion_tombstones (
  workspace_id uuid NOT NULL REFERENCES workspaces(id),
  target_type text NOT NULL,
  target_id uuid NOT NULL,
  deletion_request_id uuid NOT NULL,
  effective_at timestamptz NOT NULL,
  PRIMARY KEY(workspace_id,target_type,target_id),
  FOREIGN KEY (workspace_id,deletion_request_id)
    REFERENCES deletion_requests(workspace_id,id)
);

-- ============================================================
-- 14. Future aggregate intelligence boundary (no tenant IDs)
-- ============================================================

CREATE TABLE aggregate_intelligence.cohort_statistics (
  id uuid PRIMARY KEY,
  cohort_definition jsonb NOT NULL,
  metric_key text NOT NULL,
  statistic jsonb NOT NULL,
  contributing_accounts integer NOT NULL CHECK(contributing_accounts >= 0),
  governance_policy_version text NOT NULL,
  statistical_policy_version text NOT NULL,
  materialized_at timestamptz NOT NULL,
  expires_at timestamptz
);

-- ============================================================
-- 15. Deferred integrity triggers
-- ============================================================

CREATE OR REPLACE FUNCTION check_managed_account_projection_consistency()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, growth
AS $$
DECLARE
  ah growth.authority_history%ROWTYPE;
BEGIN
  SELECT * INTO ah
  FROM growth.authority_history
  WHERE workspace_id = NEW.workspace_id
    AND managed_account_id = NEW.id
    AND effective_to IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'managed_account % has no open authority_history row', NEW.id;
  END IF;

  IF NEW.owner_type IS DISTINCT FROM ah.owner_type
     OR NEW.authority_status IS DISTINCT FROM ah.authority_status
     OR NEW.contribution_eligibility IS DISTINCT FROM ah.contribution_eligibility
     OR NEW.authority_clause_ref IS DISTINCT FROM ah.authority_clause_ref THEN
    RAISE EXCEPTION 'managed_accounts projection does not match open authority_history for %', NEW.id;
  END IF;
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION check_authority_history_projection_consistency()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, growth
AS $$
DECLARE
  ma growth.managed_accounts%ROWTYPE;
  ah growth.authority_history%ROWTYPE;
BEGIN
  SELECT * INTO ah
  FROM growth.authority_history
  WHERE workspace_id = NEW.workspace_id
    AND managed_account_id = NEW.managed_account_id
    AND effective_to IS NULL;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'managed_account % has no open authority_history row', NEW.managed_account_id;
  END IF;

  SELECT * INTO ma
  FROM growth.managed_accounts
  WHERE workspace_id = NEW.workspace_id
    AND id = NEW.managed_account_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'managed_account % not found for authority history', NEW.managed_account_id;
  END IF;

  IF ma.owner_type IS DISTINCT FROM ah.owner_type
     OR ma.authority_status IS DISTINCT FROM ah.authority_status
     OR ma.contribution_eligibility IS DISTINCT FROM ah.contribution_eligibility
     OR ma.authority_clause_ref IS DISTINCT FROM ah.authority_clause_ref THEN
    RAISE EXCEPTION 'managed_accounts projection does not match open authority_history for %', NEW.managed_account_id;
  END IF;
  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER managed_account_projection_check
AFTER INSERT OR UPDATE ON growth.managed_accounts
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_managed_account_projection_consistency();

CREATE CONSTRAINT TRIGGER authority_history_projection_check
AFTER INSERT OR UPDATE ON growth.authority_history
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_authority_history_projection_consistency();

CREATE OR REPLACE FUNCTION assert_confirmed_insight_evidence_purity(
  p_workspace_id uuid,
  p_insight_id uuid
)
RETURNS void
LANGUAGE plpgsql
SET search_path = pg_catalog, growth
AS $$
DECLARE
  v_state text;
  owned_count integer;
  bad_count integer;
BEGIN
  SELECT state INTO v_state
  FROM growth.insights
  WHERE workspace_id = p_workspace_id
    AND id = p_insight_id;

  -- Parent may be deleted in the same transaction; then there is no remaining invariant to enforce.
  IF NOT FOUND THEN
    RETURN;
  END IF;

  IF v_state <> 'confirmed_account' THEN
    RETURN;
  END IF;

  SELECT
    count(*) FILTER (WHERE source_class = 'owned'),
    count(*) FILTER (WHERE source_class <> 'owned')
  INTO owned_count, bad_count
  FROM growth.insight_evidence
  WHERE workspace_id = p_workspace_id
    AND insight_id = p_insight_id;

  IF owned_count = 0 THEN
    RAISE EXCEPTION 'confirmed_account insight % requires at least one owned evidence row', p_insight_id;
  END IF;

  IF bad_count > 0 THEN
    RAISE EXCEPTION 'confirmed_account insight % contains non-owned evidence', p_insight_id;
  END IF;
END;
$$;

CREATE OR REPLACE FUNCTION check_insight_state_evidence_purity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, growth
AS $$
BEGIN
  PERFORM growth.assert_confirmed_insight_evidence_purity(NEW.workspace_id, NEW.id);
  RETURN NULL;
END;
$$;

CREATE OR REPLACE FUNCTION check_insight_evidence_purity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, growth
AS $$
BEGIN
  -- UPDATE can move an evidence row between insights/workspaces. Recheck both the old and new parents.
  IF TG_OP IN ('UPDATE','DELETE') THEN
    PERFORM growth.assert_confirmed_insight_evidence_purity(OLD.workspace_id, OLD.insight_id);
  END IF;

  IF TG_OP IN ('INSERT','UPDATE') THEN
    IF TG_OP = 'INSERT'
       OR NEW.workspace_id IS DISTINCT FROM OLD.workspace_id
       OR NEW.insight_id IS DISTINCT FROM OLD.insight_id
       OR NEW.source_class IS DISTINCT FROM OLD.source_class THEN
      PERFORM growth.assert_confirmed_insight_evidence_purity(NEW.workspace_id, NEW.insight_id);
    END IF;
  END IF;

  RETURN NULL;
END;
$$;

CREATE CONSTRAINT TRIGGER confirmed_insight_state_check
AFTER INSERT OR UPDATE OF state ON growth.insights
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_insight_state_evidence_purity();

CREATE CONSTRAINT TRIGGER confirmed_insight_evidence_check
AFTER INSERT OR UPDATE OR DELETE ON growth.insight_evidence
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_insight_evidence_purity();

-- ============================================================
-- 15.5 Cross-row lineage and temporal integrity guards (RC7)
-- ============================================================

CREATE OR REPLACE FUNCTION growth.reject_insight_demotion_cycle()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, growth
AS $$
DECLARE
  cycle_found boolean;
BEGIN
  IF NEW.demoted_from IS NULL THEN RETURN NEW; END IF;
  IF NEW.demoted_from = NEW.id THEN
    RAISE EXCEPTION 'insight demotion cannot reference itself';
  END IF;

  WITH RECURSIVE chain(id, demoted_from, path) AS (
    SELECT i.id, i.demoted_from, ARRAY[i.id]
    FROM growth.insights i
    WHERE i.workspace_id = NEW.workspace_id AND i.id = NEW.demoted_from
    UNION ALL
    SELECT i.id, i.demoted_from, c.path || i.id
    FROM growth.insights i
    JOIN chain c ON i.id = c.demoted_from
    WHERE i.workspace_id = NEW.workspace_id
      AND NOT i.id = ANY(c.path)
  )
  SELECT EXISTS (
    SELECT 1 FROM chain WHERE id = NEW.id OR demoted_from = NEW.id
  ) INTO cycle_found;

  IF cycle_found THEN
    RAISE EXCEPTION 'insight demotion would create a cycle';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER insights_reject_demotion_cycle
BEFORE INSERT OR UPDATE OF demoted_from ON growth.insights
FOR EACH ROW EXECUTE FUNCTION growth.reject_insight_demotion_cycle();

CREATE OR REPLACE FUNCTION growth.enforce_exposure_temporal_integrity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, growth
AS $$
DECLARE
  exp_started timestamptz;
  exp_ended timestamptz;
  earliest_outcome timestamptz;
BEGIN
  SELECT e.started_at, e.ended_at INTO exp_started, exp_ended
  FROM growth.experiments e
  WHERE e.workspace_id = NEW.workspace_id AND e.id = NEW.experiment_id;

  IF exp_started IS NOT NULL AND NEW.multiplication_eligible_at < exp_started THEN
    RAISE EXCEPTION 'exposure eligibility cannot precede experiment start';
  END IF;
  IF exp_ended IS NOT NULL AND NEW.multiplication_eligible_at > exp_ended THEN
    RAISE EXCEPTION 'exposure eligibility cannot follow experiment end';
  END IF;

  SELECT min(o.window_start) INTO earliest_outcome
  FROM growth.experiment_outcomes o
  WHERE o.workspace_id = NEW.workspace_id AND o.exposure_id = NEW.id;

  IF earliest_outcome IS NOT NULL AND NEW.multiplication_eligible_at > earliest_outcome THEN
    RAISE EXCEPTION 'exposure eligibility cannot move after an existing outcome window';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER exposures_temporal_integrity
BEFORE INSERT OR UPDATE OF experiment_id,multiplication_eligible_at,assigned_at,multiplication_released_at
ON growth.exposures
FOR EACH ROW EXECUTE FUNCTION growth.enforce_exposure_temporal_integrity();

CREATE OR REPLACE FUNCTION growth.enforce_experiment_temporal_integrity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, growth
AS $$
DECLARE
  earliest_exposure timestamptz;
  latest_exposure timestamptz;
BEGIN
  SELECT min(x.multiplication_eligible_at),
         max(GREATEST(x.multiplication_eligible_at,
                      COALESCE(x.assigned_at, x.multiplication_eligible_at),
                      COALESCE(x.multiplication_released_at, x.multiplication_eligible_at)))
    INTO earliest_exposure, latest_exposure
  FROM growth.exposures x
  WHERE x.workspace_id = NEW.workspace_id AND x.experiment_id = NEW.id;

  IF earliest_exposure IS NOT NULL AND NEW.started_at IS NOT NULL AND NEW.started_at > earliest_exposure THEN
    RAISE EXCEPTION 'experiment start cannot move after an existing exposure';
  END IF;
  IF latest_exposure IS NOT NULL AND NEW.ended_at IS NOT NULL AND NEW.ended_at < latest_exposure THEN
    RAISE EXCEPTION 'experiment end cannot move before existing exposure activity';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER experiments_temporal_integrity
BEFORE UPDATE OF started_at,ended_at ON growth.experiments
FOR EACH ROW EXECUTE FUNCTION growth.enforce_experiment_temporal_integrity();

CREATE OR REPLACE FUNCTION growth.enforce_experiment_outcome_temporal_integrity()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, growth
AS $$
DECLARE
  eligible_at timestamptz;
BEGIN
  SELECT x.multiplication_eligible_at INTO eligible_at
  FROM growth.exposures x
  WHERE x.workspace_id = NEW.workspace_id AND x.id = NEW.exposure_id;

  IF eligible_at IS NOT NULL AND NEW.window_start < eligible_at THEN
    RAISE EXCEPTION 'outcome window cannot start before exposure eligibility';
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER experiment_outcomes_temporal_integrity
BEFORE INSERT OR UPDATE OF exposure_id,window_start,window_end
ON growth.experiment_outcomes
FOR EACH ROW EXECUTE FUNCTION growth.enforce_experiment_outcome_temporal_integrity();


-- ============================================================
-- RC8 integrity hardening: deletion lifecycle, late metrics, tenant context
-- ============================================================

CREATE OR REPLACE FUNCTION growth.enforce_deletion_request_state_transition()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF TG_OP <> 'UPDATE' OR NEW.state = OLD.state THEN
    RETURN NEW;
  END IF;

  IF OLD.state = 'completed' THEN
    RAISE EXCEPTION 'completed deletion request is terminal';
  END IF;

  IF NOT (
    (OLD.state = 'requested' AND NEW.state IN ('tombstoned','failed'))
    OR (OLD.state = 'tombstoned' AND NEW.state IN ('purging','failed'))
    OR (OLD.state = 'purging' AND NEW.state IN ('provider_pending','completed','failed'))
    OR (OLD.state = 'provider_pending' AND NEW.state IN ('completed','failed'))
    OR (OLD.state = 'failed' AND NEW.state = 'requested')
  ) THEN
    RAISE EXCEPTION 'invalid deletion request transition: % -> %', OLD.state, NEW.state;
  END IF;

  IF NEW.state = 'tombstoned' AND NEW.tombstoned_at IS NULL THEN
    NEW.tombstoned_at := now();
  END IF;

  IF NEW.state = 'completed' AND NEW.completed_at IS NULL THEN
    NEW.completed_at := now();
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER deletion_requests_state_guard
BEFORE UPDATE OF state ON growth.deletion_requests
FOR EACH ROW EXECUTE FUNCTION growth.enforce_deletion_request_state_transition();

CREATE OR REPLACE FUNCTION growth.invalidate_metric_completeness_on_late_observation()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF NEW.content_item_id IS NULL THEN
    RETURN NEW;
  END IF;

  UPDATE growth.metric_completeness mc
     SET available = false,
         reason_unavailable = 'late_arrival_requires_reconciliation'
   WHERE mc.workspace_id = NEW.workspace_id
     AND mc.content_item_id = NEW.content_item_id
     AND mc.metric_key = NEW.metric_name
     AND NEW.observed_at <= mc.last_checked_at
     AND NEW.created_at > mc.last_checked_at;

  RETURN NEW;
END;
$$;

CREATE TRIGGER metric_observations_late_arrival_guard
AFTER INSERT ON growth.metric_observations
FOR EACH ROW EXECUTE FUNCTION growth.invalidate_metric_completeness_on_late_observation();

-- ============================================================
-- 16. Row-level security on all tenant-owned tables
-- ============================================================

CREATE OR REPLACE FUNCTION growth.current_workspace_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('app.workspace_id', true),'')::uuid
$$;

CREATE OR REPLACE FUNCTION growth.current_app_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT NULLIF(current_setting('app.user_id', true),'')::uuid
$$;

CREATE OR REPLACE FUNCTION growth.tenant_context_valid(p_workspace_id uuid)
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

REVOKE ALL ON FUNCTION growth.tenant_context_valid(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.tenant_context_valid(uuid) TO app_runtime;

-- Identity/workspace bootstrap policies. A user must be able to discover their memberships before a workspace is selected.
ALTER TABLE growth.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.users FORCE ROW LEVEL SECURITY;
CREATE POLICY users_self_select ON growth.users FOR SELECT
  USING (id = growth.current_app_user_id());
CREATE POLICY users_self_update ON growth.users FOR UPDATE
  USING (id = growth.current_app_user_id())
  WITH CHECK (id = growth.current_app_user_id());

ALTER TABLE growth.memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.memberships FORCE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION growth.can_manage_memberships(p_workspace_id uuid)
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
      AND m.role IN ('owner','admin')
      AND m.status = 'active'
  );
$$;

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
    AND NOT EXISTS (
      SELECT 1 FROM growth.memberships m
      WHERE m.workspace_id = p_workspace_id
    );
$$;

CREATE OR REPLACE FUNCTION growth.membership_actor_role(p_workspace_id uuid)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
  SELECT m.role
  FROM growth.memberships m
  WHERE m.workspace_id = p_workspace_id
    AND m.user_id = growth.current_app_user_id()
    AND m.status = 'active'
  LIMIT 1
$$;

CREATE OR REPLACE FUNCTION growth.membership_workspace_lock(p_workspace_id uuid)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  hex text := replace(p_workspace_id::text, '-', '');
  k1 integer;
  k2 integer;
BEGIN
  -- Stable application-owned derivation from the first 64 bits of the UUID.
  -- Collision can only over-serialize unrelated workspaces; integrity is enforced separately.
  k1 := ('x' || substr(hex,1,8))::bit(32)::integer;
  k2 := ('x' || substr(hex,9,8))::bit(32)::integer;
  PERFORM pg_advisory_xact_lock(k1,k2);
END;
$$;

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
  membership_count integer;
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

  SELECT count(*) INTO membership_count
  FROM growth.memberships m
  WHERE m.workspace_id = ws;

  SELECT growth.membership_actor_role(ws) INTO actor_role;

  IF TG_OP = 'INSERT' THEN
    IF membership_count = 0 THEN
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

REVOKE ALL ON FUNCTION growth.can_bootstrap_first_membership(uuid,uuid,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.can_manage_memberships(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.membership_actor_role(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.membership_workspace_lock(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.membership_write_guard() FROM PUBLIC;
-- The canonical deployment contract provisions app_runtime before this migration.
-- RLS policy evaluation calls can_manage_memberships(), so runtime needs EXECUTE on that single helper.
GRANT EXECUTE ON FUNCTION growth.can_manage_memberships(uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.can_bootstrap_first_membership(uuid,uuid,text,text) TO app_runtime;
-- Other SECURITY DEFINER helpers are trigger-internal and remain non-executable directly by app_runtime.

DROP TRIGGER IF EXISTS memberships_write_guard ON growth.memberships;
CREATE TRIGGER memberships_write_guard
BEFORE INSERT OR UPDATE OR DELETE ON growth.memberships
FOR EACH ROW EXECUTE FUNCTION growth.membership_write_guard();

CREATE POLICY memberships_self_select ON growth.memberships FOR SELECT
  USING (user_id = growth.current_app_user_id());
CREATE POLICY memberships_workspace_select ON growth.memberships FOR SELECT
  USING (workspace_id = growth.current_workspace_id());
CREATE POLICY memberships_workspace_insert ON growth.memberships FOR INSERT
  WITH CHECK (
    workspace_id = growth.current_workspace_id()
    AND (
      growth.can_manage_memberships(workspace_id)
      OR growth.can_bootstrap_first_membership(workspace_id, user_id, role, status)
    )
  );

CREATE POLICY memberships_workspace_update ON growth.memberships FOR UPDATE
  USING (
    workspace_id = growth.current_workspace_id()
    AND growth.can_manage_memberships(workspace_id)
  )
  WITH CHECK (
    workspace_id = growth.current_workspace_id()
    AND growth.can_manage_memberships(workspace_id)
  );
CREATE POLICY memberships_workspace_delete ON growth.memberships FOR DELETE
  USING (
    workspace_id = growth.current_workspace_id()
    AND (
      growth.can_manage_memberships(workspace_id)
      OR user_id = growth.current_app_user_id()
    )
  );

ALTER TABLE growth.workspaces ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.workspaces FORCE ROW LEVEL SECURITY;
CREATE POLICY workspaces_member_select ON growth.workspaces FOR SELECT
  USING (id = growth.current_workspace_id() OR EXISTS (
    SELECT 1 FROM growth.memberships m
    WHERE m.workspace_id = workspaces.id
      AND m.user_id = growth.current_app_user_id()
      AND m.status = 'active'
  ));
CREATE POLICY workspaces_current_insert ON growth.workspaces FOR INSERT
  WITH CHECK (id = growth.current_workspace_id());
CREATE POLICY workspaces_current_update ON growth.workspaces FOR UPDATE
  USING (id = growth.current_workspace_id())
  WITH CHECK (id = growth.current_workspace_id());

-- Helper DO block creates identical workspace policy for ordinary tenant-owned tables.
DO $$
DECLARE
  t text;
  tenant_tables text[] := ARRAY[
    'managed_accounts','authority_history','consent_events',
    'platform_connections','social_accounts','content_items','content_versions','media_assets',
    'publication_intents','publication_attempts','publication_reconciliation_attempts',
    'outbox_events','metric_observations','metric_normalized','metric_completeness','baselines',
    'insights','insight_evidence','feed_cards','feed_events','opportunities','opportunity_evidence',
    'hypotheses','experiments','content_variants','exposures','experiment_outcomes',
    'memories','memory_embeddings','purge_jobs','deletion_requests','deletion_tombstones',
    'provider_usage','audit_events'
  ];
BEGIN
  FOREACH t IN ARRAY tenant_tables LOOP
    EXECUTE format('ALTER TABLE growth.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE growth.%I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY %I ON growth.%I USING (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id)) WITH CHECK (workspace_id = growth.current_workspace_id() AND growth.tenant_context_valid(workspace_id))',
      t || '_workspace_isolation', t
    );
  END LOOP;
END $$;

-- Tombstoned content is immediately denied from the normal tenant read path.
-- A content tombstone uses target_type='content' and target_id=content_items.id.
DROP POLICY content_items_workspace_isolation ON growth.content_items;
CREATE POLICY content_items_workspace_isolation ON growth.content_items
  USING (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
    AND NOT EXISTS (
      SELECT 1
      FROM growth.deletion_tombstones dt
      WHERE dt.workspace_id = content_items.workspace_id
        AND dt.target_type = 'content'
        AND dt.target_id = content_items.id
        AND dt.effective_at <= now()
    )
  )
  WITH CHECK (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
  );

DROP POLICY content_versions_workspace_isolation ON growth.content_versions;
CREATE POLICY content_versions_workspace_isolation ON growth.content_versions
  USING (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
    AND NOT EXISTS (
      SELECT 1
      FROM growth.deletion_tombstones dt
      WHERE dt.workspace_id = content_versions.workspace_id
        AND dt.target_type = 'content'
        AND dt.target_id = content_versions.content_item_id
        AND dt.effective_at <= now()
    )
  )
  WITH CHECK (
    workspace_id = growth.current_workspace_id()
    AND growth.tenant_context_valid(workspace_id)
  );

-- jobs is intentionally internal and cross-tenant claimable; the API runtime role must have no direct privileges on it.
-- provider_usage/audit_events permit system rows with workspace_id NULL, but normal runtime RLS only exposes tenant rows matching current_workspace_id.

-- ============================================================
-- 17. Immutability guards for retained evidence classes
-- ============================================================

CREATE OR REPLACE FUNCTION reject_mutation_while_retained()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION '% is immutable while retained; use authorized purge workflow', TG_TABLE_NAME;
END;
$$;

CREATE TRIGGER metric_observations_no_update
BEFORE UPDATE ON metric_observations
FOR EACH ROW EXECUTE FUNCTION reject_mutation_while_retained();

CREATE TRIGGER publication_attempts_no_update
BEFORE UPDATE ON publication_attempts
FOR EACH ROW EXECUTE FUNCTION reject_mutation_while_retained();

CREATE TRIGGER publication_reconciliation_attempts_no_update
BEFORE UPDATE ON publication_reconciliation_attempts
FOR EACH ROW EXECUTE FUNCTION reject_mutation_while_retained();

-- DELETE remains reserved for a dedicated purge role/workflow and is controlled by privileges, not this trigger.

COMMIT;
