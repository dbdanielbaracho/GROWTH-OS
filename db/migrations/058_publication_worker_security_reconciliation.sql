-- Reconcile the worker helper boundary on an existing production database.
-- The runtime role must execute helpers only; table access stays with the
-- SECURITY DEFINER owner.

BEGIN;

ALTER FUNCTION growth.claim_due_publication_job(uuid, timestamptz, integer)
  OWNER TO growth_migrator;
ALTER FUNCTION growth.claim_due_publication_job(uuid, timestamptz, integer)
  SECURITY DEFINER;
REVOKE ALL ON FUNCTION growth.claim_due_publication_job(uuid, timestamptz, integer)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.claim_due_publication_job(uuid, timestamptz, integer)
  TO growth_worker;

ALTER FUNCTION growth.complete_publication_job(uuid, uuid, text, timestamptz, text)
  OWNER TO growth_migrator;
ALTER FUNCTION growth.complete_publication_job(uuid, uuid, text, timestamptz, text)
  SECURITY DEFINER;
REVOKE ALL ON FUNCTION growth.complete_publication_job(uuid, uuid, text, timestamptz, text)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION growth.complete_publication_job(uuid, uuid, text, timestamptz, text)
  TO growth_worker;

COMMIT;
