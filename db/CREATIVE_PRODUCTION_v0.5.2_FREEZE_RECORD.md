# Growth OS — Especificação Técnica v0.5.2 — Technical Freeze Record

**Growth OS — Especificação Técnica v0.5.2 — TECHNICAL FREEZE APPROVED**

## Frozen version

- **Base documents**: Growth OS Projeto Conceitual v1.5 CANDIDATA, Growth OS
  Especificação Técnica v0.5.2 CANDIDATA (RLS & Lineage Cycle Hardening).
- **Foundation preserved, unmodified**: RC9 DDL + Runtime Security Freeze
  (`db/migrations/001_initial_schema.sql`, SHA-256
  `b2bf18fc540bb08a0e0c17c911d91e91e9eda9d7504fa8120d5f9374eeb48b76`) and
  Post-RC9 Content Domain reconciliation (branch
  `feat/content-authoring-schema-post-rc9`). Neither is edited by this
  freeze or by the migration that follows it.

## v0.5.1 findings, both closed in v0.5.2 and physically re-verified

1. **RLS absent on the three new prototype entities**
   (`creative_requests`, `creative_generations`, `media_asset_lineage`).
   Not exploitable at the time it was found only because no grant to
   `app_runtime` existed yet on those tables — but every physical proof
   from that round (state machine, tombstone reachability, cardinality)
   had been run without tenant isolation in place, so none of it stood as
   evidence of multi-tenant safety.
2. **`media_asset_lineage` had no protection against indirect cycles.**
   `CHECK (output_asset_id <> input_asset_id)` blocks only direct
   self-reference. A 2-node cycle (A→B, then B→A) was accepted without
   error, and reconstructing it with a `UNION ALL` recursive CTE (no
   manual depth guard) produced runaway growth — 1501 rows from a 2-node
   cycle before a defensive `depth < 1000` clause cut it off.

## v0.5.2 corrections, physically re-proven on a freshly rebuilt environment

- `ENABLE ROW LEVEL SECURITY` + `FORCE ROW LEVEL SECURITY` on all three
  tables, confirmed via `relrowsecurity`/`relforcerowsecurity` **before**
  any `GRANT` was issued to `app_runtime`.
- Cross-tenant `SELECT`/`INSERT`/`UPDATE` blocked on all three tables.
- Revoked membership: zero visibility.
- `media_asset_lineage`: composite FK rejects an edge referencing an
  asset from a different workspace; cross-tenant read returns zero rows.
- Self-cycle rejected by the composite `CHECK`.
- 2-node cycle (A→B, then B→A) rejected by
  `growth.reject_media_asset_lineage_cycle()`.
- 3-node cycle (A→B→C, then C→A) rejected; the legitimate chain A→B, B→C
  continued to work.
- **Cycle creation under real concurrency**: two genuine concurrent
  `psql` sessions raced to create opposite edges between the same two
  assets, coordinated by an advisory lock keyed on the workspace. The
  second session, blocked until the first committed, correctly detected
  and rejected the resulting cycle — not a sequential test dressed up as
  concurrent.
- Shared-asset + tombstone scenario, repeated under real RLS: tombstoning
  Content A hid A's own exclusive final asset while leaving Content B's
  final asset and the shared input asset (no fixed `content_version_id`)
  fully reachable via `media_asset_lineage`.
- Full `creative_generations` state machine: all 42 possible transitions
  (7 states × 7, minus same-state) tested individually via `app_runtime`
  under real RLS — exact match against the intended allow-list, zero
  mismatches.

## Non-blocking note

`EXECUTE` on `reject_media_asset_lineage_cycle()` and
`creative_generation_transition_guard()` was left grantable to `PUBLIC`
by default at creation. Actual risk is negligible — trigger functions
cannot be invoked directly outside the trigger mechanism — but `REVOKE
ALL ... FROM PUBLIC` was applied to both anyway, matching the more
conservative precedent already set by RC9's own `membership_write_guard`
(RC9's own `reject_insight_demotion_cycle`, the pattern this was modeled
on, does not have the same revoke — an inconsistency in RC9 itself,
noted here rather than silently carried forward).

## Explicitly deferred, not a blocker of this freeze

**Publication Asset Contract**: `publication_intents` (frozen in RC9)
has no `media_asset_id` and cannot yet identify precisely which asset was
sent to a provider when a content version has multiple `publishable`
assets (e.g. per-platform exports) or multi-asset publications (e.g.
carousels). The architectural requirement is registered — Publishing
must persist the identity and order/role of the asset(s) actually sent —
but the physical design (a `publication_assets` join entity is the
leading candidate) is deferred to the Publishing module's own design
round, not decided under Creative Production pressure.

**Orphan Asset Garbage Collection**: registered as a required capability,
not implemented. An asset with no `content_version_id` and no lineage
edge reachable from any still-alive `publishable` output is a legitimate
GC candidate only after a retention/grace period and a legal-hold check
— never a direct `DELETE` on mere absence of a reference at query time.

## Gate results

`SECURITY BLOCKERS: 0` · `CORRECTNESS BLOCKERS: 0` · `CONCURRENCY BLOCKERS: 0`

**Growth OS — Especificação Técnica v0.5.2 — TECHNICAL FREEZE APPROVED.**
Any future change to the entities, RLS, grants, or state machine
introduced by the migration that implements this freeze requires a new
change record and a version subsequent to v0.5.2 — the same discipline
already applied to RC9 and to Post-RC9 Content.
