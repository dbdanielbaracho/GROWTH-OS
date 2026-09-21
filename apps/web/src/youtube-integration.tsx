import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  RadarApiError,
  authorizeYoutube,
  fetchAuthSession,
  fetchYoutubeStatus,
  revokeYoutube,
  syncYoutube,
  type YoutubeIntegration,
  type YoutubeStatusResponse,
  type YoutubeSyncResponse
} from "./api.js";
import "./youtube-integration.css";

function friendlyError(error: unknown): string {
  if (error instanceof RadarApiError) {
    if (
      error.apiStatus === "youtube_reauthorization_required"
      || error.apiStatus === "youtube_authorization_required"
      || error.apiStatus === "youtube_refresh_token_unavailable"
    ) {
      return "YouTube authorization needs to be renewed.";
    }
    if (error.apiStatus === "youtube_required_scopes_missing") return "YouTube needs both channel-read and analytics permissions.";
    if (error.apiStatus === "youtube_reauthorization_channel_mismatch") return "Reconnect returned a different YouTube channel, so the existing credential was not replaced.";
    if (error.httpStatus === 401) return "Your Growth OS session expired. Sign in again.";
    if (error.httpStatus === 403) return "This workspace is not allowed to manage this YouTube connection.";
    if (error.apiStatus === "youtube_channel_selection_required") return "More than one YouTube channel was returned. Automatic selection is blocked for safety.";
    if (error.apiStatus === "youtube_integration_not_configured" || error.apiStatus === "youtube_integration_misconfigured") {
      return "The YouTube connector is not configured correctly yet.";
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
  const authGeneration = useRef(0);
  const [authenticated, setAuthenticated] = useState(false);
  const [loading, setLoading] = useState(true);
  const [status, setStatus] = useState<YoutubeStatusResponse | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [pendingNonce, setPendingNonce] = useState<Record<string, string>>({});
  const [lastSync, setLastSync] = useState<Record<string, YoutubeSyncResponse>>({});
  const [lookbackDays, setLookbackDays] = useState<Record<string, number>>({});
  const [lastRequestedWindow, setLastRequestedWindow] = useState<Record<string, number>>({});
  const [reauthorizationRequired, setReauthorizationRequired] = useState<Record<string, boolean>>({});
  const [expanded, setExpanded] = useState(false);

  const callbackNotice = useMemo(() => {
    const value = new URLSearchParams(window.location.search).get("youtube");
    if (value === "connected") return "YouTube connected successfully. You can sync real analytics now.";
    if (value === "denied") return "YouTube authorization was cancelled. No provider credential was stored.";
    if (value === "youtube_required_scopes_missing") return "YouTube needs both channel-read and analytics permissions. Reconnect and approve both requested permissions.";
    if (value === "youtube_reauthorization_channel_mismatch") return "Reconnect used a different YouTube channel. Growth OS kept the existing credential unchanged.";
    if (value === "youtube_channel_not_found") return "No YouTube channel was found for this Google account.";
    if (value === "youtube_channel_selection_required") return "More than one YouTube channel was returned. Growth OS did not choose one automatically.";
    if (value === "youtube_refresh_token_unavailable") return "Google did not return a durable refresh credential. Reconnect and approve offline access again.";
    if (value === "youtube_authorization_rejected") return "Google rejected the YouTube authorization. Reconnect and approve both requested permissions.";
    return null;
  }, []);

  const refresh = useCallback(async () => {
    const generation = authGeneration.current;
    try {
      await fetchAuthSession();
      if (generation !== authGeneration.current) return;
      setAuthenticated(true);
      const next = await fetchYoutubeStatus();
      if (generation !== authGeneration.current) return;
      setStatus(next);
      setMessage(null);
    } catch (error) {
      if (generation !== authGeneration.current) return;
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
    const onAuthChange = (event: Event) => {
      authGeneration.current += 1;
      setAuthenticated(false);
      setExpanded(false);
      setMessage(null);
      setStatus(null);
      setBusyId(null);
      if ((event as CustomEvent<{ authenticated?: boolean }>).detail?.authenticated) void refresh();
    };
    window.addEventListener("growth-os:auth-change", onAuthChange);
    return () => window.removeEventListener("growth-os:auth-change", onAuthChange);
  }, [refresh]);

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
    setExpanded(true);
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
    const requestedLookbackDays = lookbackDays[connectionId] ?? 7;
    setPendingNonce((current) => ({ ...current, [connectionId]: nonce }));
    setBusyId(connectionId);
    setMessage(null);

    try {
      const result = await syncYoutube(connectionId, nonce, requestedLookbackDays);
      setReauthorizationRequired((current) => ({ ...current, [connectionId]: false }));
      setLastSync((current) => ({ ...current, [connectionId]: result }));
      setLastRequestedWindow((current) => ({ ...current, [connectionId]: requestedLookbackDays }));
      window.dispatchEvent(new CustomEvent("growth-os:radar-refresh"));
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
      if (error instanceof RadarApiError && error.apiStatus === "youtube_reauthorization_required") {
        setReauthorizationRequired((current) => ({ ...current, [connectionId]: true }));
      }
    } finally {
      setBusyId(null);
    }
  }

  async function revoke(row: YoutubeIntegration) {
    if (!row.connection_id) return;
    if (!window.confirm("Revoke this YouTube connection locally? The stored credential will be removed.")) return;
    const connectionId = row.connection_id;
    setBusyId(connectionId);
    setMessage(null);
    try {
      await revokeYoutube(connectionId);
      setPendingNonce((current) => {
        const next = { ...current };
        delete next[connectionId];
        return next;
      });
      setLastSync((current) => {
        const next = { ...current };
        delete next[connectionId];
        return next;
      });
      setReauthorizationRequired((current) => ({ ...current, [connectionId]: false }));
      await refresh();
    } catch (error) {
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
            const busy = busyId !== null && (busyId === row.managed_account_id || busyId === row.connection_id);

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
                    <div className="youtube-sync-controls">
                      <div className="youtube-window-picker" role="group" aria-label="Synchronization window">
                        {[7, 30].map((days) => (
                          <button
                            className="youtube-window-button"
                            key={days}
                            type="button"
                            aria-pressed={(lookbackDays[row.connection_id!] ?? 7) === days}
                            disabled={busy}
                            onClick={() => setLookbackDays((current) => ({ ...current, [row.connection_id!]: days }))}
                          >
                            {days} days
                          </button>
                        ))}
                      </div>
                      <button className="youtube-primary" type="button" disabled={busy} onClick={() => void sync(row)}>
                        {busy ? "Syncing…" : pendingNonce[row.connection_id!] ? "Retry same sync" : "Sync selected window"}
                      </button>
                      <button className="youtube-secondary" type="button" disabled={busy} onClick={() => void revoke(row)}>
                        Revoke connection
                      </button>
                    </div>
                    {reauthorizationRequired[row.connection_id!] && (
                      <button className="youtube-primary" type="button" disabled={busy} onClick={() => void connect(row)}>
                        {busy ? "Opening Google…" : "Reconnect YouTube"}
                      </button>
                    )}
                    {last && (
                      <div className="youtube-sync-result">
                        <strong>{last.observationsProcessed} real observations processed</strong>
                        <span>{lastRequestedWindow[row.connection_id!] ?? 7}-day window · {last.rowsReceived} provider row{last.rowsReceived === 1 ? "" : "s"} · through {last.returnedThroughDate ?? "no returned day"}</span>
                        {last.intelligenceStatus === "opportunity_created" ? (
                          <span className="youtube-intelligence-success">Opportunity Radar updated from stored evidence.</span>
                        ) : (
                          <span className="youtube-intelligence-muted">Not enough complete observations for a factual opportunity yet.</span>
                        )}
                      </div>
                    )}
                  </>
                ) : (
                  <button className="youtube-primary" type="button" disabled={busy || !status.configured} onClick={() => void connect(row)}>
                    {busy ? "Opening Google…" : row.connection_state === "authorizing" ? "Restart authorization" : row.connection_state ? "Reconnect YouTube" : "Connect YouTube"}
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
