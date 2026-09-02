-- Growth OS — Identity v1 schema and database authorization boundary.
-- Source: db/IDENTITY_V1_DESIGN.md, adversarially approved at
-- 2e04e011596cc938a267dc61c792abad44ab63ba and merged by PR #10.
--
-- EXECUTION IDENTITY: provider-native administrative identity. Migration 006
-- transfers narrow SECURITY DEFINER functions to growth_identity_helper and
-- therefore must not run as growth_migrator. Run
-- db/provisioning/production/05_identity_roles.sql first.
--
-- Forward-only: no existing column/table is dropped and the frozen 001 baseline
-- remains byte-identical.

\set ON_ERROR_STOP on

BEGIN;
SET search_path = growth, public;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_identity_helper') THEN
    RAISE EXCEPTION 'growth_identity_helper is required; run production/05_identity_roles.sql first';
  END IF;
END $$;

ALTER TABLE growth.users
  ADD COLUMN email_verified_at timestamptz;

CREATE TABLE growth.auth_identities (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES growth.users(id),
  provider text NOT NULL CHECK (provider IN ('password','google','apple')),
  provider_subject text,
  created_at timestamptz NOT NULL DEFAULT now(),
  revoked_at timestamptz,
  CHECK (
    (provider = 'password' AND provider_subject IS NULL)
    OR
    (provider <> 'password' AND provider_subject IS NOT NULL AND btrim(provider_subject) <> '')
  ),
  CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);

CREATE UNIQUE INDEX auth_identities_provider_subject_uq
  ON growth.auth_identities(provider, provider_subject)
  WHERE provider_subject IS NOT NULL AND revoked_at IS NULL;
CREATE UNIQUE INDEX auth_identities_one_active_password_uq
  ON growth.auth_identities(user_id)
  WHERE provider = 'password' AND revoked_at IS NULL;
CREATE INDEX auth_identities_user_idx ON growth.auth_identities(user_id);

CREATE TABLE growth.password_credentials (
  auth_identity_id uuid PRIMARY KEY REFERENCES growth.auth_identities(id) ON DELETE CASCADE,
  password_hash text NOT NULL CHECK (password_hash LIKE '$argon2id$%'),
  hash_algorithm text NOT NULL DEFAULT 'argon2id' CHECK (hash_algorithm = 'argon2id'),
  hash_version smallint NOT NULL CHECK (hash_version > 0),
  must_change boolean NOT NULL DEFAULT false,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE growth.email_verifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES growth.users(id),
  email text NOT NULL CHECK (email = lower(btrim(email)) AND length(email) BETWEEN 3 AND 320),
  token_hash text NOT NULL CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  CHECK (expires_at > created_at),
  CHECK (consumed_at IS NULL OR consumed_at >= created_at)
);
CREATE UNIQUE INDEX email_verifications_token_hash_uq
  ON growth.email_verifications(token_hash);
CREATE INDEX email_verifications_user_open_idx
  ON growth.email_verifications(user_id) WHERE consumed_at IS NULL;

CREATE TABLE growth.password_resets (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES growth.users(id),
  token_hash text NOT NULL CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  consumed_at timestamptz,
  requested_ip inet,
  requested_user_agent text,
  CHECK (expires_at > created_at),
  CHECK (consumed_at IS NULL OR consumed_at >= created_at)
);
CREATE UNIQUE INDEX password_resets_token_hash_uq ON growth.password_resets(token_hash);
CREATE INDEX password_resets_user_open_idx
  ON growth.password_resets(user_id) WHERE consumed_at IS NULL;

CREATE TABLE growth.mfa_factors (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES growth.users(id),
  factor_type text NOT NULL CHECK (factor_type IN ('totp','webauthn')),
  label text,
  secret_encrypted bytea,
  credential_id bytea,
  public_key bytea,
  sign_count bigint CHECK (sign_count IS NULL OR sign_count >= 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  confirmed_at timestamptz,
  revoked_at timestamptz,
  CHECK (
    (factor_type = 'totp' AND secret_encrypted IS NOT NULL
      AND credential_id IS NULL AND public_key IS NULL AND sign_count IS NULL)
    OR
    (factor_type = 'webauthn' AND secret_encrypted IS NULL
      AND credential_id IS NOT NULL AND public_key IS NOT NULL)
  ),
  CHECK (confirmed_at IS NULL OR confirmed_at >= created_at),
  CHECK (revoked_at IS NULL OR revoked_at >= created_at)
);
CREATE UNIQUE INDEX mfa_factors_webauthn_credential_uq
  ON growth.mfa_factors(credential_id)
  WHERE credential_id IS NOT NULL AND revoked_at IS NULL;
CREATE INDEX mfa_factors_user_active_idx
  ON growth.mfa_factors(user_id) WHERE revoked_at IS NULL;

CREATE TABLE growth.mfa_recovery_codes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES growth.users(id),
  code_hash text NOT NULL CHECK (code_hash ~ '^[0-9a-f]{64}$'),
  created_at timestamptz NOT NULL DEFAULT now(),
  consumed_at timestamptz,
  CHECK (consumed_at IS NULL OR consumed_at >= created_at)
);
CREATE UNIQUE INDEX mfa_recovery_codes_hash_uq ON growth.mfa_recovery_codes(code_hash);
CREATE INDEX mfa_recovery_codes_user_open_idx
  ON growth.mfa_recovery_codes(user_id) WHERE consumed_at IS NULL;

CREATE TABLE growth.sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES growth.users(id),
  session_token_hash text NOT NULL CHECK (session_token_hash ~ '^[0-9a-f]{64}$'),
  amr text[] NOT NULL DEFAULT '{}',
  created_at timestamptz NOT NULL DEFAULT now(),
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  absolute_expires_at timestamptz NOT NULL,
  idle_expires_at timestamptz NOT NULL,
  revoked_at timestamptz,
  revoked_reason text CHECK (revoked_reason IS NULL OR revoked_reason IN (
    'logout','logout_all','password_reset','admin_revoke','rotated'
  )),
  ip inet,
  user_agent text,
  CHECK (absolute_expires_at > created_at),
  CHECK (idle_expires_at > created_at AND idle_expires_at <= absolute_expires_at),
  CHECK (last_seen_at >= created_at),
  CHECK ((revoked_at IS NULL AND revoked_reason IS NULL)
      OR (revoked_at IS NOT NULL AND revoked_reason IS NOT NULL))
);
CREATE UNIQUE INDEX sessions_token_hash_uq ON growth.sessions(session_token_hash);
CREATE INDEX sessions_user_active_idx ON growth.sessions(user_id) WHERE revoked_at IS NULL;

CREATE TABLE growth.invitations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  workspace_id uuid NOT NULL REFERENCES growth.workspaces(id),
  invited_email text NOT NULL
    CHECK (invited_email = lower(btrim(invited_email)) AND length(invited_email) BETWEEN 3 AND 320),
  invited_role text NOT NULL CHECK (invited_role IN ('admin','editor','viewer')),
  can_publish boolean NOT NULL DEFAULT false,
  token_hash text NOT NULL CHECK (token_hash ~ '^[0-9a-f]{64}$'),
  invited_by_user_id uuid NOT NULL REFERENCES growth.users(id),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','accepted','revoked','expired')),
  accepted_at timestamptz,
  accepted_by_user_id uuid REFERENCES growth.users(id),
  revoked_at timestamptz,
  revoked_by_user_id uuid REFERENCES growth.users(id),
  CHECK (expires_at > created_at),
  CHECK (
    (status = 'pending' AND accepted_at IS NULL AND accepted_by_user_id IS NULL
      AND revoked_at IS NULL AND revoked_by_user_id IS NULL)
    OR
    (status = 'accepted' AND accepted_at IS NOT NULL AND accepted_by_user_id IS NOT NULL
      AND revoked_at IS NULL AND revoked_by_user_id IS NULL)
    OR
    (status = 'revoked' AND accepted_at IS NULL AND accepted_by_user_id IS NULL
      AND revoked_at IS NOT NULL AND revoked_by_user_id IS NOT NULL)
    OR
    (status = 'expired' AND accepted_at IS NULL AND accepted_by_user_id IS NULL
      AND revoked_at IS NULL AND revoked_by_user_id IS NULL)
  )
);
CREATE UNIQUE INDEX invitations_token_hash_uq ON growth.invitations(token_hash);
CREATE UNIQUE INDEX invitations_one_pending_per_workspace_email
  ON growth.invitations(workspace_id, invited_email) WHERE status = 'pending';
CREATE INDEX invitations_email_lookup_idx
  ON growth.invitations(invited_email) WHERE status = 'pending';

CREATE TABLE growth.login_attempts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email text NOT NULL CHECK (email = lower(btrim(email)) AND length(email) BETWEEN 3 AND 320),
  user_id uuid REFERENCES growth.users(id),
  succeeded boolean NOT NULL,
  ip inet,
  user_agent text,
  attempted_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX login_attempts_email_recent_idx
  ON growth.login_attempts(email, attempted_at DESC);
CREATE INDEX login_attempts_ip_recent_idx
  ON growth.login_attempts(ip, attempted_at DESC);

-- Keep schema evolution alterable by the ordinary migration role.
ALTER TABLE growth.auth_identities OWNER TO growth_migrator;
ALTER TABLE growth.password_credentials OWNER TO growth_migrator;
ALTER TABLE growth.email_verifications OWNER TO growth_migrator;
ALTER TABLE growth.password_resets OWNER TO growth_migrator;
ALTER TABLE growth.mfa_factors OWNER TO growth_migrator;
ALTER TABLE growth.mfa_recovery_codes OWNER TO growth_migrator;
ALTER TABLE growth.sessions OWNER TO growth_migrator;
ALTER TABLE growth.invitations OWNER TO growth_migrator;
ALTER TABLE growth.login_attempts OWNER TO growth_migrator;

-- Account-owned tables are self-scoped at the RLS layer. app_runtime still
-- receives no direct table SELECT for secret-bearing rows; approved helpers
-- below are the only production access path.
DO $$
DECLARE
  t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'auth_identities','email_verifications','password_resets','mfa_factors',
    'mfa_recovery_codes','sessions'
  ] LOOP
    EXECUTE format('ALTER TABLE growth.%I ENABLE ROW LEVEL SECURITY', t);
    EXECUTE format('ALTER TABLE growth.%I FORCE ROW LEVEL SECURITY', t);
    EXECUTE format(
      'CREATE POLICY %I ON growth.%I FOR SELECT USING (user_id = growth.current_app_user_id())',
      t || '_self_select', t
    );
  END LOOP;
END $$;

ALTER TABLE growth.password_credentials ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.password_credentials FORCE ROW LEVEL SECURITY;
CREATE POLICY password_credentials_self_select ON growth.password_credentials FOR SELECT
  USING (EXISTS (
    SELECT 1 FROM growth.auth_identities ai
    WHERE ai.id = password_credentials.auth_identity_id
      AND ai.user_id = growth.current_app_user_id()
  ));

ALTER TABLE growth.invitations ENABLE ROW LEVEL SECURITY;
ALTER TABLE growth.invitations FORCE ROW LEVEL SECURITY;
CREATE POLICY invitations_workspace_select ON growth.invitations FOR SELECT
  USING (growth.tenant_context_valid(workspace_id));

CREATE POLICY audit_events_account_self_select ON growth.audit_events FOR SELECT
  USING (workspace_id IS NULL AND actor_user_id = growth.current_app_user_id());

GRANT USAGE ON SCHEMA growth TO growth_identity_helper;
GRANT SELECT, INSERT, UPDATE ON
  growth.users, growth.workspaces, growth.memberships, growth.audit_events,
  growth.auth_identities, growth.password_credentials, growth.email_verifications,
  growth.password_resets, growth.mfa_factors, growth.mfa_recovery_codes,
  growth.sessions, growth.invitations, growth.login_attempts
TO growth_identity_helper;

-- ------------------------------------------------------------
-- Narrow BYPASSRLS predicates used by trigger-owned guards.
-- ------------------------------------------------------------

CREATE FUNCTION growth.identity_actor_can_invite(p_workspace_id uuid, p_target_role text)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM growth.memberships m
    JOIN growth.users u ON u.id = m.user_id
    WHERE m.workspace_id = p_workspace_id
      AND m.user_id = growth.current_app_user_id()
      AND m.status = 'active'
      AND u.status = 'active'
      AND u.email_verified_at IS NOT NULL
      AND (
        (m.role = 'owner' AND p_target_role IN ('admin','editor','viewer'))
        OR (m.role = 'admin' AND p_target_role IN ('editor','viewer'))
      )
  );
$$;
ALTER FUNCTION growth.identity_actor_can_invite(uuid,text) OWNER TO growth_identity_helper;
REVOKE ALL ON FUNCTION growth.identity_actor_can_invite(uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.identity_actor_can_invite(uuid,text) TO growth_migrator;

CREATE FUNCTION growth.identity_invitation_matches_current_user(p_invitation_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM growth.invitations i
    JOIN growth.users u ON u.id = growth.current_app_user_id()
    WHERE i.id = p_invitation_id
      AND i.invited_email = lower(btrim(u.email))
      AND u.status = 'active'
      AND u.email_verified_at IS NOT NULL
  );
$$;
ALTER FUNCTION growth.identity_invitation_matches_current_user(uuid) OWNER TO growth_identity_helper;
REVOKE ALL ON FUNCTION growth.identity_invitation_matches_current_user(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.identity_invitation_matches_current_user(uuid) TO growth_migrator;

CREATE FUNCTION growth.invitation_write_guard()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  actor uuid := growth.current_app_user_id();
BEGIN
  IF actor IS NULL THEN
    RAISE EXCEPTION 'invitation mutation requires app.user_id';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RAISE EXCEPTION 'invitations are retained; transition status instead of deleting';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.status <> 'pending'
       OR NEW.invited_by_user_id <> actor
       OR NOT growth.identity_actor_can_invite(NEW.workspace_id, NEW.invited_role) THEN
      RAISE EXCEPTION 'invitation issuance requires authorized owner/admin';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.id <> OLD.id OR NEW.workspace_id <> OLD.workspace_id
     OR NEW.invited_email <> OLD.invited_email OR NEW.invited_role <> OLD.invited_role
     OR NEW.can_publish <> OLD.can_publish OR NEW.token_hash <> OLD.token_hash
     OR NEW.invited_by_user_id <> OLD.invited_by_user_id
     OR NEW.created_at <> OLD.created_at OR NEW.expires_at <> OLD.expires_at THEN
    RAISE EXCEPTION 'invitation identity, authority and token fields are immutable';
  END IF;

  IF OLD.status <> 'pending' THEN
    RAISE EXCEPTION 'terminal invitation state % is immutable', OLD.status;
  END IF;

  IF NEW.status = 'accepted' THEN
    IF NEW.accepted_by_user_id <> actor
       OR NOT growth.identity_invitation_matches_current_user(NEW.id) THEN
      RAISE EXCEPTION 'invitation acceptance requires the verified invited identity';
    END IF;
    RETURN NEW;
  END IF;

  IF NEW.status IN ('revoked','expired') THEN
    IF NOT growth.identity_actor_can_invite(NEW.workspace_id, NEW.invited_role) THEN
      RAISE EXCEPTION 'invitation revoke/expiry reconciliation requires owner/admin';
    END IF;
    IF NEW.status = 'revoked' AND NEW.revoked_by_user_id <> actor THEN
      RAISE EXCEPTION 'revoked invitation must record the acting user';
    END IF;
    RETURN NEW;
  END IF;

  RAISE EXCEPTION 'invalid invitation transition % -> %', OLD.status, NEW.status;
END;
$$;
ALTER FUNCTION growth.invitation_write_guard() OWNER TO growth_migrator;
REVOKE ALL ON FUNCTION growth.invitation_write_guard() FROM PUBLIC;

CREATE TRIGGER invitations_write_guard
BEFORE INSERT OR UPDATE OR DELETE ON growth.invitations
FOR EACH ROW EXECUTE FUNCTION growth.invitation_write_guard();

CREATE FUNCTION growth.identity_consume_invitation_for_membership(
  p_token_hash text,
  p_workspace_id uuid,
  p_user_id uuid,
  p_role text,
  p_status text,
  p_can_publish boolean
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  invitation_id uuid;
BEGIN
  IF p_token_hash IS NULL
     OR p_token_hash <> NULLIF(current_setting('app.invitation_token_hash', true), '')
     OR p_user_id <> growth.current_app_user_id()
     OR p_status <> 'active' THEN
    RETURN false;
  END IF;

  SELECT i.id INTO invitation_id
  FROM growth.invitations i
  JOIN growth.users u ON u.id = p_user_id
  WHERE i.token_hash = p_token_hash
    AND i.workspace_id = p_workspace_id
    AND i.invited_role = p_role
    AND i.can_publish = p_can_publish
    AND i.status = 'pending'
    AND i.expires_at > now()
    AND i.invited_email = lower(btrim(u.email))
    AND u.status = 'active'
    AND u.email_verified_at IS NOT NULL
  FOR UPDATE OF i;

  IF invitation_id IS NULL THEN
    RETURN false;
  END IF;

  UPDATE growth.invitations
  SET status = 'accepted', accepted_at = now(), accepted_by_user_id = p_user_id
  WHERE id = invitation_id;

  RETURN true;
END;
$$;
ALTER FUNCTION growth.identity_consume_invitation_for_membership(text,uuid,uuid,text,text,boolean)
  OWNER TO growth_identity_helper;
REVOKE ALL ON FUNCTION growth.identity_consume_invitation_for_membership(text,uuid,uuid,text,text,boolean)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.identity_consume_invitation_for_membership(text,uuid,uuid,text,text,boolean)
  TO growth_migrator;

-- Preserve the RC9 membership guards and add only the invitation-authorized
-- INSERT/reactivation path. The invite is consumed inside the same statement;
-- any later failure rolls both membership and invitation back.
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
  invitation_token_hash text := NULLIF(current_setting('app.invitation_token_hash', true), '');
BEGIN
  IF TG_OP = 'DELETE' THEN ws := OLD.workspace_id; ELSE ws := NEW.workspace_id; END IF;
  IF actor IS NULL THEN RAISE EXCEPTION 'membership mutation requires app.user_id'; END IF;

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

    IF (actor_role IS NULL OR actor_role NOT IN ('owner','admin'))
       AND invitation_token_hash IS NOT NULL
       AND growth.identity_consume_invitation_for_membership(
         invitation_token_hash, NEW.workspace_id, NEW.user_id,
         NEW.role, NEW.status, NEW.can_publish
       ) THEN
      RETURN NEW;
    END IF;

    IF actor_role IS NULL OR actor_role NOT IN ('owner','admin') THEN
      RAISE EXCEPTION 'membership insert requires owner/admin authority or a valid invitation';
    END IF;
    IF actor_role = 'admin' AND NEW.role IN ('owner','admin') THEN
      RAISE EXCEPTION 'admin cannot create owner/admin membership';
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    IF NEW.workspace_id <> OLD.workspace_id OR NEW.user_id <> OLD.user_id THEN
      RAISE EXCEPTION 'workspace_id and user_id are immutable on membership update';
    END IF;

    IF OLD.status = 'revoked' AND NEW.status = 'active'
       AND invitation_token_hash IS NOT NULL
       AND growth.identity_consume_invitation_for_membership(
         invitation_token_hash, NEW.workspace_id, NEW.user_id,
         NEW.role, NEW.status, NEW.can_publish
       ) THEN
      RETURN NEW;
    END IF;

    IF actor_role NOT IN ('owner','admin') THEN
      RAISE EXCEPTION 'membership update requires owner/admin authority';
    END IF;
    IF actor_role = 'admin' AND (OLD.role IN ('owner','admin') OR NEW.role IN ('owner','admin')) THEN
      RAISE EXCEPTION 'admin cannot mutate owner/admin membership or promote to owner/admin';
    END IF;
    IF OLD.role = 'owner' AND OLD.status = 'active'
       AND (NEW.role <> 'owner' OR NEW.status <> 'active') THEN
      SELECT count(*) INTO other_active_owner_count
      FROM growth.memberships m
      WHERE m.workspace_id = ws AND m.user_id <> OLD.user_id
        AND m.role = 'owner' AND m.status = 'active';
      IF other_active_owner_count = 0 THEN
        RAISE EXCEPTION 'cannot demote/revoke the last active owner';
      END IF;
    END IF;
    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    IF actor = OLD.user_id THEN
      IF OLD.role = 'owner' AND OLD.status = 'active' THEN
        SELECT count(*) INTO other_active_owner_count
        FROM growth.memberships m
        WHERE m.workspace_id = ws AND m.user_id <> OLD.user_id
          AND m.role = 'owner' AND m.status = 'active';
        IF other_active_owner_count = 0 THEN
          RAISE EXCEPTION 'last active owner cannot leave workspace';
        END IF;
      END IF;
      RETURN OLD;
    END IF;
    IF actor_role NOT IN ('owner','admin') THEN
      RAISE EXCEPTION 'membership delete requires owner/admin authority or self-leave';
    END IF;
    IF actor_role = 'admin' AND OLD.role IN ('owner','admin') THEN
      RAISE EXCEPTION 'admin cannot delete owner/admin membership';
    END IF;
    IF OLD.role = 'owner' AND OLD.status = 'active' THEN
      SELECT count(*) INTO other_active_owner_count
      FROM growth.memberships m
      WHERE m.workspace_id = ws AND m.user_id <> OLD.user_id
        AND m.role = 'owner' AND m.status = 'active';
      IF other_active_owner_count = 0 THEN
        RAISE EXCEPTION 'cannot delete the last active owner';
      END IF;
    END IF;
    RETURN OLD;
  END IF;

  RAISE EXCEPTION 'unsupported membership operation %', TG_OP;
END;
$$;

-- ------------------------------------------------------------
-- Public database API: narrow functions, no direct secret-table grants.
-- ------------------------------------------------------------

CREATE FUNCTION growth.identity_signup(
  p_email text,
  p_password_hash text,
  p_hash_version smallint DEFAULT 19
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  normalized_email text := lower(btrim(p_email));
  new_user_id uuid := gen_random_uuid();
  new_identity_id uuid := gen_random_uuid();
BEGIN
  IF normalized_email = '' OR length(normalized_email) > 320 OR position('@' in normalized_email) < 2 THEN
    RAISE EXCEPTION 'invalid email';
  END IF;
  IF p_password_hash NOT LIKE '$argon2id$%' OR p_hash_version <= 0 THEN
    RAISE EXCEPTION 'invalid password hash material';
  END IF;

  INSERT INTO growth.users(id,email,status)
  VALUES(new_user_id,normalized_email,'active');
  INSERT INTO growth.auth_identities(id,user_id,provider)
  VALUES(new_identity_id,new_user_id,'password');
  INSERT INTO growth.password_credentials(auth_identity_id,password_hash,hash_version)
  VALUES(new_identity_id,p_password_hash,p_hash_version);
  INSERT INTO growth.audit_events(id,workspace_id,actor_user_id,event_type,resource_type,resource_id)
  VALUES(gen_random_uuid(),NULL,new_user_id,'identity.signup.completed.v1','user',new_user_id);
  RETURN new_user_id;
END;
$$;

CREATE FUNCTION growth.identity_lookup_password(p_email text)
RETURNS TABLE(
  user_id uuid,
  auth_identity_id uuid,
  password_hash text,
  hash_algorithm text,
  hash_version smallint,
  must_change boolean,
  user_status text,
  email_verified_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
  SELECT u.id, ai.id, pc.password_hash, pc.hash_algorithm, pc.hash_version,
         pc.must_change, u.status, u.email_verified_at
  FROM growth.users u
  JOIN growth.auth_identities ai
    ON ai.user_id = u.id AND ai.provider = 'password' AND ai.revoked_at IS NULL
  JOIN growth.password_credentials pc ON pc.auth_identity_id = ai.id
  WHERE lower(u.email) = lower(btrim(p_email))
  LIMIT 1;
$$;

CREATE FUNCTION growth.identity_record_login_attempt(
  p_email text, p_succeeded boolean, p_ip inet DEFAULT NULL, p_user_agent text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  normalized_email text := lower(btrim(p_email));
  matched_user_id uuid;
BEGIN
  SELECT id INTO matched_user_id FROM growth.users WHERE lower(email) = normalized_email LIMIT 1;
  INSERT INTO growth.login_attempts(email,user_id,succeeded,ip,user_agent)
  VALUES(normalized_email,matched_user_id,p_succeeded,p_ip,left(p_user_agent,1024));
END;
$$;

CREATE FUNCTION growth.identity_issue_email_verification(p_token_hash text, p_expires_at timestamptz)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  actor uuid := growth.current_app_user_id();
  actor_email text;
  verification_id uuid := gen_random_uuid();
BEGIN
  SELECT lower(btrim(email)) INTO actor_email
  FROM growth.users WHERE id = actor AND status = 'active';
  IF actor_email IS NULL OR p_expires_at <= now() THEN RAISE EXCEPTION 'invalid verification request'; END IF;
  INSERT INTO growth.email_verifications(id,user_id,email,token_hash,expires_at)
  VALUES(verification_id,actor,actor_email,p_token_hash,p_expires_at);
  RETURN verification_id;
END;
$$;

CREATE FUNCTION growth.identity_consume_email_verification(p_token_hash text)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  verification growth.email_verifications%ROWTYPE;
BEGIN
  SELECT * INTO verification FROM growth.email_verifications
  WHERE token_hash = p_token_hash AND consumed_at IS NULL AND expires_at > now()
  FOR UPDATE;
  IF verification.id IS NULL THEN RAISE EXCEPTION 'verification token invalid or expired'; END IF;
  UPDATE growth.users
  SET email_verified_at = COALESCE(email_verified_at,now())
  WHERE id = verification.user_id AND lower(btrim(email)) = verification.email AND status = 'active';
  IF NOT FOUND THEN RAISE EXCEPTION 'verification email no longer matches active user'; END IF;
  UPDATE growth.email_verifications SET consumed_at = now() WHERE id = verification.id;
  INSERT INTO growth.audit_events(id,workspace_id,actor_user_id,event_type,resource_type,resource_id)
  VALUES(gen_random_uuid(),NULL,verification.user_id,'identity.email.verified.v1','user',verification.user_id);
  RETURN verification.user_id;
END;
$$;

CREATE FUNCTION growth.identity_request_password_reset(
  p_email text, p_token_hash text, p_expires_at timestamptz,
  p_ip inet DEFAULT NULL, p_user_agent text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  matched_user_id uuid;
  reset_id uuid := gen_random_uuid();
BEGIN
  SELECT u.id INTO matched_user_id
  FROM growth.users u
  JOIN growth.auth_identities ai
    ON ai.user_id = u.id AND ai.provider = 'password' AND ai.revoked_at IS NULL
  WHERE lower(u.email) = lower(btrim(p_email)) AND u.status = 'active'
  LIMIT 1;
  IF matched_user_id IS NULL THEN RETURN NULL; END IF;
  IF p_expires_at <= now() THEN RAISE EXCEPTION 'invalid reset expiry'; END IF;
  INSERT INTO growth.password_resets(id,user_id,token_hash,expires_at,requested_ip,requested_user_agent)
  VALUES(reset_id,matched_user_id,p_token_hash,p_expires_at,p_ip,left(p_user_agent,1024));
  RETURN reset_id;
END;
$$;

CREATE FUNCTION growth.identity_complete_password_reset(
  p_token_hash text, p_password_hash text, p_hash_version smallint DEFAULT 19
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  reset_row growth.password_resets%ROWTYPE;
BEGIN
  IF p_password_hash NOT LIKE '$argon2id$%' OR p_hash_version <= 0 THEN
    RAISE EXCEPTION 'invalid password hash material';
  END IF;
  SELECT * INTO reset_row FROM growth.password_resets
  WHERE token_hash = p_token_hash AND consumed_at IS NULL AND expires_at > now()
  FOR UPDATE;
  IF reset_row.id IS NULL THEN RAISE EXCEPTION 'reset token invalid or expired'; END IF;
  UPDATE growth.password_credentials pc
  SET password_hash=p_password_hash, hash_version=p_hash_version,
      hash_algorithm='argon2id', must_change=false, updated_at=now()
  FROM growth.auth_identities ai
  WHERE pc.auth_identity_id=ai.id AND ai.user_id=reset_row.user_id
    AND ai.provider='password' AND ai.revoked_at IS NULL;
  IF NOT FOUND THEN RAISE EXCEPTION 'active password identity not found'; END IF;
  UPDATE growth.password_resets SET consumed_at=now() WHERE id=reset_row.id;
  UPDATE growth.sessions SET revoked_at=now(), revoked_reason='password_reset'
  WHERE user_id=reset_row.user_id AND revoked_at IS NULL;
  INSERT INTO growth.audit_events(id,workspace_id,actor_user_id,event_type,resource_type,resource_id)
  VALUES(gen_random_uuid(),NULL,reset_row.user_id,'identity.password_reset.completed.v1','user',reset_row.user_id);
  RETURN reset_row.user_id;
END;
$$;

CREATE FUNCTION growth.identity_create_session(
  p_user_id uuid, p_token_hash text, p_amr text[],
  p_absolute_expires_at timestamptz, p_idle_expires_at timestamptz,
  p_ip inet DEFAULT NULL, p_user_agent text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  session_id uuid := gen_random_uuid();
BEGIN
  IF growth.current_app_user_id() IS NULL OR growth.current_app_user_id() <> p_user_id THEN
    RAISE EXCEPTION 'session creation requires matching authenticated principal';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM growth.users WHERE id=p_user_id AND status='active')
     OR cardinality(p_amr)=0 OR p_idle_expires_at>p_absolute_expires_at
     OR p_idle_expires_at<=now() THEN
    RAISE EXCEPTION 'invalid session request';
  END IF;
  INSERT INTO growth.sessions(id,user_id,session_token_hash,amr,absolute_expires_at,idle_expires_at,ip,user_agent)
  VALUES(session_id,p_user_id,p_token_hash,p_amr,p_absolute_expires_at,p_idle_expires_at,p_ip,left(p_user_agent,1024));
  RETURN session_id;
END;
$$;

CREATE FUNCTION growth.identity_resolve_session(p_token_hash text)
RETURNS TABLE(session_id uuid,user_id uuid,amr text[],absolute_expires_at timestamptz,idle_expires_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
  SELECT s.id,s.user_id,s.amr,s.absolute_expires_at,s.idle_expires_at
  FROM growth.sessions s JOIN growth.users u ON u.id=s.user_id
  WHERE s.session_token_hash=p_token_hash AND s.revoked_at IS NULL
    AND now()<s.absolute_expires_at AND now()<s.idle_expires_at AND u.status='active'
  LIMIT 1;
$$;

CREATE FUNCTION growth.identity_revoke_session(p_session_id uuid, p_reason text DEFAULT 'logout')
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
BEGIN
  IF p_reason NOT IN ('logout','rotated') THEN RAISE EXCEPTION 'invalid self-revocation reason'; END IF;
  UPDATE growth.sessions SET revoked_at=now(),revoked_reason=p_reason
  WHERE id=p_session_id AND user_id=growth.current_app_user_id() AND revoked_at IS NULL;
  RETURN FOUND;
END;
$$;

CREATE FUNCTION growth.identity_revoke_all_sessions()
RETURNS integer
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE affected integer;
BEGIN
  IF growth.current_app_user_id() IS NULL THEN RAISE EXCEPTION 'logout-all requires app.user_id'; END IF;
  UPDATE growth.sessions SET revoked_at=now(),revoked_reason='logout_all'
  WHERE user_id=growth.current_app_user_id() AND revoked_at IS NULL;
  GET DIAGNOSTICS affected = ROW_COUNT;
  RETURN affected;
END;
$$;

CREATE FUNCTION growth.identity_create_workspace(
  p_name text,p_default_market text,p_default_language text,p_default_timezone text
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE actor uuid:=growth.current_app_user_id(); workspace_id uuid:=gen_random_uuid();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM growth.users WHERE id=actor AND status='active' AND email_verified_at IS NOT NULL) THEN
    RAISE EXCEPTION 'verified active user required';
  END IF;
  IF btrim(p_name)='' OR btrim(p_default_market)='' OR btrim(p_default_language)='' OR btrim(p_default_timezone)='' THEN
    RAISE EXCEPTION 'workspace fields are required';
  END IF;
  PERFORM set_config('app.workspace_id',workspace_id::text,true);
  INSERT INTO growth.workspaces(id,name,default_market,default_language,default_timezone,status)
  VALUES(workspace_id,btrim(p_name),p_default_market,p_default_language,p_default_timezone,'active');
  INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status)
  VALUES(workspace_id,actor,'owner',true,'active');
  INSERT INTO growth.audit_events(id,workspace_id,actor_user_id,event_type,resource_type,resource_id)
  VALUES(gen_random_uuid(),workspace_id,actor,'identity.workspace.created.v1','workspace',workspace_id);
  RETURN workspace_id;
END;
$$;

CREATE FUNCTION growth.identity_issue_invitation(
  p_workspace_id uuid,p_email text,p_role text,p_can_publish boolean,
  p_token_hash text,p_expires_at timestamptz
)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE actor uuid:=growth.current_app_user_id(); invitation_id uuid:=gen_random_uuid(); normalized_email text:=lower(btrim(p_email));
BEGIN
  IF growth.current_workspace_id() IS DISTINCT FROM p_workspace_id
     OR NOT growth.identity_actor_can_invite(p_workspace_id,p_role)
     OR p_expires_at<=now() THEN
    RAISE EXCEPTION 'invitation issuance denied';
  END IF;
  UPDATE growth.invitations SET status='expired'
  WHERE workspace_id=p_workspace_id AND invited_email=normalized_email
    AND status='pending' AND expires_at<=now();
  INSERT INTO growth.invitations(id,workspace_id,invited_email,invited_role,can_publish,token_hash,invited_by_user_id,expires_at)
  VALUES(invitation_id,p_workspace_id,normalized_email,p_role,p_can_publish,p_token_hash,actor,p_expires_at);
  INSERT INTO growth.audit_events(id,workspace_id,actor_user_id,event_type,resource_type,resource_id)
  VALUES(gen_random_uuid(),p_workspace_id,actor,'identity.invitation.issued.v1','invitation',invitation_id);
  RETURN invitation_id;
END;
$$;

CREATE FUNCTION growth.identity_revoke_invitation(p_invitation_id uuid)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE actor uuid:=growth.current_app_user_id(); affected integer;
BEGIN
  UPDATE growth.invitations i SET status='revoked',revoked_at=now(),revoked_by_user_id=actor
  WHERE i.id=p_invitation_id AND i.status='pending'
    AND i.workspace_id=growth.current_workspace_id()
    AND growth.identity_actor_can_invite(i.workspace_id,i.invited_role);
  GET DIAGNOSTICS affected=ROW_COUNT;
  RETURN affected=1;
END;
$$;

CREATE FUNCTION growth.identity_accept_invitation(p_token_hash text)
RETURNS uuid
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  actor uuid:=growth.current_app_user_id();
  invitation growth.invitations%ROWTYPE;
  existing_status text;
BEGIN
  IF actor IS NULL THEN RAISE EXCEPTION 'invitation acceptance requires app.user_id'; END IF;
  SELECT i.* INTO invitation
  FROM growth.invitations i JOIN growth.users u ON u.id=actor
  WHERE i.token_hash=p_token_hash AND i.status='pending' AND i.expires_at>now()
    AND i.invited_email=lower(btrim(u.email)) AND u.status='active' AND u.email_verified_at IS NOT NULL
  FOR UPDATE OF i;
  IF invitation.id IS NULL THEN RAISE EXCEPTION 'invitation invalid, expired or for another identity'; END IF;

  PERFORM set_config('app.workspace_id',invitation.workspace_id::text,true);
  PERFORM set_config('app.invitation_token_hash',p_token_hash,true);
  SELECT status INTO existing_status FROM growth.memberships
  WHERE workspace_id=invitation.workspace_id AND user_id=actor;
  IF existing_status='active' THEN RAISE EXCEPTION 'user already has active membership'; END IF;
  IF existing_status='revoked' THEN
    UPDATE growth.memberships
    SET role=invitation.invited_role,can_publish=invitation.can_publish,status='active'
    WHERE workspace_id=invitation.workspace_id AND user_id=actor;
  ELSE
    INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status)
    VALUES(invitation.workspace_id,actor,invitation.invited_role,invitation.can_publish,'active');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM growth.invitations WHERE id=invitation.id AND status='accepted') THEN
    RAISE EXCEPTION 'invitation was not consumed atomically';
  END IF;
  INSERT INTO growth.audit_events(id,workspace_id,actor_user_id,event_type,resource_type,resource_id)
  VALUES(gen_random_uuid(),invitation.workspace_id,actor,'identity.invitation.accepted.v1','invitation',invitation.id);
  RETURN invitation.workspace_id;
END;
$$;

CREATE FUNCTION growth.identity_account_audit(p_limit integer DEFAULT 100)
RETURNS TABLE(id uuid,event_type text,resource_type text,resource_id uuid,occurred_at timestamptz)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
  SELECT a.id,a.event_type,a.resource_type,a.resource_id,a.occurred_at
  FROM growth.audit_events a
  WHERE a.workspace_id IS NULL AND a.actor_user_id=growth.current_app_user_id()
  ORDER BY a.occurred_at DESC
  LIMIT LEAST(GREATEST(p_limit,1),100);
$$;

-- Transfer all public database API functions to the narrow helper role.
ALTER FUNCTION growth.identity_signup(text,text,smallint) OWNER TO growth_identity_helper;
ALTER FUNCTION growth.identity_lookup_password(text) OWNER TO growth_identity_helper;
ALTER FUNCTION growth.identity_record_login_attempt(text,boolean,inet,text) OWNER TO growth_identity_helper;
ALTER FUNCTION growth.identity_issue_email_verification(text,timestamptz) OWNER TO growth_identity_helper;
ALTER FUNCTION growth.identity_consume_email_verification(text) OWNER TO growth_identity_helper;
ALTER FUNCTION growth.identity_request_password_reset(text,text,timestamptz,inet,text) OWNER TO growth_identity_helper;
ALTER FUNCTION growth.identity_complete_password_reset(text,text,smallint) OWNER TO growth_identity_helper;
ALTER FUNCTION growth.identity_create_session(uuid,text,text[],timestamptz,timestamptz,inet,text) OWNER TO growth_identity_helper;
ALTER FUNCTION growth.identity_resolve_session(text) OWNER TO growth_identity_helper;
ALTER FUNCTION growth.identity_revoke_session(uuid,text) OWNER TO growth_identity_helper;
ALTER FUNCTION growth.identity_revoke_all_sessions() OWNER TO growth_identity_helper;
ALTER FUNCTION growth.identity_create_workspace(text,text,text,text) OWNER TO growth_identity_helper;
ALTER FUNCTION growth.identity_issue_invitation(uuid,text,text,boolean,text,timestamptz) OWNER TO growth_identity_helper;
ALTER FUNCTION growth.identity_revoke_invitation(uuid) OWNER TO growth_identity_helper;
ALTER FUNCTION growth.identity_accept_invitation(text) OWNER TO growth_identity_helper;
ALTER FUNCTION growth.identity_account_audit(integer) OWNER TO growth_identity_helper;

REVOKE ALL ON FUNCTION growth.identity_signup(text,text,smallint) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.identity_lookup_password(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.identity_record_login_attempt(text,boolean,inet,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.identity_issue_email_verification(text,timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.identity_consume_email_verification(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.identity_request_password_reset(text,text,timestamptz,inet,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.identity_complete_password_reset(text,text,smallint) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.identity_create_session(uuid,text,text[],timestamptz,timestamptz,inet,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.identity_resolve_session(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.identity_revoke_session(uuid,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.identity_revoke_all_sessions() FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.identity_create_workspace(text,text,text,text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.identity_issue_invitation(uuid,text,text,boolean,text,timestamptz) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.identity_revoke_invitation(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.identity_accept_invitation(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION growth.identity_account_audit(integer) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION growth.identity_signup(text,text,smallint) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.identity_lookup_password(text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.identity_record_login_attempt(text,boolean,inet,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.identity_issue_email_verification(text,timestamptz) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.identity_consume_email_verification(text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.identity_request_password_reset(text,text,timestamptz,inet,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.identity_complete_password_reset(text,text,smallint) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.identity_create_session(uuid,text,text[],timestamptz,timestamptz,inet,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.identity_resolve_session(text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.identity_revoke_session(uuid,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.identity_revoke_all_sessions() TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.identity_create_workspace(text,text,text,text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.identity_issue_invitation(uuid,text,text,boolean,text,timestamptz) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.identity_revoke_invitation(uuid) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.identity_accept_invitation(text) TO app_runtime;
GRANT EXECUTE ON FUNCTION growth.identity_account_audit(integer) TO app_runtime;

COMMIT;
