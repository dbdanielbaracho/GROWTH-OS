import React, { useCallback, useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  fetchAuthSession,
  fetchIntelligenceModules,
  RadarApiError,
  type IntelligenceModule,
  type IntelligenceModuleState
} from "./api.js";
import "./intelligence-modules.css";

function stateLabel(state: IntelligenceModuleState) {
  if (state === "available") return "Available";
  if (state === "limited") return "Limited evidence";
  if (state === "provider_limited") return "Provider limited";
  return "Insufficient evidence";
}

function ModuleCard({ module }: { module: IntelligenceModule }) {
  return (
    <article className="intelligence-module-card">
      <div className="intelligence-module-heading">
        <div>
          <p className="intelligence-module-kicker">Evidence-bounded module</p>
          <h3>{module.title}</h3>
        </div>
        <span className={`intelligence-state state-${module.state}`}>{stateLabel(module.state)}</span>
      </div>
      <p>{module.summary}</p>
      <div className="intelligence-stat"><strong>{module.evidence_count}</strong><span>stored evidence refs</span></div>

      {module.signals.length > 0 ? (
        <div className="intelligence-signals">
          {module.signals.map((signal, index) => (
            <div className="intelligence-signal" key={`${module.key}-${index}`}>
              <strong>{signal.label}</strong>
              <span>{signal.detail}</span>
              {signal.evidence_refs.map((ref) => <code key={ref}>{ref}</code>)}
            </div>
          ))}
        </div>
      ) : (
        <p className="intelligence-empty">No qualifying stored signal is being substituted with synthetic data.</p>
      )}

      <details className="intelligence-boundaries">
        <summary>Provider and evidence boundaries</summary>
        <div className="intelligence-provider-list">
          {module.provider_states.map((provider) => (
            <div key={`${module.key}-${provider.platform}`}>
              <strong>{provider.platform}</strong>
              <span>{provider.status}{provider.kill_switch ? " · kill switch on" : ""}</span>
              {provider.evidence_ref && <code>{provider.evidence_ref}</code>}
            </div>
          ))}
        </div>
        <ul>{module.limitations.map((item) => <li key={item}>{item}</li>)}</ul>
      </details>
    </article>
  );
}

function IntelligenceModulesPanel() {
  const authGeneration = useRef(0);
  const [authenticated, setAuthenticated] = useState(false);
  const [loading, setLoading] = useState(true);
  const [modules, setModules] = useState<IntelligenceModule[]>([]);
  const [message, setMessage] = useState<string | null>(null);

  const refresh = useCallback(async () => {
    const generation = authGeneration.current;
    try {
      await fetchAuthSession();
      if (generation !== authGeneration.current) return;
      setAuthenticated(true);
      const rows = await fetchIntelligenceModules();
      if (generation !== authGeneration.current) return;
      setModules(rows);
      setMessage(null);
    } catch (error) {
      if (generation !== authGeneration.current) return;
      if (error instanceof RadarApiError && error.httpStatus === 401) {
        setAuthenticated(false);
        setModules([]);
      } else {
        setMessage("Intelligence modules could not load. No synthetic module output was substituted.");
      }
    } finally {
      if (generation === authGeneration.current) setLoading(false);
    }
  }, []);

  useEffect(() => {
    const onAuthChange = (event: Event) => {
      authGeneration.current += 1;
      setAuthenticated(false);
      setModules([]);
      setMessage(null);
      setLoading(Boolean((event as CustomEvent<{ authenticated?: boolean }>).detail?.authenticated));
      if ((event as CustomEvent<{ authenticated?: boolean }>).detail?.authenticated) void refresh();
    };
    window.addEventListener("growth-os:auth-change", onAuthChange);
    return () => window.removeEventListener("growth-os:auth-change", onAuthChange);
  }, [refresh]);

  useEffect(() => { void refresh(); }, [refresh]);

  if (!authenticated) return null;

  return (
    <section className="intelligence-modules-shell" aria-labelledby="intelligence-modules-title">
      <div className="intelligence-modules-title-row">
        <div>
          <p className="intelligence-module-kicker">Growth Intelligence · provider aware</p>
          <h2 id="intelligence-modules-title">What the evidence can support now</h2>
          <p>Trend migration, competitor intelligence and Viral DNA stay bounded by stored evidence and provider capability. A missing data path is shown as a limitation, never filled with estimates.</p>
        </div>
        <button type="button" onClick={() => void refresh()} disabled={loading}>{loading ? "Checking…" : "Refresh evidence"}</button>
      </div>
      {message && <p className="intelligence-error" role="alert">{message}</p>}
      <div className="intelligence-modules-grid">
        {modules.map((module) => <ModuleCard key={module.key} module={module} />)}
      </div>
    </section>
  );
}

const root = document.getElementById("intelligence-modules-root");
if (root) createRoot(root).render(<IntelligenceModulesPanel />);
