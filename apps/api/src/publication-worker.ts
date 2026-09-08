import {
  preparePublicationProviderResult,
  publicationRequestHash,
  toFinalizationArguments,
  type PublicationProviderResult
} from "./publication-execution.js";

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

export class PublicationProviderError extends Error {
  constructor(
    readonly httpStatus: number | null,
    readonly providerRequestId?: string | null,
    message = "publication provider request failed"
  ) {
    super(message);
    this.name = "PublicationProviderError";
  }
}

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
  adapter: PublicationProviderAdapter;
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
    const providerResult = await input.adapter.publish({ claimed, requestHash });
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
