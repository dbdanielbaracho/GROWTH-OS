import { randomUUID } from "node:crypto";
import type { PoolClient } from "pg";
import { z } from "zod";
import type { AuthPrincipal } from "./auth.js";

// ============================================================
// Source context validation.
//
// creative_requests.source_type + source_id has no FK at the database
// level (v0.5.2, Section 2): the referenced table varies by source_type,
// and a rigid polymorphic FK was explicitly rejected in favor of the
// typed loose reference pattern already established by insight_evidence.
// This means existence + same-workspace ownership validation is this
// function's job — the one place the "não pode ser semanticamente
// órfã" requirement is actually enforced.
// ============================================================

const SOURCE_TABLE_BY_TYPE: Record<string, string> = {
  opportunity: "growth.opportunities",
  insight: "growth.insights",
  experiment: "growth.experiments",
  // MULTIPLY operates through exposures (a specific measured instance of
  // a variant/experiment) rather than owning a dedicated top-level
  // entity of its own — this is a design choice, not a spec-mandated
  // mapping, and is called out here rather than assumed silently.
  multiply: "growth.exposures",
  content: "growth.content_items"
};

export const SourceType = z.enum([
  "opportunity",
  "insight",
  "experiment",
  "multiply",
  "user_request",
  "content"
]);

export class SourceContextNotFoundError extends Error {
  constructor(sourceType: string, sourceId: string) {
    super(`source context not found or not accessible: ${sourceType}=${sourceId}`);
    this.name = "SourceContextNotFoundError";
  }
}

export async function validateSourceContext(
  client: PoolClient,
  workspaceId: string,
  sourceType: z.infer<typeof SourceType>,
  sourceId: string
): Promise<void> {
  if (sourceType === "user_request") {
    // source_id must be an active member of this workspace — the
    // ad-hoc-request case has no owning entity beyond the requester.
    const result = await client.query(
      `select 1 from growth.memberships
        where workspace_id = $1 and user_id = $2 and status = 'active'`,
      [workspaceId, sourceId]
    );
    if (result.rowCount === 0) throw new SourceContextNotFoundError(sourceType, sourceId);
    return;
  }

  const table = SOURCE_TABLE_BY_TYPE[sourceType];
  if (!table) throw new SourceContextNotFoundError(sourceType, sourceId);

  const result = await client.query(
    `select 1 from ${table} where workspace_id = $1 and id = $2`,
    [workspaceId, sourceId]
  );
  if (result.rowCount === 0) throw new SourceContextNotFoundError(sourceType, sourceId);
}

// ============================================================
// Creative Request
// ============================================================

export const CreateCreativeRequestSchema = z.object({
  contentItemId: z.string().uuid().optional(),
  contentVersionId: z.string().uuid().optional(),
  sourceType: SourceType,
  sourceId: z.string().uuid(),
  capability: z.string().trim().min(1).max(100),
  modality: z.enum(["text", "image", "video", "audio", "embedding"]),
  targetMarket: z.string().trim().min(1).max(100),
  targetLanguage: z.string().trim().min(2).max(20)
});

export type CreateCreativeRequestInput = z.infer<typeof CreateCreativeRequestSchema>;

export async function createCreativeRequest(
  client: PoolClient,
  principal: AuthPrincipal,
  input: CreateCreativeRequestInput
) {
  // Fail closed: validate the source context before ever writing a row,
  // so a request can never be persisted as semantically orphaned.
  await validateSourceContext(client, principal.workspaceId, input.sourceType, input.sourceId);

  const id = randomUUID();
  const result = await client.query(
    `insert into growth.creative_requests
       (id, workspace_id, content_item_id, content_version_id, source_type, source_id,
        capability, modality, target_market, target_language, requested_by, status)
     values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'requested')
     returning id, workspace_id, content_item_id, content_version_id, source_type, source_id,
               capability, modality, target_market, target_language, requested_by, status, created_at`,
    [
      id,
      principal.workspaceId,
      input.contentItemId ?? null,
      input.contentVersionId ?? null,
      input.sourceType,
      input.sourceId,
      input.capability,
      input.modality,
      input.targetMarket,
      input.targetLanguage,
      principal.userId
    ]
  );
  return result.rows[0];
}

// ============================================================
// Creative Generation — lifecycle
// ============================================================

export const CreateCreativeGenerationSchema = z.object({
  creativeRequestId: z.string().uuid(),
  provider: z.string().trim().min(1).max(100),
  model: z.string().trim().max(100).optional(),
  supportsProviderIdempotency: z.boolean().default(false)
});

export type CreateCreativeGenerationInput = z.infer<typeof CreateCreativeGenerationSchema>;

export async function createCreativeGeneration(
  client: PoolClient,
  principal: AuthPrincipal,
  input: CreateCreativeGenerationInput
) {
  const id = randomUUID();
  // idempotency_key is derived from our own id here (one attempt = one
  // key); when supportsProviderIdempotency is true, this same value is
  // the key propagated to the provider's own idempotency mechanism.
  const idempotencyKey = id;

  const result = await client.query(
    `insert into growth.creative_generations
       (id, workspace_id, creative_request_id, provider, model, status,
        supports_provider_idempotency, idempotency_key)
     values ($1, $2, $3, $4, $5, 'requested', $6, $7)
     returning id, workspace_id, creative_request_id, provider, model, status,
               supports_provider_idempotency, idempotency_key, external_handle,
               resolved_manually, created_at`,
    [
      id,
      principal.workspaceId,
      input.creativeRequestId,
      input.provider,
      input.model ?? null,
      input.supportsProviderIdempotency,
      idempotencyKey
    ]
  );
  return result.rows[0];
}

export type GenerationStatus =
  | "requested" | "queued" | "processing"
  | "succeeded" | "failed" | "cancelled" | "ambiguous";

export async function transitionGeneration(
  client: PoolClient,
  principal: AuthPrincipal,
  generationId: string,
  newStatus: GenerationStatus,
  opts?: { externalHandle?: string; errorClass?: string; errorDetail?: unknown }
) {
  const result = await client.query(
    `update growth.creative_generations
        set status = $1,
            external_handle = coalesce($2, external_handle),
            error_class = coalesce($3, error_class),
            error_detail = coalesce($4::jsonb, error_detail),
            started_at = case when $1 = 'processing' and started_at is null then now() else started_at end,
            completed_at = case when $1 in ('succeeded','failed','cancelled') then now() else completed_at end
      where workspace_id = $5 and id = $6
      returning id, status, external_handle, error_class, started_at, completed_at`,
    [
      newStatus,
      opts?.externalHandle ?? null,
      opts?.errorClass ?? null,
      opts?.errorDetail ? JSON.stringify(opts.errorDetail) : null,
      principal.workspaceId,
      generationId
    ]
  );
  if (result.rowCount === 0) {
    throw new Error("creative_generation not found, not visible, or the transition was rejected");
  }
  return result.rows[0];
}

export async function reconcileAmbiguousGeneration(
  client: PoolClient,
  principal: AuthPrincipal,
  generationId: string,
  resolvedStatus: "succeeded" | "failed",
  resolvedBy: string
) {
  const result = await client.query(
    `update growth.creative_generations
        set status = $1, resolved_manually = true, resolved_by = $2, resolved_at = now(),
            completed_at = now()
      where workspace_id = $3 and id = $4
      returning id, status, resolved_manually, resolved_by, resolved_at`,
    [resolvedStatus, resolvedBy, principal.workspaceId, generationId]
  );
  if (result.rowCount === 0) {
    throw new Error("creative_generation not found, not visible, or the transition was rejected");
  }
  return result.rows[0];
}

// ============================================================
// Media Assets + Lineage
// ============================================================

export const CreateMediaAssetSchema = z.object({
  storageRef: z.string().trim().min(1).max(2000),
  mimeType: z.string().trim().min(1).max(200),
  checksum: z.string().trim().min(1).max(200),
  rightsStatus: z.string().trim().min(1).max(100),
  sourceClass: z.string().trim().min(1).max(100),
  bytes: z.number().int().nonnegative().optional(),
  durationSeconds: z.number().nonnegative().optional(),
  widthPx: z.number().int().positive().optional(),
  heightPx: z.number().int().positive().optional(),
  purpose: z.enum(["source", "intermediate", "publishable"]).optional(),
  contentVersionId: z.string().uuid().optional(),
  creativeGenerationId: z.string().uuid().optional()
});

export type CreateMediaAssetInput = z.infer<typeof CreateMediaAssetSchema>;

export async function createMediaAsset(
  client: PoolClient,
  principal: AuthPrincipal,
  input: CreateMediaAssetInput
) {
  const id = randomUUID();
  const result = await client.query(
    `insert into growth.media_assets
       (id, workspace_id, storage_ref, mime_type, checksum, rights_status, source_class,
        bytes, duration_seconds, width_px, height_px, purpose, content_version_id, creative_generation_id)
     values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
     returning id, workspace_id, storage_ref, mime_type, checksum, rights_status, source_class,
               bytes, duration_seconds, width_px, height_px, purpose, content_version_id,
               creative_generation_id, created_at`,
    [
      id,
      principal.workspaceId,
      input.storageRef,
      input.mimeType,
      input.checksum,
      input.rightsStatus,
      input.sourceClass,
      input.bytes ?? null,
      input.durationSeconds ?? null,
      input.widthPx ?? null,
      input.heightPx ?? null,
      input.purpose ?? null,
      input.contentVersionId ?? null,
      input.creativeGenerationId ?? null
    ]
  );
  return result.rows[0];
}

export const CreateLineageEdgeSchema = z.object({
  outputAssetId: z.string().uuid(),
  inputAssetId: z.string().uuid(),
  role: z.string().trim().max(100).optional()
});

export type CreateLineageEdgeInput = z.infer<typeof CreateLineageEdgeSchema>;

export async function createLineageEdge(
  client: PoolClient,
  principal: AuthPrincipal,
  input: CreateLineageEdgeInput
) {
  const result = await client.query(
    `insert into growth.media_asset_lineage (workspace_id, output_asset_id, input_asset_id, role)
     values ($1, $2, $3, $4)
     returning workspace_id, output_asset_id, input_asset_id, role, created_at`,
    [principal.workspaceId, input.outputAssetId, input.inputAssetId, input.role ?? null]
  );
  return result.rows[0];
}
