from pathlib import Path
import re


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text()
    if old not in text:
        raise SystemExit(f"expected text not found in {path}: {old[:100]!r}")
    p.write_text(text.replace(old, new, 1))


def regex_replace_once(path: str, pattern: str, replacement: str) -> None:
    p = Path(path)
    text = p.read_text()
    next_text, count = re.subn(pattern, replacement, text, count=1, flags=re.S)
    if count != 1:
        raise SystemExit(f"expected one regex replacement in {path}, got {count}")
    p.write_text(next_text)


connector = Path("apps/api/src/youtube-connector.ts")
text = connector.read_text()
marker = "async function beginAuthorizationRow(client: PoolClient, managedAccountId: string): Promise<string> {"
helper = r'''type YoutubeConnectionStatusRow = {
  managed_account_id: string;
  connection_id: string | null;
  connection_state: string | null;
  connection_updated_at: string | null;
  social_account_id: string | null;
  provider_account_id: string | null;
};

export function youtubeMissingRequiredScopesForTest(scopes: readonly string[]): string[] {
  return YOUTUBE_SCOPES.filter((scope) => !scopes.includes(scope));
}

async function reusableYoutubeConnection(
  client: PoolClient,
  managedAccountId: string
): Promise<YoutubeConnectionStatusRow | null> {
  const result = await client.query<YoutubeConnectionStatusRow>(
    `select managed_account_id, connection_id, connection_state, connection_updated_at,
            social_account_id, provider_account_id
       from growth.youtube_integration_status()
      where managed_account_id = $1
        and connection_id is not null
        and connection_state = 'connected'
        and social_account_id is not null
        and provider_account_id is not null
      order by connection_updated_at desc nulls last
      limit 1`,
    [managedAccountId]
  );
  return result.rows[0] ?? null;
}

async function youtubeConnectionForCallback(
  principal: AuthPrincipal,
  connectionId: string
): Promise<YoutubeConnectionStatusRow | null> {
  return withTenantTransaction(principal, async (client) => {
    const result = await client.query<YoutubeConnectionStatusRow>(
      `select managed_account_id, connection_id, connection_state, connection_updated_at,
              social_account_id, provider_account_id
         from growth.youtube_integration_status()
        where connection_id = $1
        limit 1`,
      [connectionId]
    );
    return result.rows[0] ?? null;
  });
}

'''
if helper.strip() not in text:
    if marker not in text:
        raise SystemExit("beginAuthorizationRow marker not found")
    text = text.replace(marker, helper + marker, 1)
connector.write_text(text)

replace_once(
    "apps/api/src/youtube-connector.ts",
    "  const config = requireConnectorConfig();\n  const connectionId = await beginAuthorizationRow(client, managedAccountId);",
    "  const config = requireConnectorConfig();\n  const reusable = await reusableYoutubeConnection(client, managedAccountId);\n  const connectionId = reusable?.connection_id ?? await beginAuthorizationRow(client, managedAccountId);"
)

new_complete = r'''export async function completeYoutubeAuthorizationFromCallback(
  sealedState: string,
  code: string
): Promise<{ workspaceId: string; connectionId: string; socialAccountId: string; channelId: string; channelTitle: string | null }> {
  const config = requireConnectorConfig();
  const state = openYoutubeState(sealedState);
  const token = await exchangeAuthorizationCode(code, config);
  const scopes = token.scope?.split(/\s+/).filter(Boolean) ?? [...YOUTUBE_SCOPES];
  const missingScopes = youtubeMissingRequiredScopesForTest(scopes);
  if (missingScopes.length > 0) {
    throw new YoutubeConnectorError("youtube_required_scopes_missing", 409);
  }

  const channels = await fetchAuthorizedChannels(token.access_token);
  if (channels.length === 0) throw new YoutubeConnectorError("youtube_channel_not_found", 409);
  if (channels.length > 1) throw new YoutubeConnectorError("youtube_channel_selection_required", 409);
  const channel = channels[0]!;
  if (!channel.id) throw new YoutubeConnectorError("youtube_channel_identity_invalid", 502);

  const principal: AuthPrincipal = { userId: state.userId, workspaceId: state.workspaceId };
  const existing = await youtubeConnectionForCallback(principal, state.connectionId);
  if (existing?.social_account_id && existing.connection_id) {
    if (existing.provider_account_id !== channel.id) {
      throw new YoutubeConnectorError("youtube_reauthorization_channel_mismatch", 409);
    }
    if (!token.refresh_token) {
      throw new YoutubeConnectorError("youtube_refresh_token_unavailable", 409);
    }
  }

  const expiresAt = new Date(Date.now() + token.expires_in * 1000).toISOString();
  const credential: StoredCredential = {
    v: 1,
    accessToken: token.access_token,
    refreshToken: token.refresh_token ?? null,
    tokenType: token.token_type ?? "Bearer",
    scopes,
    expiresAt
  };

  if (existing?.social_account_id && existing.connection_id) {
    const ciphertext = sealCredential(credential, state.workspaceId, existing.connection_id, config);
    const updated = await withTenantTransaction(principal, async (client) => {
      const result = await client.query<{ updated: boolean }>(
        `select growth.youtube_update_connection_credential(
          $1,$2,$3,$4,$5,$6,$7::text[]
        ) as updated`,
        [
          existing.connection_id,
          ciphertext,
          "aes-256-gcm.v1",
          config.keyVersion,
          expiresAt,
          true,
          scopes
        ]
      );
      return result.rows[0]?.updated === true;
    });
    if (!updated) {
      throw new YoutubeConnectorError("youtube_credential_refresh_not_persisted", 500);
    }
    return {
      workspaceId: state.workspaceId,
      connectionId: existing.connection_id,
      socialAccountId: existing.social_account_id,
      channelId: channel.id,
      channelTitle: channel.snippet?.title ?? null
    };
  }

  const ciphertext = sealCredential(credential, state.workspaceId, state.connectionId, config);
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
}'''
regex_replace_once(
    "apps/api/src/youtube-connector.ts",
    r"export async function completeYoutubeAuthorizationFromCallback\([\s\S]*?\n\}\n\nasync function loadCredential",
    new_complete + "\n\nasync function loadCredential"
)

replace_once(
    "apps/api/src/youtube-routes.ts",
    '''    try {\n      await completeYoutubeAuthorizationFromCallback(parsed.data.state, parsed.data.code);\n      return reply.redirect("/?youtube=connected", 303);\n    } catch (error) {\n      return integrationError(app, reply, error);\n    }'''.replace('\\n','\n'),
    '''    try {\n      await completeYoutubeAuthorizationFromCallback(parsed.data.state, parsed.data.code);\n      return reply.redirect("/?youtube=connected", 303);\n    } catch (error) {\n      if (error instanceof YoutubeConnectorError) {\n        app.log.warn(\n          {\n            provider: "youtube",\n            connectorCode: error.code,\n            httpStatus: error.httpStatus,\n            providerOperation: error.providerOperation,\n            providerHttpStatus: error.providerHttpStatus\n          },\n          "youtube connector callback failed"\n        );\n        return reply.redirect(`/?youtube=${encodeURIComponent(error.code)}`, 303);\n      }\n      return integrationError(app, reply, error);\n    }'''.replace('\\n','\n')
)

replace_once(
    "apps/web/src/youtube-integration.tsx",
    '''    if (value === "connected") return "YouTube connected successfully. You can sync real analytics now.";\n    if (value === "denied") return "YouTube authorization was cancelled. No provider credential was stored.";\n    return null;'''.replace('\\n','\n'),
    '''    if (value === "connected") return "YouTube connected successfully. You can sync real analytics now.";\n    if (value === "denied") return "YouTube authorization was cancelled. No provider credential was stored.";\n    if (value === "youtube_required_scopes_missing") return "YouTube needs both channel-read and analytics permissions. Reconnect and approve both requested permissions.";\n    if (value === "youtube_reauthorization_channel_mismatch") return "Reconnect used a different YouTube channel. Growth OS kept the existing credential unchanged.";\n    if (value === "youtube_channel_not_found") return "No YouTube channel was found for this Google account.";\n    if (value === "youtube_channel_selection_required") return "More than one YouTube channel was returned. Growth OS did not choose one automatically.";\n    if (value === "youtube_refresh_token_unavailable") return "Google did not return a durable refresh credential. Reconnect and approve offline access again.";\n    if (value === "youtube_authorization_rejected") return "Google rejected the YouTube authorization. Reconnect and approve both requested permissions.";\n    return null;'''.replace('\\n','\n')
)

replace_once(
    "apps/web/src/youtube-integration.tsx",
    '''    if (error.httpStatus === 401) return "Your Growth OS session expired. Sign in again.";''',
    '''    if (error.apiStatus === "youtube_required_scopes_missing") return "YouTube needs both channel-read and analytics permissions.";\n    if (error.apiStatus === "youtube_reauthorization_channel_mismatch") return "Reconnect returned a different YouTube channel, so the existing credential was not replaced.";\n    if (error.httpStatus === 401) return "Your Growth OS session expired. Sign in again.";'''.replace('\\n','\n')
)

# Add unit coverage for the required OAuth scope boundary.
test_path = Path("apps/api/src/youtube-connector.test.ts")
test_text = test_path.read_text()
extra_test = r'''

test("YouTube reconnect requires both channel and analytics scopes", () => {
  assert.deepEqual(
    connector.youtubeMissingRequiredScopesForTest([
      "https://www.googleapis.com/auth/youtube.readonly",
      "https://www.googleapis.com/auth/yt-analytics.readonly"
    ]),
    []
  );
  assert.deepEqual(
    connector.youtubeMissingRequiredScopesForTest([
      "https://www.googleapis.com/auth/yt-analytics.readonly"
    ]),
    ["https://www.googleapis.com/auth/youtube.readonly"]
  );
});
'''
if "YouTube reconnect requires both channel and analytics scopes" not in test_text:
    test_path.write_text(test_text.rstrip() + extra_test + "\n")

# Make migration 069 part of the production reconciler.
apply_path = Path("db/scripts/apply-production-migrations.mjs")
apply_text = apply_path.read_text()
step = r'''

  {
    file: '069_youtube_reauthorization_cleanup.sql',
    present: async () => {
      const result = await client.query(`
        select position(
          'delete from growth.platform_connections'
          in lower(pg_get_functiondef('growth.youtube_begin_authorization(uuid,text[])'::regprocedure))
        ) > 0 as present
      `);
      return result.rows[0]?.present === true;
    },
  },
'''
if "069_youtube_reauthorization_cleanup.sql" not in apply_text:
    needle = "\n\n];\n\ntry {"
    if needle not in apply_text:
        raise SystemExit("production migration step insertion point not found")
    apply_path.write_text(apply_text.replace(needle, step + "\n];\n\ntry {", 1))

# Extend release hardening to require the reconnect cleanup migration.
hardening = Path("db/scripts/release-hardening-gate.mjs")
hard_text = hardening.read_text()
block = r'''

const youtubeReauthorization = await readFile(join(migrationDir, "069_youtube_reauthorization_cleanup.sql"), "utf8");
for (const marker of ["youtube_begin_authorization", "DELETE FROM growth.platform_connections", "authorizing"]) {
  if (!youtubeReauthorization.includes(marker)) {
    throw new Error("release hardening: YouTube reauthorization marker missing " + marker);
  }
}
'''
if "const youtubeReauthorization" not in hard_text:
    needle = '\nconst commercial = await readFile(join(migrationDir, "038_commercial_entitlements.sql"), "utf8");'
    if needle not in hard_text:
        raise SystemExit("release hardening insertion point not found")
    hardening.write_text(hard_text.replace(needle, block + needle, 1))

# Existing provider authorization gate now proves superseded authorizing attempts are cleaned.
provider_gate = Path("db/tests/062_provider_authorization_runtime.sql")
gate_text = provider_gate.read_text()
old_begin = r'''SELECT growth.youtube_begin_authorization(
  'c0000000-0000-4000-8000-000000000041'::uuid,
  ARRAY['https://www.googleapis.com/auth/youtube.readonly']::text[]
) AS connection_id
\gset youtube_
'''
new_begin = r'''SELECT growth.youtube_begin_authorization(
  'c0000000-0000-4000-8000-000000000041'::uuid,
  ARRAY['https://www.googleapis.com/auth/youtube.readonly']::text[]
) AS connection_id
\gset youtube_first_

SELECT growth.youtube_begin_authorization(
  'c0000000-0000-4000-8000-000000000041'::uuid,
  ARRAY['https://www.googleapis.com/auth/youtube.readonly']::text[]
) AS connection_id
\gset youtube_

SELECT count(*) = 1 AS youtube_single_authorizing
FROM growth.youtube_integration_status()
WHERE managed_account_id = 'c0000000-0000-4000-8000-000000000041'::uuid
  AND connection_state = 'authorizing'
\gset
\if :youtube_single_authorizing
\else
  \echo 'TEST FAIL: YouTube authorization attempts were not superseded safely'
  \quit 1
\endif
'''
if "youtube_first_connection_id" not in gate_text:
    if old_begin not in gate_text:
        raise SystemExit("provider gate YouTube begin block not found")
    provider_gate.write_text(gate_text.replace(old_begin, new_begin, 1))

print("YouTube reauthorization patch applied")
