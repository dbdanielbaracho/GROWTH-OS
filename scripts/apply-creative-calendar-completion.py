from pathlib import Path
import re


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if new in text:
        return
    if old not in text:
        raise SystemExit(f"marker missing in {path}: {old[:100]!r}")
    p.write_text(text.replace(old, new, 1))


# Creative read models used by the product surface.
p = Path("apps/api/src/creative.ts")
text = p.read_text()
if "export async function listCreativeRequests" not in text:
    text += '''

export async function listCreativeRequests(client: PoolClient, principal: AuthPrincipal, limit = 100) {
  const result = await client.query(
    `select id, workspace_id, content_item_id, content_version_id, source_type, source_id,
            capability, modality, target_market, target_language, requested_by, status, created_at
       from growth.creative_requests
      where workspace_id = $1
      order by created_at desc, id desc
      limit $2`,
    [principal.workspaceId, limit]
  );
  return result.rows;
}

export async function listCreativeGenerations(client: PoolClient, principal: AuthPrincipal, limit = 100) {
  const result = await client.query(
    `select id, workspace_id, creative_request_id, provider, model, status,
            supports_provider_idempotency, idempotency_key, external_handle,
            error_class, resolved_manually, resolved_by, resolved_at,
            started_at, completed_at, created_at
       from growth.creative_generations
      where workspace_id = $1
      order by created_at desc, id desc
      limit $2`,
    [principal.workspaceId, limit]
  );
  return result.rows;
}

export async function listMediaAssets(client: PoolClient, principal: AuthPrincipal, limit = 200) {
  const result = await client.query(
    `select id, workspace_id, storage_ref, mime_type, checksum, rights_status, source_class,
            bytes, duration_seconds, width_px, height_px, purpose,
            content_version_id, creative_generation_id, created_at
       from growth.media_assets
      where workspace_id = $1
      order by created_at desc, id desc
      limit $2`,
    [principal.workspaceId, limit]
  );
  return result.rows;
}

export async function listMediaAssetLineage(client: PoolClient, principal: AuthPrincipal, limit = 400) {
  const result = await client.query(
    `select workspace_id, output_asset_id, input_asset_id, role, created_at
       from growth.media_asset_lineage
      where workspace_id = $1
      order by created_at desc, output_asset_id, input_asset_id
      limit $2`,
    [principal.workspaceId, limit]
  );
  return result.rows;
}
'''
    p.write_text(text)

replace_once(
    "apps/api/src/app.ts",
    '  CreateLineageEdgeSchema, createLineageEdge,\n  SourceContextNotFoundError\n} from "./creative.js";',
    '  CreateLineageEdgeSchema, createLineageEdge,\n  listCreativeRequests, listCreativeGenerations, listMediaAssets, listMediaAssetLineage,\n  SourceContextNotFoundError\n} from "./creative.js";'
)

creative_routes = '''  app.get("/v1/creative/requests", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;
    try {
      const creativeRequests = await withTenantTransaction(principal, (client) =>
        listCreativeRequests(client, principal)
      );
      return { status: "ok", creativeRequests };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.get("/v1/creative/generations", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;
    try {
      const creativeGenerations = await withTenantTransaction(principal, (client) =>
        listCreativeGenerations(client, principal)
      );
      return { status: "ok", creativeGenerations };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.get("/v1/media-assets", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;
    try {
      const mediaAssets = await withTenantTransaction(principal, (client) =>
        listMediaAssets(client, principal)
      );
      return { status: "ok", mediaAssets };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.get("/v1/media-assets/lineage", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;
    try {
      const lineage = await withTenantTransaction(principal, (client) =>
        listMediaAssetLineage(client, principal)
      );
      return { status: "ok", lineage };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

'''
replace_once(
    "apps/api/src/app.ts",
    '  app.post("/v1/creative/requests", async (request, reply) => {',
    creative_routes + '  app.post("/v1/creative/requests", async (request, reply) => {'
)

# Scheduling becomes part of the typed publication contract.
p = Path("apps/api/src/publishing.ts")
text = p.read_text()
text = text.replace(
    '  idempotencyKey: z.string().trim().min(1).max(200)\n});',
    '  idempotencyKey: z.string().trim().min(1).max(200),\n  scheduledFor: z.string().datetime().optional()\n});'
)
pattern = re.compile(r"export async function createPublicationIntent\([\s\S]*?\n}\n\n\nexport async function cancelPublicationIntent", re.M)
replacement = '''export async function createPublicationIntent(
  client: PoolClient,
  principal: AuthPrincipal,
  input: CreatePublicationIntentInput
) {
  let intent;
  if (input.mediaAssetId) {
    const result = await client.query(
      `select * from growth.create_publication_intent($1, $2, $3, $4, $5, $6)`,
      [principal.workspaceId, input.socialAccountId, input.contentVersionId,
       input.requestNonce, input.idempotencyKey, input.mediaAssetId]
    );
    intent = result.rows[0];
  } else {
    const result = await client.query(
      `select * from growth.create_publication_intent($1, $2, $3, $4, $5)`,
      [principal.workspaceId, input.socialAccountId, input.contentVersionId,
       input.requestNonce, input.idempotencyKey]
    );
    intent = result.rows[0];
  }

  if (!input.scheduledFor) return intent;

  const scheduled = await client.query(
    `select * from growth.schedule_publication_intent($1, $2, $3)`,
    [principal.workspaceId, intent.id, input.scheduledFor]
  );
  return scheduled.rows[0];
}


export async function cancelPublicationIntent'''
if "input.scheduledFor" not in text:
    text, count = pattern.subn(replacement, text, count=1)
    if count != 1:
        raise SystemExit("createPublicationIntent function marker missing")
p.write_text(text)

# Worker discovers due schedules before claiming one durable job.
replace_once(
    "apps/api/src/publication-queue-worker.ts",
    '    async (client) => {\n      const result = await client.query<PublicationQueueJob>(',
    '    async (client) => {\n      await client.query(\n        `select growth.enqueue_due_scheduled_publications($1,$2,$3)`,\n        [input.servicePrincipalId, now.toISOString(), 25]\n      );\n      const result = await client.query<PublicationQueueJob>('
)

# Web client contracts for Creative Studio and calendar scheduling.
p = Path("apps/web/src/api.ts")
text = p.read_text()
text = text.replace(
    'export async function createPublicationIntent(input: {\n  socialAccountId: string;\n  contentVersionId: string;\n  requestNonce: string;\n  idempotencyKey: string;\n}): Promise<PublicationIntentMutationResponse> {',
    'export async function createPublicationIntent(input: {\n  socialAccountId: string;\n  contentVersionId: string;\n  requestNonce: string;\n  idempotencyKey: string;\n  mediaAssetId?: string;\n  scheduledFor?: string;\n}): Promise<PublicationIntentMutationResponse> {'
)
if "export type CreativeRequest = {" not in text:
    text += '''

export type CreativeRequest = {
  id: string;
  workspace_id: string;
  content_item_id: string | null;
  content_version_id: string | null;
  source_type: "opportunity" | "insight" | "experiment" | "multiply" | "user_request" | "content";
  source_id: string;
  capability: string;
  modality: "text" | "image" | "video" | "audio" | "embedding";
  target_market: string;
  target_language: string;
  requested_by: string;
  status: "requested" | "in_progress" | "completed" | "failed" | "cancelled";
  created_at: string;
};

export type CreativeGeneration = {
  id: string;
  workspace_id: string;
  creative_request_id: string;
  provider: string;
  model: string | null;
  status: "requested" | "queued" | "processing" | "succeeded" | "failed" | "cancelled" | "ambiguous";
  supports_provider_idempotency: boolean;
  idempotency_key: string;
  external_handle: string | null;
  error_class: string | null;
  resolved_manually: boolean;
  resolved_by: string | null;
  resolved_at: string | null;
  started_at: string | null;
  completed_at: string | null;
  created_at: string;
};

export type MediaAsset = {
  id: string;
  workspace_id: string;
  storage_ref: string;
  mime_type: string;
  checksum: string;
  rights_status: string;
  source_class: string;
  bytes: number | null;
  duration_seconds: number | null;
  width_px: number | null;
  height_px: number | null;
  purpose: "source" | "intermediate" | "publishable" | null;
  content_version_id: string | null;
  creative_generation_id: string | null;
  created_at: string;
};

export type MediaAssetLineage = {
  workspace_id: string;
  output_asset_id: string;
  input_asset_id: string;
  role: string | null;
  created_at: string;
};

export async function fetchCreativeRequests(): Promise<CreativeRequest[]> {
  const response = await requestJson<{ status: "ok"; creativeRequests: CreativeRequest[] }>("/v1/creative/requests");
  return response.creativeRequests;
}

export async function createCreativeRequest(input: {
  contentItemId?: string;
  contentVersionId?: string;
  sourceType: CreativeRequest["source_type"];
  sourceId: string;
  capability: string;
  modality: CreativeRequest["modality"];
  targetMarket: string;
  targetLanguage: string;
}): Promise<CreativeRequest> {
  const response = await requestJson<{ status: "created"; creativeRequest: CreativeRequest }>("/v1/creative/requests", { method: "POST", body: input });
  return response.creativeRequest;
}

export async function fetchCreativeGenerations(): Promise<CreativeGeneration[]> {
  const response = await requestJson<{ status: "ok"; creativeGenerations: CreativeGeneration[] }>("/v1/creative/generations");
  return response.creativeGenerations;
}

export async function createCreativeGeneration(input: {
  creativeRequestId: string;
  provider: string;
  model?: string;
  supportsProviderIdempotency?: boolean;
}): Promise<CreativeGeneration> {
  const response = await requestJson<{ status: "created"; creativeGeneration: CreativeGeneration }>("/v1/creative/generations", { method: "POST", body: input });
  return response.creativeGeneration;
}

export async function transitionCreativeGeneration(
  generationId: string,
  status: CreativeGeneration["status"]
): Promise<CreativeGeneration> {
  const response = await requestJson<{ status: "ok"; creativeGeneration: CreativeGeneration }>(
    `/v1/creative/generations/${encodeURIComponent(generationId)}`,
    { method: "PATCH", body: { status } }
  );
  return response.creativeGeneration;
}

export async function reconcileCreativeGeneration(
  generationId: string,
  resolvedStatus: "succeeded" | "failed"
): Promise<CreativeGeneration> {
  const response = await requestJson<{ status: "ok"; creativeGeneration: CreativeGeneration }>(
    `/v1/creative/generations/${encodeURIComponent(generationId)}/reconcile`,
    { method: "POST", body: { resolvedStatus } }
  );
  return response.creativeGeneration;
}

export async function fetchMediaAssets(): Promise<MediaAsset[]> {
  const response = await requestJson<{ status: "ok"; mediaAssets: MediaAsset[] }>("/v1/media-assets");
  return response.mediaAssets;
}

export async function createMediaAsset(input: {
  storageRef: string;
  mimeType: string;
  checksum: string;
  rightsStatus: string;
  sourceClass: string;
  bytes?: number;
  durationSeconds?: number;
  widthPx?: number;
  heightPx?: number;
  purpose?: MediaAsset["purpose"];
  contentVersionId?: string;
  creativeGenerationId?: string;
}): Promise<MediaAsset> {
  const response = await requestJson<{ status: "created"; mediaAsset: MediaAsset }>("/v1/media-assets", { method: "POST", body: input });
  return response.mediaAsset;
}

export async function fetchMediaAssetLineage(): Promise<MediaAssetLineage[]> {
  const response = await requestJson<{ status: "ok"; lineage: MediaAssetLineage[] }>("/v1/media-assets/lineage");
  return response.lineage;
}

export async function createMediaAssetLineage(input: {
  outputAssetId: string;
  inputAssetId: string;
  role?: string;
}): Promise<MediaAssetLineage> {
  const response = await requestJson<{ status: "created"; lineageEdge: MediaAssetLineage }>("/v1/media-assets/lineage", { method: "POST", body: input });
  return response.lineageEdge;
}
'''
p.write_text(text)

# Mount the two new product surfaces.
replace_once(
    "apps/web/index.html",
    '    <div id="copilot-panel-root"></div>\n',
    '    <div id="copilot-panel-root"></div>\n    <div id="creative-studio-root"></div>\n    <div id="publication-calendar-root"></div>\n'
)
replace_once(
    "apps/web/index.html",
    '    <script type="module" src="/src/copilot-panel.tsx"></script>\n',
    '    <script type="module" src="/src/copilot-panel.tsx"></script>\n    <script type="module" src="/src/creative-studio.tsx"></script>\n    <script type="module" src="/src/publication-calendar.tsx"></script>\n'
)

# Production migration reconciliation must know migration 070.
replace_once(
    "db/scripts/apply-production-migrations.mjs",
    "  {\n    file: '069_youtube_reauthorization_cleanup.sql',\n    present: async () => {\n      const result = await client.query(`\n        select position(\n          'delete from growth.platform_connections'\n          in lower(pg_get_functiondef('growth.youtube_begin_authorization(uuid,text[])'::regprocedure))\n        ) > 0 as present\n      `);\n      return result.rows[0]?.present === true;\n    },\n  },\n\n];",
    "  {\n    file: '069_youtube_reauthorization_cleanup.sql',\n    present: async () => {\n      const result = await client.query(`\n        select position(\n          'delete from growth.platform_connections'\n          in lower(pg_get_functiondef('growth.youtube_begin_authorization(uuid,text[])'::regprocedure))\n        ) > 0 as present\n      `);\n      return result.rows[0]?.present === true;\n    },\n  },\n  {\n    file: '070_scheduled_publication_dispatch.sql',\n    present: async () => {\n      const scheduleSignature = 'growth.schedule_publication_intent(uuid,uuid,timestamptz)';\n      const dispatchSignature = 'growth.enqueue_due_scheduled_publications(uuid,timestamptz,integer)';\n      if (!(await functionExists(scheduleSignature)) || !(await functionExists(dispatchSignature))) return false;\n      const result = await client.query(`\n        select\n          has_function_privilege('app_runtime', $1::regprocedure, 'EXECUTE')\n          and has_function_privilege('growth_worker', $2::regprocedure, 'EXECUTE')\n          and not has_function_privilege('public', $1::regprocedure, 'EXECUTE')\n          and not has_function_privilege('public', $2::regprocedure, 'EXECUTE')\n          as present\n      `, [scheduleSignature, dispatchSignature]);\n      return result.rows[0]?.present === true;\n    },\n  },\n\n];"
)

# CI physically proves the calendar -> queue transition.
marker = '''      - name: Run publication worker runtime-context gate
        env:
          PGPASSWORD: growth_test_harness
        run: |
          psql --host=127.0.0.1 --port=5432 --username=growth_test_harness --dbname="$CI_DATABASE_NAME" --set=ON_ERROR_STOP=1 --file=db/tests/049_publication_worker_runtime_context.sql
'''
replacement = marker + '''
      - name: Run scheduled publication dispatch gate
        env:
          PGPASSWORD: growth_test_harness
        run: |
          psql --host=127.0.0.1 --port=5432 --username=growth_test_harness --dbname="$CI_DATABASE_NAME" --set=ON_ERROR_STOP=1 --file=db/tests/070_scheduled_publication_dispatch.sql
'''
replace_once(".github/workflows/ci.yml", marker, replacement)

# Browser fixtures recognize all new authenticated read contracts.
replace_once(
    "tests/browser/growth-os.browser.spec.ts",
    '      "/v1/commercial/entitlements", "/v1/commercial/enterprise-policy"\n',
    '      "/v1/commercial/entitlements", "/v1/commercial/enterprise-policy",\n      "/v1/creative/requests", "/v1/creative/generations", "/v1/media-assets", "/v1/media-assets/lineage"\n'
)
browser_marker = '''    if (mode === "authenticated" && path === "/v1/publication-intents") {
      return json(route, 200, { status: "ok", publicationIntents });
    }
'''
browser_add = browser_marker + '''
    if (mode === "authenticated" && path === "/v1/creative/requests") {
      return json(route, 200, { status: "ok", creativeRequests: [] });
    }
    if (mode === "authenticated" && path === "/v1/creative/generations") {
      return json(route, 200, { status: "ok", creativeGenerations: [] });
    }
    if (mode === "authenticated" && path === "/v1/media-assets") {
      return json(route, 200, { status: "ok", mediaAssets: [] });
    }
    if (mode === "authenticated" && path === "/v1/media-assets/lineage") {
      return json(route, 200, { status: "ok", lineage: [] });
    }
'''
replace_once("tests/browser/growth-os.browser.spec.ts", browser_marker, browser_add)

test_marker = 'test("Copilot stays evidence-grounded, accessible and read-only in the authenticated shell", async ({ page }) => {'
test_add = '''test("Creative Studio and Publication Calendar are accessible fail-closed product surfaces", async ({ page }) => {
  const unhandled = await mockApi(page, "authenticated");
  await page.goto("/");

  const creativeToggle = page.getByRole("button", { name: /Creative Studio.*Requests/i });
  await expect(creativeToggle).toBeVisible();
  await creativeToggle.click();
  await expect(page.getByRole("heading", { name: "Build creative work without losing provenance." })).toBeVisible();
  await expect(page.getByText("No creative requests yet.", { exact: true })).toBeVisible();

  const calendarToggle = page.getByRole("button", { name: /Publication Calendar.*Schedule/i });
  await expect(calendarToggle).toBeVisible();
  await calendarToggle.click();
  await expect(page.getByRole("heading", { name: "Schedule approved content without bypassing the worker." })).toBeVisible();
  await expect(page.getByText("No publication intents yet.", { exact: true })).toBeVisible();

  await expectNoHorizontalOverflow(page);
  await expectNoSeriousAccessibilityViolations(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await expectNoHorizontalOverflow(page);
  await expectNoSeriousAccessibilityViolations(page);
  expect(unhandled).toEqual([]);
});

'''
replace_once("tests/browser/growth-os.browser.spec.ts", test_marker, test_add + test_marker)
