import { createCipheriv, createDecipheriv, createHash, randomBytes } from "node:crypto";
import type { PoolClient } from "pg";
import { z } from "zod";
import { env } from "./config.js";
import type { AuthPrincipal } from "./auth.js";
import { withTenantTransaction } from "./tenant-db.js";

const YOUTUBE_SCOPES = [
  "https://www.googleapis.com/auth/youtube.readonly",
  "https://www.googleapis.com/auth/yt-analytics.readonly"
] as const;
const YOUTUBE_CALLBACK_PATH = "/v1/integrations/youtube/callback";
const YOUTUBE_SOURCE_TIMEZONE = "America/Los_Angeles";
const OAUTH_STATE_TTL_MS = 10 * 60 * 1000;
const VIEW_SEMANTIC_BREAK = "2026-08-24";
const ADAPTER_VERSION = "youtube-v0.2";
const PROVIDER_API_VERSION = "youtube-data-v3+analytics-v2@2026-09";
const SOURCE_SCHEMA_VERSION = "youtube.analytics.daily.v2";

export const YoutubeAuthorizeSchema = z.object({
  managedAccountId: z.string().uuid()
});

export const YoutubeSyncSchema = z.object({
  connectionId: z.string().uuid(),
  requestNonce: z.string().uuid(),
  lookbackDays: z.coerce.number().int().min(1).max(30).default(7)
});

export const YoutubeCallbackQuerySchema = z.object({
  code: z.string().min(1).optional(),
  state: z.string().min(1),
  error: z.string().min(1).optional()
});

type YoutubeConfig = {
  clientId: string;
  clientSecret: string;
  credentialKey: Buffer;
  keyVersion: string;
  redirectUri: string;
  derivedAnalyticsPolicyAccepted: boolean;
};

export type YoutubeState = {
  v: 1;
  userId: string;
  workspaceId: string;
  managedAccountId: string;
  connectionId: string;
  nonce: string;
  expiresAt: number;
};

type StoredCredential = {
  v: 1;
  accessToken: string;
  refreshToken: string | null;
  tokenType: string;
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

type TokenResponse = {
  access_token: string;
  expires_in: number;
  refresh_token?: string;
  scope?: string;
  token_type?: string;
};

type YoutubeChannel = {
  id: string;
  snippet?: {
    title?: string;
    customUrl?: string;
  };
};

type AnalyticsResponse = {
  columnHeaders?: Array<{ name?: string; columnType?: string; dataType?: string }>;
  rows?: unknown[][];
};

type ZonedDateTimeParts = {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
};

type RequiredDateTimePart = "year" | "month" | "day" | "hour" | "minute" | "second";

export class YoutubeConnectorError extends Error {
  constructor(public readonly code: string, public readonly httpStatus: number) {
    super(code);
  }
}

function parseConnectorConfig(): YoutubeConfig | null {
  const clientId = process.env.YOUTUBE_OAUTH_CLIENT_ID?.trim();
  const clientSecret = process.env.YOUTUBE_OAUTH_CLIENT_SECRET?.trim();
  const encodedKey = process.env.PROVIDER_CREDENTIALS_KEY_B64URL?.trim();
  const configured = [clientId, clientSecret, encodedKey].filter(Boolean).length;
  if (configured === 0) return null;
  if (configured !== 3 || !clientId || !clientSecret || !encodedKey) {
    throw new YoutubeConnectorError("youtube_integration_misconfigured", 503);
  }

  const credentialKey = Buffer.from(encodedKey, "base64url");
  if (credentialKey.length !== 32) {
    throw new YoutubeConnectorError("youtube_credential_key_invalid", 503);
  }

  return {
    clientId,
    clientSecret,
    credentialKey,
    keyVersion: process.env.PROVIDER_CREDENTIALS_KEY_VERSION?.trim() || "v1",
    redirectUri: new URL(YOUTUBE_CALLBACK_PATH, env.APP_ORIGIN).toString(),
    derivedAnalyticsPolicyAccepted: process.env.YOUTUBE_DERIVED_ANALYTICS_POLICY_ACCEPTED === "true"
  };
}

export function youtubeConnectorConfigured(): boolean {
  return parseConnectorConfig() !== null;
}

function requireConnectorConfig(): YoutubeConfig {
  const config = parseConnectorConfig();
  if (!config) throw new YoutubeConnectorError("youtube_integration_not_configured", 503);
  return config;
}

function stateKey(): Buffer {
  return createHash("sha256").update(`${env.CSRF_SECRET}:youtube-oauth-state:v1`, "utf8").digest();
}

function sealJson(payload: unknown, key: Buffer, aad: string): string {
  const nonce = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", key, nonce);
  cipher.setAAD(Buffer.from(aad, "utf8"));
  const encrypted = Buffer.concat([cipher.update(JSON.stringify(payload), "utf8"), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [nonce, tag, encrypted].map((part) => part.toString("base64url")).join(".");
}

function openJson<T>(sealed: string, key: Buffer, aad: string): T {
  const parts = sealed.split(".");
  if (parts.length !== 3) throw new YoutubeConnectorError("youtube_state_invalid", 400);
  try {
    const [noncePart, tagPart, ciphertextPart] = parts;
    const decipher = createDecipheriv("aes-256-gcm", key, Buffer.from(noncePart!, "base64url"));
    decipher.setAAD(Buffer.from(aad, "utf8"));
    decipher.setAuthTag(Buffer.from(tagPart!, "base64url"));
    const plaintext = Buffer.concat([
      decipher.update(Buffer.from(ciphertextPart!, "base64url")),
      decipher.final()
    ]);
    return JSON.parse(plaintext.toString("utf8")) as T;
  } catch {
    throw new YoutubeConnectorError("youtube_state_invalid", 400);
  }
}

export function sealYoutubeStateForTest(state: YoutubeState): string {
  return sealJson(state, stateKey(), "youtube-oauth-state-v1");
}

export function openYoutubeStateForTest(sealed: string): YoutubeState {
  return openYoutubeState(sealed);
}

function sealYoutubeState(state: YoutubeState): string {
  return sealJson(state, stateKey(), "youtube-oauth-state-v1");
}

function openYoutubeState(sealed: string): YoutubeState {
  const state = openJson<YoutubeState>(sealed, stateKey(), "youtube-oauth-state-v1");
  if (state.v !== 1 || state.expiresAt <= Date.now()) {
    throw new YoutubeConnectorError("youtube_state_expired", 400);
  }
  const uuid = z.string().uuid();
  if (
    !uuid.safeParse(state.userId).success
    || !uuid.safeParse(state.workspaceId).success
    || !uuid.safeParse(state.managedAccountId).success
    || !uuid.safeParse(state.connectionId).success
  ) {
    throw new YoutubeConnectorError("youtube_state_invalid", 400);
  }
  return state;
}

function credentialAad(workspaceId: string, connectionId: string): string {
  return `youtube-credential:v1:${workspaceId}:${connectionId}`;
}

function sealCredential(credential: StoredCredential, workspaceId: string, connectionId: string, config: YoutubeConfig): Buffer {
  return Buffer.from(
    sealJson(credential, config.credentialKey, credentialAad(workspaceId, connectionId)),
    "utf8"
  );
}

function openCredential(ciphertext: Buffer, workspaceId: string, connectionId: string, config: YoutubeConfig): StoredCredential {
  try {
    return openJson<StoredCredential>(
      ciphertext.toString("utf8"),
      config.credentialKey,
      credentialAad(workspaceId, connectionId)
    );
  } catch {
    throw new YoutubeConnectorError("youtube_credential_unreadable", 503);
  }
}

async function googleJson<T>(url: string, init: RequestInit): Promise<T> {
  const response = await fetch(url, init);
  if (!response.ok) {
    if (response.status === 401 || response.status === 403) {
      throw new YoutubeConnectorError("youtube_authorization_rejected", 401);
    }
    if (response.status === 429) throw new YoutubeConnectorError("youtube_rate_limited", 503);
    if (response.status >= 500) throw new YoutubeConnectorError("youtube_provider_unavailable", 503);
    throw new YoutubeConnectorError("youtube_provider_request_failed", 502);
  }
  try {
    return await response.json() as T;
  } catch {
    throw new YoutubeConnectorError("youtube_provider_response_invalid", 502);
  }
}

async function exchangeAuthorizationCode(code: string, config: YoutubeConfig): Promise<TokenResponse> {
  const body = new URLSearchParams({
    code,
    client_id: config.clientId,
    client_secret: config.clientSecret,
    redirect_uri: config.redirectUri,
    grant_type: "authorization_code"
  });
  const token = await googleJson<Partial<TokenResponse>>("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body
  });
  if (!token.access_token || typeof token.expires_in !== "number") {
    throw new YoutubeConnectorError("youtube_token_response_invalid", 502);
  }
  return token as TokenResponse;
}

async function refreshAccessToken(refreshToken: string, config: YoutubeConfig): Promise<TokenResponse> {
  const body = new URLSearchParams({
    refresh_token: refreshToken,
    client_id: config.clientId,
    client_secret: config.clientSecret,
    grant_type: "refresh_token"
  });
  const token = await googleJson<Partial<TokenResponse>>("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body
  });
  if (!token.access_token || typeof token.expires_in !== "number") {
    throw new YoutubeConnectorError("youtube_refresh_response_invalid", 502);
  }
  return token as TokenResponse;
}

async function fetchAuthorizedChannels(accessToken: string): Promise<YoutubeChannel[]> {
  const url = new URL("https://www.googleapis.com/youtube/v3/channels");
  url.searchParams.set("part", "snippet");
  url.searchParams.set("mine", "true");
  const payload = await googleJson<{ items?: YoutubeChannel[] }>(url.toString(), {
    headers: { authorization: `Bearer ${accessToken}` }
  });
  return payload.items ?? [];
}

async function fetchDailyAnalytics(accessToken: string, startDate: string, endDate: string): Promise<AnalyticsResponse> {
  const url = new URL("https://youtubeanalytics.googleapis.com/v2/reports");
  url.searchParams.set("ids", "channel==MINE");
  url.searchParams.set("startDate", startDate);
  url.searchParams.set("endDate", endDate);
  url.searchParams.set("dimensions", "day");
  url.searchParams.set("metrics", [
    "views",
    "engagedViews",
    "estimatedMinutesWatched",
    "averageViewDuration",
    "likes",
    "comments",
    "shares",
    "subscribersGained",
    "subscribersLost"
  ].join(","));
  return googleJson<AnalyticsResponse>(url.toString(), {
    headers: { authorization: `Bearer ${accessToken}` }
  });
}

async function beginAuthorizationRow(client: PoolClient, managedAccountId: string): Promise<string> {
  const result = await client.query<{ connection_id: string }>(
    "select growth.youtube_begin_authorization($1,$2::text[]) as connection_id",
    [managedAccountId, [...YOUTUBE_SCOPES]]
  );
  const connectionId = result.rows[0]?.connection_id;
  if (!connectionId) throw new YoutubeConnectorError("youtube_authorization_not_started", 500);
  return connectionId;
}

export async function beginYoutubeAuthorization(
  client: PoolClient,
  principal: AuthPrincipal,
  managedAccountId: string
): Promise<{ connectionId: string; authorizationUrl: string }> {
  const config = requireConnectorConfig();
  const connectionId = await beginAuthorizationRow(client, managedAccountId);
  const state = sealYoutubeState({
    v: 1,
    userId: principal.userId,
    workspaceId: principal.workspaceId,
    managedAccountId,
    connectionId,
    nonce: randomBytes(18).toString("base64url"),
    expiresAt: Date.now() + OAUTH_STATE_TTL_MS
  });

  const authorization = new URL("https://accounts.google.com/o/oauth2/v2/auth");
  authorization.searchParams.set("client_id", config.clientId);
  authorization.searchParams.set("redirect_uri", config.redirectUri);
  authorization.searchParams.set("response_type", "code");
  authorization.searchParams.set("scope", YOUTUBE_SCOPES.join(" "));
  authorization.searchParams.set("access_type", "offline");
  authorization.searchParams.set("include_granted_scopes", "true");
  authorization.searchParams.set("prompt", "consent");
  authorization.searchParams.set("state", state);

  return { connectionId, authorizationUrl: authorization.toString() };
}

export async function completeYoutubeAuthorizationFromCallback(
  sealedState: string,
  code: string
): Promise<{ workspaceId: string; connectionId: string; socialAccountId: string; channelId: string; channelTitle: string | null }> {
  const config = requireConnectorConfig();
  const state = openYoutubeState(sealedState);
  const token = await exchangeAuthorizationCode(code, config);
  const channels = await fetchAuthorizedChannels(token.access_token);
  if (channels.length === 0) throw new YoutubeConnectorError("youtube_channel_not_found", 409);
  if (channels.length > 1) throw new YoutubeConnectorError("youtube_channel_selection_required", 409);
  const channel = channels[0]!;
  if (!channel.id) throw new YoutubeConnectorError("youtube_channel_identity_invalid", 502);

  const expiresAt = new Date(Date.now() + token.expires_in * 1000).toISOString();
  const scopes = token.scope?.split(/\s+/).filter(Boolean) ?? [...YOUTUBE_SCOPES];
  const credential: StoredCredential = {
    v: 1,
    accessToken: token.access_token,
    refreshToken: token.refresh_token ?? null,
    tokenType: token.token_type ?? "Bearer",
    scopes,
    expiresAt
  };
  const ciphertext = sealCredential(credential, state.workspaceId, state.connectionId, config);
  const principal: AuthPrincipal = { userId: state.userId, workspaceId: state.workspaceId };

  const socialAccountId = await withTenantTransaction(principal, async (client) => {
    const result = await client.query<{ social_account_id: string }>(
      `select growth.youtube_complete_authorization(
        $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12::text[]
      ) as social_account_id`,
      [
        state.connectionId,
        channel.id,
        channel.snippet?.customUrl ?? channel.snippet?.title ?? null,
        "channel",
        null,
        YOUTUBE_SOURCE_TIMEZONE,
        ciphertext,
        "aes-256-gcm.v1",
        config.keyVersion,
        expiresAt,
        Boolean(token.refresh_token),
        scopes
      ]
    );
    const id = result.rows[0]?.social_account_id;
    if (!id) throw new YoutubeConnectorError("youtube_connection_not_persisted", 500);
    return id;
  });

  return {
    workspaceId: state.workspaceId,
    connectionId: state.connectionId,
    socialAccountId,
    channelId: channel.id,
    channelTitle: channel.snippet?.title ?? null
  };
}

async function loadCredential(client: PoolClient, connectionId: string): Promise<CredentialRow> {
  const result = await client.query<CredentialRow>(
    "select * from growth.youtube_get_connection_credential($1)",
    [connectionId]
  );
  const row = result.rows[0];
  if (!row) throw new YoutubeConnectorError("youtube_connection_not_found", 404);
  return row;
}

async function usableCredential(
  principal: AuthPrincipal,
  connectionId: string
): Promise<{ row: CredentialRow; credential: StoredCredential }> {
  const config = requireConnectorConfig();
  const row = await withTenantTransaction(principal, (client) => loadCredential(client, connectionId));
  let credential = openCredential(row.credential_ciphertext, principal.workspaceId, connectionId, config);
  const expiresSoon = new Date(credential.expiresAt).getTime() <= Date.now() + 60_000;
  if (!expiresSoon) return { row, credential };
  if (!credential.refreshToken) throw new YoutubeConnectorError("youtube_reauthorization_required", 401);

  const refreshed = await refreshAccessToken(credential.refreshToken, config);
  credential = {
    ...credential,
    accessToken: refreshed.access_token,
    refreshToken: refreshed.refresh_token ?? credential.refreshToken,
    tokenType: refreshed.token_type ?? credential.tokenType,
    scopes: refreshed.scope?.split(/\s+/).filter(Boolean) ?? credential.scopes,
    expiresAt: new Date(Date.now() + refreshed.expires_in * 1000).toISOString()
  };
  const ciphertext = sealCredential(credential, principal.workspaceId, connectionId, config);
  await withTenantTransaction(principal, async (client) => {
    const updated = await client.query<{ updated: boolean }>(
      `select growth.youtube_update_connection_credential(
        $1,$2,$3,$4,$5,$6,$7::text[]
      ) as updated`,
      [
        connectionId,
        ciphertext,
        "aes-256-gcm.v1",
        config.keyVersion,
        credential.expiresAt,
        Boolean(credential.refreshToken),
        credential.scopes
      ]
    );
    if (updated.rows[0]?.updated !== true) {
      throw new YoutubeConnectorError("youtube_credential_refresh_not_persisted", 500);
    }
  });
  return { row, credential };
}

function isoDateUtc(date: Date): string {
  return date.toISOString().slice(0, 10);
}

function parseIsoDay(day: string): { year: number; month: number; dayOfMonth: number } {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) {
    throw new YoutubeConnectorError("youtube_analytics_day_invalid", 502);
  }
  const parsed = new Date(`${day}T00:00:00Z`);
  if (Number.isNaN(parsed.getTime()) || isoDateUtc(parsed) !== day) {
    throw new YoutubeConnectorError("youtube_analytics_day_invalid", 502);
  }
  return {
    year: parsed.getUTCFullYear(),
    month: parsed.getUTCMonth() + 1,
    dayOfMonth: parsed.getUTCDate()
  };
}

function addIsoDays(day: string, delta: number): string {
  const parsed = parseIsoDay(day);
  const date = new Date(Date.UTC(parsed.year, parsed.month - 1, parsed.dayOfMonth));
  date.setUTCDate(date.getUTCDate() + delta);
  return isoDateUtc(date);
}

function zonedDateTimeParts(instant: Date, timeZone: string): ZonedDateTimeParts {
  const formatter = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit"
  });
  const parts = formatter.formatToParts(instant);
  const read = (partType: RequiredDateTimePart): number => {
    const value = parts.find((part) => part.type === partType)?.value;
    if (!value) throw new YoutubeConnectorError("youtube_timezone_conversion_failed", 500);
    return Number(value);
  };
  return {
    year: read("year"),
    month: read("month"),
    day: read("day"),
    hour: read("hour"),
    minute: read("minute"),
    second: read("second")
  };
}

function timezoneOffsetMs(instant: Date, timeZone: string): number {
  const parts = zonedDateTimeParts(instant, timeZone);
  const wallClockAsUtc = Date.UTC(
    parts.year,
    parts.month - 1,
    parts.day,
    parts.hour,
    parts.minute,
    parts.second
  );
  const wholeSecondInstant = Math.trunc(instant.getTime() / 1000) * 1000;
  return wallClockAsUtc - wholeSecondInstant;
}

function zonedMidnightUtc(day: string, timeZone: string): Date {
  const parsed = parseIsoDay(day);
  const targetWallClockAsUtc = Date.UTC(parsed.year, parsed.month - 1, parsed.dayOfMonth, 0, 0, 0);
  let candidate = new Date(targetWallClockAsUtc);

  // Resolve the IANA-zone offset iteratively. Pacific DST transitions occur away from
  // midnight, but iterating also avoids assuming a fixed UTC-7/UTC-8 offset.
  for (let attempt = 0; attempt < 3; attempt++) {
    const offset = timezoneOffsetMs(candidate, timeZone);
    const next = new Date(targetWallClockAsUtc - offset);
    if (next.getTime() === candidate.getTime()) break;
    candidate = next;
  }

  const local = zonedDateTimeParts(candidate, timeZone);
  if (
    local.year !== parsed.year
    || local.month !== parsed.month
    || local.day !== parsed.dayOfMonth
    || local.hour !== 0
    || local.minute !== 0
    || local.second !== 0
  ) {
    throw new YoutubeConnectorError("youtube_timezone_conversion_failed", 500);
  }
  return candidate;
}

function isoDayInTimeZone(instant: Date, timeZone: string): string {
  const local = zonedDateTimeParts(instant, timeZone);
  const pad = (value: number) => String(value).padStart(2, "0");
  return `${local.year}-${pad(local.month)}-${pad(local.day)}`;
}

function youtubeProviderDayRange(day: string): { startUtc: string; endExclusiveUtc: string } {
  const start = zonedMidnightUtc(day, YOUTUBE_SOURCE_TIMEZONE);
  const nextDay = addIsoDays(day, 1);
  const endExclusive = zonedMidnightUtc(nextDay, YOUTUBE_SOURCE_TIMEZONE);
  return { startUtc: start.toISOString(), endExclusiveUtc: endExclusive.toISOString() };
}

export function youtubePacificDayRangeForTest(day: string) {
  return youtubeProviderDayRange(day);
}

function boundedAnalyticsRange(lookbackDays: number, now = new Date()): { startDate: string; endDate: string } {
  const providerToday = isoDayInTimeZone(now, YOUTUBE_SOURCE_TIMEZONE);
  const endDate = addIsoDays(providerToday, -1);
  if (endDate < VIEW_SEMANTIC_BREAK) {
    throw new YoutubeConnectorError("youtube_metric_semantic_window_unavailable", 409);
  }
  const candidateStart = addIsoDays(endDate, -Math.max(lookbackDays - 1, 0));
  const startDate = candidateStart < VIEW_SEMANTIC_BREAK ? VIEW_SEMANTIC_BREAK : candidateStart;
  return { startDate, endDate };
}

export function youtubeBoundedAnalyticsRangeForTest(lookbackDays: number, nowIso: string) {
  return boundedAnalyticsRange(lookbackDays, new Date(nowIso));
}

function metricSemanticVersion(metricName: string): { version: string; effectiveFrom: string | null } {
  if (metricName === "views") {
    return {
      version: "youtube.analytics.views.provider-day-2026-08-24.v2",
      // The source series is segmented at the first YouTube Analytics provider-day boundary
      // covered by the documented 2026-08-24 view-counting change.
      effectiveFrom: youtubeProviderDayRange(VIEW_SEMANTIC_BREAK).startUtc
    };
  }
  if (metricName === "engagedViews") {
    return {
      // The 2026-08-27 YouTube Analytics revision history explicitly marks Engaged View
      // as unchanged by the 2026-08-24 public-view alignment.
      version: "youtube.analytics.engagedViews.stable.v2",
      effectiveFrom: null
    };
  }
  return { version: `youtube.analytics.${metricName}.core-2026-09.v1`, effectiveFrom: null };
}

export function youtubeMetricSemanticVersionForTest(metricName: string) {
  return metricSemanticVersion(metricName);
}

function metricUnit(metricName: string): string {
  if (metricName === "averageViewDuration") return "seconds";
  if (metricName === "estimatedMinutesWatched") return "minutes";
  return "count";
}

export async function syncYoutubeAnalytics(
  principal: AuthPrincipal,
  connectionId: string,
  requestNonce: string,
  lookbackDays: number
): Promise<{
  connectionId: string;
  requestNonce: string;
  socialAccountId: string;
  requestedStartDate: string;
  requestedEndDate: string;
  returnedThroughDate: string | null;
  observationsProcessed: number;
  rowsReceived: number;
  derivedAnalyticsPolicyAccepted: boolean;
}> {
  const config = requireConnectorConfig();
  const { row, credential } = await usableCredential(principal, connectionId);
  const range = boundedAnalyticsRange(lookbackDays);
  const report = await fetchDailyAnalytics(credential.accessToken, range.startDate, range.endDate);
  const headers = report.columnHeaders ?? [];
  const rows = report.rows ?? [];
  if (headers.length === 0) throw new YoutubeConnectorError("youtube_analytics_schema_missing", 502);

  const names = headers.map((header) => header.name ?? "");
  const dayIndex = names.indexOf("day");
  if (dayIndex < 0) throw new YoutubeConnectorError("youtube_analytics_day_missing", 502);
  const metricNames = names.filter((name) => name && name !== "day");
  const collectedAt = new Date();
  const retentionDeadline = new Date(collectedAt.getTime() + 30 * 24 * 60 * 60 * 1000);
  const refreshRequiredBy = new Date(collectedAt.getTime() + 29 * 24 * 60 * 60 * 1000);
  const payloadDigest = createHash("sha256").update(JSON.stringify(report), "utf8").digest("hex");
  let observationsProcessed = 0;
  let returnedThroughDate: string | null = null;

  await withTenantTransaction(principal, async (client) => {
    for (const reportRow of rows) {
      const day = String(reportRow[dayIndex] ?? "");
      const sourcePeriod = youtubeProviderDayRange(day);
      returnedThroughDate = !returnedThroughDate || day > returnedThroughDate ? day : returnedThroughDate;

      for (const metricName of metricNames) {
        const index = names.indexOf(metricName);
        const raw = reportRow[index];
        const numeric = typeof raw === "number" ? raw : Number(raw);
        if (!Number.isFinite(numeric)) {
          throw new YoutubeConnectorError("youtube_analytics_metric_invalid", 502);
        }
        const semantic = metricSemanticVersion(metricName);
        const idempotencyKey = createHash("sha256").update([
          "youtube",
          requestNonce,
          row.provider_account_id,
          day,
          metricName,
          semantic.version,
          SOURCE_SCHEMA_VERSION
        ].join("|"), "utf8").digest("hex");

        await client.query(
          `select growth.youtube_record_metric_observation(
            $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18,
            $19,$20,$21,$22,$23,$24,$25,$26,$27
          )`,
          [
            row.social_account_id,
            row.provider_account_id,
            metricName,
            numeric,
            metricUnit(metricName),
            sourcePeriod.startUtc,
            sourcePeriod.startUtc,
            PROVIDER_API_VERSION,
            SOURCE_SCHEMA_VERSION,
            "youtube_analytics",
            "channel_daily_report",
            semantic.version,
            semantic.effectiveFrom,
            null,
            sourcePeriod.startUtc,
            sourcePeriod.endExclusiveUtc,
            collectedAt.toISOString(),
            "authorized_account",
            retentionDeadline.toISOString(),
            refreshRequiredBy.toISOString(),
            "complete",
            "fresh",
            requestNonce,
            idempotencyKey,
            `sha256:${payloadDigest}`,
            ADAPTER_VERSION,
            "polling"
          ]
        );
        observationsProcessed++;
      }
    }
  });

  return {
    connectionId,
    requestNonce,
    socialAccountId: row.social_account_id,
    requestedStartDate: range.startDate,
    requestedEndDate: range.endDate,
    returnedThroughDate,
    observationsProcessed,
    rowsReceived: rows.length,
    derivedAnalyticsPolicyAccepted: config.derivedAnalyticsPolicyAccepted
  };
}
