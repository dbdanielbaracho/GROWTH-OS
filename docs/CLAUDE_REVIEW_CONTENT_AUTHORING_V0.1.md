# Claude Adversarial Review — Content Authoring v0.1

Do not approve by inspection alone. Review the branch `feat/content-authoring-v0.1` against the frozen Growth OS conceptual/technical contracts and RC8 structural database freeze.

## Required review

1. Inspect all changed files in the branch and compare them with `main`.
2. Verify that `POST /v1/content` cannot create cross-workspace data and that all database operations execute inside transaction-local `app.workspace_id` and `app.user_id` context.
3. Verify that the application assumptions match RC8 table names, columns, foreign keys, unique constraints, tombstone/RLS behavior, and expected runtime role restrictions.
4. Challenge error handling: distinguish authentication failure, authorization/RLS failure, validation failure, and database/internal failure. Flag any path that leaks internals or misclassifies a server failure as a client error.
5. Challenge atomicity: confirm content item + initial content version are in the same PostgreSQL transaction and rollback together.
6. Challenge checksum semantics and deduplication assumptions. Identify collisions in semantic intent caused by hashing only body/structure and whether ai_provenance should or should not participate.
7. Review validation limits and abuse cases, including oversized JSON structure/provenance, unexpected sourceType/platformTarget values, empty body, Unicode, and malformed JSON.
8. Review `GET /v1/content` latest-version lateral join for correctness, deterministic ordering, tombstoned data behavior, and performance/index implications.
9. Run the repository CI commands on the branch: dependency install, typecheck, build, tests. Do not call PASS unless physically executed.
10. Return findings classified as BLOCKER / HIGH / MEDIUM / LOW, with exact file/line or code reference and a concrete correction.

## Required verdict format

- `APPROVED FOR MERGE` only if there are no BLOCKER/HIGH findings and all required commands physically pass.
- Otherwise `CHANGES REQUIRED`.
- Include executed commands and their actual outputs/statuses.
- Do not modify the RC8 frozen baseline. Any necessary schema evolution must be proposed as a forward migration, not a rewrite.
