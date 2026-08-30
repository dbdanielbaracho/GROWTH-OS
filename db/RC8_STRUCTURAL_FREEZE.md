# RC8 Structural Freeze Record

Status: structurally frozen.

Canonical package: `Growth_OS_DDL_v1_RC8_STRUCTURAL_FREEZE.zip`

Canonical schema file: `001_initial_schema.sql`

Schema SHA-256:

`b2bf18fc540bb08a0e0c17c911d91e91e9eda9d7504fa8120d5f9374eeb48b76`

The RC8 execution gate was completed against PostgreSQL 18.6 before freeze. The baseline includes tenant/RLS isolation, membership authorization/concurrency protections, publication lineage, temporal guards, job concurrency contracts, metric uniqueness constraints, authority-history concurrency behavior, and immutable retained-evidence classes.

This repository must not claim that the canonical SQL has been imported until the byte-identical file is present and its SHA-256 is verified in CI. Until then this record is traceability metadata, not an executable migration.