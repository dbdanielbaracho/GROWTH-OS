import React, { useCallback, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { createContent, fetchAuthSession, RadarApiError } from "./api.js";
import "./content-authoring.css";

function contentError(error: unknown): string {
  if (error instanceof RadarApiError) {
    if (error.httpStatus === 401) return "Your Growth OS session expired. Sign in again.";
    if (error.httpStatus === 403) return "This workspace is not allowed to create content.";
    if (error.httpStatus === 400) return "Complete the required content fields before saving.";
  }
  return "The draft could not be saved. No content was published.";
}

function ContentAuthoringPanel() {
  const [authenticated, setAuthenticated] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [checking, setChecking] = useState(true);
  const [saving, setSaving] = useState(false);
  const [market, setMarket] = useState("US");
  const [language, setLanguage] = useState("en-US");
  const [platform, setPlatform] = useState("Instagram");
  const [objective, setObjective] = useState("");
  const [body, setBody] = useState("");
  const [message, setMessage] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    try {
      await fetchAuthSession();
      setAuthenticated(true);
    } catch (error) {
      if (error instanceof RadarApiError && error.httpStatus === 401) {
        setAuthenticated(false);
      }
    } finally {
      setChecking(false);
    }
  }, []);

  useEffect(() => {
    void refresh();
    const onFocus = () => void refresh();
    window.addEventListener("focus", onFocus);
    return () => window.removeEventListener("focus", onFocus);
  }, [refresh]);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setSaving(true);
    setMessage(null);
    try {
      const result = await createContent({
        objective: objective.trim() || undefined,
        market,
        language,
        platformTarget: platform,
        sourceType: "manual",
        body,
        structure: { format: "plain_text", editor: "growth-os-content-authoring-v1" }
      });
      setMessage(`Draft saved · version ${result.version.version_no} · checksum ${result.version.checksum.slice(0, 12)}…`);
      setBody("");
      setObjective("");
      window.dispatchEvent(new CustomEvent("growth-os:content-refresh"));
    } catch (error) {
      if (error instanceof RadarApiError && error.httpStatus === 401) setAuthenticated(false);
      setMessage(contentError(error));
    } finally {
      setSaving(false);
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
          <p className="content-kicker">Create from evidence</p>
          <h2>Start a draft</h2>
          <p className="content-copy">Write and save an auditable draft before any approval or publishing step. Nothing is published from this panel.</p>

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
            {message && <div className={message.startsWith("Draft saved") ? "content-notice" : "content-error"} role="status">{message}</div>}
            <button className="content-primary" type="submit" disabled={saving || body.trim().length === 0}>
              {saving ? "Saving draft…" : "Save draft"}
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
