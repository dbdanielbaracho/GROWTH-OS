import { randomUUID } from "node:crypto";
import type { AuthPrincipal } from "./auth.js";
import { withTenantTransaction } from "./tenant-db.js";
import type {
  ClaimablePublicationIntent,
  PublicationExecutionStore,
  PublicationFinalization
} from "./publication-worker.js";

type PublicationContextRow = {
  publication_intent_id: string;
  workspace_id: string;
  connection_id: string;
  claim_token: string;
  attempt_no: number;
  provider: string;
  social_account_id: string;
  content_version_id: string;
  body: string | null;
  structure: unknown;
  media_asset_id: string;
  storage_ref: string;
  mime_type: string;
  bytes: number | string | null;
  provider_account_id: string;
  credential_ciphertext: Buffer;
  cipher_version: string;
  key_version: string;
  token_expires_at: string | null;
  refresh_available: boolean;
  granted_scopes: string[];
};

function provider(value: string): "instagram" | "youtube" {
  if (value === "instagram" || value === "youtube") return value;
  throw new Error("unsupported publication provider");
}

function mapContext(row: PublicationContextRow): ClaimablePublicationIntent {
  if (!row.publication_intent_id || !row.claim_token || !row.attempt_no || !row.connection_id) {
    throw new Error("publication claim returned an incomplete context");
  }
  return {
    workspaceId: row.workspace_id,
    publicationIntentId: row.publication_intent_id,
    claimToken: row.claim_token,
    attemptNo: row.attempt_no,
    provider: provider(row.provider),
    socialAccountId: row.social_account_id,
    contentVersionId: row.content_version_id,
    body: row.body,
    structure: row.structure,
    assetRefs: [row.media_asset_id, row.storage_ref],
    connectionId: row.connection_id,
    mediaAssetId: row.media_asset_id,
    storageRef: row.storage_ref,
    mimeType: row.mime_type,
    bytes: row.bytes,
    providerAccountId: row.provider_account_id,
    credentialCiphertext: row.credential_ciphertext,
    cipherVersion: row.cipher_version,
    keyVersion: row.key_version,
    tokenExpiresAt: row.token_expires_at,
    refreshAvailable: row.refresh_available,
    grantedScopes: row.granted_scopes
  };
}

export function createDatabasePublicationExecutionStore(
  principal: AuthPrincipal,
  publicationIntentId: string,
  claimToken = randomUUID()
): PublicationExecutionStore {
  let claimed: ClaimablePublicationIntent | null = null;

  return {
    claim: async () => {
      const result = await withTenantTransaction(principal, async (client) => {
        const claimResult = await client.query<{ [key: string]: unknown }>(
          `select *
             from growth.claim_publication_intent($1,$2,$3,$4)`,
          [
            principal.workspaceId,
            publicationIntentId,
            claimToken,
            new Date().toISOString()
          ]
        );
        const claim = claimResult.rows[0];
        if (!claim) throw new Error("publication claim returned no intent");

        const contextResult = await client.query<PublicationContextRow>(
          `select *
             from growth.get_publication_execution_context($1,$2,$3)`,
          [principal.workspaceId, publicationIntentId, claimToken]
        );
        const context = contextResult.rows[0];
        if (!context) throw new Error("publication execution context unavailable");
        return mapContext(context);
      });
      claimed = result;
      return result;
    },
    finalize: async (
      claimedIntent: ClaimablePublicationIntent,
      result: PublicationFinalization
    ) => {
      if (claimed && claimedIntent.claimToken !== claimed.claimToken) {
        throw new Error("publication finalization claim token mismatch");
      }
      return withTenantTransaction(principal, async (client) => {
        const finalizationResult = await client.query(
          `select *
             from growth.finalize_publication_intent(
               $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13
             )`,
          [
            principal.workspaceId,
            claimedIntent.publicationIntentId,
            claimedIntent.claimToken,
            claimedIntent.attemptNo,
            result.requestHash,
            result.outcome,
            result.httpStatus,
            result.providerRequestId,
            result.providerContentId,
            result.providerPermalink,
            result.startedAt,
            result.providerRespondedAt,
            result.rawPayloadRef
          ]
        );
        return finalizationResult.rows[0];
      });
    }
  };
}
