import React, { useCallback, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  appendContentVersion,
  approveContentVersion,
  ContentListItem,
  createContent,
  fetchAuthSession,
  fetchContent,
  fetchPublicationIntents,
  fetchInstagramStatus,
  fetchYoutubeStatus,
  createPublicationIntent,
  executePublicationIntent,
  cancelPublicationIntent,
  PublicationIntentListItem,
  RadarApiError,
  requestContentChanges
} from "./api.js";
import "./content-authoring.css";

function contentError(error: unknown): string {
  if (error instanceof RadarApiError) {
    if (error.httpStatus === 401) return "Your Growth OS session expired. Sign in again.";
    if (error.httpStatus === 403) return "This workspace is not allowed to create content.";
    if (error.httpStatus === 404) return "That draft is no longer available in this workspace.";
    if (error.httpStatus === 400) return "Complete the required content fields before saving.";
  }
  return "The draft could not be saved. No content was published.";
}

function shortBody(body: string | null): string {
  const normalized = body?.replace(/\s+/g, " ").trim() ?? "";
  return normalized.length > 96 ? `${normalized.slice(0, 96)}…` : normalized || "Empty draft";
}

function publicationLabel(intent: PublicationIntentListItem): string {
  return intent.status.replace(/_/g, " ");
}

type ConnectedPublicationAccount = {
  id: string;
  label: string;
  platform: "Instagram" | "YouTube";
};

function ContentAuthoringPanel() {
  const [authenticated, setAuthenticated] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [checking, setChecking] = useState(true);
  const [loadingDrafts, setLoadingDrafts] = useState(false);
  const [loadingPublications, setLoadingPublications] = useState(false);
  const [saving, setSaving] = useState(false);
  const [decisionBusyId, setDecisionBusyId] = useState<string | null>(null);
  const [drafts, setDrafts] = useState<ContentListItem[]>([]);
  const [publicationIntents, setPublicationIntents] = useState<PublicationIntentListItem[]>([]);
  const [connectedAccounts, setConnectedAccounts] = useState<ConnectedPublicationAccount[]>([]);
  const [publicationBusyId, setPublicationBusyId] = useState<string | null>(null);
  const [selectedAccountByDraft, setSelectedAccountByDraft] = useState<Record<string, string>>({});
  const [editingId, setEditingId] = useState<string | null>(null);
  const [market, setMarket] = useState("US");
  const [language, setLanguage] = useState("en-US");
  const [platform, setPlatform] = useState("Instagram");
  const [objective, setObjective] = useState("");
  const [body, setBody] = useState("");
  const [message, setMessage] = useState<string | null>(null);

  const loadDrafts = useCallback(async () => {
    setLoadingDrafts(true);
    try {
      setDrafts(await fetchContent());
    } catch (error) {
      if (error instanceof RadarApiError && error.httpStatus === 401) setAuthenticated(false);
    } finally {
      setLoadingDrafts(false);
    }
  }, []);

  const loadPublications = useCallback(async () => {
    setLoadingPublications(true);
    try {
      setPublicationIntents(await fetchPublicationIntents());
    } catch (error) {
      if (error instanceof RadarApiError && error.httpStatus === 401) setAuthenticated(false);
    } finally {
      setLoadingPublications(false);
    }
  }, []);

  const loadConnectedAccounts = useCallback(async () => {
    const [instagram, youtube] = await Promise.allSettled([
      fetchInstagramStatus(),
      fetchYoutubeStatus()
    ]);
    const accounts: ConnectedPublicationAccount[] = [];
    if (instagram.status === "fulfilled") {
      for (const row of instagram.value.integrations) {
        if (row.connection_state === "connected" && row.social_account_id) {
          accounts.push({
            id: row.social_account_id,
            label: row.handle || row.provider_account_id || "Instagram account",
            platform: "Instagram"
          });
        }
      }
    }
    if (youtube.status === "fulfilled") {
      for (const row of youtube.value.integrations) {
        if (row.connection_state === "connected" && row.social_account_id) {
          accounts.push({
            id: row.social_account_id,
            label: row.handle || row.provider_account_id || "YouTube channel",
            platform: "YouTube"
          });
        }
      }
    }
    if (
      (instagram.status === "rejected" && instagram.reason instanceof RadarApiError && instagram.reason.httpStatus === 401) ||
      (youtube.status === "rejected" && youtube.reason instanceof RadarApiError && youtube.reason.httpStatus === 401)
    ) {
      setAuthenticated(false);
    }
    setConnectedAccounts(accounts);
  }, []);

  const refresh = useCallback(async () => {
    try {
      await fetchAuthSession();
      setAuthenticated(true);
      await Promise.all([loadDrafts(), loadPublications(), loadConnectedAccounts()]);
    } catch (error) {
      if (error instanceof RadarApiError && error.httpStatus === 401) {
        setAuthenticated(false);
        setDrafts([]);
      }
    } finally {
      setChecking(false);
    }
  }, [loadDrafts, loadPublications, loadConnectedAccounts]);

  useEffect(() => {
    void refresh();
    const onFocus = () => void refresh();
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, [refresh]);

  useEffect(() => {
    const onContentRefresh = () => void Promise.all([loadDrafts(), loadPublications(), loadConnectedAccounts()]);
    window.addEventListener("growth-os:content-refresh", onContentRefresh);
    return () => window.removeEventListener("growth-os:content-refresh", onContentRefresh);
  }, [loadDrafts, loadPublications, loadConnectedAccounts]);

  useEffect(() => {
    const onCreateDraft = (event: Event) => {
      const detail = (event as CustomEvent<{ objective?: string; market?: string; platform?: string }>).detail;
      if (!detail || typeof detail.market !== "string") return;
      setExpanded(true);
      setEditingId(null);
      setObjective(detail.objective ?? `${detail.market} opportunity`);
      setMarket(detail.market);
      setPlatform(detail.platform === "YouTube" ? "YouTube" : "Instagram");
      setBody("");
      setMessage("Opportunity context loaded. Add the draft text before saving.");
    };
    window.addEventListener("growth-os:create-draft", onCreateDraft);
    return () => window.removeEventListener("growth-os:create-draft", onCreateDraft);
  }, []);

  function startNewDraft() {
    setEditingId(null);
    setObjective("");
    setBody("");
    setMessage(null);
  }

  function editDraft(draft: ContentListItem) {
    setEditingId(draft.id);
    setObjective(draft.objective ?? "");
    setMarket(draft.market);
    setLanguage(draft.language);
    setPlatform(draft.platform_target ?? "Instagram");
    setBody(draft.body ?? "");
    setMessage(null);
  }

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setSaving(true);
    setMessage(null);
    try {
      const structure = { format: "plain_text", editor: "growth-os-content-authoring-v1" };
      const result = editingId
        ? await appendContentVersion({ contentItemId: editingId, body, structure })
        : await createContent({
            objective: objective.trim() || undefined,
            market,
            language,
            platformTarget: platform,
            sourceType: "manual",
            body,
            structure
          });
      setMessage(`${editingId ? "Draft version saved" : "Draft saved"} · version ${result.version.version_no} · checksum ${result.version.checksum.slice(0, 12)}…`);
      startNewDraft();
      await Promise.all([loadDrafts(), loadPublications()]);
    } catch (error) {
      if (error instanceof RadarApiError && error.httpStatus === 401) setAuthenticated(false);
      setMessage(contentError(error));
    } finally {
      setSaving(false);
    }
  }

  async function decide(draft: ContentListItem, decision: "approve" | "request_changes") {
    if (!draft.current_version_id || draft.status !== "ready_for_review") return;
    setDecisionBusyId(draft.id);
    setMessage(null);
    try {
      if (decision === "approve") {
        await approveContentVersion(draft.current_version_id);
        setMessage("Version approved. Publishing remains a separate controlled step.");
      } else {
        await requestContentChanges(draft.current_version_id);
        setMessage("Changes requested. The item returned to draft.");
      }
      await Promise.all([loadDrafts(), loadPublications()]);
    } catch (error) {
      if (error instanceof RadarApiError && error.httpStatus === 401) setAuthenticated(false);
      setMessage(contentError(error));
    } finally {
      setDecisionBusyId(null);
    }
  }

  async function publishDraft(draft: ContentListItem) {
    if (draft.status !== "approved" || !draft.current_version_id) return;
    const platform = draft.platform_target?.toLowerCase();
    const accounts = connectedAccounts.filter((account) => account.platform.toLowerCase() === platform);
    const socialAccountId = selectedAccountByDraft[draft.id] ?? accounts[0]?.id;
    if (!socialAccountId) {
      setMessage("Connect an account for this platform before creating a publication intent.");
      return;
    }

    setPublicationBusyId(draft.id);
    setMessage(null);
    try {
      await createPublicationIntent({
        socialAccountId,
        contentVersionId: draft.current_version_id,
        requestNonce: crypto.randomUUID(),
        idempotencyKey: `content-version:${draft.current_version_id}:account:${socialAccountId}`
      });
      setMessage("Publication intent created. Execute it from Publishing status when ready.");
      await loadPublications();
    } catch (error) {
      if (error instanceof RadarApiError && error.httpStatus === 401) setAuthenticated(false);
      setMessage(contentError(error));
    } finally {
      setPublicationBusyId(null);
    }
  }

  async function executeIntent(intent: PublicationIntentListItem) {
    if (!["ready", "queued", "failed_retryable", "retrying"].includes(intent.status)) return;
    setPublicationBusyId(intent.id);
    setMessage(null);
    try {
      await executePublicationIntent(intent.id);
      setMessage("Publication attempt processed. Review the resulting status and provider id.");
      await loadPublications();
    } catch (error) {
      if (error instanceof RadarApiError && error.httpStatus === 401) setAuthenticated(false);
      setMessage(contentError(error));
    } finally {
      setPublicationBusyId(null);
    }
  }

  async function cancelIntent(intent: PublicationIntentListItem) {
    if (!["ready", "scheduled", "queued", "failed_retryable", "retrying", "needs_user_action"].includes(intent.status)) return;
    if (!window.confirm("Cancel this publication intent? This does not remove provider content already confirmed.")) return;
    setPublicationBusyId(intent.id);
    setMessage(null);
    try {
      await cancelPublicationIntent(intent.id);
      setMessage("Publication intent cancelled.");
      await loadPublications();
    } catch (error) {
      if (error instanceof RadarApiError && error.httpStatus === 401) setAuthenticated(false);
      setMessage(contentError(error));
    } finally {
      setPublicationBusyId(null);
    }
  }

  if (checking || !authenticated) return null;

  return (
    <aside className={`content-authoring-panel${expanded ? " expanded" : ""}`} aria-live="polite">
      <button className="content-panel-toggle" type="button" onClick={() => setExpanded((value) => !value)} aria-expanded={expanded}>
        <span className="content-create-mark" aria-hidden="true">+</span>
        <span><strong>Create</strong><small>Content Authoring</small></span>
        <span className="content-panel-chevron" aria-hidden="true">{expanded ? "×" : "↑"}</span>
      </button>

      {expanded && (
        <div className="content-panel-body">
          <div className="content-draft-header">
            <div>
              <p className="content-kicker">Create from evidence</p>
              <h2>{editingId ? "Edit this draft" : "Start a draft"}</h2>
            </div>
            {editingId && <button className="content-secondary" type="button" onClick={startNewDraft}>New draft</button>}
          </div>
          <p className="content-copy">Write and save an auditable draft before any approval or publishing step. Nothing is published from this panel.</p>

          <div className="content-draft-list">
            <div className="content-list-heading"><span>Saved drafts</span><small>{drafts.length}</small></div>
            {loadingDrafts && <p className="content-list-empty">Loading drafts…</p>}
            {!loadingDrafts && drafts.length === 0 && <p className="content-list-empty">No drafts saved in this workspace yet.</p>}
            {!loadingDrafts && drafts.slice(0, 5).map((draft) => (
              <div className={`content-draft-row${editingId === draft.id ? " selected" : ""}`} key={draft.id}>
                <div>
                  <strong>{draft.objective || "Untitled draft"}</strong>
                  <small>{draft.platform_target || "Unassigned"} · v{draft.version_no ?? "—"}</small>
                  <p>{shortBody(draft.body)}</p>
                </div>
                <div className="content-draft-actions">
                  <button className="content-secondary" type="button" onClick={() => editDraft(draft)}>Edit</button>
                  {draft.status === "ready_for_review" && (
                    <>
                      <button className="content-secondary content-approve" type="button" disabled={decisionBusyId === draft.id} onClick={() => void decide(draft, "approve")}>Approve</button>
                      <button className="content-secondary" type="button" disabled={decisionBusyId === draft.id} onClick={() => void decide(draft, "request_changes")}>Changes</button>
                    </>
                  )}
                  {draft.status === "approved" && draft.current_version_id && (
                    <div className="content-publish-controls">
                      {connectedAccounts.filter((account) => account.platform.toLowerCase() === (draft.platform_target ?? "").toLowerCase()).length > 0 ? (
                        <>
                          <select
                            aria-label="Publication account"
                            value={selectedAccountByDraft[draft.id] ?? ""}
                            onChange={(event) => setSelectedAccountByDraft((current) => ({ ...current, [draft.id]: event.target.value }))}
                          >
                            <option value="">Choose account</option>
                            {connectedAccounts
                              .filter((account) => account.platform.toLowerCase() === (draft.platform_target ?? "").toLowerCase())
                              .map((account) => <option key={account.id} value={account.id}>{account.label}</option>)}
                          </select>
                          <button
                            className="content-secondary content-approve"
                            type="button"
                            disabled={publicationBusyId === draft.id}
                            onClick={() => void publishDraft(draft)}
                          >
                            {publicationBusyId === draft.id ? "Creating…" : "Prepare publish"}
                          </button>
                        </>
                      ) : (
                        <small className="content-publish-hint">Connect {draft.platform_target || "a channel"} first.</small>
                      )}
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>

          <div className="content-draft-list">
            <div className="content-list-heading"><span>Publishing status</span><small>{publicationIntents.length}</small></div>
            {loadingPublications && <p className="content-list-empty">Loading publication status…</p>}
            {!loadingPublications && publicationIntents.length === 0 && <p className="content-list-empty">No publication intents exist in this workspace yet.</p>}
            {!loadingPublications && publicationIntents.slice(0, 5).map((intent) => (
              <div className="content-draft-row" key={intent.id}>
                <div>
                  <strong>{publicationLabel(intent)}</strong>
                  <small>Attempt {intent.current_attempt_no ?? "—"} · retry {intent.retry_count}</small>
                  <p>{intent.provider_content_id ? "Provider content id recorded." : "No provider content id recorded."}</p>
                </div>
                <div className="content-publication-actions">
                  <span className="content-status">{publicationLabel(intent)}</span>
                  {["ready", "queued", "failed_retryable", "retrying"].includes(intent.status) && (
                    <button
                      className="content-secondary content-approve"
                      type="button"
                      disabled={publicationBusyId === intent.id}
                      onClick={() => void executeIntent(intent)}
                    >
                      {publicationBusyId === intent.id ? "Processing…" : "Execute"}
                    </button>
                  )}
                  {["ready", "scheduled", "queued", "failed_retryable", "retrying", "needs_user_action"].includes(intent.status) && (
                    <button
                      className="content-secondary"
                      type="button"
                      disabled={publicationBusyId === intent.id}
                      onClick={() => void cancelIntent(intent)}
                    >
                      Cancel
                    </button>
                  )}
                </div>
              </div>
            ))}
          </div>

          <form className="content-form" onSubmit={submit}>
            <label>
              <span>Objective <small>optional</small></span>
              <input value={objective} onChange={(event) => setObjective(event.target.value)} maxLength={500} placeholder="What should this draft help achieve?" />
            </label>
            <div className="content-form-grid">
              <label><span>Market</span><input value={market} onChange={(event) => setMarket(event.target.value)} maxLength={100} required /></label>
              <label><span>Language</span><input value={language} onChange={(event) => setLanguage(event.target.value)} maxLength={20} required /></label>
            </div>
            <label>
              <span>Platform</span>
              <select value={platform} onChange={(event) => setPlatform(event.target.value)}>
                <option>Instagram</option>
                <option>YouTube</option>
              </select>
            </label>
            <label>
              <span>Draft text</span>
              <textarea value={body} onChange={(event) => setBody(event.target.value)} maxLength={100000} required rows={6} placeholder="Add the first version of the idea or copy…" />
            </label>
            {message && <div className={message.startsWith("Draft") ? "content-notice" : "content-error"} role="status">{message}</div>}
            <button className="content-primary" type="submit" disabled={saving || body.trim().length === 0}>
              {saving ? "Saving draft…" : editingId ? "Save new version" : "Save draft"}
            </button>
          </form>
        </div>
      )}
    </aside>
  );
}

const root = document.getElementById("content-authoring-root");
if (root) {
  createRoot(root).render(
    <React.StrictMode>
      <ContentAuthoringPanel />
    </React.StrictMode>
  );
}
