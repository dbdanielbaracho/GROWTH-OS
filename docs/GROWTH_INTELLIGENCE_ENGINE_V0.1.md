# Growth OS — Growth Intelligence Engine v0.1

Status: implementation candidate for Issue #26; requires exact-SHA CI, isolated Postgres validation, real provider proof and Claude adversarial review before merge or production promotion.

## Purpose

Convert provenance-complete authorized YouTube observations into a deterministic chain:

`metric_observations -> factual_signals -> insights/evidence -> opportunities -> Opportunity Radar`

This version intentionally implements one narrow signal:

- metric: `views`;
- provider: YouTube Analytics;
- signal: `views_acceleration`;
- baseline: mean of the previous complete observations;
- minimum sample: three complete/fresh observations;
- threshold: latest observation at least 25% above the previous-observation mean.

## Authority and data contract

The engine only evaluates rows that have:

- the current tenant context;
- a connected YouTube social account;
- `authority_status=contractually_granted`;
- `authorization_class=authorized_account`;
- `completeness_status=complete`;
- `freshness_status=fresh`;
- metric name `views`.

The engine does not use derived analytics, public competitor data, causal claims, synthetic rows, or unsupported provider fields.

## Deterministic output

For a qualifying sample, migration 015 creates or updates:

1. `growth.factual_signals` with latest value, baseline, delta, sample size, source observation IDs, confidence and logic version.
2. `growth.insights` linked by `source_signal_id`, with state `confirmed_account`, a factual account claim and stored evidence rows.
3. `growth.opportunities` linked by `source_signal_id`, with a deterministic score, market, platform, expiry and ranking version.
4. `growth.insight_evidence` and `growth.opportunity_evidence` referencing the actual metric observation IDs.

The natural key includes workspace, account, signal type, metric, source-window end and logic version. Repeating the same sync/recompute is therefore update-safe and does not create duplicate signal, insight or opportunity rows.

## No-op behavior

If the sample has fewer than three observations, the baseline is unavailable/non-positive, or the delta is below 25%, the function returns `insufficient_signal` and creates no user-facing opportunity. The UI must show the truthful empty/no-op state.

## Security boundary

The recompute function is:

- `SECURITY DEFINER`;
- owned by `growth_migrator`;
- non-executable by `PUBLIC`;
- executable by `app_runtime`;
- tenant-context validated;
- protected by RLS + FORCE RLS on the new factual signal table;
- not a direct table-write grant to `app_runtime`.

## Explicit non-claims

This slice does not claim:

- that the increase was caused by a specific action;
- that the opportunity will produce future growth;
- that the signal is a market-wide trend;
- that an action prescription is verified;
- that a single provider signal completes the whole Growth OS product.

Those claims require separate evidence, policy and adversarial review.


## Integration no-op proof

The integration fixture also creates a connected, authorized YouTube account with zero observations. Calling the deterministic helper for that account must return:

- `insufficient_signal`;
- null signal, insight, and opportunity IDs;
- zero observations used;
- null delta ratio.

This keeps the truthful empty/no-op behavior executable and prevents a sparse account from becoming a synthetic Radar item.
