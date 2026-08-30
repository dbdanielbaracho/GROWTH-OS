-- Requires fixtures for workspace + content_item; replace psql vars or run from integration harness.
-- Purpose: prove NULL windows behave as one logical lifetime metric, not infinitely many UNIQUE-null duplicates.
\set ON_ERROR_STOP on
\echo 'NOT SELF-CONTAINED: run from integration fixture harness with content item IDs.'
\echo 'Expected: second identical lifetime metric_normalized row with NULL window_start/window_end is rejected.'
