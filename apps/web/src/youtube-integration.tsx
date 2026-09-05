import React, { useCallback, useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  RadarApiError,
  authorizeYoutube,
  fetchAuthSession,
  fetchYoutubeStatus,
  syncYoutube,
  type YoutubeIntegration,
  type YoutubeStatusResponse,
  type YoutubeSyncResponse
} from "./api.js";
import "./youtube-integration.css";

function friendlyError(error: unknown): string {
  if (error instanceof RadarApiError) {
    if (error.httpStatus === 401) return "Your Growth OS session expired. Sign in again.";
    if (error.httpStatus === 403) return "This workspace is not allowed to manage this YouTube connection.";
    if (error.apiStatus === "youtube_channel_selection_required") return "More than one YouTube channel was returned. Automatic selection is blocked for safety.";
    if (error.apiStatus === "youtube_integration_not_configured" || error.apiStatus === "youtube_integration_misconfigured") {
      return "The YouTube connector is not configured correctly yet.";
    }
    if (error.apiStatus === "youtube_authorization_required" || error.apiStatus === "youtube_refresh_token_unavailable") {
      return "YouTube authorization needs to be renewed.";
    }
    if (error.httpStatus === 429) return "YouTube is rate-limiting this request. Try again later.";
    if (error.httpStatus >= 500) return "The YouTube provider path is temporarily unavailable.";
  }
  return "The YouTube integration could not complete this action.";
}

function connectionLabel(row: YoutubeIntegration): string {
  if (!row.connection_state) return "Not connected";
  return row.connection_state.replace(/_/g, " ");
}

function channelLabel(row: YoutubeIntegration): string {
  return row.handle || row.provider_account_id || "Authorized YouTube channel";
}

function YoutubeIntegrationPanel() {
  const [authenticated, setAuthenticated] = useState(false);
  const [loading, setLoading] = useState(true);
  const [status, setStatus] = useState<YoutubeStatusResponse | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [pendingNonce, setPendingNonce] = useState<Record<string, string>>({});
  const [lastSync, setLastSync] = useState<Record<string, YoutubeSyncResponse>>({});
  const [expanded, setExpanded] = useState(true);

  const callbackNotice = useMemo(() => {
    const value = new URLSearchParams(window.location.search).get("youtube");
    if (value === "connected") return "YouTube connected successfully. You can sync real analytics now.";
    if (value === "denied") return "YouTube authorization was cancelled. No provider credential was stored.";
    return null;
  }, []);

  const refresh = useCallback(async () => {
    try {
      await fetchAuthSession();
      setAuthenticated(true);
      const next = await fetchYoutubeStatus();
      setStatus(next);
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
    url.searchParams.delete("youtube");
    window.history.replaceState({}, "", `${url.pathname}${url.search}${url.hash}`);
  }, [callbackNotice]);

  async function connect(row: YoutubeIntegration) {
    setBusyId(row.managed_account_id);
    setMessage(null);
    try {
      const result = await authorizeYoutube(row.managed_account_id);
      window.location.assign(result.authorizationUrl);
    } catch (error) {
      setMessage(friendlyError(error));
      setBusyId(null);
    }
  }

  async function sync(row: YoutubeIntegration) {
    if (!row.connection_id) return;
    const connectionId = row.connection_id;
    const nonce = pendingNonce[connectionId] ?? crypto.randomUUID();
    setPendingNonce((current) => ({ ...current, [connectionId]: nonce }));
    setBusyId(connectionId);
    setMessage(null);

    try {
      const result = await syncYoutube(connectionId, nonce, 7);
      setLastSync((current) => ({ ...current, [connectionId]: result }));
      setPendingNonce((current) => {
        const next = { ...current };
        delete next[connectionId];
        return next;
      });
      await refresh();
    } catch (error) {
      // Preserve the nonce after an ambiguous/request failure. An explicit retry
      // therefore remains the same logical sync instead of silently duplicating it.
      setMessage(friendlyError(error));
    } finally {
      setBusyId(null);
    }
  }

  if (!authenticated) return null;

  return (
    <aside className={`youtube-integration-panel${expanded ? " expanded" : ""}`} aria-live="polite">
      <button className="youtube-panel-toggle" type="button" onClick={() => setExpanded((value) => !value)} aria-expanded={expanded}>
        <span className="youtube-icon" aria-hidden="true">▶</span>
        <span><strong>YouTube</strong><small>{status?.integrations.some((row) => row.connection_state === "connected") ? "Connected" : "Data source"}</small></span>
        <span className="youtube-chevron" aria-hidden="true">{expanded ? "×" : "+"}</span>
      </button>

      {expanded && (
        <div className="youtube-panel-body">
          <p className="youtube-kicker">Real signal source</p>
          <h2>Connect your YouTube channel</h2>
          <p className="youtube-copy">Growth OS reads authorized channel analytics and stores provenance-complete observations. It does not enable derived rankings or benchmarks.</p>

          {callbackNotice && <div className="youtube-notice">{callbackNotice}</div>}
          {message && <div className="youtube-error" role="alert">{message}</div>}

          {loading && <p className="youtube-muted">Checking connector status…</p>}

          {!loading && status && !status.configured && (
            <div className="youtube-error">Connector configuration is incomplete. Authorization remains fail-closed.</div>
          )}

          {!loading && status?.configured && status.integrations.length === 0 && (
            <div className="youtube-empty">
              <strong>No authorized managed account is available.</strong>
              <span>Growth OS will not create provider authority from OAuth consent alone.</span>
            </div>
          )}

          {status?.integrations.map((row) => {
            const connected = row.connection_state === "connected" && Boolean(row.connection_id);
            const last = row.connection_id ? lastSync[row.connection_id] : undefined;
            const busy = busyId === row.managed_account_id || busyId === row.connection_id;

            return (
              <section className="youtube-account" key={row.managed_account_id}>
                <div className="youtube-account-heading">
                  <div>
                    <strong>{connected ? channelLabel(row) : "YouTube managed account"}</strong>
                    <span>{connectionLabel(row)}</span>
                  </div>
                  <span className={`youtube-state state-${row.connection_state ?? "new"}`}>{connected ? "Live" : "Setup"}</span>
                </div>

                {connected ? (
                  <>
                    <dl className="youtube-meta">
                      {row.market && <><dt>Market</dt><dd>{row.market}</dd></>}
                      {row.source_timezone && <><dt>Provider day</dt><dd>{row.source_timezone}</dd></>}
                      <dt>Derived analytics</dt><dd>{status.derived_analytics_policy_accepted ? "Policy accepted" : "Disabled"}</dd>
                    </dl>
                    <button className="youtube-primary" type="button" disabled={busy} onClick={() => void sync(row)}>
                      {busy ? "Syncing…" : pendingNonce[row.connection_id!] ? "Retry same sync" : "Sync last 7 days"}
                    </button>
                    {last && (
                      <div className="youtube-sync-result">
                        <strong>{last.observationsProcessed} real observations processed</strong>
                        <span>{last.rowsReceived} provider row{last.rowsReceived === 1 ? "" : "s"} · through {last.returnedThroughDate ?? "no returned day"}</span>
                      </div>
                    )}
                  </>
                ) : (
                  <button className="youtube-primary" type="button" disabled={busy || !status.configured} onClick={() => void connect(row)}>
                    {busy ? "Opening Google…" : row.connection_state === "authorizing" ? "Restart authorization" : "Connect YouTube"}
                  </button>
                )}
              </section>
            );
          })}

          <p className="youtube-policy-note">Derived analytics remains fail-closed until the separate YouTube policy gate is formally accepted.</p>
        </div>
      )}
    </aside>
  );
}

const root = document.getElementById("youtube-integration-root");
if (root) {
  createRoot(root).render(
    <React.StrictMode>
      <YoutubeIntegrationPanel />
    </React.StrictMode>
  );
}
