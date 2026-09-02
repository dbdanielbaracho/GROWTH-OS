-- Growth OS validation-environment preflight.
-- Run after migrations/provisioning and BEFORE any test fixtures. A full suite
-- must start from an empty data baseline in the dedicated validation database.

\set ON_ERROR_STOP on

DO $$
DECLARE
  table_record record;
  has_rows boolean;
  dirty_tables text[] := ARRAY[]::text[];
BEGIN
  FOR table_record IN
    SELECT tablename
    FROM pg_catalog.pg_tables
    WHERE schemaname = 'growth'
    ORDER BY tablename
  LOOP
    EXECUTE format('SELECT EXISTS (SELECT 1 FROM growth.%I LIMIT 1)', table_record.tablename)
      INTO has_rows;
    IF has_rows THEN
      dirty_tables := array_append(dirty_tables, table_record.tablename);
    END IF;
  END LOOP;

  IF cardinality(dirty_tables) > 0 THEN
    RAISE EXCEPTION 'TEST FAIL: validation database is not empty; restore it before the full suite. Tables containing rows: %', dirty_tables;
  END IF;

  RAISE NOTICE 'PASS: dedicated validation database has an empty data baseline';
END $$;
