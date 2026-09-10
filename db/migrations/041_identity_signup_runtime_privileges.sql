-- Growth OS Identity v1.2 — repaired signup execution path.
-- The original signup wrapper called a helper-owned function without granting
-- EXECUTE to that helper. PostgreSQL correctly returned 42501 in production.
-- New functions are created by the migration role, granted before ownership is
-- transferred to the identity helper, and then used by the API.

\set ON_ERROR_STOP on

BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'app_runtime')
     OR NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'growth_identity_helper') THEN
    RAISE EXCEPTION 'identity runtime roles are required';
  END IF;
END $$;

GRANT USAGE ON SCHEMA growth TO app_runtime, growth_identity_helper;
GRANT SELECT, INSERT, UPDATE ON
  growth.users,
  growth.auth_identities,
  growth.password_credentials,
  growth.email_verifications,
  growth.audit_events
TO growth_identity_helper;

CREATE FUNCTION growth.identity_signup_v2(
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
  IF normalized_email = '' OR length(normalized_email) > 320
     OR position('@' in normalized_email) < 2 THEN
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
  INSERT INTO growth.audit_events(
    id,workspace_id,actor_user_id,event_type,resource_type,resource_id
  )
  VALUES(
    gen_random_uuid(),NULL,new_user_id,'identity.signup.completed.v1','user',new_user_id
  );
  RETURN new_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION growth.identity_signup_v2(text,text,smallint)
  TO growth_identity_helper;
ALTER FUNCTION growth.identity_signup_v2(text,text,smallint)
  OWNER TO growth_identity_helper;

CREATE FUNCTION growth.identity_signup_with_verification_v2(
  p_email text,
  p_password_hash text,
  p_hash_version smallint,
  p_token_hash text,
  p_expires_at timestamptz
)
RETURNS TABLE(user_id uuid, verification_id uuid)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = pg_catalog, growth
AS $$
DECLARE
  created_user_id uuid;
  created_verification_id uuid := gen_random_uuid();
BEGIN
  IF p_token_hash !~ '^[0-9a-f]{64}$' OR p_expires_at <= now() THEN
    RAISE EXCEPTION 'invalid verification material';
  END IF;

  created_user_id := growth.identity_signup_v2(
    p_email, p_password_hash, p_hash_version
  );

  INSERT INTO growth.email_verifications(
    id, user_id, email, token_hash, expires_at
  )
  SELECT
    created_verification_id,
    u.id,
    lower(btrim(u.email)),
    p_token_hash,
    p_expires_at
  FROM growth.users u
  WHERE u.id = created_user_id
    AND u.status = 'active';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'signup user was not created';
  END IF;

  RETURN QUERY SELECT created_user_id, created_verification_id;
END;
$$;

GRANT EXECUTE ON FUNCTION growth.identity_signup_with_verification_v2(
  text,text,smallint,text,timestamptz
) TO app_runtime;
ALTER FUNCTION growth.identity_signup_with_verification_v2(
  text,text,smallint,text,timestamptz
) OWNER TO growth_identity_helper;

DO $$
BEGIN
  IF NOT has_function_privilege(
    'app_runtime',
    'growth.identity_signup_with_verification_v2(text,text,smallint,text,timestamptz)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'app_runtime cannot execute repaired identity signup';
  END IF;
  IF NOT has_function_privilege(
    'growth_identity_helper',
    'growth.identity_signup_v2(text,text,smallint)',
    'EXECUTE'
  ) THEN
    RAISE EXCEPTION 'identity helper cannot execute repaired identity signup';
  END IF;
END $$;

COMMIT;
