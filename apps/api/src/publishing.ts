import type { PoolClient } from "pg";
import { z } from "zod";
import type { AuthPrincipal } from "./auth.js";

export const CreatePublicationIntentSchema = z.object({
  socialAccountId: z.string().uuid(),
  contentVersionId: z.string().uuid(),
  mediaAssetId: z.string().uuid().optional(),
  requestNonce: z.string().uuid(),
  idempotencyKey: z.string().trim().min(1).max(200)
});

export type CreatePublicationIntentInput = z.infer<typeof CreatePublicationIntentSchema>;

export async function createPublicationIntent(
  client: PoolClient,
  principal: AuthPrincipal,
  input: CreatePublicationIntentInput
) {
  if (input.mediaAssetId) {
    const result = await client.query(
      `select *
         from growth.create_publication_intent($1, $2, $3, $4, $5, $6)`,
      [
        principal.workspaceId,
        input.socialAccountId,
        input.contentVersionId,
        input.requestNonce,
        input.idempotencyKey,
        input.mediaAssetId
      ]
    );
    return result.rows[0];
  }

  const result = await client.query(
    `select *
       from growth.create_publication_intent($1, $2, $3, $4, $5)`,
    [
      principal.workspaceId,
      input.socialAccountId,
      input.contentVersionId,
      input.requestNonce,
      input.idempotencyKey
    ]
  );

  return result.rows[0];
}


export async function cancelPublicationIntent(
  client: PoolClient,
  principal: AuthPrincipal,
  publicationIntentId: string
) {
  const result = await client.query(
    `select *
       from growth.cancel_publication_intent($1, $2, $3)`,
    [principal.workspaceId, publicationIntentId, principal.userId]
  );
  return result.rows[0];
}


export const PublicationReconciliationSchema = z.object({
  attemptNo: z.number().int().positive(),
  method: z.enum(["exact", "resumable_status", "fuzzy_recent_content", "manual"]),
  confidence: z.enum(["exact", "high", "medium", "low", "none"]),
  reconciliationStatus: z.enum(["pending", "matched", "not_found", "ambiguous", "escalated"]),
  candidateProviderContentId: z.string().trim().max(500).optional(),
  evidenceRef: z.string().trim().max(500).optional()
});

export type PublicationReconciliationInput = z.infer<typeof PublicationReconciliationSchema>;

export async function recordPublicationReconciliation(
  client: PoolClient,
  principal: AuthPrincipal,
  publicationIntentId: string,
  input: PublicationReconciliationInput
) {
  const result = await client.query(
    `select *
       from growth.record_publication_reconciliation(
         $1, $2, $3, $4, $5, $6, $7, $8
       )`,
    [
      principal.workspaceId,
      publicationIntentId,
      input.attemptNo,
      input.method,
      input.confidence,
      input.reconciliationStatus,
      input.candidateProviderContentId ?? null,
      input.evidenceRef ?? null
    ]
  );
  return result.rows[0];
}
