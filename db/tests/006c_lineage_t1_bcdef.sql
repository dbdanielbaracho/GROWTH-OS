-- Growth OS RC9 — T1 (b-f), completing 006_lineage_temporal_guards.sql's
-- experiment/exposure/outcome chronology scenarios. Built against the
-- exact trigger logic read from the schema (not guessed):
--   enforce_exposure_temporal_integrity(): exposure.eligible_at vs
--     experiment.started_at/ended_at (T1a, done) and vs min(outcome
--     window_start) for that exposure (T1c).
--   enforce_experiment_temporal_integrity(): experiment.started_at/
--     ended_at UPDATE vs existing exposures' eligible_at / latest
--     activity (T1d, T1e).
--   enforce_experiment_outcome_temporal_integrity(): outcome.window_start
--     vs exposure.multiplication_eligible_at (T1b).
--
-- Reuses experiment exp='92000000-...-0003' (started_at=2026-06-01) from
-- 006b_lineage_l1_t1.sql's T1a setup; T1a's own exposure attempt was
-- correctly rejected and left no row, so a fresh valid exposure is created
-- here first.

\set ON_ERROR_STOP on
SET search_path = growth, public;

DO $$
DECLARE
  exp uuid := '92000000-0000-4000-8000-000000000003';
  sa uuid := '91000000-0000-4000-8000-000000000003';
  valid_exposure uuid := '92000000-0000-4000-8000-000000000005';
  caught_sqlstate text;
  caught_message text;
BEGIN
  -- Setup: one valid exposure, eligible_at within experiment bounds.
  INSERT INTO growth.exposures(id,workspace_id,experiment_id,social_account_id,multiplication_eligible_at)
  VALUES(valid_exposure,'b0000000-0000-4000-8000-000000000001'::uuid,exp,sa,'2026-06-05T00:00:00Z');
  RAISE NOTICE 'PASS (T1 setup): valid exposure created within experiment bounds';

  -- T1b: outcome.window_start before exposure eligibility must fail.
  BEGIN
    INSERT INTO growth.experiment_outcomes(id,workspace_id,exposure_id,metric_key,window_start,window_end,value,completeness)
    VALUES('92000000-0000-4000-8000-000000000006'::uuid,'b0000000-0000-4000-8000-000000000001'::uuid,valid_exposure,'engagement_rate','2026-06-01T00:00:00Z','2026-06-10T00:00:00Z',0.5,'complete');
    RAISE EXCEPTION 'TEST FAIL (T1b): outcome window_start before exposure eligibility was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE, caught_message = MESSAGE_TEXT;
  END;
  IF caught_message NOT ILIKE '%outcome window cannot start before exposure eligibility%' THEN
    RAISE EXCEPTION 'TEST FAIL (T1b): rejected for the wrong reason: % (%)', caught_message, caught_sqlstate;
  END IF;
  RAISE NOTICE 'PASS (T1b): outcome window before exposure eligibility rejected — %', caught_message;

  -- Now insert a VALID outcome (window_start >= eligible_at) so T1c has
  -- something real to test moving the exposure past.
  INSERT INTO growth.experiment_outcomes(id,workspace_id,exposure_id,metric_key,window_start,window_end,value,completeness)
  VALUES('92000000-0000-4000-8000-000000000007'::uuid,'b0000000-0000-4000-8000-000000000001'::uuid,valid_exposure,'engagement_rate','2026-06-06T00:00:00Z','2026-06-10T00:00:00Z',0.5,'complete');
  RAISE NOTICE 'PASS (T1 setup): valid outcome created (window_start >= exposure eligibility)';

  -- T1c: moving exposure eligibility to AFTER the existing outcome's
  -- window_start must fail.
  BEGIN
    UPDATE growth.exposures SET multiplication_eligible_at = '2026-06-08T00:00:00Z'
     WHERE id = valid_exposure AND workspace_id = 'b0000000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION 'TEST FAIL (T1c): moving exposure eligibility past an existing outcome window was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE, caught_message = MESSAGE_TEXT;
  END;
  IF caught_message NOT ILIKE '%exposure eligibility cannot move after an existing outcome window%' THEN
    RAISE EXCEPTION 'TEST FAIL (T1c): rejected for the wrong reason: % (%)', caught_message, caught_sqlstate;
  END IF;
  RAISE NOTICE 'PASS (T1c): moving exposure past existing outcome window rejected — %', caught_message;

  -- T1d: moving experiment.started_at to AFTER the existing exposure's
  -- eligible_at must fail.
  BEGIN
    UPDATE growth.experiments SET started_at = '2026-06-10T00:00:00Z'
     WHERE id = exp AND workspace_id = 'b0000000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION 'TEST FAIL (T1d): moving experiment start past an existing exposure was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE, caught_message = MESSAGE_TEXT;
  END;
  IF caught_message NOT ILIKE '%experiment start cannot move after an existing exposure%' THEN
    RAISE EXCEPTION 'TEST FAIL (T1d): rejected for the wrong reason: % (%)', caught_message, caught_sqlstate;
  END IF;
  RAISE NOTICE 'PASS (T1d): moving experiment start past existing exposure rejected — %', caught_message;

  -- T1e: moving experiment.ended_at to BEFORE existing exposure activity
  -- must fail. Exposure activity = GREATEST(eligible_at, assigned_at,
  -- released_at) = 2026-06-05 (no assigned_at/released_at set).
  BEGIN
    UPDATE growth.experiments SET ended_at = '2026-06-02T00:00:00Z'
     WHERE id = exp AND workspace_id = 'b0000000-0000-4000-8000-000000000001'::uuid;
    RAISE EXCEPTION 'TEST FAIL (T1e): moving experiment end before existing exposure activity was accepted';
  EXCEPTION WHEN OTHERS THEN
    GET STACKED DIAGNOSTICS caught_sqlstate = RETURNED_SQLSTATE, caught_message = MESSAGE_TEXT;
  END;
  IF caught_message NOT ILIKE '%experiment end cannot move before existing exposure activity%' THEN
    RAISE EXCEPTION 'TEST FAIL (T1e): rejected for the wrong reason: % (%)', caught_message, caught_sqlstate;
  END IF;
  RAISE NOTICE 'PASS (T1e): moving experiment end before existing exposure activity rejected — %', caught_message;

  -- T1f: a fully valid chronology, built end to end, must succeed.
  DECLARE
    exp2 uuid := '92000000-0000-4000-8000-000000000008';
    exposure2 uuid := '92000000-0000-4000-8000-000000000009';
    rows_after int;
  BEGIN
    INSERT INTO growth.experiments(id,workspace_id,hypothesis_id,design_type,status,eligibility_rule,started_at,ended_at)
    VALUES(exp2,'b0000000-0000-4000-8000-000000000001'::uuid,'92000000-0000-4000-8000-000000000001'::uuid,'ab','running','{}'::jsonb,'2026-07-01T00:00:00Z','2026-07-31T00:00:00Z');
    INSERT INTO growth.exposures(id,workspace_id,experiment_id,social_account_id,multiplication_eligible_at)
    VALUES(exposure2,'b0000000-0000-4000-8000-000000000001'::uuid,exp2,sa,'2026-07-05T00:00:00Z');
    INSERT INTO growth.experiment_outcomes(id,workspace_id,exposure_id,metric_key,window_start,window_end,value,completeness)
    VALUES('92000000-0000-4000-8000-00000000000a'::uuid,'b0000000-0000-4000-8000-000000000001'::uuid,exposure2,'engagement_rate','2026-07-06T00:00:00Z','2026-07-10T00:00:00Z',0.7,'complete');

    SELECT count(*) INTO rows_after FROM growth.experiment_outcomes WHERE exposure_id = exposure2;
    IF rows_after <> 1 THEN
      RAISE EXCEPTION 'TEST FAIL (T1f): valid end-to-end chronology did not insert as expected';
    END IF;
    RAISE NOTICE 'PASS (T1f): fully valid experiment/exposure/outcome chronology accepted end to end';
  END;
END $$;

\echo 'PASS: T1 (b-f) fully executed and verified. T1 (all a-f) now complete.'
