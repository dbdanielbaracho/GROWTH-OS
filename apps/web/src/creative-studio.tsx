import React, { useCallback, useEffect, useMemo, useRef, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  createCreativeGeneration,
  createCreativeRequest,
  createMediaAsset,
  createMediaAssetLineage,
  CreativeGeneration,
  CreativeRequest,
  fetchAuthSession,
  fetchContent,
  fetchCreativeGenerations,
  fetchCreativeRequests,
  fetchMediaAssetLineage,
  fetchMediaAssets,
  fetchOpportunities,
  MediaAsset,
  MediaAssetLineage,
  OpportunitySummary,
  ContentListItem,
  RadarApiError,
  reconcileCreativeGeneration,
  transitionCreativeGeneration
} from "./api.js";
import "./creative-studio.css";

function studioError(error: unknown): string {
  if (error instanceof RadarApiError) {
    if (error.httpStatus === 401) return "Your Growth OS session expired. Sign in again.";
    if (error.httpStatus === 403) return "This workspace is not allowed to use Creative Studio.";
    if (error.httpStatus === 422) return "The selected source is not available in this workspace.";
    if (error.httpStatus === 409) return "That creative operation conflicts with its current lifecycle state.";
    if (error.httpStatus === 400) return "Complete the required Creative Studio fields.";
  }
  return "Creative Studio could not complete that operation.";
}

function short(value: string | null | undefined, limit = 76): string {
  const normalized = value?.replace(/\s+/g, " ").trim() ?? "";
  if (!normalized) return "Untitled";
  return normalized.length > limit ? `${normalized.slice(0, limit)}…` : normalized;
}

function titleCase(value: string): string {
  return value.replace(/_/g, " ").replace(/\b\w/g, (letter) => letter.toUpperCase());
}

type SourceChoice = {
  type: "content" | "opportunity";
  id: string;
  label: string;
};

function CreativeStudioPanel() {
  const authGeneration = useRef(0);
  const [authenticated, setAuthenticated] = useState(false);
  const [checking, setChecking] = useState(true);
  const [expanded, setExpanded] = useState(false);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [content, setContent] = useState<ContentListItem[]>([]);
  const [opportunities, setOpportunities] = useState<OpportunitySummary[]>([]);
  const [requests, setRequests] = useState<CreativeRequest[]>([]);
  const [generations, setGenerations] = useState<CreativeGeneration[]>([]);
  const [assets, setAssets] = useState<MediaAsset[]>([]);
  const [lineage, setLineage] = useState<MediaAssetLineage[]>([]);

  const [sourceKey, setSourceKey] = useState("");
  const [capability, setCapability] = useState("draft_copy");
  const [modality, setModality] = useState<"text" | "image" | "video" | "audio">("text");
  const [market, setMarket] = useState("US");
  const [language, setLanguage] = useState("en-US");
  const [provider, setProvider] = useState("manual_provider");
  const [model, setModel] = useState("");

  const [storageRef, setStorageRef] = useState("");
  const [mimeType, setMimeType] = useState("image/png");
  const [checksum, setChecksum] = useState("");
  const [rightsStatus, setRightsStatus] = useState("workspace_owned");
  const [sourceClass, setSourceClass] = useState("user_supplied");
  const [purpose, setPurpose] = useState<"source" | "intermediate" | "publishable">("source");
  const [assetGenerationId, setAssetGenerationId] = useState("");
  const [outputAssetId, setOutputAssetId] = useState("");
  const [inputAssetId, setInputAssetId] = useState("");
  const [lineageRole, setLineageRole] = useState("source");

  const sourceChoices = useMemo<SourceChoice[]>(() => [
    ...content.map((item) => ({
      type: "content" as const,
      id: item.id,
      label: `Content · ${short(item.objective || item.body)}`
    })),
    ...opportunities.map((item) => ({
      type: "opportunity" as const,
      id: item.id,
      label: `Opportunity · ${item.market} · ${item.platform} · ${item.id.slice(0, 8)}`
    }))
  ], [content, opportunities]);

  const refresh = useCallback(async () => {
    const generation = authGeneration.current;
    try {
      await fetchAuthSession();
      if (generation !== authGeneration.current) return;
      setAuthenticated(true);
      const [contentRows, opportunityRows, requestRows, generationRows, assetRows, lineageRows] = await Promise.all([
        fetchContent(),
        fetchOpportunities(),
        fetchCreativeRequests(),
        fetchCreativeGenerations(),
        fetchMediaAssets(),
        fetchMediaAssetLineage()
      ]);
      if (generation !== authGeneration.current) return;
      setContent(contentRows);
      setOpportunities(opportunityRows);
      setRequests(requestRows);
      setGenerations(generationRows);
      setAssets(assetRows);
      setLineage(lineageRows);
    } catch (error) {
      if (generation !== authGeneration.current) return;
      if (error instanceof RadarApiError && error.httpStatus === 401) setAuthenticated(false);
      else setMessage(studioError(error));
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
      setRequests([]);
      setGenerations([]);
      setAssets([]);
      setLineage([]);
      if ((event as CustomEvent<{ authenticated?: boolean }>).detail?.authenticated) void refresh();
    };
    window.addEventListener("growth-os:auth-change", onAuthChange);
    return () => window.removeEventListener("growth-os:auth-change", onAuthChange);
  }, [refresh]);

  useEffect(() => { void refresh(); }, [refresh]);

  async function submitRequest(event: React.FormEvent) {
    event.preventDefault();
    const choice = sourceChoices.find((candidate) => `${candidate.type}:${candidate.id}` === sourceKey);
    if (!choice) {
      setMessage("Choose persisted content or an opportunity as the creative source.");
      return;
    }
    setBusy(true);
    setMessage(null);
    try {
      const created = await createCreativeRequest({
        sourceType: choice.type,
        sourceId: choice.id,
        capability,
        modality,
        targetMarket: market,
        targetLanguage: language
      });
      setMessage(`Creative request created · ${created.id.slice(0, 8)} · evidence source preserved.`);
      await refresh();
    } catch (error) {
      setMessage(studioError(error));
    } finally {
      setBusy(false);
    }
  }

  async function createGeneration(request: CreativeRequest) {
    setBusy(true);
    setMessage(null);
    try {
      const created = await createCreativeGeneration({
        creativeRequestId: request.id,
        provider: provider.trim() || "manual_provider",
        model: model.trim() || undefined,
        supportsProviderIdempotency: false
      });
      setMessage(`Generation attempt registered · ${created.id.slice(0, 8)}. Provider execution remains fail-closed until an execution adapter is configured.`);
      await refresh();
    } catch (error) {
      setMessage(studioError(error));
    } finally {
      setBusy(false);
    }
  }

  async function moveGeneration(generation: CreativeGeneration, status: CreativeGeneration["status"]) {
    setBusy(true);
    setMessage(null);
    try {
      await transitionCreativeGeneration(generation.id, status);
      setMessage(`Generation ${generation.id.slice(0, 8)} moved to ${titleCase(status)}.`);
      await refresh();
    } catch (error) {
      setMessage(studioError(error));
    } finally {
      setBusy(false);
    }
  }

  async function reconcile(generation: CreativeGeneration, status: "succeeded" | "failed") {
    setBusy(true);
    setMessage(null);
    try {
      await reconcileCreativeGeneration(generation.id, status);
      setMessage(`Ambiguous generation reconciled as ${status}.`);
      await refresh();
    } catch (error) {
      setMessage(studioError(error));
    } finally {
      setBusy(false);
    }
  }

  async function submitAsset(event: React.FormEvent) {
    event.preventDefault();
    if (!storageRef.trim() || !checksum.trim()) {
      setMessage("Storage reference and checksum are required for an auditable asset.");
      return;
    }
    setBusy(true);
    setMessage(null);
    try {
      const created = await createMediaAsset({
        storageRef: storageRef.trim(),
        mimeType: mimeType.trim(),
        checksum: checksum.trim(),
        rightsStatus: rightsStatus.trim(),
        sourceClass: sourceClass.trim(),
        purpose,
        creativeGenerationId: assetGenerationId || undefined
      });
      setStorageRef("");
      setChecksum("");
      setMessage(`Asset registered · ${created.id.slice(0, 8)} · rights and provenance retained.`);
      await refresh();
    } catch (error) {
      setMessage(studioError(error));
    } finally {
      setBusy(false);
    }
  }

  async function submitLineage(event: React.FormEvent) {
    event.preventDefault();
    if (!outputAssetId || !inputAssetId || outputAssetId === inputAssetId) {
      setMessage("Choose two different assets for a lineage edge.");
      return;
    }
    setBusy(true);
    setMessage(null);
    try {
      await createMediaAssetLineage({ outputAssetId, inputAssetId, role: lineageRole.trim() || undefined });
      setMessage("Asset lineage recorded. Cycles remain rejected by the database guard.");
      await refresh();
    } catch (error) {
      setMessage(studioError(error));
    } finally {
      setBusy(false);
    }
  }

  if (checking || !authenticated) return null;

  return (
    <aside className={`creative-studio-panel${expanded ? " expanded" : ""}`} aria-live="polite">
      <button className="creative-studio-toggle" type="button" onClick={() => setExpanded((value) => !value)} aria-expanded={expanded}>
        <span className="creative-studio-mark" aria-hidden="true">✦</span>
        <span><strong>Creative Studio</strong><small>Requests · generations · assets · lineage</small></span>
        <span aria-hidden="true">{expanded ? "×" : "↑"}</span>
      </button>

      {expanded && (
        <div className="creative-studio-body">
          <header>
            <p className="creative-kicker">Evidence-bound production</p>
            <h2>Build creative work without losing provenance.</h2>
            <p>Requests are tied to persisted workspace sources. Provider execution is never simulated: this surface tracks the generation lifecycle and assets until an authorized provider adapter executes the job.</p>
          </header>

          {message && <p className="creative-message" role="status">{message}</p>}

          <section className="creative-grid" aria-label="Creative request and generation controls">
            <form className="creative-card" onSubmit={submitRequest}>
              <h3>1 · Creative request</h3>
              <label>Source
                <select value={sourceKey} onChange={(event) => setSourceKey(event.target.value)} required>
                  <option value="">Choose persisted source</option>
                  {sourceChoices.map((choice) => <option key={`${choice.type}:${choice.id}`} value={`${choice.type}:${choice.id}`}>{choice.label}</option>)}
                </select>
              </label>
              <label>Capability
                <select value={capability} onChange={(event) => setCapability(event.target.value)}>
                  <option value="draft_copy">Draft copy</option>
                  <option value="visual_concept">Visual concept</option>
                  <option value="video_brief">Video brief</option>
                  <option value="audio_brief">Audio brief</option>
                </select>
              </label>
              <label>Modality
                <select value={modality} onChange={(event) => setModality(event.target.value as typeof modality)}>
                  <option value="text">Text</option><option value="image">Image</option><option value="video">Video</option><option value="audio">Audio</option>
                </select>
              </label>
              <div className="creative-pair"><label>Market<input value={market} onChange={(event) => setMarket(event.target.value)} /></label><label>Language<input value={language} onChange={(event) => setLanguage(event.target.value)} /></label></div>
              <button disabled={busy || !sourceKey}>Create request</button>
            </form>

            <div className="creative-card">
              <h3>2 · Generation attempts</h3>
              <div className="creative-pair"><label>Provider<input value={provider} onChange={(event) => setProvider(event.target.value)} /></label><label>Model optional<input value={model} onChange={(event) => setModel(event.target.value)} /></label></div>
              <div className="creative-scroll">
                {requests.length === 0 && <p className="creative-empty">No creative requests yet.</p>}
                {requests.map((request) => (
                  <article key={request.id} className="creative-row">
                    <div><strong>{titleCase(request.capability)}</strong><span>{titleCase(request.modality)} · {request.target_market} · {request.target_language}</span><code>{request.source_type}:{request.source_id.slice(0, 8)}</code></div>
                    <button type="button" disabled={busy} onClick={() => void createGeneration(request)}>Register attempt</button>
                  </article>
                ))}
              </div>
            </div>
          </section>

          <section className="creative-card" aria-label="Generation lifecycle">
            <h3>Generation lifecycle</h3>
            <div className="creative-scroll wide">
              {generations.length === 0 && <p className="creative-empty">No generation attempts have been registered.</p>}
              {generations.map((generation) => (
                <article key={generation.id} className="creative-row lifecycle">
                  <div><strong>{generation.provider}{generation.model ? ` · ${generation.model}` : ""}</strong><span>{titleCase(generation.status)} · request {generation.creative_request_id.slice(0, 8)}</span><code>{generation.id}</code></div>
                  <div className="creative-actions">
                    {generation.status === "requested" && <><button type="button" onClick={() => void moveGeneration(generation, "queued")}>Queue</button><button type="button" onClick={() => void moveGeneration(generation, "cancelled")}>Cancel</button></>}
                    {generation.status === "queued" && <><button type="button" onClick={() => void moveGeneration(generation, "processing")}>Processing</button><button type="button" onClick={() => void moveGeneration(generation, "cancelled")}>Cancel</button></>}
                    {generation.status === "processing" && <><button type="button" onClick={() => void moveGeneration(generation, "succeeded")}>Succeeded</button><button type="button" onClick={() => void moveGeneration(generation, "failed")}>Failed</button><button type="button" onClick={() => void moveGeneration(generation, "ambiguous")}>Ambiguous</button></>}
                    {generation.status === "ambiguous" && <><button type="button" onClick={() => void reconcile(generation, "succeeded")}>Reconcile success</button><button type="button" onClick={() => void reconcile(generation, "failed")}>Reconcile failure</button></>}
                  </div>
                </article>
              ))}
            </div>
          </section>

          <section className="creative-grid" aria-label="Asset library and lineage">
            <form className="creative-card" onSubmit={submitAsset}>
              <h3>3 · Asset library</h3>
              <label>Storage reference<input value={storageRef} onChange={(event) => setStorageRef(event.target.value)} placeholder="s3://bucket/object or durable provider ref" /></label>
              <div className="creative-pair"><label>MIME type<input value={mimeType} onChange={(event) => setMimeType(event.target.value)} /></label><label>Checksum<input value={checksum} onChange={(event) => setChecksum(event.target.value)} /></label></div>
              <div className="creative-pair"><label>Rights status<input value={rightsStatus} onChange={(event) => setRightsStatus(event.target.value)} /></label><label>Source class<input value={sourceClass} onChange={(event) => setSourceClass(event.target.value)} /></label></div>
              <label>Purpose<select value={purpose} onChange={(event) => setPurpose(event.target.value as typeof purpose)}><option value="source">Source</option><option value="intermediate">Intermediate</option><option value="publishable">Publishable</option></select></label>
              <label>Generation optional<select value={assetGenerationId} onChange={(event) => setAssetGenerationId(event.target.value)}><option value="">No generation link</option>{generations.map((generation) => <option key={generation.id} value={generation.id}>{generation.id.slice(0, 8)} · {generation.provider} · {generation.status}</option>)}</select></label>
              <button disabled={busy}>Register asset</button>
            </form>

            <form className="creative-card" onSubmit={submitLineage}>
              <h3>4 · Asset lineage</h3>
              <label>Output asset<select value={outputAssetId} onChange={(event) => setOutputAssetId(event.target.value)}><option value="">Choose output</option>{assets.map((asset) => <option key={asset.id} value={asset.id}>{asset.id.slice(0, 8)} · {asset.purpose || "asset"} · {asset.mime_type}</option>)}</select></label>
              <label>Input asset<select value={inputAssetId} onChange={(event) => setInputAssetId(event.target.value)}><option value="">Choose input</option>{assets.map((asset) => <option key={asset.id} value={asset.id}>{asset.id.slice(0, 8)} · {asset.purpose || "asset"} · {asset.mime_type}</option>)}</select></label>
              <label>Role<input value={lineageRole} onChange={(event) => setLineageRole(event.target.value)} /></label>
              <button disabled={busy || !outputAssetId || !inputAssetId}>Add lineage edge</button>
              <div className="creative-scroll lineage-list">
                {lineage.length === 0 && <p className="creative-empty">No lineage edges yet.</p>}
                {lineage.map((edge) => <p key={`${edge.output_asset_id}:${edge.input_asset_id}`}><code>{edge.input_asset_id.slice(0, 8)}</code> → <code>{edge.output_asset_id.slice(0, 8)}</code> · {edge.role || "source"}</p>)}
              </div>
            </form>
          </section>

          <section className="creative-card asset-summary" aria-label="Creative asset inventory">
            <h3>Inventory</h3>
            <div className="creative-stats"><span><strong>{requests.length}</strong> requests</span><span><strong>{generations.length}</strong> attempts</span><span><strong>{assets.length}</strong> assets</span><span><strong>{lineage.length}</strong> lineage edges</span></div>
          </section>
        </div>
      )}
    </aside>
  );
}

const root = document.getElementById("creative-studio-root");
if (root) createRoot(root).render(<React.StrictMode><CreativeStudioPanel /></React.StrictMode>);
