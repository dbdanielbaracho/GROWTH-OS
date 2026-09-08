import {
  preparePublicationProviderResult,
  PublicationProviderError,
  publicationRequestHash,
  toFinalizationArguments,
  type PublicationProviderResult
} from "./publication-execution.js";

export { PublicationProviderError } from "./publication-execution.js";

export type ClaimablePublicationIntent = {
  workspaceId: string;
  publicationIntentId: string;
  claimToken: string;
  attemptNo: number;
  provider: "instagram" | "youtube";
  socialAccountId: string;
  contentVersionId: string;
  body: string | null;
  structure: unknown;
  assetRefs: string[];
  connectionId?: string;
  mediaAssetId?: string | null;
  storageRef?: string;
  mimeType?: string;
  bytes?: number | string | null;
  providerAccountId?: string;
  credentialCiphertext?: Buffer;
  cipherVersion?: string;
  keyVersion?: string;
  tokenExpiresAt?: string | null;
  refreshAvailable?: boolean;
  grantedScopes?: string[];
};

export type PublicationFinalization = ReturnType<typeof toFinalizationArguments>;

export type PublicationExecutionStore = {
  claim: () => Promise<ClaimablePublicationIntent>;
  finalize: (
    claimed: ClaimablePublicationIntent,
    result: PublicationFinalization
  ) => Promise<unknown>;
};

export type PublicationProviderAdapter = {
  publish: (input: {
    claimed: ClaimablePublicationIntent;
    requestHash: string;
  }) => Promise<PublicationProviderResult>;
};

export type PublicationProviderAdapterFactory = (
  claimed: ClaimablePublicationIntent
) => PublicationProviderAdapter;

function failureResult(error: unknown, startedAt: string) {
  const providerError = error instanceof PublicationProviderError ? error : null;
  return preparePublicationProviderResult({
    httpStatus: providerError?.httpStatus ?? null,
    providerRequestId: providerError?.providerRequestId ?? null,
    startedAt,
    providerRespondedAt: new Date().toISOString(),
    rawPayload: {
      error_class: error instanceof Error ? error.name : "unknown_provider_error"
    }
  });
}

export async function executePublicationIntent(input: {
  store: PublicationExecutionStore;
  adapter?: PublicationProviderAdapter;
  adapterFactory?: PublicationProviderAdapterFactory;
}): Promise<unknown> {
  const claimed = await input.store.claim();
  const startedAt = new Date().toISOString();
  const requestHash = publicationRequestHash({
    provider: claimed.provider,
    socialAccountId: claimed.socialAccountId,
    contentVersionId: claimed.contentVersionId,
    attemptNo: claimed.attemptNo,
    body: claimed.body,
    structure: claimed.structure,
    assetRefs: claimed.assetRefs
  });

  try {
    const adapter = input.adapterFactory?.(claimed) ?? input.adapter;
    if (!adapter) throw new Error("publication provider adapter is not configured");
    const providerResult = await adapter.publish({ claimed, requestHash });
    return input.store.finalize(
      claimed,
      toFinalizationArguments(providerResult, requestHash)
    );
  } catch (error) {
    const providerResult = failureResult(error, startedAt);
    return input.store.finalize(
      claimed,
      toFinalizationArguments(providerResult, requestHash)
    );
  }
}
