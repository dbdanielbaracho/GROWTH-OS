\set ON_ERROR_STOP on
SET search_path = growth, public;

-- This script is intended to run after 001_initial_schema.sql in an isolated test DB.
-- It uses explicit UUID fixtures and raises on unexpected success.
--
-- RC9 correction: the insight_evidence INSERT below now supplies an explicit
-- id. insight_evidence.id is uuid PRIMARY KEY with no DEFAULT (schema is
-- immutable and unchanged); the original RC8 fixture omitted id and could
-- never complete execution. This is a fix to the test fixture only.

DO $$
DECLARE
  w uuid := '10000000-0000-0000-0000-000000000001';
  ma uuid := '20000000-0000-0000-0000-000000000001';
  ah uuid := '30000000-0000-0000-0000-000000000001';
BEGIN
  INSERT INTO growth.workspaces(id,name,default_market,default_language,default_timezone,status)
  VALUES(w,'trigger-test','US','en','UTC','active');

  -- Must work even if session search_path does not contain growth because trigger bodies are schema-qualified.
  PERFORM set_config('search_path', '"$user", public', false);

  INSERT INTO growth.managed_accounts(id,workspace_id,owner_type,authority_status,contribution_eligibility)
  VALUES(ma,w,'direct','contractually_granted','private_only');
  INSERT INTO growth.authority_history(id,workspace_id,managed_account_id,owner_type,authority_status,contribution_eligibility,effective_from)
  VALUES(ah,w,ma,'direct','contractually_granted','private_only',clock_timestamp());

  SET CONSTRAINTS ALL IMMEDIATE;
END$$;

-- confirmed_account with ZERO evidence must fail at deferred-check time.
DO $$
DECLARE
  w uuid := '10000000-0000-0000-0000-000000000001';
  i uuid := '40000000-0000-0000-0000-000000000001';
  failed boolean := false;
BEGIN
  BEGIN
    INSERT INTO growth.insights(id,workspace_id,state,claim,logic_version,valid_from)
    VALUES(i,w,'confirmed_account','must fail: zero evidence','vtest',clock_timestamp());
    SET CONSTRAINTS ALL IMMEDIATE;
  EXCEPTION WHEN others THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'TEST FAIL: confirmed_account with zero evidence was accepted';
  END IF;
END$$;

-- confirmed_account with one owned evidence must pass.
DO $$
DECLARE
  w uuid := '10000000-0000-0000-0000-000000000001';
  i uuid := '40000000-0000-0000-0000-000000000002';
BEGIN
  INSERT INTO growth.insights(id,workspace_id,state,claim,logic_version,valid_from)
  VALUES(i,w,'account_hypothesis','owned evidence path','vtest',clock_timestamp());
  INSERT INTO growth.insight_evidence(id,workspace_id,insight_id,evidence_type,evidence_ref,source_class)
  VALUES('50000000-0000-0000-0000-000000000001',w,i,'metric','owned:test','owned');
  UPDATE growth.insights SET state='confirmed_account' WHERE workspace_id=w AND id=i;
  SET CONSTRAINTS ALL IMMEDIATE;
END$$;

-- Deleting the last owned evidence from a confirmed insight must fail.
DO $$
DECLARE
  w uuid := '10000000-0000-0000-0000-000000000001';
  i uuid := '40000000-0000-0000-0000-000000000002';
  failed boolean := false;
BEGIN
  BEGIN
    DELETE FROM growth.insight_evidence WHERE workspace_id=w AND insight_id=i;
    SET CONSTRAINTS ALL IMMEDIATE;
  EXCEPTION WHEN others THEN
    failed := true;
  END;
  IF NOT failed THEN
    RAISE EXCEPTION 'TEST FAIL: last owned evidence could be deleted from confirmed insight';
  END IF;
END$$;

-- Moving the only owned evidence away from a confirmed insight via UPDATE must fail.
DO $$
DECLARE
  w uuid := '10000000-0000-0000-0000-000000000001';
  confirmed_i uuid := '40000000-0000-0000-0000-000000000002';
  target_i uuid := '40000000-0000-0000-0000-000000000003';
  failed boolean := false;
BEGIN
  INSERT INTO growth.insights(id,workspace_id,state,claim,logic_version,valid_from)
  VALUES(target_i,w,'account_hypothesis','move target','vtest',clock_timestamp());

  BEGIN
    UPDATE growth.insight_evidence
       SET insight_id = target_i
     WHERE workspace_id=w AND insight_id=confirmed_i;
    SET CONSTRAINTS ALL IMMEDIATE;
  EXCEPTION WHEN others THEN
    failed := true;
  END;

  IF NOT failed THEN
    RAISE EXCEPTION 'TEST FAIL: evidence could be moved away from confirmed insight leaving zero owned evidence';
  END IF;
END$$;
