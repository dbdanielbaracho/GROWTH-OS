import React, { useCallback, useEffect, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  applyDeletionTombstone,
  createSupportCase,
  fetchAgencyClients,
  fetchAuthSession,
  fetchConsents,
  fetchDeletionRequests,
  fetchSupportCases,
  RadarApiError,
  recordConsent,
  requestDeletion,
  updateAgencyClient,
  updateSupportCase,
  type AgencyClient,
  type ConsentRecord,
  type DeletionRequest,
  type SupportCase,
  type WorkspaceSummary
} from "./api.js";
import "./enterprise-operations.css";

function label(value: string) {
  return value.replaceAll("_", " ").replace(/\b\w/g, (character) => character.toUpperCase());
}

function EnterpriseOperationsPanel() {
  const generation = useRef(0);
  const [authenticated, setAuthenticated] = useState(false);
  const [workspace, setWorkspace] = useState<WorkspaceSummary | null>(null);
  const [workspaces, setWorkspaces] = useState<WorkspaceSummary[]>([]);
  const [clients, setClients] = useState<AgencyClient[]>([]);
  const [cases, setCases] = useState<SupportCase[]>([]);
  const [consents, setConsents] = useState<ConsentRecord[]>([]);
  const [deletions, setDeletions] = useState<DeletionRequest[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [clientWorkspaceId, setClientWorkspaceId] = useState("");
  const [clientLabel, setClientLabel] = useState("");
  const [supportSubject, setSupportSubject] = useState("");
  const [supportDescription, setSupportDescription] = useState("");
  const [supportCategory, setSupportCategory] = useState<SupportCase["category"]>("product");
  const [supportPriority, setSupportPriority] = useState<SupportCase["priority"]>("normal");
  const [consentType, setConsentType] = useState<ConsentRecord["consent_type"]>("ai_processing");
  const [consentDecision, setConsentDecision] = useState<ConsentRecord["decision"]>("granted");
  const [policyVersion, setPolicyVersion] = useState("privacy-v1");
  const [deletionScope, setDeletionScope] = useState<DeletionRequest["scope"]>("workspace");
  const [deletionTarget, setDeletionTarget] = useState("");
  const [manifestVersion, setManifestVersion] = useState("deletion-v1");
  const [confirmedTombstones, setConfirmedTombstones] = useState<Record<string, boolean>>({});

  const refresh = useCallback(async () => {
    const currentGeneration = generation.current;
    try {
      const session = await fetchAuthSession();
      if (currentGeneration !== generation.current) return;
      setAuthenticated(true);
      setWorkspace(session.selected_workspace);
      setWorkspaces(session.workspaces);
      if (!session.selected_workspace) return;
      const [nextClients, nextCases, nextConsents, nextDeletions] = await Promise.all([
        fetchAgencyClients(), fetchSupportCases(), fetchConsents(), fetchDeletionRequests()
      ]);
      if (currentGeneration !== generation.current) return;
      setClients(nextClients);
      setCases(nextCases);
      setConsents(nextConsents);
      setDeletions(nextDeletions);
      setMessage(null);
    } catch (error) {
      if (currentGeneration !== generation.current) return;
      if (error instanceof RadarApiError && error.httpStatus === 401) {
        setAuthenticated(false);
      } else {
        setMessage("Enterprise operations could not load. No administrative state was changed.");
      }
    }
  }, []);

  useEffect(() => { void refresh(); }, [refresh]);
  useEffect(() => {
    const onAuthChange = (event: Event) => {
      generation.current += 1;
      setAuthenticated(Boolean((event as CustomEvent<{ authenticated?: boolean }>).detail?.authenticated));
      setWorkspace(null);
      setClients([]);
      setCases([]);
      setConsents([]);
      setDeletions([]);
      if ((event as CustomEvent<{ authenticated?: boolean }>).detail?.authenticated) void refresh();
    };
    window.addEventListener("growth-os:auth-change", onAuthChange);
    return () => window.removeEventListener("growth-os:auth-change", onAuthChange);
  }, [refresh]);

  if (!authenticated || !workspace) return null;
  const canAdminister = workspace.role === "owner" || workspace.role === "admin";
  const availableClients = workspaces.filter((item) =>
    item.id !== workspace.id
    && (item.role === "owner" || item.role === "admin")
    && !clients.some((client) => client.client_workspace_id === item.id)
  );
  const deletionTargetValue = deletionScope === "workspace" ? workspace.id : deletionTarget;

  async function run(action: () => Promise<void>, success: string) {
    setBusy(true);
    setMessage(null);
    try {
      await action();
      await refresh();
      setMessage(success);
    } catch {
      setMessage("The operation was rejected. Check your role, target and current state.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="enterprise-operations-shell" aria-labelledby="enterprise-operations-title">
      <header>
        <div>
          <p className="enterprise-kicker">Enterprise operations · audited</p>
          <h2 id="enterprise-operations-title">Agency, support and privacy</h2>
          <p>Administrative actions stay tenant-scoped and append evidence. A deletion request never claims purge completion.</p>
        </div>
        <span className="enterprise-role">{label(workspace.role)}</span>
      </header>

      <div className="enterprise-grid">
        <article>
          <h3>Agency portfolio</h3>
          <p>Link only client workspaces where you already hold administration rights.</p>
          {canAdminister && availableClients.length > 0 && (
            <form onSubmit={(event) => {
              event.preventDefault();
              void run(async () => {
                await updateAgencyClient({ clientWorkspaceId, label: clientLabel, state: "active" });
                setClientWorkspaceId(""); setClientLabel("");
              }, "Client workspace linked.");
            }}>
              <label>Client workspace<select required value={clientWorkspaceId} onChange={(event) => setClientWorkspaceId(event.target.value)}><option value="">Select workspace</option>{availableClients.map((item) => <option key={item.id} value={item.id}>{item.name}</option>)}</select></label>
              <label>Portfolio label<input required minLength={1} maxLength={120} value={clientLabel} onChange={(event) => setClientLabel(event.target.value)} /></label>
              <button disabled={busy || !clientWorkspaceId}>Link client</button>
            </form>
          )}
          <div className="enterprise-list">{clients.length ? clients.map((client) => <div key={client.link_id}><strong>{client.label}</strong><span>{client.client_workspace_name} · {label(client.client_role)} · {label(client.state)}</span>{canAdminister && <button disabled={busy} onClick={() => void run(() => updateAgencyClient({ clientWorkspaceId: client.client_workspace_id, label: client.label, state: client.state === "active" ? "paused" : "active" }), "Client state updated.")}>{client.state === "active" ? "Pause" : "Activate"}</button>}</div>) : <p>No client workspaces linked.</p>}</div>
        </article>

        <article>
          <h3>Support console</h3>
          <p>Create auditable cases without exposing provider payloads or credentials.</p>
          <form onSubmit={(event) => {
            event.preventDefault();
            void run(async () => {
              await createSupportCase({ category: supportCategory, priority: supportPriority, subject: supportSubject, description: supportDescription });
              setSupportSubject(""); setSupportDescription("");
            }, "Support case created.");
          }}>
            <div className="enterprise-form-row"><label>Category<select value={supportCategory} onChange={(event) => setSupportCategory(event.target.value as SupportCase["category"])}>{["product","provider","privacy","security","billing"].map((item) => <option key={item} value={item}>{label(item)}</option>)}</select></label><label>Priority<select value={supportPriority} onChange={(event) => setSupportPriority(event.target.value as SupportCase["priority"])}>{["normal","high","urgent"].map((item) => <option key={item} value={item}>{label(item)}</option>)}</select></label></div>
            <label>Subject<input required minLength={3} maxLength={160} value={supportSubject} onChange={(event) => setSupportSubject(event.target.value)} /></label>
            <label>Description<textarea required minLength={3} maxLength={4000} value={supportDescription} onChange={(event) => setSupportDescription(event.target.value)} /></label>
            <button disabled={busy}>Create case</button>
          </form>
          <div className="enterprise-list">{cases.slice(0, 5).map((item) => <div key={item.id}><strong>{item.subject}</strong><span>{label(item.category)} · {label(item.priority)} · {label(item.state)}</span>{canAdminister && item.state !== "closed" && <button disabled={busy} onClick={() => void run(() => updateSupportCase({ caseId: item.id, note: "Resolved from enterprise operations console.", state: "resolved" }), "Support case resolved.")}>Resolve</button>}</div>)}</div>
        </article>

        <article>
          <h3>Consent ledger</h3>
          <p>Every decision is append-only and tied to an explicit policy version.</p>
          {canAdminister && <form onSubmit={(event) => {
            event.preventDefault();
            void run(() => recordConsent({ consentType, decision: consentDecision, policyVersion }), "Consent decision recorded.");
          }}>
            <label>Consent<select value={consentType} onChange={(event) => setConsentType(event.target.value as ConsentRecord["consent_type"])}>{["ai_processing","analytics_storage","aggregate_learning","provider_data_processing","marketing_communications"].map((item) => <option key={item} value={item}>{label(item)}</option>)}</select></label>
            <div className="enterprise-form-row"><label>Decision<select value={consentDecision} onChange={(event) => setConsentDecision(event.target.value as ConsentRecord["decision"])}>{["granted","denied","revoked"].map((item) => <option key={item} value={item}>{label(item)}</option>)}</select></label><label>Policy version<input required maxLength={100} value={policyVersion} onChange={(event) => setPolicyVersion(event.target.value)} /></label></div>
            <button disabled={busy}>Record decision</button>
          </form>}
          <div className="enterprise-list">{consents.length ? consents.map((item) => <div key={item.consent_event_id}><strong>{label(item.consent_type)}</strong><span>{label(item.decision)} · {item.policy_version}</span></div>) : <p>No consent decision recorded.</p>}</div>
        </article>

        <article>
          <h3>Deletion operations</h3>
          <p>Requests are reviewed first. Tombstoning is explicit; purge completion requires separate subsystem evidence.</p>
          {canAdminister && <form onSubmit={(event) => {
            event.preventDefault();
            void run(() => requestDeletion({ scope: deletionScope, targetId: deletionTargetValue, manifestVersion }), "Deletion request recorded for review.");
          }}>
            <label>Scope<select value={deletionScope} onChange={(event) => setDeletionScope(event.target.value as DeletionRequest["scope"])}>{["workspace","account","content","user"].map((item) => <option key={item} value={item}>{label(item)}</option>)}</select></label>
            {deletionScope !== "workspace" && <label>Target ID<input required pattern="[0-9a-fA-F-]{36}" value={deletionTarget} onChange={(event) => setDeletionTarget(event.target.value)} /></label>}
            <label>Manifest version<input required maxLength={100} value={manifestVersion} onChange={(event) => setManifestVersion(event.target.value)} /></label>
            <button disabled={busy || !deletionTargetValue}>Request deletion</button>
          </form>}
          <div className="enterprise-list">{deletions.length ? deletions.map((item) => <div key={item.id}><strong>{label(item.scope)} · {label(item.state)}</strong><span>{item.target_id} · purge {item.purge_jobs_confirmed}/{item.purge_jobs_total}</span>{canAdminister && item.state === "requested" && <><label className="tombstone-confirm"><input type="checkbox" checked={Boolean(confirmedTombstones[item.id])} onChange={(event) => setConfirmedTombstones((current) => ({ ...current, [item.id]: event.target.checked }))} />I understand tombstoning immediately affects normal reads.</label><button className="danger" disabled={busy || !confirmedTombstones[item.id]} onClick={() => void run(() => applyDeletionTombstone(item.id), "Deletion tombstone applied; purge remains pending evidence.")}>Apply tombstone</button></>}</div>) : <p>No deletion requests.</p>}</div>
        </article>
      </div>
      {message && <p className="enterprise-message" role="status">{message}</p>}
    </section>
  );
}

const root = document.getElementById("enterprise-operations-root");
if (root) createRoot(root).render(<EnterpriseOperationsPanel />);
