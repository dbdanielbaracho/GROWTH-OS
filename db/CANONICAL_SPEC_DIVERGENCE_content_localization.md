# Growth OS — Canonical Spec Divergence Record

## CANONICAL SPEC DIVERGENCE: content_localizations target_market/target_language

**Affected document**: Growth OS Especificação Técnica v0.4.1 CONGELADA, Section 10 (Content Domain).

**Old design** (as literally specified): the `localization` entity carries
`source_version, target_market/language, adaptation_notes, model provenance`
as its own stored fields — `target_market`/`target_language` as columns on
the localization record itself.

**New design** (as implemented in
`db/migrations/003_post_rc9_content_reconciliation.sql`):
`content_localizations` stores only `source_content_version_id`,
`localized_content_version_id`, `adaptation_notes`, `ai_provenance`. No
`target_market`/`target_language` columns exist. Both values are derived at
read time via a JOIN from `content_localizations.localized_content_version_id`
→ `content_versions.content_item_id` → `content_items.market` /
`content_items.language`, which are already required (`NOT NULL`) fields
on every content item.

**Reason**: every `content_item` already carries its own authoritative
`market`/`language`. Storing them a second time on
`content_localizations` creates two independently-writable copies of the
same fact with no mechanism forcing them to agree — the exact scenario
flagged during design review: a `content_localizations` row could claim
`target_market='BR', target_language='pt-BR'` while the `content_item`
behind `localized_content_version_id` actually has `market='US',
language='en-US'`. Deriving instead of duplicating makes that
contradiction structurally impossible rather than something a trigger or
application check would need to continuously re-verify.

**Integrity improvement**: physically confirmed — a fixture with source
`US/en` and localized `BR/pt-BR` was created, and the derived JOIN
correctly returned `target_market='BR', target_language='pt-BR'` with zero
duplicated storage of that fact (`db/tests/016_post_rc9_content_reconciliation.sql`,
scenario 7).

**Trade-off, recorded and not hidden**: this design requires the localized
`content_version` to already exist at the moment the `content_localizations`
row is created. There is no "pending localization request" state (e.g.
"pt-BR localization requested, not yet generated") representable in this
schema. No evidence in either frozen document (Projeto Conceitual v1.4.1 or
Especificação Técnica v0.4.1) requires that intermediate state for
Release 1. If a future release needs it, the natural extension is a
nullable `localized_content_version_id` plus a `status` column — a
separate, later migration, not implied by anything already built here.

**Disposition**: this divergence is not silently reconciled by editing the
frozen Especificação Técnica v0.4.1 document. It is recorded here as the
delta a future version of that document (v0.4.2 or later) would need to
incorporate, with the reasoning and physical evidence preserved
alongside it.
