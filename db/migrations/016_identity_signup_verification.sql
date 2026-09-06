-- Growth OS Identity v1.1 — atomic signup plus email verification issuance.
-- This migration is forward-only and is applied with the isolated CI admin
-- identity because the SECURITY DEFINER owner is the test/prod identity helper.

BEGIN;

CREATE FUNCTION growth.identity_signup_with_verification(
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

  created_user_id := growth.identity_signup(p_email, p_password_hash, p_hash_version);

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

ALTER FUNCTION growth.identity_signup_with_verification(text,text,smallint,text,timestamptz)
  OWNER TO growth_identity_helper;
REVOKE ALL ON FUNCTION growth.identity_signup_with_verification(text,text,smallint,text,timestamptz) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.identity_signup_with_verification(text,text,smallint,text,timestamptz) TO app_runtime;

COMMIT;
