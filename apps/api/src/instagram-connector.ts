import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";
import type { PoolClient } from "pg";
import { z } from "zod";
import { env } from "./config.js";
import type { AuthPrincipal } from "./auth.js";
import { withTenantTransaction } from "./tenant-db.js";

const INSTAGRAM_SCOPES = [
  "instagram_business_basic",
  "instagram_business_content_publish",
  "instagram_business_manage_insights"
] as const;
const INSTAGRAM_CALLBACK_PATH = "/v1/integrations/instagram/callback";
const OAUTH_STATE_TTL_MS = 10 * 60 * 1000;
const ADAPTER_VERSION = "instagram-v0.1";
const CIPHER_VERSION = "aes-256-gcm.v1";

export const InstagramAuthorizeSchema = z.object({
  managedAccountId: z.string().uuid()
});

export const InstagramCallbackQuerySchema = z.object({
  code: z.string().min(1).optional(),
  state: z.string().min(1),
  error: z.string().min(1).optional()
});

type InstagramConfig = {
  appId: string;
  appSecret: string;
  credentialKey: Buffer;
  keyVersion: string;
  redirectUri: string;
  graphApiVersion: string;
};

export type InstagramState = {
  v: 1;
  userId: string;
  workspaceId: string;
  managedAccountId: string;
  connectionId: string;
  nonce: string;
  expiresAt: number;
};

type InstagramTokenResponse = {
  access_token: string;
  user_id?: string;
  expires_in?: number;
  permissions?: string[];
};

type InstagramProfile = {
  id: string;
  username?: string;
  name?: string;
  account_type?: string;
  media_count?: number;
  followers_count?: number;
};

type StoredCredential = {
  v: 1;
  accessToken: string;
  refreshToken: null;
  tokenType: "Bearer";
  scopes: string[];
  expiresAt: string;
};

type CredentialRow = {
  social_account_id: string;
  provider_account_id: string;
  credential_ciphertext: Buffer;
  cipher_version: string;
  key_version: string;
  token_expires_at: string | null;
  refresh_available: boolean;
  granted_scopes: string[];
};

export class InstagramConnectorError extends Error {
  constructor(public readonly code: string, public readonly httpStatus: number) {
    super(code);
  }
}

function parseConfig(): InstagramConfig | null {
  const appId = process.env.INSTAGRAM_APP_ID?.trim();
  const appSecret = process.env.INSTAGRAM_APP_SECRET?.trim();
  const encodedKey = process.env.PROVIDER_CREDENTIALS_KEY_B64URL?.trim();
  const configured = [appId, appSecret, encodedKey].filter(Boolean).length;
  if (configured === 0) return null;
  if (configured !== 3 || !appId || !appSecret || !encodedKey) {
    throw new InstagramConnectorError("instagram_integration_misconfigured", 503);
  }
  const credentialKey = Buffer.from(encodedKey, "base64url");
  if (credentialKey.length !== 32) {
    throw new InstagramConnectorError("instagram_credential_key_invalid", 503);
  }
  const graphApiVersion = process.env.INSTAGRAM_GRAPH_API_VERSION?.trim() || "v24.0";
  if (!/^v[0-9]+\.[0-9]+$/.test(graphApiVersion)) {
    throw new InstagramConnectorError("instagram_graph_api_version_invalid", 503);
  }
  return {
    appId,
    appSecret,
    credentialKey,
    keyVersion: process.env.PROVIDER_CREDENTIALS_KEY_VERSION?.trim() || "v1",
    redirectUri: new URL(INSTAGRAM_CALLBACK_PATH, env.APP_ORIGIN).toString(),
    graphApiVersion
  };
}

export function instagramConnectorConfigured(): boolean {
  return parseConfig() !== null;
}

function requireConfig(): InstagramConfig {
  const config = parseConfig();
  if (!config) throw new InstagramConnectorError("instagram_integration_not_configured", 503);
  return config;
}

function stateKey(): Buffer {
  return createHash("sha256").update(`${env.CSRF_SECRET}:instagram-oauth-state:v1`, "utf8").digest();
}

function sealJson(payload: unknown, key: Buffer, aad: string): string {
  const nonce = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, nonce);
  cipher.setAAD(Buffer.from(aad, "utf8"));
  const encrypted = Buffer.concat([cipher.update(JSON.stringify(payload), "utf8"), cipher.final()]);
  return [nonce, cipher.getAuthTag(), encrypted].map((part) => part.toString("base64url")).join(".");
}

function openJson<T>(sealed: string, key: Buffer, aad: string): T {
  const parts = sealed.split(".");
  if (parts.length !== 3) throw new InstagramConnectorError("instagram_state_invalid", 400);
  try {
    const decipher = createDecipheriv("aes-256-gcm", key, Buffer.from(parts[0]!, "base64url"));
    decipher.setAAD(Buffer.from(aad, "utf8"));
    decipher.setAuthTag(Buffer.from(parts[1]!, "base64url"));
    const plaintext = Buffer.concat([
      decipher.update(Buffer.from(parts[2]!, "base64url")),
      decipher.final()
    ]);
    return JSON.parse(plaintext.toString("utf8")) as T;
  } catch {
    throw new InstagramConnectorError("instagram_state_invalid", 400);
  }
}

function sealState(state: InstagramState): string {
  return sealJson(state, stateKey(), "instagram-oauth-state-v1");
}

function openState(sealed: string): InstagramState {
  const state = openJson<InstagramState>(sealed, stateKey(), "instagram-oauth-state-v1");
  const uuid = z.string().uuid();
  if (
    state.v !== 1 ||
    state.expiresAt <= Date.now() ||
    !uuid.safeParse(state.userId).success ||
    !uuid.safeParse(state.workspaceId).success ||
    !uuid.safeParse(state.managedAccountId).success ||
    !uuid.safeParse(state.connectionId).success
  ) {
    throw new InstagramConnectorError("instagram_state_invalid_or_expired", 400);
  }
  return state;
}

function credentialAad(workspaceId: string, connectionId: string): string {
  return `instagram-credential:v1:${workspaceId}:${connectionId}`;
}

function sealCredential(
  credential: StoredCredential,
  workspaceId: string,
  connectionId: string,
  config: InstagramConfig
): Buffer {
  return Buffer.from(sealJson(credential, config.credentialKey, credentialAad(workspaceId, connectionId)), "utf8");
}

async function metaJson<T>(url: string, init: RequestInit): Promise<T> {
  const response = await fetch(url, init);
  if (!response.ok) {
    if (response.status === 401 || response.status === 403) {
      throw new InstagramConnectorError("instagram_authorization_rejected", 401);
    }
    if (response.status === 429) throw new InstagramConnectorError("instagram_rate_limited", 503);
    if (response.status >= 500) throw new InstagramConnectorError("instagram_provider_unavailable", 503);
    throw new InstagramConnectorError("instagram_provider_request_failed", 502);
  }
  try {
    return await response.json() as T;
  } catch {
    throw new InstagramConnectorError("instagram_provider_response_invalid", 502);
  }
}

async function exchangeAuthorizationCode(code: string, config: InstagramConfig): Promise<InstagramTokenResponse> {
  const body = new URLSearchParams({
    client_id: config.appId,
    client_secret: config.appSecret,
    grant_type: "authorization_code",
    redirect_uri: config.redirectUri,
    code
  });
  const token = await metaJson<InstagramTokenResponse>("https://api.instagram.com/oauth/access_token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body
  });
  if (!token.access_token || !token.user_id) {
    throw new InstagramConnectorError("instagram_token_response_invalid", 502);
  }
  return token;
}

async function exchangeLongLivedToken(
  shortLivedToken: string,
  config: InstagramConfig
): Promise<{ access_token: string; expires_in: number; scopes: string[] }> {
  const url = new URL("https://graph.instagram.com/access_token");
  url.searchParams.set("grant_type", "ig_exchange_token");
  url.searchParams.set("client_secret", config.appSecret);
  url.searchParams.set("access_token", shortLivedToken);
  const token = await metaJson<{ access_token?: string; expires_in?: number }>(url.toString(), {});
  if (!token.access_token || typeof token.expires_in !== "number") {
    throw new InstagramConnectorError("instagram_long_lived_token_invalid", 502);
  }
  return { access_token: token.access_token, expires_in: token.expires_in, scopes: [...INSTAGRAM_SCOPES] };
}

async function fetchProfile(accessToken: string, config: InstagramConfig): Promise<InstagramProfile> {
  const url = new URL(`https://graph.instagram.com/${config.graphApiVersion}/me`);
  url.searchParams.set("fields", "id,username,name,account_type,media_count,followers_count");
  const profile = await metaJson<InstagramProfile>(url.toString(), {
    headers: { authorization: `Bearer ${accessToken}` }
  });
  if (!profile.id || !profile.account_type) {
    throw new InstagramConnectorError("instagram_profile_invalid", 502);
  }
  if (!["BUSINESS", "CREATOR", "business", "creator"].includes(profile.account_type)) {
    throw new InstagramConnectorError("instagram_professional_account_required", 409);
  }
  return profile;
}

export async function beginInstagramAuthorization(
  client: PoolClient,
  principal: AuthPrincipal,
  managedAccountId: string
): Promise<{ connectionId: string; authorizationUrl: string }> {
  const config = requireConfig();
  const result = await client.query<{ connection_id: string }>(
    "select growth.instagram_begin_authorization($1,$2::text[]) as connection_id",
    [managedAccountId, [...INSTAGRAM_SCOPES]]
  );
  const connectionId = result.rows[0]?.connection_id;
  if (!connectionId) throw new InstagramConnectorError("instagram_authorization_not_started", 500);

  const state = sealState({
    v: 1,
    userId: principal.userId,
    workspaceId: principal.workspaceId,
    managedAccountId,
    connectionId,
    nonce: randomBytes(18).toString("base64url"),
    expiresAt: Date.now() + OAUTH_STATE_TTL_MS
  });
  const url = new URL("https://www.instagram.com/oauth/authorize");
  url.searchParams.set("client_id", config.appId);
  url.searchParams.set("redirect_uri", config.redirectUri);
  url.searchParams.set("response_type", "code");
  url.searchParams.set("scope", INSTAGRAM_SCOPES.join(","));
  url.searchParams.set("state", state);
  return { connectionId, authorizationUrl: url.toString() };
}

export async function completeInstagramAuthorizationFromCallback(
  sealedState: string,
  code: string
): Promise<{ workspaceId: string; connectionId: string; socialAccountId: string; providerAccountId: string; handle: string | null }> {
  const config = requireConfig();
  const state = openState(sealedState);
  const shortLived = await exchangeAuthorizationCode(code, config);
  const longLived = await exchangeLongLivedToken(shortLived.access_token, config);
  const profile = await fetchProfile(longLived.access_token, config);
  const expiresAt = new Date(Date.now() + longLived.expires_in * 1000).toISOString();
  const credential: StoredCredential = {
    v: 1,
    accessToken: longLived.access_token,
    refreshToken: null,
    tokenType: "Bearer",
    scopes: longLived.scopes,
    expiresAt
  };
  const ciphertext = sealCredential(credential, state.workspaceId, state.connectionId, config);
  const principal: AuthPrincipal = { userId: state.userId, workspaceId: state.workspaceId };
  const socialAccountId = await withTenantTransaction(principal, async (client) => {
    const result = await client.query<{ social_account_id: string }>(
      `select growth.instagram_complete_authorization(
        $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::text[]
      ) as social_account_id`,
      [
        state.connectionId,
        profile.id,
        profile.username ?? profile.name ?? null,
        profile.account_type,
        null,
        null,
        ciphertext,
        CIPHER_VERSION,
        config.keyVersion,
        expiresAt,
        false,
        longLived.scopes
      ]
    );
    const id = result.rows[0]?.social_account_id;
    if (!id) throw new InstagramConnectorError("instagram_connection_not_persisted", 500);
    return id;
  });
  return {
    workspaceId: state.workspaceId,
    connectionId: state.connectionId,
    socialAccountId,
    providerAccountId: profile.id,
    handle: profile.username ?? null
  };
}

export function sealInstagramStateForTest(state: InstagramState): string {
  return sealState(state);
}

export function openInstagramStateForTest(sealed: string): InstagramState {
  return openState(sealed);
}
