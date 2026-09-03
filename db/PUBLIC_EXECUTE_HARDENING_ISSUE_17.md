# Issue #17 — PUBLIC EXECUTE hardening matrix

## Scope
This record covers the 16 `growth.*` functions found with PostgreSQL's default `EXECUTE` grant to `PUBLIC` during the production security inventory.

The goal is not to remove function execution indiscriminately. The goal is to remove ambient/public execution and replace it only with the explicit non-owner grants physically proven necessary on the isolated `Postgres-Validation` cluster.

## Dependency-inventory result
A clean rebuild of `Postgres-Validation` from `main` was used before inventory. Catalog inspection found database-side consumers of `current_app_user_id()` / `current_workspace_id()` owned by exactly four relevant roles:

- `app_runtime` through direct RLS policy evaluation;
- `growth_migrator` through owned `SECURITY DEFINER` functions and trigger/business helpers;
- `growth_rls_helper` through RLS helper functions;
- `growth_identity_helper` through Identity v1 `SECURITY DEFINER` functions.

No fifth owner/role appeared in the systematic inventory.

`growth_migrator` owns all 16 reviewed functions, so PostgreSQL owner rights already preserve its EXECUTE capability. Migration 007 therefore does not add redundant explicit grants to the owner.

## Final reviewed matrix

| Function | PUBLIC after 007 | Explicit non-owner EXECUTE after 007 | Reason |
|---|---:|---|---|
| `assert_confirmed_insight_evidence_purity(uuid,uuid)` | no | `app_runtime` | nested call from invoker-security evidence-purity trigger functions under runtime DML |
| `check_authority_history_projection_consistency()` | no | none | internal constraint trigger |
| `check_insight_evidence_purity()` | no | none | internal constraint trigger; nested helper grant handled separately |
| `check_insight_state_evidence_purity()` | no | none | internal constraint trigger; nested helper grant handled separately |
| `check_managed_account_projection_consistency()` | no | none | internal constraint trigger |
| `content_approval_assign_decision_no()` | no | none | internal trigger |
| `content_version_visible(uuid,uuid)` | no | `app_runtime` | direct RLS-policy dependency; `growth_migrator` retains owner execution for SECURITY DEFINER lifecycle paths |
| `current_app_user_id()` | no | `app_runtime`, `growth_rls_helper`, `growth_identity_helper` | direct RLS plus nested SECURITY DEFINER dependencies; `growth_migrator` retains owner execution |
| `current_workspace_id()` | no | `app_runtime`, `growth_rls_helper`, `growth_identity_helper` | direct RLS plus nested SECURITY DEFINER dependencies; `growth_migrator` retains owner execution |
| `enforce_deletion_request_state_transition()` | no | none | internal trigger |
| `enforce_experiment_outcome_temporal_integrity()` | no | none | internal trigger |
| `enforce_experiment_temporal_integrity()` | no | none | internal trigger |
| `enforce_exposure_temporal_integrity()` | no | none | internal trigger |
| `invalidate_metric_completeness_on_late_observation()` | no | none | internal trigger |
| `reject_insight_demotion_cycle()` | no | none | internal trigger |
| `reject_mutation_while_retained()` | no | none | internal trigger |

## Validation requirements
Before merge or production use:

1. rebuild `Postgres-Validation` cleanly from the PR head;
2. apply migration 007 as `growth_migrator`;
3. run `026_public_execute_least_privilege.sql`;
4. run the full ordered SQL suite, including physical concurrency;
5. run Identity, content-authoring, creative-production and Node integration tests;
6. prove all 16 functions have zero PUBLIC EXECUTE;
7. prove the explicit grant matrix above exactly, not approximately;
8. obtain Claude adversarial `APPROVE` on the exact PR SHA.

Production must not be changed before these gates are green and the PR is merged.
