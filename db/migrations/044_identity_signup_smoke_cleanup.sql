-- User-authorized, one-time cleanup of the synthetic production signup smoke account.
-- The email is exact and normalized. The operation is transactional, fail-closed,
-- and refuses to delete an account with non-identity foreign-key references.
BEGIN;

CREATE TABLE IF NOT EXISTS growth.identity_signup_smoke_cleanup_044 (
  normalized_email text PRIMARY KEY,
  action text NOT NULL CHECK (action IN ('not_found', 'deleted')),
  user_id uuid,
  blocking_reference_count integer NOT NULL DEFAULT 0,
  completed_at timestamptz NOT NULL DEFAULT now()
);

DO $$
DECLARE
  target_email text := 'codex-smoke-mtvpyq4m@example.test';
  target_user_id uuid;
  match_count integer;
  blocking_count integer := 0;
  reference_count bigint;
  fk record;
BEGIN
  IF EXISTS (
    SELECT 1
    FROM growth.identity_signup_smoke_cleanup_044
    WHERE normalized_email = target_email
  ) THEN
    RAISE NOTICE 'Signup smoke cleanup already reconciled';
    RETURN;
  END IF;

  SELECT count(*) INTO match_count
  FROM growth.users
  WHERE lower(btrim(email)) = target_email;

  IF match_count = 0 THEN
    INSERT INTO growth.identity_signup_smoke_cleanup_044(normalized_email, action)
    VALUES (target_email, 'not_found');
    RAISE NOTICE 'Signup smoke cleanup found no matching account';
    RETURN;
  END IF;

  IF match_count <> 1 THEN
    RAISE EXCEPTION 'Signup smoke cleanup refused: unexpected duplicate count %', match_count;
  END IF;

  SELECT id INTO target_user_id
  FROM growth.users
  WHERE lower(btrim(email)) = target_email;

  -- Remove only identity-owned records first.
  DELETE FROM growth.password_resets WHERE user_id = target_user_id;
  DELETE FROM growth.email_verifications WHERE user_id = target_user_id;
  DELETE FROM growth.sessions WHERE user_id = target_user_id;
  UPDATE growth.login_attempts SET user_id = NULL WHERE user_id = target_user_id;
  UPDATE growth.audit_events SET actor_user_id = NULL WHERE actor_user_id = target_user_id;
  DELETE FROM growth.password_credentials
  WHERE auth_identity_id IN (
    SELECT id FROM growth.auth_identities WHERE user_id = target_user_id
  );
  DELETE FROM growth.auth_identities WHERE user_id = target_user_id;

  -- Any remaining FK reference means the account is linked to non-identity data.
  FOR fk IN
    SELECT
      child_ns.nspname AS child_schema,
      child.relname AS child_table,
      child_col.attname AS child_column
    FROM pg_constraint c
    JOIN pg_class parent ON parent.oid = c.confrelid
    JOIN pg_namespace parent_ns ON parent_ns.oid = parent.relnamespace
    JOIN pg_class child ON child.oid = c.conrelid
    JOIN pg_namespace child_ns ON child_ns.oid = child.relnamespace
    JOIN pg_attribute child_col
      ON child_col.attrelid = child.oid
     AND child_col.attnum = c.conkey[1]
    WHERE c.contype = 'f'
      AND parent_ns.nspname = 'growth'
      AND parent.relname = 'users'
      AND array_length(c.conkey, 1) = 1
  LOOP
    EXECUTE format(
      'SELECT count(*) FROM %I.%I WHERE %I = $1',
      fk.child_schema,
      fk.child_table,
      fk.child_column
    )
    INTO reference_count
    USING target_user_id;

    blocking_count := blocking_count + reference_count::integer;
  END LOOP;

  IF blocking_count > 0 THEN
    RAISE EXCEPTION
      'Signup smoke cleanup refused: % non-identity references remain',
      blocking_count;
  END IF;

  DELETE FROM growth.users WHERE id = target_user_id;

  INSERT INTO growth.identity_signup_smoke_cleanup_044(
    normalized_email, action, user_id
  )
  VALUES (target_email, 'deleted', target_user_id);

  RAISE NOTICE 'Signup smoke cleanup deleted the synthetic account';
END;
$$;

COMMIT;
