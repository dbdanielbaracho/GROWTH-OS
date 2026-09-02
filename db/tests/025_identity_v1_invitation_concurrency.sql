-- Growth OS Identity v1 — final-state assertion for a real dual-session
-- invitation acceptance race.
--
-- Setup: create one verified invited user and one pending invitation. Start
-- two independent psql sessions as app_runtime with the same app.user_id.
-- In both sessions call growth.identity_accept_invitation(<same token hash>)
-- concurrently. Exactly one call must commit; the other must fail after the
-- FOR UPDATE waiter observes status='accepted'. Then execute this assertion.

\set ON_ERROR_STOP on
SET search_path = growth, public;

DO $$
DECLARE
  invitation_rows integer;
  membership_rows integer;
  invitation_state text;
BEGIN
  SELECT count(*),max(status) INTO invitation_rows,invitation_state
  FROM growth.invitations WHERE token_hash=repeat('9',64);
  SELECT count(*) INTO membership_rows
  FROM growth.memberships m
  JOIN growth.users u ON u.id=m.user_id
  WHERE u.email='identity.concurrent@example.com' AND m.status='active';
  IF invitation_rows<>1 OR invitation_state<>'accepted' OR membership_rows<>1 THEN
    RAISE EXCEPTION 'TEST FAIL: race final state invitation_rows=% state=% membership_rows=%',
      invitation_rows,invitation_state,membership_rows;
  END IF;
  RAISE NOTICE 'PASS: concurrent accept produced one accepted invitation and one active membership';
END $$;

\echo 'PASS: Identity v1 invitation acceptance concurrency'
