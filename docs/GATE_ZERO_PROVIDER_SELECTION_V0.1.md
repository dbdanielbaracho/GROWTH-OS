# Growth OS — Gate Zero Provider Selection v0.1

Status: **CANDIDATE — pending Claude adversarial re-review after ChatGPT corrections**  
Issue: #26 — Build real signal ingestion and Growth Intelligence Engine  
Date: 2026-09-04  
Baseline main SHA: `6a3ca1c9bde91d8cd3677bd0ed4e8f684299bb52`

## 1. Decision candidate

**Preferred first provider: YouTube.**

**Preferred first production slice:**

> **Authorized YouTube channel + YouTube Analytics API + YouTube Data API**, with PubSubHubbub upload/update notifications where useful.

The initial slice must be capable of ingesting real authorized channel analytics, preserving provenance and metric semantics, and producing only evidence-backed signals. Public YouTube metadata/statistics may complement the authorized channel data, but public Data API alone is not the first slice because it cannot provide the private Analytics depth needed for the core Growth Intelligence loop.

This decision is not frozen until Claude re-reviews this corrected document.

## 2. Critical policy dependency — derived analytics

YouTube generally prohibits API clients from creating metrics that replace or modify YouTube API data. Since 2026, YouTube provides an explicit policy path for accepted analytics use cases to create additional derived metrics such as custom channel scores, ratios, leaderboards, sentiment analysis, categorization, and suitability scoring.

The policy page explicitly lists examples such as a Creator Influence Score based on average views, subscriber growth and engagement ratios. It also states that accepted use cases may store certain statistical and derived metrics for up to 36 calendar months; other data such as titles, creator names, descriptions and comment text remains subject to the ordinary 30-day refresh/deletion policy.

**Growth OS rule:**

- raw/authorized ingestion may be built in parallel;
- **no user-facing custom score, benchmark, leaderboard or other YouTube-derived analytic that falls under this amendment may be enabled until the relevant YouTube Analytics & Reporting use case has been accepted under the current Developer Policies / quota-extension process;**
- the approval state must be represented in the provider capability registry and enforced fail-closed.

Primary sources:
- https://developers.google.com/youtube/terms/derived-metrics-policy
- https://developers.google.com/youtube/terms/revision-history

## 3. YouTube evidence

### 3.1 Authorized analytics

All YouTube Analytics API requests require OAuth 2.0 authorization. The API exposes user-activity and performance metrics including core metrics such as `engagedViews`, `averageViewDuration`, `estimatedMinutesWatched`, `likes`, `comments`, `shares`, `subscribersGained`, `subscribersLost`, `viewerPercentage`, and `views`, with dimensions including time and geography.

Primary sources:
- https://developers.google.com/youtube/analytics/reference/reports/query
- https://developers.google.com/youtube/analytics/metrics
- https://developers.google.com/youtube/analytics/dimensions
- https://developers.google.com/youtube/reporting/guides/authorization

### 3.2 Public data and batch statistics

`videos.batchGetStats` was added in June 2026. It can retrieve statistics for public videos without OAuth; non-public videos require authorization. The method costs 1 unit in its own granular quota bucket and has a default quota of 10,000 units/day.

Primary sources:
- https://developers.google.com/youtube/v3/docs/videos/batchGetStats
- https://developers.google.com/youtube/v3/revision_history

### 3.3 Push notifications

YouTube Data API supports PubSubHubbub push notifications. Notifications are delivered for channel video uploads and changes to video title or description. This can reduce polling for event discovery, while metrics still need appropriate fetch/reconciliation.

Primary source:
- https://developers.google.com/youtube/v3/guides/push_notifications

### 3.4 Metric semantic break — `viewCount`

The current YouTube Data API documentation states that, starting **2026-08-24**, `statistics.viewCount` for long-form, Live and Shorts counts a view when a video begins to play, including autoplay / hover / click-tap behavior. YouTube Analytics documentation distinguishes `Engaged View` as playback continuing past the first frame or an explicit play interaction.

**Architecture implication:** observations must store metric semantic version and effective date. Signals must not compare incompatible definitions as if they were homogeneous.

**Correction to prior Claude review:** this document does **not** state that the `viewCount` change was non-retroactive because current primary documentation reviewed here does not provide sufficient support for that specific claim.

Primary sources:
- https://developers.google.com/youtube/v3/docs/videos
- https://developers.google.com/youtube/analytics/revision_history
- https://developers.google.com/youtube/analytics/metrics

## 4. Provider comparison — corrected Gate Zero

### YouTube

- Own/authorized analytics: **high** — deep channel/video analytics via OAuth.
- Public intelligence: **high for metadata/public stats**, subject to storage/refresh and derived-metric policies.
- Historical usefulness: **high for authorized analytics**, with provider-policy constraints for stored API data.
- Freshness: **high**; PubSubHubbub supports near-real-time upload/update discovery.
- Cost/quota: favorable relative to X for the first slice; `batchGetStats` has a dedicated quota bucket.
- Main blocker: explicit acceptance path required before enabling additional derived analytics governed by the 2026 policy amendment.

### Instagram / Meta

Meta's current Instagram API supports professional Business/Creator accounts. Insights are available for app users' professional accounts; Advanced Access is required when serving professional accounts the app does not own/manage. Current documentation states User Metrics data is stored by Meta for up to 90 days. The API can also obtain basic metadata and metrics about other Instagram Businesses/Creators, but this is not equivalent to private account Insights.

For Growth OS, Instagram remains a high-priority later connector, but current evidence does not make it superior to YouTube as the first full intelligence slice.

Primary sources:
- https://www.postman.com/meta/instagram/folder/23987686-f659d7d1-d74c-44e4-9192-9b1e8694c511
- https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api

**Not frozen in this Gate Zero:** a single numeric Instagram rate-limit formula. Rate limiting is layered and can vary by access/use case; implementation must use current Meta response headers and current product-specific documentation rather than a hard-coded assumption from older documentation.

### TikTok

TikTok Research Tools expose public account/content data only to qualified researchers under eligibility rules that require independence from commercial interests and non-commercial/public-interest research. This is not an acceptable commercial backbone for Growth OS.

The ordinary TikTok commercial developer products (for example Display/Login/Content Posting) do not currently provide an equivalent general-purpose organic competitor-intelligence backbone in the primary documentation reviewed for this Gate Zero.

Primary source:
- https://developers.tiktok.com/products/research-api/

### X

X currently uses pay-per-use pricing for self-serve access. Current pricing lists Posts reads at $0.005/resource and User reads at $0.010/resource, with a 2 million monthly Post-read cap for pay-per-use. Recent Search covers the last 7 days.

**Correction to prior Claude review:** Full-Archive Search is **not Enterprise-only**. Current X documentation states Full-Archive Search is available to pay-per-use/self-serve and Enterprise customers. Enterprise remains relevant for higher volume and exclusive streaming/firehose capabilities.

This correction improves X's historical capability score but does not make X the preferred first connector because every high-volume public-data read has direct marginal cost and the first Growth OS slice benefits more from YouTube's deep authorized analytics + comparatively favorable quota model.

Primary sources:
- https://docs.x.com/x-api/getting-started/pricing
- https://docs.x.com/x-api/fundamentals/post-cap
- https://docs.x.com/x-api/posts/search/introduction
- https://docs.x.com/x-api/posts/search/quickstart/full-archive-search
- https://docs.x.com/enterprise-api/getting-started/pricing

## 5. Capability model

The provider capability registry should distinguish at least:

1. `authorized_analytics`
2. `public_metadata`
3. `public_stats`
4. `push_upload_events`
5. `derived_analytics`

`derived_analytics` is intentionally separate because its policy/approval/retention boundary can differ from the raw authorized/public inputs used to compute it.

Each capability should include, at minimum:

- provider;
- API/product/version;
- authorization class;
- access/review status;
- policy approval status where required;
- allowed storage/retention class;
- refresh obligation;
- quota/budget class;
- kill switch;
- validated_at;
- evidence reference.

## 6. Observation provenance contract

Every normalized observation must preserve enough information to make a later signal/opportunity auditable:

- provider;
- provider API/product version;
- source object/type and stable provider ID;
- metric name;
- metric semantic version;
- semantic effective date/range when known;
- raw value/unit;
- source timestamp / report date range;
- `collected_at`;
- authorization class;
- provenance/evidence reference;
- retention deadline / refresh obligation;
- completeness/freshness status;
- collection run / idempotency key.

Normalization must not erase provider semantics.

## 7. First intelligence slice — allowed before derived-analytics approval

Before the YouTube derived-analytics use case is accepted, Growth OS may build and physically validate:

1. OAuth connection for an authorized YouTube channel;
2. authorized Analytics ingestion;
3. Data API metadata/public statistics ingestion where policy-compliant;
4. PubSubHubbub event intake;
5. normalized observations + provenance;
6. deterministic freshness/completeness checks;
7. direct factual deltas that do not create prohibited replacement/modified metrics;
8. truthful empty/no-op behavior when evidence is insufficient.

Any proposed score/ranking/benchmark based on YouTube API Data must remain behind a capability gate until the relevant policy acceptance is documented.

## 8. Gate Zero outcome candidate

**Decision:** `YOUTUBE_FIRST`

**Slice:** `AUTHORIZED_YOUTUBE_ANALYTICS_PLUS_DATA_API`

**Mandatory precondition for user-facing derived analytics:** `YOUTUBE_DERIVED_ANALYTICS_POLICY_ACCEPTED=true`

**Do not freeze yet.** Claude must re-review this corrected v0.1 because this document changes two claims from the prior adversarial review:

1. X Full-Archive Search availability;
2. removal of the unsupported `viewCount` non-retroactive assertion.

After Claude APPROVE on this exact document/version, Gate Zero may be frozen and implementation may begin.
