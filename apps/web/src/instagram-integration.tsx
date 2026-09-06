import React, { useCallback, useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  RadarApiError,
  authorizeInstagram,
  fetchAuthSession,
  fetchInstagramStatus,
  refreshInstagram,
  reconnectInstagram,
  syncInstagram,
  revokeInstagram,
  type InstagramIntegration,
  type InstagramStatusResponse
} from "./api.js";
import "./instagram-integration.css";

function friendlyError(error: unknown): string {
  if (error instanceof RadarApiError) {
    if (error.httpStatus === 401) return "Your Growth OS session expired. Sign in again.";
    if (error.httpStatus === 403) return "This workspace is not allowed to manage this Instagram connection.";
    if (error.apiStatus === "instagram_integration_not_configured" || error.apiStatus === "instagram_integration_misconfigured") {
      return "Instagram is not configured yet. Authorization remains safely disabled.";
    }
    if (error.apiStatus === "instagram_professional_account_required") {
      return "Instagram Business or Creator account access is required.";
    }
    if (error.apiStatus === "instagram_authorization_rejected") {
      return "Instagram rejected the authorization or the token is no longer valid.";
    }
    if (error.apiStatus === "instagram_rate_limited") return "Instagram is rate-limiting this request. Try again later.";
    if (error.httpStatus >= 500) return "The Instagram provider path is temporarily unavailable.";
  }
  return "The Instagram integration could not complete this action.";
}

function stateLabel(value: string | null): string {
  if (!value) return "Not connected";
  return value.replace(/_/g, " ");
}

function accountLabel(row: InstagramIntegration): string {
  return row.handle || row.provider_account_id || "Authorized Instagram account";
}

function InstagramIntegrationPanel() {
  const [authenticated, setAuthenticated] = useState(false);
  const [loading, setLoading] = useState(true);
  const [status, setStatus] = useState<InstagramStatusResponse | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [lastRefresh, setLastRefresh] = useState<Record<string, string>>({});
  const [lastSync, setLastSync] = useState<Record<string, { media: number; observations: number; at: string }>>({});
  const [expanded, setExpanded] = useState(true);

  const callbackNotice = useMemo(() => {
    const value = new URLSearchParams(window.location.search).get("instagram");
    if (value === "connected") return "Instagram connected successfully. The account is ready for the next approved product flow.";
    if (value === "denied") return "Instagram authorization was cancelled. No provider credential was stored.";
    return null;
  }, []);

  const refresh = useCallback(async () => {
    try {
      await fetchAuthSession();
      setAuthenticated(true);
      setStatus(await fetchInstagramStatus());
      setMessage(null);
    } catch (error) {
      if (error instanceof RadarApiError && error.httpStatus === 401) {
        setAuthenticated(false);
        setStatus(null);
        return;
      }
      if (authenticated) setMessage(friendlyError(error));
    } finally {
      setLoading(false);
    }
  }, [authenticated]);

  useEffect(() => {
    void refresh();
    const timer = window.setInterval(() => void refresh(), authenticated ? 15000 : 2500);
    const focus = () => void refresh();
    window.addEventListener("focus", focus);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener("focus", focus);
    };
  }, [authenticated, refresh]);

  useEffect(() => {
    if (!callbackNotice) return;
    const url = new URL(window.location.href);
    url.searchParams.delete("instagram");
    window.history.replaceState({}, "", `${url.pathname}${url.search}${url.hash}`);
  }, [callbackNotice]);

  async function beginAuthorization(row: InstagramIntegration) {
    if (row.connection_state === "connected") return;
    setBusyId(row.managed_account_id);
    setMessage(null);
    try {
      const result = row.connection_state
        ? await reconnectInstagram(row.managed_account_id)
        : await authorizeInstagram(row.managed_account_id);
      window.location.assign(result.authorizationUrl);
    } catch (error) {
      setMessage(friendlyError(error));
      setBusyId(null);
    }
  }

  async function refreshToken(row: InstagramIntegration) {
    if (!row.connection_id) return;
    setBusyId(row.connection_id);
    setMessage(null);
    try {
      const result = await refreshInstagram(row.connection_id);
      setLastRefresh((current) => ({ ...current, [row.connection_id!]: result.tokenExpiresAt }));
      await refresh();
    } catch (error) {
      setMessage(friendlyError(error));
    } finally {
      setBusyId(null);
    }
  }

  async function syncMedia(row: InstagramIntegration) {
    if (!row.connection_id) return;
    setBusyId(row.connection_id);
    setMessage(null);
    try {
      const result = await syncInstagram(row.connection_id, crypto.randomUUID(), 7);
      setLastSync((current) => ({
        ...current,
        [row.connection_id!]: {
          media: result.mediaProcessed,
          observations: result.observationsProcessed,
          at: new Date().toISOString()
        }
      }));
      await refresh();
    } catch (error) {
      setMessage(friendlyError(error));
    } finally {
      setBusyId(null);
    }
  }

  async function revoke(row: InstagramIntegration) {
    if (!row.connection_id) return;
    if (!window.confirm("Revoke this Instagram connection locally? The stored credential will be removed.")) return;
    setBusyId(row.connection_id);
    setMessage(null);
    try {
      await revokeInstagram(row.connection_id);
      await refresh();
    } catch (error) {
      setMessage(friendlyError(error));
    } finally {
      setBusyId(null);
    }
  }

  if (!authenticated) return null;

  return (
    <aside className={`instagram-integration-panel${expanded ? " expanded" : ""}`} aria-live="polite">
      <button className="instagram-panel-toggle" type="button" onClick={() => setExpanded((value) => !value)} aria-expanded={expanded}>
        <span className="instagram-icon" aria-hidden="true">◎</span>
        <span><strong>Instagram</strong><small>{status?.integrations.some((row) => row.connection_state === "connected") ? "Connected" : "Data source"}</small></span>
        <span className="instagram-chevron" aria-hidden="true">{expanded ? "×" : "+"}</span>
      </button>

      {expanded && (
        <div className="instagram-panel-body">
          <p className="instagram-kicker">Professional account source</p>
          <h2>Connect your Instagram</h2>
          <p className="instagram-copy">Growth OS keeps authority, credentials and account state separate. Only Business and Creator accounts can be authorized.</p>

          {callbackNotice && <div className="instagram-notice">{callbackNotice}</div>}
          {message && <div className="instagram-error" role="alert">{message}</div>}
          {loading && <p className="instagram-muted">Checking connector status…</p>}

          {!loading && status && !status.configured && (
            <div className="instagram-error">Meta app configuration is incomplete. Authorization remains fail-closed.</div>
          )}

          {!loading && status?.configured && status.integrations.length === 0 && (
            <div className="instagram-empty">
              <strong>No authorized managed account is available.</strong>
              <span>Growth OS will not create provider authority from OAuth consent alone.</span>
            </div>
          )}

          {status?.integrations.map((row) => {
            const connected = row.connection_state === "connected" && Boolean(row.connection_id);
            const busy = busyId === row.managed_account_id || busyId === row.connection_id;
            const expiresAt = row.connection_id ? lastRefresh[row.connection_id] : undefined;
            const sync = row.connection_id ? lastSync[row.connection_id] : undefined;

            return (
              <section className="instagram-account" key={row.managed_account_id}>
                <div className="instagram-account-heading">
                  <div>
                    <strong>{connected ? accountLabel(row) : "Instagram managed account"}</strong>
                    <span>{stateLabel(row.connection_state)}</span>
                  </div>
                  <span className={`instagram-state state-${row.connection_state ?? "new"}`}>{connected ? "Live" : "Setup"}</span>
                </div>

                {connected ? (
                  <>
                    <dl className="instagram-meta">
                      {row.account_type && <><dt>Account</dt><dd>{row.account_type}</dd></>}
                      {row.market && <><dt>Market</dt><dd>{row.market}</dd></>}
                      {row.source_timezone && <><dt>Provider day</dt><dd>{row.source_timezone}</dd></>}
                      <dt>Publishing</dt><dd>Protected until enabled</dd>
                      <dt>Insights</dt><dd>Protected until enabled</dd>
                      {expiresAt && <><dt>Token until</dt><dd>{new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(expiresAt))}</dd></>}
                      {sync && (
                        <><dt>Last sync</dt><dd>{sync.media} media / {sync.observations} metrics</dd></>
                      )}
                    </dl>
                    <div className="instagram-actions">
                      <button className="instagram-primary" type="button" disabled={busy} onClick={() => void syncMedia(row)}>
                        {busy ? "Syncing…" : "Sync media & metrics"}
                      </button>
                      <button className="instagram-secondary" type="button" disabled={busy} onClick={() => void refreshToken(row)}>
                        Refresh token
                      </button>
                      <button className="instagram-secondary" type="button" disabled={busy} onClick={() => void revoke(row)}>
                        Revoke locally
                      </button>
                    </div>
                  </>
                ) : (
                  <button className="instagram-primary" type="button" disabled={busy || !status.configured} onClick={() => void beginAuthorization(row)}>
                    {busy ? "Opening Instagram…" : row.connection_state ? "Reconnect Instagram" : "Connect Instagram"}
                  </button>
                )}
              </section>
            );
          })}

          <p className="instagram-policy-note">Media metadata and direct engagement counts are now synced with provenance and retry-safe writes. Publishing and advanced insights remain separately gated.</p>
        </div>
      )}
    </aside>
  );
}

const root = document.getElementById("instagram-integration-root");
if (root) {
  createRoot(root).render(
    <React.StrictMode>
      <InstagramIntegrationPanel />
    </React.StrictMode>
  );
}
