-- Growth OS — creative_generations full state machine, all 42 possible
-- transitions (7 states x 7, minus same-state), executed one by one via
-- app_runtime under real RLS (not growth_test_harness, not a bypass).

\set ON_ERROR_STOP on
SET search_path = growth, public;

DO $$
DECLARE
  states text[] := ARRAY['requested','queued','processing','succeeded','failed','cancelled','ambiguous'];
  s1 text;
  s2 text;
  test_id uuid;
  succeeded_transition boolean;
  expected boolean;
  wrong_count int := 0;
  total_checked int := 0;
BEGIN
  FOREACH s1 IN ARRAY states LOOP
    FOREACH s2 IN ARRAY states LOOP
      CONTINUE WHEN s1 = s2;
      total_checked := total_checked + 1;

      expected := (s1,s2) IN (
        ('requested','queued'), ('requested','cancelled'),
        ('queued','processing'), ('queued','cancelled'),
        ('processing','succeeded'), ('processing','failed'),
        ('processing','ambiguous'), ('processing','cancelled'),
        ('ambiguous','succeeded'), ('ambiguous','failed')
      );

      test_id := gen_random_uuid();
      INSERT INTO growth.creative_generations(id,workspace_id,creative_request_id,provider,status,idempotency_key)
      VALUES(test_id,'b0000000-0000-4000-8000-000000000001','e1000000-0000-4000-8000-000000000001','test-provider',s1,'idem-sm-'||test_id::text);

      BEGIN
        UPDATE growth.creative_generations SET status = s2 WHERE id = test_id;
        succeeded_transition := true;
      EXCEPTION WHEN OTHERS THEN
        succeeded_transition := false;
      END;

      IF succeeded_transition <> expected THEN
        wrong_count := wrong_count + 1;
        RAISE NOTICE 'MISMATCH: % -> % : expected=%, actual=%', s1, s2, expected, succeeded_transition;
      END IF;
    END LOOP;
  END LOOP;

  IF total_checked <> 42 THEN
    RAISE EXCEPTION 'TEST SETUP FAIL: expected to check 42 transitions, checked %', total_checked;
  END IF;
  IF wrong_count > 0 THEN
    RAISE EXCEPTION 'TEST FAIL: % of 42 transitions mismatched the expected allow-list', wrong_count;
  END IF;
  RAISE NOTICE 'PASS: all 42 transitions verified under real RLS (app_runtime, tenant-scoped session)';
END $$;

\echo 'PASS: creative_generations full state machine (42/42) verified under real RLS'

-- Cleanup: app_runtime deliberately has no DELETE on creative_generations
-- (append-only-ish philosophy), so the 42 fixture rows above are removed
-- via growth_test_harness (BYPASSRLS, test-only role).
SET ROLE growth_test_harness;
SELECT set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
DELETE FROM growth.creative_generations WHERE provider = 'test-provider';
RESET ROLE;
