-- Growth OS RC9 — TEST-ONLY. Allows the harness to SET ROLE app_runtime
-- for adversarial operations after seeding fixtures as the privileged
-- harness identity. Membership only; does not change app_runtime itself.

\set ON_ERROR_STOP on

GRANT app_runtime TO growth_test_harness;
