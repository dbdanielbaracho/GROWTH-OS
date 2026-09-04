# Growth OS — Gate Zero Provider Selection v0.2 — FROZEN

Status: **FROZEN**  
Issue: #26 — Build real signal ingestion and Growth Intelligence Engine  
Date: 2026-09-04  
Supersedes: `docs/GATE_ZERO_PROVIDER_SELECTION_V0.1.md` (candidate record)  
Approved candidate SHA: `f97c30b21be47b14398339d9e89ce449cdac671f`  
Gate Zero merge SHA: `e24f9daf6cbcd869b120c3c98dd6928e8aa7d362`

## Frozen decision

- `YOUTUBE_FIRST`
- first production slice: `AUTHORIZED_YOUTUBE_ANALYTICS_PLUS_DATA_API`
- PubSubHubbub may be used for upload/update discovery where useful
- `derived_analytics` is a separate capability
- user-facing YouTube custom scores, rankings, leaderboards or benchmarks governed by the derived-metrics policy remain fail-closed until documented policy acceptance

## Frozen corrections

1. X Full-Archive Search is available to pay-per-use/self-serve as well as Enterprise under the current primary documentation; it is not treated as Enterprise-only.
2. The YouTube `viewCount` semantic change beginning 2026-08-24 is recorded, but this document does not claim that the change is non-retroactive because the reviewed primary documentation does not explicitly establish that detail.

## Observation/provenance contract

Every new provider observation must preserve, when applicable:

- provider
- provider API/product/version
- stable provider object ID/type
- metric name and raw value/unit
- metric semantic version
- semantic effective date/range
- source timestamp/report range
- collected_at
- authorization class
- provenance/evidence reference
- retention deadline / refresh obligation
- completeness/freshness status
- collection run / idempotency key

Provider-specific semantics must not be erased during normalization.

## Approval record

Claude adversarially re-reviewed the corrected v0.1 at exact SHA `f97c30b21be47b14398339d9e89ce449cdac671f` and returned `APPROVE GATE ZERO V0.1`, explicitly confirming:

1. `YOUTUBE_FIRST`
2. `AUTHORIZED_YOUTUBE_ANALYTICS_PLUS_DATA_API`
3. separate `derived_analytics`
4. fail-closed derived scores/benchmarks until policy acceptance
5. corrected X Full-Archive availability
6. removal of the unsupported non-retroactivity assertion
7. no material remaining gap in the Gate Zero decision

This v0.2 changes no substantive provider decision from the approved candidate; it is the versioned freeze record required by project governance.

## Primary evidence carried forward

- https://developers.google.com/youtube/terms/derived-metrics-policy
- https://developers.google.com/youtube/terms/revision-history
- https://developers.google.com/youtube/analytics/reference/reports/query
- https://developers.google.com/youtube/analytics/metrics
- https://developers.google.com/youtube/analytics/dimensions
- https://developers.google.com/youtube/reporting/guides/authorization
- https://developers.google.com/youtube/v3/docs/videos/batchGetStats
- https://developers.google.com/youtube/v3/guides/push_notifications
- https://developers.google.com/youtube/v3/docs/videos
- https://docs.x.com/x-api/getting-started/pricing
- https://docs.x.com/x-api/posts/search/introduction
- https://developers.tiktok.com/products/research-api/
