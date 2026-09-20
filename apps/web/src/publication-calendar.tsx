import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  cancelPublicationIntent,
  ContentListItem,
  createPublicationIntent,
  fetchAuthSession,
  fetchContent,
  fetchInstagramStatus,
  fetchPublicationIntents,
  fetchYoutubeStatus,
  PublicationIntentListItem,
  RadarApiError
} from "./api.js";
import "./publication-calendar.css";

type CalendarAccount = {
  id: string;
  platform: "Instagram" | "YouTube";
  label: string;
};

function calendarError(error: unknown): string {
  if (error instanceof RadarApiError) {
    if (error.httpStatus === 401) return "Your Growth OS session expired. Sign in again.";
    if (error.httpStatus === 403) return "This workspace is not allowed to schedule publication.";
    if (error.httpStatus === 409) return "That content already has an active publication for the selected account, or its state changed.";
    if (error.httpStatus === 400) return "Choose approved content, a connected account and a valid future time.";
  }
  return "The publication calendar could not save that schedule.";
}

function labelStatus(status: string): string {
  return status.replace(/_/g, " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function futureLocalDefault(): string {
  const date = new Date(Date.now() + 60 * 60 * 1000);
  date.setSeconds(0, 0);
  const local = new Date(date.getTime() - date.getTimezoneOffset() * 60_000);
  return local.toISOString().slice(0, 16);
}

function PublicationCalendarPanel() {
  const authGeneration = useRef(0);
  const [authenticated, setAuthenticated] = useState(false);
  const [checking, setChecking] = useState(true);
  const [expanded, setExpanded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [content, setContent] = useState<ContentListItem[]>([]);
  const [accounts, setAccounts] = useState<CalendarAccount[]>([]);
  const [intents, setIntents] = useState<PublicationIntentListItem[]>([]);
  const [contentId, setContentId] = useState("");
  const [accountId, setAccountId] = useState("");
  const [scheduledLocal, setScheduledLocal] = useState(futureLocalDefault);

  const approved = useMemo(() => content.filter((item) => item.status === "approved" && item.current_version_id), [content]);
  const selectedContent = approved.find((item) => item.id === contentId) ?? null;
  const compatibleAccounts = useMemo(() => {
    const platform = selectedContent?.platform_target?.toLowerCase();
    if (!platform) return accounts;
    return accounts.filter((account) => account.platform.toLowerCase() === platform);
  }, [accounts, selectedContent]);

  const refresh = useCallback(async () => {
    const generation = authGeneration.current;
    try {
      await fetchAuthSession();
      if (generation !== authGeneration.current) return;
      setAuthenticated(true);
      const [contentRows, publicationRows, instagram, youtube] = await Promise.all([
        fetchContent(),
        fetchPublicationIntents(),
        fetchInstagramStatus(),
        fetchYoutubeStatus()
      ]);
      if (generation !== authGeneration.current) return;
      const nextAccounts: CalendarAccount[] = [];
      for (const row of instagram.integrations) {
        if (row.connection_state === "connected" && row.social_account_id) {
          nextAccounts.push({ id: row.social_account_id, platform: "Instagram", label: row.handle || row.provider_account_id || "Instagram account" });
        }
      }
      for (const row of youtube.integrations) {
        if (row.connection_state === "connected" && row.social_account_id) {
          nextAccounts.push({ id: row.social_account_id, platform: "YouTube", label: row.handle || row.provider_account_id || "YouTube channel" });
        }
      }
      setContent(contentRows);
      setIntents(publicationRows);
      setAccounts(nextAccounts);
    } catch (error) {
      if (generation !== authGeneration.current) return;
      if (error instanceof RadarApiError && error.httpStatus === 401) setAuthenticated(false);
      else setMessage(calendarError(error));
    } finally {
      if (generation === authGeneration.current) setChecking(false);
    }
  }, []);

  useEffect(() => {
    const onAuthChange = (event: Event) => {
      authGeneration.current += 1;
      setAuthenticated(false);
      setExpanded(false);
      setMessage(null);
      setContent([]);
      setAccounts([]);
      setIntents([]);
      if ((event as CustomEvent<{ authenticated?: boolean }>).detail?.authenticated) void refresh();
    };
    window.addEventListener("growth-os:auth-change", onAuthChange);
    return () => window.removeEventListener("growth-os:auth-change", onAuthChange);
  }, [refresh]);

  useEffect(() => { void refresh(); }, [refresh]);

  useEffect(() => {
    if (compatibleAccounts.some((account) => account.id === accountId)) return;
    setAccountId(compatibleAccounts[0]?.id ?? "");
  }, [compatibleAccounts, accountId]);

  async function schedule(event: React.FormEvent) {
    event.preventDefault();
    if (!selectedContent?.current_version_id || !accountId) {
      setMessage("Choose approved content and a connected account first.");
      return;
    }
    const scheduled = new Date(scheduledLocal);
    if (Number.isNaN(scheduled.getTime()) || scheduled.getTime() <= Date.now()) {
      setMessage("Choose a future publication time.");
      return;
    }

    setBusy(true);
    setMessage(null);
    try {
      const scheduledFor = scheduled.toISOString();
      await createPublicationIntent({
        socialAccountId: accountId,
        contentVersionId: selectedContent.current_version_id,
        requestNonce: crypto.randomUUID(),
        idempotencyKey: `calendar:${selectedContent.current_version_id}:${accountId}:${scheduledFor}`,
        scheduledFor
      });
      setMessage("Publication scheduled. It will enter the durable worker queue only when the scheduled time is due.");
      await refresh();
    } catch (error) {
      setMessage(calendarError(error));
    } finally {
      setBusy(false);
    }
  }

  async function cancel(intent: PublicationIntentListItem) {
    if (!["ready", "scheduled", "queued", "failed_retryable", "retrying", "needs_user_action"].includes(intent.status)) return;
    setBusy(true);
    setMessage(null);
    try {
      await cancelPublicationIntent(intent.id);
      setMessage("Scheduled publication cancelled locally. Confirmed provider content is never deleted by this action.");
      await refresh();
    } catch (error) {
      setMessage(calendarError(error));
    } finally {
      setBusy(false);
    }
  }

  if (checking || !authenticated) return null;

  const ordered = [...intents].sort((a, b) => {
    const left = a.scheduled_for ? new Date(a.scheduled_for).getTime() : new Date(a.created_at).getTime();
    const right = b.scheduled_for ? new Date(b.scheduled_for).getTime() : new Date(b.created_at).getTime();
    return left - right;
  });

  return (
    <aside className={`publication-calendar-panel${expanded ? " expanded" : ""}`} aria-live="polite">
      <button className="publication-calendar-toggle" type="button" onClick={() => setExpanded((value) => !value)} aria-expanded={expanded}>
        <span className="publication-calendar-mark" aria-hidden="true">◫</span>
        <span><strong>Publication Calendar</strong><small>Schedule · queue · recovery visibility</small></span>
        <span aria-hidden="true">{expanded ? "×" : "↑"}</span>
      </button>

      {expanded && (
        <div className="publication-calendar-body">
          <header>
            <p className="calendar-kicker">Controlled orchestration</p>
            <h2>Schedule approved content without bypassing the worker.</h2>
            <p>A calendar entry stays local until its due time. The worker then moves it through the existing queue, retry, reconciliation and provider safeguards.</p>
          </header>

          {message && <p className="calendar-message" role="status">{message}</p>}

          <div className="calendar-layout">
            <form className="calendar-card" onSubmit={schedule}>
              <h3>New schedule</h3>
              <label>Approved content
                <select value={contentId} onChange={(event) => setContentId(event.target.value)} required>
                  <option value="">Choose approved content</option>
                  {approved.map((item) => <option key={item.id} value={item.id}>{item.platform_target || "Any platform"} · {(item.objective || item.body || item.id).slice(0, 90)}</option>)}
                </select>
              </label>
              <label>Connected account
                <select value={accountId} onChange={(event) => setAccountId(event.target.value)} required>
                  <option value="">Choose connected account</option>
                  {compatibleAccounts.map((account) => <option key={account.id} value={account.id}>{account.platform} · {account.label}</option>)}
                </select>
              </label>
              <label>Publication time
                <input type="datetime-local" value={scheduledLocal} onChange={(event) => setScheduledLocal(event.target.value)} required />
              </label>
              <button disabled={busy || !selectedContent || !accountId}>Schedule publication</button>
              {selectedContent && compatibleAccounts.length === 0 && <p className="calendar-warning">No connected {selectedContent.platform_target || "matching"} account is available. Scheduling remains fail-closed.</p>}
            </form>

            <section className="calendar-card" aria-label="Publication calendar timeline">
              <div className="calendar-heading"><h3>Timeline</h3><span>{ordered.length} intents</span></div>
              <div className="calendar-timeline">
                {ordered.length === 0 && <p className="calendar-empty">No publication intents yet.</p>}
                {ordered.map((intent) => (
                  <article key={intent.id} className={`calendar-row status-${intent.status}`}>
                    <time>{intent.scheduled_for ? new Date(intent.scheduled_for).toLocaleString() : "Immediate / unscheduled"}</time>
                    <div><strong>{labelStatus(intent.status)}</strong><span>{intent.content_version_id.slice(0, 8)} · account {intent.social_account_id.slice(0, 8)}</span>{intent.last_error_class && <small>{intent.last_error_class}</small>}</div>
                    {["ready", "scheduled", "queued", "failed_retryable", "retrying", "needs_user_action"].includes(intent.status) && <button type="button" disabled={busy} onClick={() => void cancel(intent)}>Cancel</button>}
                  </article>
                ))}
              </div>
            </section>
          </div>
        </div>
      )}
    </aside>
  );
}

const root = document.getElementById("publication-calendar-root");
if (root) createRoot(root).render(<React.StrictMode><PublicationCalendarPanel /></React.StrictMode>);
