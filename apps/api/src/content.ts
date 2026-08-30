import { createHash, randomUUID } from "node:crypto";
import type { PoolClient } from "pg";
import { z } from "zod";
import type { AuthPrincipal } from "./auth.js";

export const CreateContentSchema = z.object({
  objective: z.string().trim().min(1).max(500).optional(),
  market: z.string().trim().min(1).max(100),
  language: z.string().trim().min(2).max(20),
  platformTarget: z.string().trim().min(1).max(50).optional(),
  sourceType: z.string().trim().min(1).max(50),
  body: z.string().max(100_000).default(""),
  structure: z.record(z.string(), z.unknown()).default({}),
  aiProvenance: z.record(z.string(), z.unknown()).optional()
});

export type CreateContentInput = z.infer<typeof CreateContentSchema>;

export async function createContent(
  client: PoolClient,
  principal: AuthPrincipal,
  input: CreateContentInput
) {
  const contentItemId = randomUUID();
  const contentVersionId = randomUUID();
  const checksum = createHash("sha256")
    .update(JSON.stringify({ body: input.body, structure: input.structure }))
    .digest("hex");

  const itemResult = await client.query(
    `insert into growth.content_items
       (id, workspace_id, objective, market, language, platform_target, source_type, status, created_by)
     values ($1, $2, $3, $4, $5, $6, $7, 'draft', $8)
     returning id, workspace_id, objective, market, language, platform_target, source_type, status, created_by, created_at`,
    [
      contentItemId,
      principal.workspaceId,
      input.objective ?? null,
      input.market,
      input.language,
      input.platformTarget ?? null,
      input.sourceType,
      principal.userId
    ]
  );

  const versionResult = await client.query(
    `insert into growth.content_versions
       (id, workspace_id, content_item_id, version_no, body, structure_json, ai_provenance, checksum)
     values ($1, $2, $3, 1, $4, $5::jsonb, $6::jsonb, $7)
     returning id, workspace_id, content_item_id, version_no, body, structure_json, ai_provenance, checksum, created_at`,
    [
      contentVersionId,
      principal.workspaceId,
      contentItemId,
      input.body,
      JSON.stringify(input.structure),
      input.aiProvenance ? JSON.stringify(input.aiProvenance) : null,
      checksum
    ]
  );

  return { item: itemResult.rows[0], version: versionResult.rows[0] };
}

export async function listContent(
  client: PoolClient,
  principal: AuthPrincipal,
  limit = 25
) {
  const safeLimit = Math.min(Math.max(limit, 1), 100);
  const result = await client.query(
    `select ci.id, ci.objective, ci.market, ci.language, ci.platform_target,
            ci.source_type, ci.status, ci.created_by, ci.created_at,
            cv.id as current_version_id, cv.version_no, cv.body, cv.structure_json,
            cv.ai_provenance, cv.checksum, cv.created_at as version_created_at
       from growth.content_items ci
       left join lateral (
         select v.*
           from growth.content_versions v
          where v.workspace_id = ci.workspace_id
            and v.content_item_id = ci.id
          order by v.version_no desc
          limit 1
       ) cv on true
      where ci.workspace_id = $1
      order by ci.created_at desc
      limit $2`,
    [principal.workspaceId, safeLimit]
  );

  return result.rows;
}
