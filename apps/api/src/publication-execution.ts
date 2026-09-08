import { createHash } from "node:crypto";
import { z } from "zod";

export const PublicationOutcomeSchema = z.enum([
  "confirmed",
  "failed_retryable",
  "needs_user_action"
]);

export type PublicationOutcome = z.infer<typeof PublicationOutcomeSchema>;

const PublicationResultSchema = z.object({
  outcome: PublicationOutcomeSchema,
  httpStatus: z.number().int().min(100).max(599).nullable().default(null),
  providerRequestId: z.string().trim().min(1).max(500).nullable().default(null),
  providerContentId: z.string().trim().min(1).max(500).nullable().default(null),
  providerPermalink: z.string().trim().url().max(2_000).nullable().default(null),
  startedAt: z.string().trim().min(1).max(100).nullable().default(null),
  providerRespondedAt: z.string().trim().min(1).max(100).nullable().default(null),
  rawPayload: z.unknown().nullable().default(null)
});

export type PublicationProviderResult = z.infer<typeof PublicationResultSchema>;

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

export type PublicationRequestIdentity = {
  provider: "instagram" | "youtube";
  socialAccountId: string;
  contentVersionId: string;
  attemptNo: number;
  body: string | null;
  structure: unknown;
  assetRefs: string[];
};

type CanonicalValue = null | boolean | number | string | CanonicalValue[] | { [key: string]: CanonicalValue };

function canonicalize(value: unknown): CanonicalValue {
  if (value === null || typeof value === "boolean" || typeof value === "number" || typeof value === "string") {
    return value;
  }
  if (Array.isArray(value)) return value.map(canonicalize);
  if (typeof value === "object") {
    return Object.fromEntries(
      Object.entries(value as Record<string, unknown>)
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([key, item]) => [key, canonicalize(item)])
    );
  }
  return String(value);
}

export function publicationRequestHash(identity: PublicationRequestIdentity): string {
  const canonical = JSON.stringify(canonicalize({
    provider: identity.provider,
    socialAccountId: identity.socialAccountId,
    contentVersionId: identity.contentVersionId,
    attemptNo: identity.attemptNo,
    body: identity.body,
    structure: identity.structure,
    assetRefs: identity.assetRefs
  }));
  return createHash("sha256").update(canonical, "utf8").digest("hex");
}

export function providerPayloadRef(payload: unknown): string | null {
  if (payload === null || payload === undefined) return null;
  const canonical = JSON.stringify(canonicalize(payload));
  return `sha256:${createHash("sha256").update(canonical, "utf8").digest("hex")}`;
}

export function classifyProviderResponse(
  httpStatus: number | null,
  providerContentId: string | null
): PublicationOutcome {
  if (httpStatus !== null && httpStatus >= 200 && httpStatus < 300 && providerContentId?.trim()) {
    return "confirmed";
  }
  if (
    httpStatus === 401 ||
    httpStatus === 403 ||
    httpStatus === 404 ||
    httpStatus === 409 ||
    httpStatus === 422
  ) {
    return "needs_user_action";
  }
  return "failed_retryable";
}

export function preparePublicationProviderResult(input: {
  httpStatus: number | null;
  providerRequestId?: string | null;
  providerContentId?: string | null;
  providerPermalink?: string | null;
  startedAt?: string | null;
  providerRespondedAt?: string | null;
  rawPayload?: unknown;
}): PublicationProviderResult {
  const providerContentId = input.providerContentId?.trim() || null;
  const outcome = classifyProviderResponse(input.httpStatus, providerContentId);
  if (outcome === "confirmed" && !providerContentId) {
    throw new Error("confirmed publication requires provider content id");
  }

  return PublicationResultSchema.parse({
    outcome,
    httpStatus: input.httpStatus,
    providerRequestId: input.providerRequestId?.trim() || null,
    providerContentId,
    providerPermalink: input.providerPermalink?.trim() || null,
    startedAt: input.startedAt?.trim() || null,
    providerRespondedAt: input.providerRespondedAt?.trim() || null,
    rawPayload: input.rawPayload ?? null
  });
}

export function toFinalizationArguments(
  result: PublicationProviderResult,
  requestHash: string
) {
  return {
    requestHash,
    outcome: result.outcome,
    httpStatus: result.httpStatus,
    providerRequestId: result.providerRequestId,
    providerContentId: result.providerContentId,
    providerPermalink: result.providerPermalink,
    startedAt: result.startedAt,
    providerRespondedAt: result.providerRespondedAt,
    rawPayloadRef: providerPayloadRef(result.rawPayload)
  };
}
