import { randomUUID } from "node:crypto";
import { buildApp } from "../src/app.js";
import { db } from "../src/db.js";

const legit = { "x-user-id": "a0000000-0000-4000-8000-000000000001", "x-workspace-id": "b0000000-0000-4000-8000-000000000001" };
const attacker = { "x-user-id": "a0000000-0000-4000-8000-000000000002", "x-workspace-id": "b0000000-0000-4000-8000-000000000002" };

let failures = 0;
function check(name: string, ok: boolean, detail?: unknown) {
  if (ok) console.log(`PASS: ${name}`);
  else { failures++; console.error(`FAIL: ${name}`, detail ?? ""); }
}

const app = buildApp(false);
const runTag = randomUUID().slice(0, 8);

async function fetchOneAsTenant(workspaceId: string, userId: string, sql: string, params: unknown[]) {
  const client = await db.connect();
  try {
    await client.query("BEGIN");
    await client.query("SELECT set_config('app.workspace_id', $1, true)", [workspaceId]);
    await client.query("SELECT set_config('app.user_id', $1, true)", [userId]);
    const result = await client.query(sql, params);
    await client.query("COMMIT");
    return result;
  } finally {
    client.release();
  }
}

// 1. Creative Request with an EXISTING, same-workspace source (an opportunity
//    already present in the fixtures) must succeed.
const oppLookup = await fetchOneAsTenant(legit["x-workspace-id"], legit["x-user-id"],
  `select id from growth.opportunities where workspace_id = $1 limit 1`, [legit["x-workspace-id"]]);
const opportunityId: string | undefined = oppLookup.rows[0]?.id;
check("(setup) a fixture opportunity exists to reference", !!opportunityId, oppLookup.rows);

const crRes = await app.inject({
  method: "POST", url: "/v1/creative/requests", headers: legit,
  payload: {
    sourceType: "opportunity", sourceId: opportunityId,
    capability: "voice_clone", modality: "audio",
    targetMarket: "US", targetLanguage: "en"
  }
});
check("(1) create creative_request with a real, same-workspace source succeeds", crRes.statusCode === 201, crRes.body);
const creativeRequestId = crRes.json()?.creativeRequest?.id;

// 2. Creative Request referencing a NONEXISTENT source must be rejected (422).
const crBadRes = await app.inject({
  method: "POST", url: "/v1/creative/requests", headers: legit,
  payload: {
    sourceType: "opportunity", sourceId: "00000000-0000-4000-8000-000000000000",
    capability: "voice_clone", modality: "audio", targetMarket: "US", targetLanguage: "en"
  }
});
check("(2) nonexistent source_id is rejected with 422", crBadRes.statusCode === 422, crBadRes.body);

// 3. Creative Request referencing a source from ANOTHER workspace must be rejected.
// (Looked up using legit_owner's identity in victim_ws — legit_owner owns both
// workspaces in the fixtures; attacker deliberately has zero memberships
// anywhere, so using attacker's identity here would return nothing regardless
// of whether the fixture exists.)
const victimOppLookup = await fetchOneAsTenant(attacker["x-workspace-id"], legit["x-user-id"],
  `select id from growth.opportunities where workspace_id = $1 limit 1`, [attacker["x-workspace-id"]]);
const victimOpportunityId: string | undefined = victimOppLookup.rows[0]?.id;
if (victimOpportunityId) {
  const crCrossRes = await app.inject({
    method: "POST", url: "/v1/creative/requests", headers: legit, // legit user, but pointing at victim's opportunity
    payload: {
      sourceType: "opportunity", sourceId: victimOpportunityId,
      capability: "voice_clone", modality: "audio", targetMarket: "US", targetLanguage: "en"
    }
  });
  check("(3) cross-workspace source_id is rejected with 422", crCrossRes.statusCode === 422, crCrossRes.body);
} else {
  // HARDENED (Test Integrity & Method Hardening Gate): this used to be a
  // silent SKIP, which meant test (3) — a SECURITY-relevant cross-tenant
  // check — could go completely unexercised in a run without the overall
  // suite reporting any failure. A missing fixture for a security test is
  // itself a test-infrastructure defect, not a reason to quietly move on.
  // db/provisioning/test/04_creative_production_test_fixtures.sql now
  // seeds this fixture as standard provisioning, so reaching this branch
  // at all means that provisioning step did not run or was altered —
  // treated as a hard FAIL, not a SKIP.
  check(
    "(3) cross-workspace source_id is rejected with 422 [fixture missing — provisioning gap, not a legitimate skip]",
    false,
    "expected an opportunity fixture in the victim workspace (seeded by 04_creative_production_test_fixtures.sql); none found"
  );
}

// 4. Creative Generation lifecycle: create -> processing -> succeeded.
let generationId: string | undefined;
if (creativeRequestId) {
  const genRes = await app.inject({
    method: "POST", url: "/v1/creative/generations", headers: legit,
    payload: { creativeRequestId, provider: "elevenlabs", supportsProviderIdempotency: false }
  });
  check("(4) create creative_generation succeeds", genRes.statusCode === 201, genRes.body);
  generationId = genRes.json()?.creativeGeneration?.id;
}

// 5. Cross-tenant read/write of the generation must fail.
if (generationId) {
  const crossRead = await fetchOneAsTenant(legit["x-workspace-id"], legit["x-user-id"],
    `select 1 from growth.creative_generations where id = $1`, [generationId]);
  check("(5) generation row exists for the legit tenant", crossRead.rowCount! > 0);
}

// 6. Media asset + lineage, tenant-scoped via HTTP.
const assetRes = await app.inject({
  method: "POST", url: "/v1/media-assets", headers: legit,
  payload: {
    storageRef: `s3://http-test-voice-${runTag}`, mimeType: "audio/mp3", checksum: `chk-http-voice-${runTag}`,
    rightsStatus: "licensed", sourceClass: "ai_generated", purpose: "source"
  }
});
check("(6) create media_asset via HTTP succeeds", assetRes.statusCode === 201, assetRes.body);
const assetId = assetRes.json()?.mediaAsset?.id;

const asset2Res = await app.inject({
  method: "POST", url: "/v1/media-assets", headers: legit,
  payload: {
    storageRef: `s3://http-test-final-${runTag}`, mimeType: "video/mp4", checksum: `chk-http-final-${runTag}`,
    rightsStatus: "licensed", sourceClass: "ai_generated", purpose: "publishable"
  }
});
const asset2Id = asset2Res.json()?.mediaAsset?.id;

if (assetId && asset2Id) {
  const lineageRes = await app.inject({
    method: "POST", url: "/v1/media-assets/lineage", headers: legit,
    payload: { outputAssetId: asset2Id, inputAssetId: assetId, role: "voice" }
  });
  check("(7) create lineage edge via HTTP succeeds", lineageRes.statusCode === 201, lineageRes.body);

  // 8. Self-cycle via HTTP must be rejected.
  const selfCycleRes = await app.inject({
    method: "POST", url: "/v1/media-assets/lineage", headers: legit,
    payload: { outputAssetId: assetId, inputAssetId: assetId, role: "self" }
  });
  check("(8) self-cycle via HTTP is rejected", selfCycleRes.statusCode >= 400 && selfCycleRes.statusCode < 500, selfCycleRes.body);
}

// 10. Full generation lifecycle via HTTP: requested -> queued -> processing
//     -> ambiguous -> reconcile -> succeeded.
if (generationId) {
  const toQueued = await app.inject({ method: "PATCH", url: `/v1/creative/generations/${generationId}`, headers: legit, payload: { status: "queued" } });
  check("(10a) requested -> queued via HTTP", toQueued.statusCode === 200, toQueued.body);

  const toProcessing = await app.inject({ method: "PATCH", url: `/v1/creative/generations/${generationId}`, headers: legit, payload: { status: "processing" } });
  check("(10b) queued -> processing via HTTP", toProcessing.statusCode === 200, toProcessing.body);

  const toAmbiguous = await app.inject({ method: "PATCH", url: `/v1/creative/generations/${generationId}`, headers: legit, payload: { status: "ambiguous" } });
  check("(10c) processing -> ambiguous via HTTP", toAmbiguous.statusCode === 200, toAmbiguous.body);

  // A blind retry (ambiguous -> queued) must be rejected.
  const blindRetry = await app.inject({ method: "PATCH", url: `/v1/creative/generations/${generationId}`, headers: legit, payload: { status: "queued" } });
  check("(10d) blind retry (ambiguous -> queued) is rejected via HTTP", blindRetry.statusCode === 409, blindRetry.body);

  // Legitimate reconciliation: ambiguous -> succeeded, with resolved_manually set.
  const reconciled = await app.inject({ method: "POST", url: `/v1/creative/generations/${generationId}/reconcile`, headers: legit, payload: { resolvedStatus: "succeeded" } });
  check("(10e) legitimate reconciliation succeeds", reconciled.statusCode === 200 && reconciled.json()?.creativeGeneration?.resolved_manually === true, reconciled.body);
}

// 11. Cross-tenant PATCH on the generation must fail (0 rows affected -> error).
if (generationId) {
  const crossPatch = await app.inject({ method: "PATCH", url: `/v1/creative/generations/${generationId}`, headers: attacker, payload: { status: "cancelled" } });
  check("(11) cross-tenant PATCH on creative_generations is rejected", crossPatch.statusCode >= 400, crossPatch.body);
}

// 12. Shared asset + tombstone via HTTP: create Content A and B (using the
//     content.ts routes already in this app), a shared input asset, link it
//     into both via lineage, tombstone A directly at the DB level (no
//     deletion-request HTTP route exists yet), then confirm via HTTP GET
//     that A's own content disappears while B's content and the shared
//     asset remain reachable.
{
  const contentARes = await app.inject({ method: "POST", url: "/v1/content", headers: legit, payload: { market: "US", language: "en", sourceType: "manual", body: `content A ${runTag}` } });
  const contentBRes = await app.inject({ method: "POST", url: "/v1/content", headers: legit, payload: { market: "US", language: "en", sourceType: "manual", body: `content B ${runTag}` } });
  const contentAVersionId = contentARes.json()?.version?.id;
  const contentAItemId = contentARes.json()?.item?.id;
  const contentBVersionId = contentBRes.json()?.version?.id;

  check("(12 setup) two content pieces created via HTTP", contentARes.statusCode === 201 && contentBRes.statusCode === 201, { a: contentARes.body, b: contentBRes.body });

  if (contentAVersionId && contentBVersionId && contentAItemId) {
    const sharedRes = await app.inject({ method: "POST", url: "/v1/media-assets", headers: legit, payload: { storageRef: `s3://http-shared-${runTag}`, mimeType: "audio/mp3", checksum: `chk-http-shared-${runTag}`, rightsStatus: "licensed", sourceClass: "ai_generated", purpose: "source" } });
    const finalARes = await app.inject({ method: "POST", url: "/v1/media-assets", headers: legit, payload: { storageRef: `s3://http-finalA-${runTag}`, mimeType: "video/mp4", checksum: `chk-http-finalA-${runTag}`, rightsStatus: "licensed", sourceClass: "ai_generated", purpose: "publishable", contentVersionId: contentAVersionId } });
    const finalBRes = await app.inject({ method: "POST", url: "/v1/media-assets", headers: legit, payload: { storageRef: `s3://http-finalB-${runTag}`, mimeType: "video/mp4", checksum: `chk-http-finalB-${runTag}`, rightsStatus: "licensed", sourceClass: "ai_generated", purpose: "publishable", contentVersionId: contentBVersionId } });

    const sharedId = sharedRes.json()?.mediaAsset?.id;
    const finalAId = finalARes.json()?.mediaAsset?.id;
    const finalBId = finalBRes.json()?.mediaAsset?.id;

    if (sharedId && finalAId && finalBId) {
      await app.inject({ method: "POST", url: "/v1/media-assets/lineage", headers: legit, payload: { outputAssetId: finalAId, inputAssetId: sharedId, role: "voice" } });
      await app.inject({ method: "POST", url: "/v1/media-assets/lineage", headers: legit, payload: { outputAssetId: finalBId, inputAssetId: sharedId, role: "voice" } });

      // Tombstone Content A directly at the DB level, via a separate admin
      // connection — app_runtime deliberately has no INSERT on
      // deletion_requests/deletion_tombstones (deletion is an
      // administrative/internal operation, never something the API runtime
      // role does directly). No HTTP deletion route exists yet — that is
      // Publishing/Content's own future surface.
      const { Pool } = await import("pg");
      const adminPool = new Pool({ connectionString: "postgresql://growth_migrator@127.0.0.1:5433/growth_rc9" });
      const adminClient = await adminPool.connect();
      const deletionRequestId = randomUUID();
      try {
        await adminClient.query("BEGIN");
        await adminClient.query("SELECT set_config('app.workspace_id', $1, true)", [legit["x-workspace-id"]]);
        await adminClient.query("SELECT set_config('app.user_id', $1, true)", [legit["x-user-id"]]);
        await adminClient.query(
          `insert into growth.deletion_requests(id,workspace_id,requested_by,scope,target_id,state,manifest_version)
           values ($1,$2,$3,'content',$4,'tombstoned','v1')`,
          [deletionRequestId, legit["x-workspace-id"], legit["x-user-id"], contentAItemId]
        );
        await adminClient.query(
          `insert into growth.deletion_tombstones(workspace_id,target_type,target_id,deletion_request_id,effective_at)
           values ($1,'content',$2,$3,now())`,
          [legit["x-workspace-id"], contentAItemId, deletionRequestId]
        );
        await adminClient.query("COMMIT");
      } finally {
        adminClient.release();
        await adminPool.end();
      }

      const contentListRes = await app.inject({ method: "GET", url: "/v1/content", headers: legit });
      const visibleIds: string[] = (contentListRes.json()?.content ?? []).map((c: any) => c.id);
      check("(12a) Content A no longer visible via HTTP after tombstone", !visibleIds.includes(contentAItemId), visibleIds);

      const finalAVisible = await fetchOneAsTenant(legit["x-workspace-id"], legit["x-user-id"], `select 1 from growth.media_assets where id = $1`, [finalAId]);
      const finalBVisible = await fetchOneAsTenant(legit["x-workspace-id"], legit["x-user-id"], `select 1 from growth.media_assets where id = $1`, [finalBId]);
      const sharedVisible = await fetchOneAsTenant(legit["x-workspace-id"], legit["x-user-id"], `select 1 from growth.media_assets where id = $1`, [sharedId]);
      check("(12b) A's own final asset hidden after tombstone", finalAVisible.rowCount === 0, finalAVisible.rows);
      check("(12c) B's final asset still visible", finalBVisible.rowCount === 1, finalBVisible.rows);
      check("(12d) shared input asset still visible (used by B)", sharedVisible.rowCount === 1, sharedVisible.rows);
    }
  }
}

// 9. Unauthenticated request (no headers) must be 401.
const unauthedRes = await app.inject({ method: "POST", url: "/v1/creative/requests", payload: {} });
check("(9) missing identity headers -> 401", unauthedRes.statusCode === 401, unauthedRes.body);

await app.close();
await db.end();
process.exit(failures > 0 ? 1 : 0);
