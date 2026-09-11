-- Growth OS — align Instagram factual signal types with the shared signal table.
-- Forward-only migration 054.
--
-- Migration 039 introduced 'likes_acceleration' in the Instagram intelligence
-- function, but the shared table constraint from migration 015 only allowed the
-- original YouTube signal. Keep both provider signal types explicit.

BEGIN;
SET search_path = growth, public;

ALTER TABLE growth.factual_signals
  DROP CONSTRAINT IF EXISTS factual_signals_signal_type_check;

ALTER TABLE growth.factual_signals
  ADD CONSTRAINT factual_signals_signal_type_check
  CHECK (signal_type IN ('views_acceleration', 'likes_acceleration'));

COMMIT;
