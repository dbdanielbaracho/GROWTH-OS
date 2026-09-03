-- Growth OS — production identity adapter support (Issue #24).
-- Forward-only migration. Do not modify Identity v1 migration 006.
-- Adds only narrow SECURITY DEFINER helpers required by the production
-- application adapter; no direct secret-table grants are widened.

\set ON_ERROR_STOP on

BEGIN;
SET search_path = growth, public;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_runtime') THEN
    RAISE EXCEPTION 'app_runtime role is required';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_identity_helper') THEN
    RAISE EXCEPTION 'growth_identity_helper role is required';
  END IF;
  IF to_regclass('growth.sessions') IS NULL
     OR to_regclass('growth.users') IS NULL
     OR to_regclass('growth.login_attempts') IS NULL
     OR to_regclass('growth.auth_identities') IS NULL
     OR to_regclass('growth.password_credentials') IS NULL THEN
    RAISE EXCEPTION 'Identity v1 tables are required before migration 009';
  END IF;
END $$;

-- ------------------------------------------------------------------
-- Session idle-expiry renewal.
-- Resolve remains read-only; touch is a second fail-closed check after
-- app.user_id has been established from the resolved session.
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION growth.identity_touch_session(
  p_session_id uuid,
  p_requested_idle_expires_at timestamptz
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  actor uuid := growth.current_app_user_id();
  affected integer;
BEGIN
  IF actor IS NULL OR p_requested_idle_expires_at IS NULL OR p_requested_idle_expires_at <= now() THEN
    RETURN false;
  END IF;

  UPDATE growth.sessions s
     SET last_seen_at = now(),
         idle_expires_at = GREATEST(
           s.idle_expires_at,
           LEAST(p_requested_idle_expires_at, s.absolute_expires_at)
         )
   WHERE s.id = p_session_id
     AND s.user_id = actor
     AND s.revoked_at IS NULL
     AND now() < s.absolute_expires_at
     AND now() < s.idle_expires_at
     AND EXISTS (
       SELECT 1 FROM growth.users u
       WHERE u.id = s.user_id AND u.status = 'active'
     );

  GET DIAGNOSTICS affected = ROW_COUNT;
  RETURN affected = 1;
END;
$$;
ALTER FUNCTION growth.identity_touch_session(uuid,timestamptz) OWNER TO growth_identity_helper;
REVOKE ALL ON FUNCTION growth.identity_touch_session(uuid,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.identity_touch_session(uuid,timestamptz) TO app_runtime;

-- ------------------------------------------------------------------
-- Atomic distributed login-throttle reservation.
--
-- Every credential attempt reserves a row BEFORE the expensive Argon2
-- verification. Transaction-scoped advisory locks serialize reservations
-- for the same normalized email and IP, preventing a concurrent burst from
-- racing through a separate check-then-record sequence.
--
-- The reservation is pessimistically stored as succeeded=false. A genuinely
-- successful credential verification upgrades exactly that reservation via
-- identity_complete_login_attempt(). Failed attempts require no second write.
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION growth.identity_begin_login_attempt(
  p_email text,
  p_ip inet,
  p_user_agent text,
  p_window interval,
  p_max_email_failures integer,
  p_max_ip_failures integer
)
RETURNS TABLE(
  attempt_id uuid,
  email_failures integer,
  ip_failures integer,
  blocked boolean
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  normalized_email text := lower(btrim(p_email));
  window_start timestamptz;
  last_success timestamptz;
  matched_user_id uuid;
BEGIN
  IF normalized_email = '' OR length(normalized_email) > 320
     OR p_window IS NULL OR p_window <= interval '0 seconds'
     OR p_window > interval '24 hours'
     OR p_max_email_failures < 1 OR p_max_email_failures > 1000
     OR p_max_ip_failures < 1 OR p_max_ip_failures > 10000 THEN
    RAISE EXCEPTION 'invalid login throttle policy';
  END IF;

  -- Deterministic lock order prevents email/IP lock-order deadlocks.
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('growth-login-email:' || normalized_email, 0)
  );
  IF p_ip IS NOT NULL THEN
    PERFORM pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('growth-login-ip:' || p_ip::text, 0)
    );
  END IF;

  window_start := now() - p_window;

  SELECT max(la.attempted_at)
    INTO last_success
    FROM growth.login_attempts la
   WHERE la.email = normalized_email
     AND la.succeeded = true
     AND la.attempted_at >= window_start;

  SELECT count(*)::integer
    INTO email_failures
    FROM growth.login_attempts la
   WHERE la.email = normalized_email
     AND la.succeeded = false
     AND la.attempted_at >= GREATEST(window_start, COALESCE(last_success, window_start));

  IF p_ip IS NULL THEN
    ip_failures := 0;
  ELSE
    SELECT count(*)::integer
      INTO ip_failures
      FROM growth.login_attempts la
     WHERE la.ip = p_ip
       AND la.succeeded = false
       AND la.attempted_at >= window_start;
  END IF;

  blocked := email_failures >= p_max_email_failures
             OR ip_failures >= p_max_ip_failures;

  IF blocked THEN
    attempt_id := NULL;
    RETURN NEXT;
    RETURN;
  END IF;

  SELECT u.id
    INTO matched_user_id
    FROM growth.users u
   WHERE lower(u.email) = normalized_email
   LIMIT 1;

  attempt_id := gen_random_uuid();
  INSERT INTO growth.login_attempts(
    id, email, user_id, succeeded, ip, user_agent
  ) VALUES (
    attempt_id,
    normalized_email,
    matched_user_id,
    false,
    p_ip,
    left(p_user_agent, 1024)
  );

  email_failures := email_failures + 1;
  IF p_ip IS NOT NULL THEN
    ip_failures := ip_failures + 1;
  END IF;
  blocked := false;
  RETURN NEXT;
END;
$$;
ALTER FUNCTION growth.identity_begin_login_attempt(text,inet,text,interval,integer,integer)
  OWNER TO growth_identity_helper;
REVOKE ALL ON FUNCTION growth.identity_begin_login_attempt(text,inet,text,interval,integer,integer)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.identity_begin_login_attempt(text,inet,text,interval,integer,integer)
  TO app_runtime;

CREATE OR REPLACE FUNCTION growth.identity_complete_login_attempt(p_attempt_id uuid)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  affected integer;
BEGIN
  IF p_attempt_id IS NULL THEN
    RETURN false;
  END IF;

  UPDATE growth.login_attempts
     SET succeeded = true
   WHERE id = p_attempt_id
     AND succeeded = false;

  GET DIAGNOSTICS affected = ROW_COUNT;
  RETURN affected = 1;
END;
$$;
ALTER FUNCTION growth.identity_complete_login_attempt(uuid) OWNER TO growth_identity_helper;
REVOKE ALL ON FUNCTION growth.identity_complete_login_attempt(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.identity_complete_login_attempt(uuid) TO app_runtime;

-- ------------------------------------------------------------------
-- Transparent Argon2 work-factor upgrade after a successful login.
-- app_runtime never receives UPDATE on password_credentials.
-- ------------------------------------------------------------------
CREATE OR REPLACE FUNCTION growth.identity_upgrade_password_hash(
  p_auth_identity_id uuid,
  p_password_hash text,
  p_hash_version smallint DEFAULT 19
)
RETURNS boolean
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  actor uuid := growth.current_app_user_id();
  affected integer;
BEGIN
  IF actor IS NULL OR p_password_hash NOT LIKE '$argon2id$%' OR p_hash_version <= 0 THEN
    RETURN false;
  END IF;

  UPDATE growth.password_credentials pc
     SET password_hash = p_password_hash,
         hash_algorithm = 'argon2id',
         hash_version = p_hash_version,
         updated_at = now()
    FROM growth.auth_identities ai
   WHERE pc.auth_identity_id = ai.id
     AND ai.id = p_auth_identity_id
     AND ai.user_id = actor
     AND ai.provider = 'password'
     AND ai.revoked_at IS NULL;

  GET DIAGNOSTICS affected = ROW_COUNT;
  RETURN affected = 1;
END;
$$;
ALTER FUNCTION growth.identity_upgrade_password_hash(uuid,text,smallint)
  OWNER TO growth_identity_helper;
REVOKE ALL ON FUNCTION growth.identity_upgrade_password_hash(uuid,text,smallint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.identity_upgrade_password_hash(uuid,text,smallint) TO app_runtime;

COMMIT;
