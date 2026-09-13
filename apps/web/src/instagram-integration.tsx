import React, { useCallback, useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  RadarApiError,
  authorizeInstagram,
  fetchAuthSession,
  fetchInstagramMedia,
  fetchInstagramStatus,
  refreshInstagram,
  reconnectInstagram,
  syncInstagram,
  revokeInstagram,
  type InstagramIntegration,
  type InstagramMediaRecord,
  type InstagramStatusResponse
} from "./api.js";
import "./instagram-integration.css";

function friendlyError(error: unknown): string {
  if (error instanceof RadarApiError) {
    if (error.httpStatus === 401) return "Your Growth OS session expired. Sign in again.";
    if (error.apiStatus === "csrf_rejected") return "Your security token expired. Retry the Instagram action."; 
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

function formatMediaDate(value: string | null): string {
  if (!value) return "Publication date unavailable";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(date);
}

function formatMetric(value: string | number | null): string {
  if (value === null) return "—";
  const numeric = Number(value);
  return Number.isFinite(numeric) ? new Intl.NumberFormat().format(numeric) : String(value);
}

function mediaTypeLabel(media: InstagramMediaRecord): string {
  if (media.media_product_type?.toLowerCase() === "reels" || media.permalink?.includes("/reel/")) return "Reel";
  if (media.media_type === "VIDEO") return "Video";
  if (media.media_type === "CAROUSEL_ALBUM") return "Carousel";
  return "Image";
}

function InstagramIntegrationPanel() {
  const [authenticated, setAuthenticated] = useState(false);
  const [loading, setLoading] = useState(true);
  const [status, setStatus] = useState<InstagramStatusResponse | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [busyId, setBusyId] = useState<string | null>(null);
  const [lastRefresh, setLastRefresh] = useState<Record<string, string>>({});
  const [mediaByConnection, setMediaByConnection] = useState<Record<string, InstagramMediaRecord[]>>({});
  const [mediaLoading, setMediaLoading] = useState(false);
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
      const nextStatus = await fetchInstagramStatus();
      setStatus(nextStatus);
      const connected = nextStatus.integrations.filter((row) => row.connection_id && row.connection_state === "connected");
      setMediaLoading(true);
      const mediaEntries = await Promise.all(connected.map(async (row) => {
        try {
          return [row.connection_id!, await fetchInstagramMedia(row.connection_id!, 7, 50)] as const;
        } catch {
          return [row.connection_id!, []] as const;
        }
      }));
      setMediaByConnection(Object.fromEntries(mediaEntries));
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
      setMediaLoading(false);
    }
  }, [authenticated]);

  useEffect(() => {
    void refresh();
    const timer = window.setInterval(() => void refresh(), authenticated ? 15000 : 2500);
    const focus = () => void refresh();
    const pageShow = () => {
      setBusyId(null);
      void refresh();
    };
    window.addEventListener("focus", focus);
    window.addEventListener("pageshow", pageShow);
    return () => {
      window.clearInterval(timer);
      window.removeEventListener("focus", focus);
      window.removeEventListener("pageshow", pageShow);
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
    const controller = new AbortController();
    const timeout = window.setTimeout(() => controller.abort(), 15000);
    try {
      const result = row.connection_state
        ? await reconnectInstagram(row.managed_account_id, controller.signal)
        : await authorizeInstagram(row.managed_account_id, controller.signal);
      window.location.assign(result.authorizationUrl);
    } catch (error) {
      if (error instanceof Error && error.name === "AbortError") {
        setMessage("Instagram authorization did not respond. Try again.");
      } else {
        setMessage(friendlyError(error));
      }
      setBusyId(null);
    } finally {
      window.clearTimeout(timeout);
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
      await syncInstagram(row.connection_id, crypto.randomUUID(), 7);
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
            const busy = busyId !== null && (busyId === row.managed_account_id || busyId === row.connection_id);
            const expiresAt = row.connection_id ? lastRefresh[row.connection_id] : undefined;
            const media = row.connection_id ? mediaByConnection[row.connection_id] ?? [] : [];
            const lastSyncedAt = media.reduce<string | null>((latest, item) => {
              if (!latest) return item.last_synced_at;
              return new Date(item.last_synced_at).getTime() > new Date(latest).getTime()
                ? item.last_synced_at
                : latest;
            }, null);
            const metricCount = media.reduce((total, item) => total + item.latest_metric_count, 0);

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
                      <dt>Publishing</dt><dd>Enabled for authorized test account</dd>
                      <dt>Insights</dt><dd>Direct metrics enabled</dd>
                      {expiresAt && <><dt>Token until</dt><dd>{new Intl.DateTimeFormat(undefined, { dateStyle: "medium" }).format(new Date(expiresAt))}</dd></>}
                      {lastSyncedAt && (
                        <><dt>Last sync</dt><dd>{media.length} media / {metricCount} metrics</dd></>
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
                    {mediaLoading && <p className="instagram-muted">Loading synchronized media…</p>}
                    {!mediaLoading && media.length > 0 && (
                      <section className="instagram-media-trace" aria-label="Instagram media analyzed by Growth OS">
                        <div className="instagram-media-trace-heading">
                          <strong>Media analyzed</strong>
                          <span>last 7 days</span>
                        </div>
                        <div className="instagram-media-list">
                          {media.map((item) => (
                            <article className="instagram-media-item" key={item.media_id}>
                              {item.thumbnail_url ? (
                                <img src={item.thumbnail_url} alt="" loading="lazy" />
                              ) : (
                                <div className="instagram-media-placeholder" aria-hidden="true">◎</div>
                              )}
                              <div className="instagram-media-content">
                                <div className="instagram-media-title-row">
                                  <strong>{mediaTypeLabel(item)}</strong>
                                  {item.opportunity_count !== "0" && <span className="instagram-media-opportunity">Radar</span>}
                                </div>
                                <time dateTime={item.posted_at ?? undefined}>{formatMediaDate(item.posted_at)}</time>
                                <span>{formatMetric(item.latest_like_count)} curtidas · {formatMetric(item.latest_comments_count)} comentários</span>
                                <span>{item.observation_count} observações · sincronizado {formatMediaDate(item.last_synced_at)}</span>
                                {item.caption && <p>{item.caption}</p>}
                                {item.permalink && (
                                  <a href={item.permalink} target="_blank" rel="noreferrer">Abrir no Instagram ↗</a>
                                )}
                                {!item.permalink && <span>ID da mídia: {item.provider_media_id}</span>}
                              </div>
                            </article>
                          ))}
                        </div>
                      </section>
                    )}
                  </>
                ) : (
                  <button className="instagram-primary" type="button" disabled={busy || !status.configured} onClick={() => void beginAuthorization(row)}>
                    {busy ? "Opening Instagram…" : row.connection_state ? "Reconnect Instagram" : "Connect Instagram"}
                  </button>
                )}
              </section>
            );
          })}

          <p className="instagram-policy-note">Media metadata, direct engagement counts and the controlled publishing path are available for authorized test accounts. Advanced Meta insights and access for external accounts remain subject to their separate review and permission gates.</p>
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
