import type { PoolClient } from "pg";
import { z } from "zod";
import type { AuthPrincipal } from "./auth.js";

export const CreatePublicationIntentSchema = z.object({
  socialAccountId: z.string().uuid(),
  contentVersionId: z.string().uuid(),
  requestNonce: z.string().uuid(),
  idempotencyKey: z.string().trim().min(1).max(200)
});

export type CreatePublicationIntentInput = z.infer<typeof CreatePublicationIntentSchema>;

export async function createPublicationIntent(
  client: PoolClient,
  principal: AuthPrincipal,
  input: CreatePublicationIntentInput
) {
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
