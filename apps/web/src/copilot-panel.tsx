import React, { useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import { fetchAuthSession, queryCopilot, RadarApiError, type CopilotReply } from "./api.js";
import "./copilot-panel.css";

function copilotError(error: unknown): string {
  if (error instanceof RadarApiError) {
    if (error.httpStatus === 401) return "Your Growth OS session expired. Sign in again.";
    if (error.httpStatus === 403) return "This workspace is not allowed to use Copilot.";
    if (error.httpStatus === 400) return "Ask a specific question about the current workspace.";
  }
  return "Copilot could not read the workspace evidence. No answer was invented.";
}

function CopilotPanel() {
  const authGeneration = useRef(0);
  const [authenticated, setAuthenticated] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [message, setMessage] = useState("");
  const [reply, setReply] = useState<CopilotReply | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  async function verifySession() {
    const generation = authGeneration.current;
    try {
      await fetchAuthSession();
      if (generation === authGeneration.current) setAuthenticated(true);
    } catch {
      if (generation === authGeneration.current) setAuthenticated(false);
    }
  }

  useEffect(() => {
    void verifySession();
    const onAuthChange = (event: Event) => {
      authGeneration.current += 1;
      setAuthenticated(Boolean((event as CustomEvent<{ authenticated?: boolean }>).detail?.authenticated));
      setReply(null);
      setError(null);
      setExpanded(false);
    };
    window.addEventListener("growth-os:auth-change", onAuthChange);
    return () => window.removeEventListener("growth-os:auth-change", onAuthChange);
  }, []);

  async function ask(question = message) {
    const trimmed = question.trim();
    if (!trimmed) return;
    setMessage(trimmed);
    setBusy(true);
    setError(null);
    try {
      setReply(await queryCopilot(trimmed));
    } catch (nextError) {
      setReply(null);
      setError(copilotError(nextError));
    } finally {
      setBusy(false);
    }
  }

  if (!authenticated) return null;

  return (
    <aside className={`copilot-panel ${expanded ? "is-expanded" : "is-collapsed"}`} aria-live="polite">
      <button
        type="button"
        className="copilot-toggle"
        aria-label={expanded ? "Close Copilot" : "Open Copilot"}
        aria-expanded={expanded}
        aria-controls="copilot-panel-body"
        onClick={() => setExpanded((value) => !value)}
      >
        <span className="copilot-spark" aria-hidden="true">✦</span>
        <span className="copilot-toggle-copy"><strong>Copilot</strong><small>Evidence grounded</small></span>
        <span className="copilot-toggle-state" aria-hidden="true">{expanded ? "×" : "+"}</span>
      </button>

      {expanded && (
        <div id="copilot-panel-body" className="copilot-body">
          <p className="copilot-kicker">Workspace intelligence</p>
          <h2>Ask what the evidence supports</h2>
          <p className="copilot-copy">Copilot reads only persisted workspace evidence. It cannot publish, approve or bypass Autopilot controls.</p>

          <form onSubmit={(event) => { event.preventDefault(); void ask(); }} className="copilot-form">
            <label htmlFor="copilot-question">Question</label>
            <div className="copilot-input-row">
              <input
                id="copilot-question"
                value={message}
                onChange={(event) => setMessage(event.target.value)}
                placeholder="What should I do next?"
                maxLength={1000}
                required
              />
              <button type="submit" disabled={busy}>{busy ? "Reading…" : "Ask"}</button>
            </div>
          </form>

          <div className="copilot-prompts" aria-label="Suggested Copilot questions">
            {[
              "What changed in my metrics?",
              "What evidence supports the top opportunity?",
              "What should I do next?",
              "Is anything in operations blocked?"
            ].map((prompt) => (
              <button type="button" key={prompt} disabled={busy} onClick={() => void ask(prompt)}>{prompt}</button>
            ))}
          </div>

          {error && <div className="copilot-error" role="alert">{error}</div>}
          {reply && (
            <section className="copilot-answer" aria-label="Copilot answer">
              <div className="copilot-answer-head">
                <span>{reply.intent.replaceAll("_", " ")}</span>
                <span>Evidence grounded</span>
              </div>
              <p>{reply.answer}</p>

              <div className="copilot-pulse" aria-label="Workspace pulse">
                <span><strong>{reply.workspace_pulse.opportunities}</strong> opportunities</span>
                <span><strong>{reply.workspace_pulse.insights}</strong> insights</span>
                <span><strong>{reply.workspace_pulse.metric_rows}</strong> metric groups</span>
                <span><strong>{reply.workspace_pulse.quality_alerts}</strong> quality alerts</span>
                <span><strong>{reply.workspace_pulse.automation_needs_attention}</strong> automation alerts</span>
                <span className={reply.workspace_pulse.automation_kill_switch ? "copilot-stop" : ""}>
                  Emergency stop {reply.workspace_pulse.automation_kill_switch ? "ON" : "off"}
                </span>
              </div>

              {reply.citations.length > 0 && (
                <div className="copilot-citations">
                  <strong>Evidence references</strong>
                  <ul>
                    {reply.citations.map((citation) => (
                      <li key={`${citation.kind}:${citation.ref}`}>
                        <span>{citation.kind}</span>
                        <code>{citation.ref}</code>
                        <small>{citation.label}</small>
                      </li>
                    ))}
                  </ul>
                </div>
              )}
              <details className="copilot-limitations">
                <summary>Evidence boundaries</summary>
                <ul>{reply.limitations.map((line) => <li key={line}>{line}</li>)}</ul>
              </details>
            </section>
          )}
        </div>
      )}
    </aside>
  );
}

const root = document.getElementById("copilot-panel-root");
if (root) {
  createRoot(root).render(
    <React.StrictMode>
      <CopilotPanel />
    </React.StrictMode>
  );
}
