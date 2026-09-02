-- Growth OS — creative_requests.source_id existence validation.
--
-- By design (v0.5.2, Section 2 "Source Context obrigatório"), source_id
-- has NO foreign key — the referenced table varies by source_type, and a
-- rigid polymorphic FK was explicitly rejected in favor of the typed
-- loose reference pattern already established by insight_evidence.
--
-- This means the DATABASE alone does not reject a nonexistent or
-- cross-workspace source_id at INSERT time. That is intentional, not an
-- oversight — but it also means existence/ownership validation MUST
-- happen at the application/service layer, with real tests, or the
-- "não pode ser semanticamente órfã" requirement is unenforced in
-- practice. This file documents the current DB-level reality explicitly
-- rather than silently assume it; the actual validation contract is
-- implemented and tested at the application layer
-- (apps/api/src/creative.ts), where the real check happens.

\set ON_ERROR_STOP on
SET search_path = growth, public;

DO $$
DECLARE
  fake_id uuid := gen_random_uuid();
  inserted boolean;
BEGIN
  SET ROLE app_runtime;
  PERFORM set_config('app.user_id', 'a0000000-0000-4000-8000-000000000001', true);
  PERFORM set_config('app.workspace_id', 'b0000000-0000-4000-8000-000000000001', true);
  BEGIN
    INSERT INTO growth.creative_requests(id,workspace_id,source_type,source_id,capability,modality,target_market,target_language,requested_by,status)
    VALUES(gen_random_uuid(),'b0000000-0000-4000-8000-000000000001','experiment',fake_id,'x','text','US','en','a0000000-0000-4000-8000-000000000001','requested');
    inserted := true;
  EXCEPTION WHEN OTHERS THEN
    inserted := false;
  END;
  RESET ROLE;

  IF NOT inserted THEN
    RAISE EXCEPTION 'TEST FAIL: a nonexistent source_id was unexpectedly rejected at the DB level — the design assumption (no FK, application-layer validation) no longer matches reality; re-confirm which layer is actually responsible before trusting this test';
  END IF;
  RAISE NOTICE 'CONFIRMED (by design): the database accepts a nonexistent source_id — source_type + source_id existence/ownership validation is an application-layer responsibility, tested separately against apps/api/src/creative.ts, not enforced here';
END $$;
