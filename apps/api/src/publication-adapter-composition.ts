import { createDecipheriv } from "node:crypto";
import { z } from "zod";
import { env } from "./config.js";
import {
  publishInstagram,
  publishYoutubeVideo,
  type PublicationFetch
} from "./publication-provider-adapters.js";
import {
  PublicationProviderError,
  type ClaimablePublicationIntent,
  type PublicationProviderAdapter
} from "./publication-worker.js";

const PublicationStructureSchema = z.object({
  mediaKind: z.enum(["image", "reel"]).optional(),
  title: z.string().trim().min(1).max(100).optional(),
  description: z.string().max(5_000).optional(),
  tags: z.array(z.string().trim().min(1).max(500)).max(50).optional(),
  privacyStatus: z.enum(["private", "public", "unlisted"]).optional()
}).passthrough();

type StoredCredential = {
  accessToken: string;
  refreshToken?: string | null;
  expiresAt?: string;
};

function credentialKey(): Buffer {
  const encoded = process.env.PROVIDER_CREDENTIALS_KEY_B64URL?.trim();
  if (!encoded) throw new PublicationProviderError(503, null, "publication credential key is not configured");
  const key = Buffer.from(encoded, "base64url");
  if (key.length !== 32) {
    throw new PublicationProviderError(503, null, "publication credential key is invalid");
  }
  return key;
}

function openCredential(
  ciphertext: Buffer,
  provider: "instagram" | "youtube",
  workspaceId: string,
  connectionId: string
): StoredCredential {
  try {
    const parts = ciphertext.toString("utf8").split(".");
    if (parts.length !== 3) throw new Error("invalid credential envelope");
    const decipher = createDecipheriv("aes-256-gcm", credentialKey(), Buffer.from(parts[0]!, "base64url"));
    decipher.setAAD(Buffer.from(`${provider}-credential:v1:${workspaceId}:${connectionId}`, "utf8"));
    decipher.setAuthTag(Buffer.from(parts[1]!, "base64url"));
    const plaintext = Buffer.concat([
      decipher.update(Buffer.from(parts[2]!, "base64url")),
      decipher.final()
    ]);
    const parsed = JSON.parse(plaintext.toString("utf8")) as StoredCredential;
    if (typeof parsed.accessToken !== "string" || parsed.accessToken.length === 0) {
      throw new Error("credential access token is missing");
    }
    return parsed;
  } catch (error) {
    if (error instanceof PublicationProviderError) throw error;
    throw new PublicationProviderError(503, null, "publication credential is unreadable");
  }
}

function allowedAssetHost(storageRef: string): boolean {
  const hosts = (process.env.PUBLICATION_ASSET_HOSTS ?? "")
    .split(",")
    .map((host) => host.trim().toLowerCase())
    .filter(Boolean);
  if (hosts.length === 0) return false;
  try {
    const url = new URL(storageRef);
    return url.protocol === "https:" && hosts.includes(url.hostname.toLowerCase());
  } catch {
    return false;
  }
}

function requireContextField<T>(
  value: T | undefined | null,
  field: string
): T {
  if (value === undefined || value === null || value === "") {
    throw new PublicationProviderError(422, null, `publication context field missing: ${field}`);
  }
  return value;
}

async function fetchYoutubeAsset(
  storageRef: string,
  expectedBytes: number | string | null | undefined,
  fetchImpl: PublicationFetch
): Promise<Uint8Array> {
  if (!allowedAssetHost(storageRef)) {
    throw new PublicationProviderError(422, null, "publication asset host is not allowlisted");
  }
  const response = await fetchImpl(storageRef, { method: "GET" });
  if (!response.ok) {
    throw new PublicationProviderError(response.status, null, "publication asset could not be read");
  }
  const body = new Uint8Array(await response.arrayBuffer());
  if (expectedBytes !== null && expectedBytes !== undefined && body.byteLength !== Number(expectedBytes)) {
    throw new PublicationProviderError(502, null, "publication asset byte count changed");
  }
  return body;
}

function parsedStructure(value: unknown) {
  const result = PublicationStructureSchema.safeParse(value ?? {});
  if (!result.success) {
    throw new PublicationProviderError(422, null, "publication structure is invalid");
  }
  return result.data;
}

export function createPublicationProviderAdapter(
  claimed: ClaimablePublicationIntent,
  options: { fetchImpl?: PublicationFetch } = {}
): PublicationProviderAdapter {
  const fetchImpl = options.fetchImpl ?? fetch;
  const connectionId = requireContextField(claimed.connectionId, "connectionId");
  const storageRef = requireContextField(claimed.storageRef, "storageRef");
  const providerAccountId = requireContextField(claimed.providerAccountId, "providerAccountId");
  const credentialCiphertext = requireContextField(claimed.credentialCiphertext, "credentialCiphertext");
  const structure = parsedStructure(claimed.structure);

  return {
    publish: async () => {
      const credential = openCredential(
        credentialCiphertext,
        claimed.provider,
        claimed.workspaceId,
        connectionId
      );

      if (claimed.provider === "instagram") {
        if (!allowedAssetHost(storageRef)) {
          throw new PublicationProviderError(422, null, "publication asset host is not allowlisted");
        }
        const mediaKind = structure.mediaKind
          ?? (claimed.mimeType?.startsWith("video/") ? "reel" : "image");
        return publishInstagram({
          apiVersion: env.INSTAGRAM_GRAPH_API_VERSION,
          providerAccountId,
          accessToken: credential.accessToken,
          mediaKind,
          mediaUrl: storageRef,
          caption: claimed.body ?? "",
          fetchImpl
        });
      }

      const mimeType = requireContextField(claimed.mimeType, "mimeType");
      if (!mimeType.startsWith("video/")) {
        throw new PublicationProviderError(422, null, "YouTube publication requires a video asset");
      }
      const title = requireContextField(structure.title, "title");
      const mediaBody = await fetchYoutubeAsset(storageRef, claimed.bytes, fetchImpl);
      return publishYoutubeVideo({
        accessToken: credential.accessToken,
        mimeType: z.enum(["video/mp4", "video/quicktime", "video/webm"]).parse(mimeType),
        bytes: mediaBody.byteLength,
        title,
        description: structure.description ?? claimed.body ?? "",
        tags: structure.tags ?? [],
        privacyStatus: structure.privacyStatus ?? "private",
        mediaBody,
        fetchImpl
      });
    }
  };
}
