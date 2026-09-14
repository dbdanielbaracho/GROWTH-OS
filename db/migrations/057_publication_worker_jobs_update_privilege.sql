-- The SECURITY DEFINER publication queue helpers are owned by growth_migrator.
-- Claim and completion update only the durable job row; keep the grant narrow.

BEGIN;

GRANT SELECT, UPDATE ON growth.jobs TO growth_migrator;

COMMIT;
