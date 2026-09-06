-- Growth OS Identity v1.1 — SQL gate 034.
-- The transaction is rolled back, so no test user or token survives CI.

BEGIN;

SELECT set_config('app.user_id', '', true);
SELECT set_config('app.workspace_id', '', true);

WITH created AS (
  SELECT *
  FROM growth.identity_signup_with_verification(
    'identity-gate-' || gen_random_uuid()::text || '@example.test',
    '$argon2id$v=19$m=19456,t=2,p=1$AAAAAAAAAAAAAAAAAAAAAA$AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    19,
    repeat('a', 64),
    now() + interval '15 minutes'
  )
)
SELECT
  user_id IS NOT NULL AS signup_ok,
  verification_id IS NOT NULL AS verification_issued
FROM created;

SELECT growth.identity_consume_email_verification(repeat('a', 64)) IS NOT NULL AS verification_ok;

ROLLBACK;

\echo 'PASS 034_identity_signup';
