# Growth OS database baseline

The canonical database baseline is Growth OS DDL v1 RC8 Structural Freeze.

Canonical schema SHA-256:

`b2bf18fc540bb08a0e0c17c911d91e91e9eda9d7504fa8120d5f9374eeb48b76`

Target: PostgreSQL 18.x.

## Rules

- The canonical RC8 SQL is immutable as a structural baseline.
- Product changes are introduced as forward migrations; do not silently rewrite the frozen baseline.
- Production application code must connect with a runtime role, not the migration/owner role.
- Tenant context and RLS invariants are mandatory application contracts.
- Database migrations are explicit operations and are never run automatically on API process startup.
- Backup/DR technical proof is deliberately deferred; this does not relax runtime data-integrity requirements.

## Layout

- `migrations/` — ordered forward migrations.
- `tests/` — database contract/invariant checks.
- `scripts/` — migration and verification tooling.

The full frozen RC8 artifact remains the source of truth until its byte-identical SQL and regression tests are imported into this repository.