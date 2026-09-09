import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  fetchAuthSession,
  createWorkspace,
  signUp,
  requestPasswordReset,
  completePasswordReset,
  verifyEmail,
  fetchOpportunities,
  fetchOpportunityDetail,
  fetchRecommendations,
  createRecommendation,
  recordRecommendationFeedback,
  createExperiment,
  addExperimentVariant,
  fetchAutomationPolicy,
  fetchAutomationRequests,
  createAutomationRequest,
  decideAutomationRequest,
  hasDevelopmentIdentity,
  selectWorkspace,
  signIn,
  signOut,
  RadarApiError,
  type AuthSessionResponse,
  type OpportunityDetail,
  type OpportunitySummary,
  type RelatedInsight,
  type Recommendation,
  type Experiment,
  type ExperimentVariant,
  type AutomationPolicy,
  type AutomationActionRequest
} from "./api.js";
import "./styles.css";
import "./auth.css";

function titleCase(value: string) {
  return value
    .replace(/[_-]+/g, " ")
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function formatConfidence(value: unknown): string {
  if (value === null || value === undefined) return "Not scored";
  if (typeof value === "number") {
    return value >= 0 && value <= 1 ? `${Math.round(value * 100)}%` : String(value);
  }
  if (typeof value === "string") return value;
  if (typeof value === "object") {
    const record = value as Record<string, unknown>;
    for (const key of ["label", "level", "score", "probability"]) {
      const candidate = record[key];
      if (typeof candidate === "number") {
        return candidate >= 0 && candidate <= 1 ? `${Math.round(candidate * 100)}%` : String(candidate);
      }
      if (typeof candidate === "string" && candidate.trim()) return candidate;
    }
    return "Recorded";
  }
  return "Recorded";
}

function formatScore(score: string | null): string {
  if (score === null) return "Unranked";
  const numeric = Number(score);
  return Number.isFinite(numeric) ? numeric.toFixed(numeric % 1 === 0 ? 0 : 1) : score;
}

function formatDate(value: string | null): string {
  if (!value) return "No expiry";
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return value;
  return new Intl.DateTimeFormat(undefined, { month: "short", day: "numeric", year: "numeric" }).format(date);
}

function insightLabel(insight: RelatedInsight) {
  switch (insight.state) {
    case "confirmed_account": return "Confirmed";
    case "account_hypothesis": return "Hypothesis";
    case "general_practice": return "General practice";
    case "insufficient_signal": return "Insufficient signal";
  }
}

function errorMessage(error: unknown): string {
  if (error instanceof RadarApiError) {
    if (error.httpStatus === 401) return "Your session is no longer available. Please sign in again.";
    if (error.httpStatus === 403) return "This workspace is not allowed to read the requested opportunity data.";
    if (error.httpStatus === 404) return "This opportunity is no longer available in the current workspace.";
    if (error.httpStatus === 503) return "Growth OS cannot reach the intelligence database right now.";
  }
  return "Opportunity Radar could not load. No synthetic opportunities were substituted.";
}

function OpportunityCard({
  opportunity,
  active,
  onSelect
}: {
  opportunity: OpportunitySummary;
  active: boolean;
  onSelect: () => void;
}) {
  return (
    <button className={`opportunity-card${active ? " active" : ""}`} onClick={onSelect} type="button">
      <div className="card-row">
        <span className="platform-label">{titleCase(opportunity.platform)}</span>
        <span className="score-pill">Score {formatScore(opportunity.score)}</span>
      </div>
      <h3>{opportunity.market} opportunity</h3>
      <p className="card-status">{titleCase(opportunity.status)}</p>
      <div className="card-metrics">
        <span><strong>{formatConfidence(opportunity.confidence)}</strong> confidence</span>
        <span><strong>{opportunity.evidence_count}</strong> evidence item{opportunity.evidence_count === 1 ? "" : "s"}</span>
      </div>
      <div className="card-footer">
        <span>{opportunity.expires_at ? `Expires ${formatDate(opportunity.expires_at)}` : "No expiry recorded"}</span>
        <span aria-hidden="true">→</span>
      </div>
    </button>
  );
}


function recommendationLabel(code: Recommendation["action_code"]) {
  if (code === "draft_content") return "Start a content draft";
  if (code === "review_evidence") return "Review the evidence";
  return "Plan an experiment";
}

function RecommendationPanel({ opportunityId }: { opportunityId: string }) {
  const [recommendations, setRecommendations] = useState<Recommendation[]>([]);
  const [loading, setLoading] = useState(true);
  const [busy, setBusy] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function load() {
    setLoading(true);
    setMessage(null);
    try {
      setRecommendations(await fetchRecommendations(opportunityId));
    } catch {
      setMessage("No stored recommendation could be loaded for this opportunity.");
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    void load();
  }, [opportunityId]);

  async function add(actionCode: Recommendation["action_code"]) {
    setBusy(actionCode);
    setMessage(null);
    try {
      const created = await createRecommendation(opportunityId, actionCode);
      setRecommendations((current) => {
        const withoutDuplicate = current.filter((item) => item.id !== created.id);
        return [created, ...withoutDuplicate];
      });
    } catch {
      setMessage("This action remains unavailable until stored evidence passes the recommendation boundary.");
    } finally {
      setBusy(null);
    }
  }

  async function giveFeedback(id: string, feedback: "accepted" | "dismissed" | "completed" | "irrelevant") {
    setBusy(id);
    setMessage(null);
    try {
      await recordRecommendationFeedback(id, feedback);
      setRecommendations((current) => current.map((item) => item.id === id ? {
        ...item,
        status: feedback === "accepted" ? "accepted" : feedback === "completed" ? "completed" : "dismissed",
        feedback_count: item.feedback_count + 1
      } : item));
    } catch {
      setMessage("Feedback was not recorded. The recommendation state was left unchanged.");
    } finally {
      setBusy(null);
    }
  }

  return (
    <section className="detail-section action-section">
      <p className="section-kicker">Recommended action</p>
      <h3>Evidence-linked next actions</h3>
      <p>
        Actions are stored only when this opportunity has persisted evidence. Growth OS never invents a recommendation or executes it automatically.
      </p>
      <div className="recommendation-actions">
        {(["draft_content", "review_evidence", "plan_experiment"] as const).map((actionCode) => (
          <button key={actionCode} className="detail-action-button" type="button" disabled={busy !== null} onClick={() => void add(actionCode)}>
            {busy === actionCode ? "Saving…" : recommendationLabel(actionCode)}
          </button>
        ))}
      </div>
      {loading && <p className="recommendation-muted">Loading stored recommendations…</p>}
      {!loading && recommendations.length === 0 && <p className="recommendation-muted">No action has been stored for this opportunity yet.</p>}
      {recommendations.length > 0 && (
        <div className="recommendation-list">
          {recommendations.map((recommendation) => (
            <article className="recommendation-card" key={recommendation.id}>
              <div>
                <strong>{recommendationLabel(recommendation.action_code)}</strong>
                <span>{titleCase(recommendation.status)} · {recommendation.feedback_count} feedback item{recommendation.feedback_count === 1 ? "" : "s"}</span>
              </div>
              <div className="recommendation-feedback">
                <button type="button" disabled={busy !== null} onClick={() => void giveFeedback(recommendation.id, "accepted")}>Accept</button>
                <button type="button" disabled={busy !== null} onClick={() => void giveFeedback(recommendation.id, "completed")}>Complete</button>
                <button type="button" disabled={busy !== null} onClick={() => void giveFeedback(recommendation.id, "irrelevant")}>Not relevant</button>
              </div>
            </article>
          ))}
        </div>
      )}
      {message && <p className="recommendation-error" role="alert">{message}</p>}
    </section>
  );
}


function ExperimentPlanner({ opportunityId }: { opportunityId: string }) {
  const [name, setName] = useState("");
  const [hypothesis, setHypothesis] = useState("");
  const [decisionRule, setDecisionRule] = useState("");
  const [variantLabel, setVariantLabel] = useState("");
  const [experiment, setExperiment] = useState<Experiment | null>(null);
  const [variants, setVariants] = useState<ExperimentVariant[]>([]);
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function submitExperiment(event: React.FormEvent) {
    event.preventDefault();
    setBusy(true);
    setMessage(null);
    try {
      setExperiment(await createExperiment({ opportunityId, name, hypothesis, decisionRule }));
    } catch {
      setMessage("The experiment plan could not be stored. Evidence and tenant checks remain enforced.");
    } finally {
      setBusy(false);
    }
  }

  async function submitVariant(event: React.FormEvent) {
    event.preventDefault();
    if (!experiment || !variantLabel.trim()) return;
    setBusy(true);
    setMessage(null);
    try {
      const variant = await addExperimentVariant(experiment.id, variantLabel, opportunityId);
      setVariants((current) => [...current, variant]);
      setVariantLabel("");
    } catch {
      setMessage("The variant lineage could not be stored.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="detail-section experiment-planner">
      <p className="section-kicker">Experiments</p>
      <h3>Plan a measurable next test</h3>
      <p>Planning is stored with the source opportunity. Growth OS does not publish variants or declare a winner without outcome evidence.</p>
      {!experiment ? (
        <form className="experiment-form" onSubmit={submitExperiment}>
          <label><span>Experiment name</span><input value={name} onChange={(event) => setName(event.target.value)} required maxLength={160} /></label>
          <label><span>Hypothesis</span><textarea value={hypothesis} onChange={(event) => setHypothesis(event.target.value)} required maxLength={2000} /></label>
          <label><span>Decision rule</span><textarea value={decisionRule} onChange={(event) => setDecisionRule(event.target.value)} required maxLength={2000} /></label>
          <button className="detail-action-button" type="submit" disabled={busy}>{busy ? "Saving…" : "Save experiment plan"}</button>
        </form>
      ) : (
        <>
          <div className="experiment-summary">
            <strong>{experiment.name}</strong>
            <span>{titleCase(experiment.status)} · {experiment.hypothesis}</span>
            <small>Decision rule: {experiment.decision_rule}</small>
          </div>
          <form className="experiment-variant-form" onSubmit={submitVariant}>
            <label><span>Variant label</span><input value={variantLabel} onChange={(event) => setVariantLabel(event.target.value)} required maxLength={120} /></label>
            <button className="detail-action-button" type="submit" disabled={busy}>{busy ? "Saving…" : "Add lineage-preserving variant"}</button>
          </form>
          {variants.length > 0 && (
            <ul className="experiment-variant-list">
              {variants.map((variant) => <li key={variant.id}><strong>{variant.label}</strong><span>{titleCase(variant.status)} · source opportunity preserved</span></li>)}
            </ul>
          )}
        </>
      )}
      {message && <p className="recommendation-error" role="alert">{message}</p>}
    </section>
  );
}

function AutomationPanel({ opportunityId, evidenceRef }: { opportunityId: string; evidenceRef: string | null }) {
  const [policy, setPolicy] = useState<AutomationPolicy | null>(null);
  const [requests, setRequests] = useState<AutomationActionRequest[]>([]);
  const [actionCode, setActionCode] = useState<AutomationActionRequest["action_code"]>("plan_experiment");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function load() {
    try {
      const [nextPolicy, nextRequests] = await Promise.all([
        fetchAutomationPolicy(),
        fetchAutomationRequests()
      ]);
      setPolicy(nextPolicy);
      setRequests(nextRequests.filter((request) => request.target_ref === opportunityId));
    } catch {
      setMessage("Automation controls are unavailable; no action was queued.");
    }
  }

  useEffect(() => {
    void load();
  }, [opportunityId]);

  async function queueRequest() {
    if (!evidenceRef) {
      setMessage("An action needs a stored evidence item before it can be queued.");
      return;
    }
    setBusy(true);
    setMessage(null);
    try {
      const created = await createAutomationRequest({
        actionCode,
        targetRef: opportunityId,
        evidenceRef,
        note: "Requested from the evidence-linked opportunity view."
      });
      setRequests((current) => [created, ...current]);
    } catch {
      setMessage("The request was blocked by policy, evidence, quota, or tenant controls.");
    } finally {
      setBusy(false);
    }
  }

  async function decide(requestId: string, decision: "approve" | "reject") {
    setBusy(true);
    setMessage(null);
    try {
      const updated = await decideAutomationRequest(requestId, decision);
      setRequests((current) => current.map((item) => item.id === updated.id ? updated : item));
    } catch {
      setMessage("Only an owner or admin can approve or reject, and the kill switch always wins.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="detail-section automation-panel">
      <p className="section-kicker">Automation control</p>
      <h3>Queue a bounded action for approval</h3>
      <p>Requests are never executed here. They remain auditable and pending until an owner or admin approves them.</p>
      <div className="automation-status">
        <span>Mode: {policy ? titleCase(policy.mode) : "Loading"}</span>
        <span>Daily limit: {policy?.daily_request_limit ?? "—"}</span>
        <span className={policy?.kill_switch ? "automation-stop" : "automation-ready"}>
          {policy?.kill_switch ? "Kill switch active" : "Kill switch off"}
        </span>
      </div>
      <div className="automation-request-form">
        <select value={actionCode} onChange={(event) => setActionCode(event.target.value as AutomationActionRequest["action_code"])}>
          <option value="draft_content">Draft content</option>
          <option value="review_evidence">Review evidence</option>
          <option value="plan_experiment">Plan experiment</option>
          <option value="publish_content">Publish content</option>
          <option value="multiply_variant">Multiply variant</option>
        </select>
        <button className="detail-action-button" type="button" disabled={busy || !evidenceRef} onClick={() => void queueRequest()}>
          {busy ? "Saving…" : "Queue for approval"}
        </button>
      </div>
      {requests.length > 0 && (
        <div className="automation-request-list">
          {requests.map((request) => (
            <article className="automation-request-card" key={request.id}>
              <div>
                <strong>{titleCase(request.action_code)}</strong>
                <span>{titleCase(request.status)} · evidence stored</span>
              </div>
              {request.status === "pending" && (
                <div className="recommendation-feedback">
                  <button type="button" disabled={busy} onClick={() => void decide(request.id, "approve")}>Approve</button>
                  <button type="button" disabled={busy} onClick={() => void decide(request.id, "reject")}>Reject</button>
                </div>
              )}
            </article>
          ))}
        </div>
      )}
      {!evidenceRef && <p className="recommendation-muted">No stored evidence is available, so automation remains unavailable.</p>}
      {message && <p className="recommendation-error" role="alert">{message}</p>}
    </section>
  );
}

function DetailPanel({
  detail,
  loading,
  error
}: {
  detail: OpportunityDetail | null;
  loading: boolean;
  error: string | null;
}) {
  if (loading) {
    return (
      <section className="detail-panel loading-panel" aria-live="polite">
        <div className="skeleton wide" />
        <div className="skeleton" />
        <div className="skeleton tall" />
      </section>
    );
  }

  if (error) {
    return (
      <section className="detail-panel empty-detail" aria-live="polite">
        <p className="eyebrow">Opportunity detail unavailable</p>
        <h2>We could not open this opportunity.</h2>
        <p>{error}</p>
      </section>
    );
  }

  if (!detail) {
    return (
      <section className="detail-panel empty-detail">
        <p className="eyebrow">Opportunity detail</p>
        <h2>Select an opportunity</h2>
        <p>Growth OS will show only evidence and insights that are actually stored for the selected workspace.</p>
      </section>
    );
  }

  const { opportunity, evidence, related_insights: relatedInsights } = detail;

  return (
    <section className="detail-panel" aria-live="polite">
      <div className="detail-header">
        <div>
          <p className="eyebrow">Opportunity detail</p>
          <h2>{titleCase(opportunity.platform)} · {opportunity.market}</h2>
        </div>
        <span className="confidence-badge">{formatConfidence(opportunity.confidence)} confidence</span>
      </div>

      <div className="detail-meta">
        <span>Score {formatScore(opportunity.score)}</span>
        <span>{titleCase(opportunity.status)}</span>
        <span>{opportunity.evidence_count} evidence item{opportunity.evidence_count === 1 ? "" : "s"}</span>
        <span>Ranking {opportunity.ranking_version}</span>
      </div>

      <section className="detail-section">
        <div className="section-heading">
          <div>
            <p className="section-kicker">Evidence</p>
            <h3>Evidence recorded for this opportunity</h3>
          </div>
          <span>{evidence.length}{opportunity.evidence_count > evidence.length ? ` / ${opportunity.evidence_count}` : ""}</span>
        </div>

        {evidence.length === 0 ? (
          <div className="truthful-empty compact">
            <strong>No evidence rows are stored for this opportunity yet.</strong>
            <p>The Radar will not manufacture an explanation to fill this gap.</p>
          </div>
        ) : (
          <div className="evidence-list">
            {evidence.map((item) => (
              <article className="evidence-row" key={item.id}>
                <div>
                  <span className="source-badge">{titleCase(item.source_class)}</span>
                  <p>{item.evidence_ref}</p>
                </div>
                <time>{item.observed_at ? formatDate(item.observed_at) : "Observation time not recorded"}</time>
              </article>
            ))}
          </div>
        )}
      </section>

      <section className="detail-section">
        <div className="section-heading">
          <div>
            <p className="section-kicker">Related intelligence</p>
            <h3>What we know about this account</h3>
          </div>
          <span>{relatedInsights.length}</span>
        </div>

        {relatedInsights.length === 0 ? (
          <div className="truthful-empty compact">
            <strong>No account-linked insight is currently available.</strong>
            <p>General or unrelated claims are not being attached to this opportunity automatically.</p>
          </div>
        ) : (
          <div className="insight-list">
            {relatedInsights.map((insight) => (
              <article className={`insight-card state-${insight.state}`} key={insight.id}>
                <div className="insight-topline">
                  <span className="state-badge">{insightLabel(insight)}</span>
                  <span>{formatConfidence(insight.confidence)} confidence</span>
                </div>
                <p className="insight-claim">{insight.claim}</p>
                <div className="insight-meta">
                  <span>{insight.evidence_count} evidence item{insight.evidence_count === 1 ? "" : "s"}</span>
                  {insight.sample_size !== null && <span>Sample {insight.sample_size}</span>}
                </div>
                {insight.evidence.length > 0 && (
                  <div className="insight-evidence" aria-label={`Stored evidence for ${insightLabel(insight)} insight`}>
                    {insight.evidence.map((item) => (
                      <div className="insight-evidence-row" key={item.id}>
                        <span>{titleCase(item.source_class)}</span>
                        <p>{item.evidence_ref}</p>
                      </div>
                    ))}
                    {insight.evidence_count > insight.evidence.length && (
                      <p className="evidence-truncation">Showing {insight.evidence.length} of {insight.evidence_count} stored evidence items.</p>
                    )}
                  </div>
                )}
              </article>
            ))}
          </div>
        )}
      </section>

      <RecommendationPanel opportunityId={opportunity.id} />
      <ExperimentPlanner opportunityId={opportunity.id} />
      <AutomationPanel opportunityId={opportunity.id} evidenceRef={evidence[0]?.evidence_ref ?? null} />
    </section>
  );
}

function RadarApp({
  auth,
  onSignOut,
  onUnauthorized
}: {
  auth: AuthSessionResponse | null;
  onSignOut: (() => Promise<void>) | null;
  onUnauthorized: () => void;
}) {
  const [opportunities, setOpportunities] = useState<OpportunitySummary[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<OpportunityDetail | null>(null);
  const [listState, setListState] = useState<"loading" | "ready" | "error">("loading");
  const [detailLoading, setDetailLoading] = useState(false);
  const [listMessage, setListMessage] = useState<string | null>(null);
  const [detailMessage, setDetailMessage] = useState<string | null>(null);
  const [radarRefreshToken, setRadarRefreshToken] = useState(0);

  useEffect(() => {
    const refresh = () => setRadarRefreshToken((value) => value + 1);
    window.addEventListener("growth-os:radar-refresh", refresh);
    return () => window.removeEventListener("growth-os:radar-refresh", refresh);
  }, []);

  useEffect(() => {
    let active = true;
    fetchOpportunities()
      .then((rows) => {
        if (!active) return;
        setOpportunities(rows);
        setListState("ready");
        setSelectedId((current) => current ?? rows[0]?.id ?? null);
      })
      .catch((error) => {
        if (!active) return;
        if (error instanceof RadarApiError && error.httpStatus === 401) {
          onUnauthorized();
          return;
        }
        setListMessage(errorMessage(error));
        setListState("error");
      });
    return () => { active = false; };
  }, [onUnauthorized, radarRefreshToken]);

  useEffect(() => {
    if (!selectedId) {
      setDetail(null);
      setDetailMessage(null);
      return;
    }

    let active = true;
    setDetailLoading(true);
    setDetailMessage(null);
    fetchOpportunityDetail(selectedId)
      .then((result) => {
        if (!active) return;
        setDetail(result);
        setDetailLoading(false);
      })
      .catch((error) => {
        if (!active) return;
        if (error instanceof RadarApiError && error.httpStatus === 401) {
          onUnauthorized();
          return;
        }
        setDetail(null);
        setDetailMessage(errorMessage(error));
        setDetailLoading(false);
      });
    return () => { active = false; };
  }, [selectedId, onUnauthorized]);

  return (
    <main className="app-shell">
      <header className="topbar">
        <a className="brand" href="/" aria-label="Growth OS home">
          <span className="brand-mark">G</span>
          <span>Growth OS</span>
        </a>
        <div className="topbar-actions">
          {auth?.selected_workspace && (
            <span className="workspace-chip">{auth.selected_workspace.name}</span>
          )}
          <div className="product-label"><span className="live-dot" /> Opportunity Radar</div>
          {onSignOut && (
            <button className="signout-button" type="button" onClick={() => void onSignOut()}>Sign out</button>
          )}
        </div>
      </header>

      <section className="hero editorial-hero">
        <div className="hero-copy">
          <p className="eyebrow">Signal feed · this week</p>
          <h1>See what is beginning to move.</h1>
          <p className="lede">
            Growth OS turns stored observations into ranked opportunities, so the next move starts with evidence—not noise.
          </p>
          <div className="hero-actions">
            <a className="hero-text-link" href="#radar-feed">Open opportunity feed ↓</a>
            <span className="hero-note">Evidence first · no synthetic signals</span>
          </div>
        </div>
        <div className="signal-stage" aria-label="Current signal summary">
          <div className="signal-orbit" aria-hidden="true">
            <span className="signal-ring ring-outer" />
            <span className="signal-ring ring-inner" />
            <span className="signal-point point-one" />
            <span className="signal-point point-two" />
            <span className="signal-point point-three" />
            <span className="signal-core" />
          </div>
          <div className="signal-readout">
            <span className="signal-kicker">Primary signal</span>
            <strong>{opportunities[0] ? `${titleCase(opportunities[0].market)} opportunity` : "Waiting for a real signal"}</strong>
            <span>{opportunities[0] ? `${formatConfidence(opportunities[0].confidence)} confidence · ${opportunities[0].evidence_count} evidence items` : "No synthetic signal is displayed."}</span>
          </div>
        </div>
      </section>

      {listMessage && listState === "error" && (
        <section className="truthful-empty error-state">
          <p className="eyebrow">Radar unavailable</p>
          <h2>We could not load your workspace opportunities.</h2>
          <p>{listMessage}</p>
          <button type="button" onClick={() => window.location.reload()}>Try again</button>
        </section>
      )}

      {listState !== "error" && (
        <section id="radar-feed" className="radar-layout">
          <aside className="opportunity-list" aria-label="Ranked opportunities">
            <div className="list-heading">
              <div>
                <p className="eyebrow">Ranked now</p>
                <h2>Opportunities</h2>
              </div>
              <span>{opportunities.length}</span>
            </div>

            {listState === "loading" && (
              <div className="loading-stack" aria-label="Loading opportunities">
                <div className="skeleton card-skeleton" />
                <div className="skeleton card-skeleton" />
                <div className="skeleton card-skeleton" />
              </div>
            )}

            {listState === "ready" && opportunities.length === 0 && (
              <div className="truthful-empty">
                <div className="empty-icon">◎</div>
                <h3>No real opportunities are available yet.</h3>
                <p>
                  Growth OS has not received enough stored opportunity data for this workspace. Nothing synthetic is being shown in its place.
                </p>
              </div>
            )}

            <div className="cards-stack">
              {opportunities.map((opportunity) => (
                <OpportunityCard
                  key={opportunity.id}
                  opportunity={opportunity}
                  active={selectedId === opportunity.id}
                  onSelect={() => setSelectedId(opportunity.id)}
                />
              ))}
            </div>
          </aside>

          <DetailPanel detail={detail} loading={detailLoading} error={detailMessage} />
        </section>
      )}

      <footer>
        <span>Growth OS</span>
        <span>Evidence first. No synthetic production opportunities.</span>
      </footer>
    </main>
  );
}

function AuthLoading() {
  return (
    <main className="auth-shell">
      <div className="auth-card auth-loading" aria-live="polite">
        <span className="brand-mark">G</span>
        <div className="skeleton wide" />
        <div className="skeleton" />
      </div>
    </main>
  );
}

function SignInScreen({ onSignedIn, onCreateAccount, onForgotPassword }: {
  onSignedIn: (session: AuthSessionResponse) => void;
  onCreateAccount: () => void;
  onForgotPassword: () => void;
}) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setMessage(null);
    try {
      onSignedIn(await signIn(email, password));
    } catch (error) {
      if (error instanceof RadarApiError) {
        if (error.apiStatus === "rate_limited") setMessage("Too many sign-in attempts. Try again later.");
        else if (error.apiStatus === "password_change_required") setMessage("This account requires a password change before continuing.");
        else if (error.httpStatus === 401) setMessage("Email or password is incorrect.");
        else if (error.httpStatus === 403) setMessage("This sign-in request was rejected by the security policy.");
        else setMessage("Growth OS could not sign you in right now.");
      } else {
        setMessage("Growth OS could not sign you in right now.");
      }
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="auth-shell">
      <section className="auth-card">
        <div className="auth-brand"><span className="brand-mark">G</span><strong>Growth OS</strong></div>
        <p className="eyebrow">Organic growth intelligence</p>
        <h1 className="auth-title">Sign in to see your next opportunity.</h1>
        <p className="auth-copy">Your session stays server-side. Growth OS does not store authentication tokens in browser storage.</p>

        <form className="auth-form" onSubmit={submit}>
          <label>
            <span>Email</span>
            <input autoComplete="email" inputMode="email" name="email" type="email" value={email} onChange={(event) => setEmail(event.target.value)} required />
          </label>
          <label>
            <span>Password</span>
            <input autoComplete="current-password" name="password" type="password" value={password} onChange={(event) => setPassword(event.target.value)} required />
          </label>
          {message && <p className="auth-error" role="alert">{message}</p>}
          <button className="auth-primary" type="submit" disabled={submitting}>
            {submitting ? "Signing in…" : "Sign in"}
          </button>
        </form>
        <button className="auth-secondary" type="button" onClick={onForgotPassword}>Forgot password?</button>
        <button className="auth-secondary" type="button" onClick={onCreateAccount}>Create a new account</button>
      </section>
    </main>
  );
}

function SignupScreen({ onBack }: { onBack: () => void }) {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (password !== confirmation) {
      setMessage("Passwords do not match.");
      return;
    }
    setSubmitting(true);
    setMessage(null);
    try {
      await signUp(email, password);
      setMessage("Account created. Check your email to verify the account before signing in.");
    } catch (error) {
      if (error instanceof RadarApiError && error.apiStatus === "identity_email_unavailable") {
        setMessage("Account email delivery is not configured yet. Please contact the workspace administrator.");
      } else if (error instanceof RadarApiError && error.httpStatus === 409) {
        setMessage("This account cannot be created with the submitted details.");
      } else {
        setMessage("Growth OS could not create the account right now.");
      }
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="auth-shell">
      <section className="auth-card">
        <div className="auth-brand"><span className="brand-mark">G</span><strong>Growth OS</strong></div>
        <p className="eyebrow">Create your account</p>
        <h1 className="auth-title">Start with a verified identity.</h1>
        <p className="auth-copy">We send a verification link before any workspace access is granted.</p>
        <form className="auth-form" onSubmit={submit}>
          <label><span>Email</span><input autoComplete="email" type="email" value={email} onChange={(event) => setEmail(event.target.value)} required /></label>
          <label><span>Password</span><input autoComplete="new-password" type="password" minLength={12} value={password} onChange={(event) => setPassword(event.target.value)} required /></label>
          <label><span>Confirm password</span><input autoComplete="new-password" type="password" minLength={12} value={confirmation} onChange={(event) => setConfirmation(event.target.value)} required /></label>
          {message && <p className="auth-error" role="alert">{message}</p>}
          <button className="auth-primary" type="submit" disabled={submitting}>{submitting ? "Creating…" : "Create account"}</button>
        </form>
        <button className="auth-secondary" type="button" onClick={onBack}>Back to sign in</button>
      </section>
    </main>
  );
}

function PasswordResetRequestScreen({ onBack }: { onBack: () => void }) {
  const [email, setEmail] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [submitted, setSubmitted] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setMessage(null);
    try {
      await requestPasswordReset(email);
      setSubmitted(true);
    } catch (error) {
      if (error instanceof RadarApiError && error.httpStatus === 400) {
        setMessage("Enter a valid email address.");
      } else {
        setMessage("Growth OS could not send the reset request right now. Try again later.");
      }
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="auth-shell">
      <section className="auth-card">
        <div className="auth-brand"><span className="brand-mark">G</span><strong>Growth OS</strong></div>
        <p className="eyebrow">Password recovery</p>
        {submitted ? (
          <>
            <h1 className="auth-title">Check your email.</h1>
            <p className="auth-copy">If an account exists for that address, we sent a password-reset link. Check your inbox and spam folder.</p>
            <button className="auth-primary" type="button" onClick={onBack}>Back to sign in</button>
          </>
        ) : (
          <>
            <h1 className="auth-title">Reset your password.</h1>
            <p className="auth-copy">Enter your email and we’ll send a one-time reset link if an account exists.</p>
            <form className="auth-form" onSubmit={submit}>
              <label><span>Email</span><input autoComplete="email" inputMode="email" type="email" value={email} onChange={(event) => setEmail(event.target.value)} required /></label>
              {message && <p className="auth-error" role="alert">{message}</p>}
              <button className="auth-primary" type="submit" disabled={submitting}>{submitting ? "Sending…" : "Send reset link"}</button>
            </form>
            <button className="auth-secondary" type="button" onClick={onBack}>Back to sign in</button>
          </>
        )}
      </section>
    </main>
  );
}

function PasswordResetCompleteScreen({ token, onDone }: { token: string; onDone: () => void }) {
  const [password, setPassword] = useState("");
  const [confirmation, setConfirmation] = useState("");
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [completed, setCompleted] = useState(false);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    if (password !== confirmation) {
      setMessage("Passwords do not match.");
      return;
    }
    setSubmitting(true);
    setMessage(null);
    try {
      await completePasswordReset(token, password);
      setCompleted(true);
    } catch (error) {
      if (error instanceof RadarApiError && error.httpStatus === 400) {
        setMessage("Use a password with at least 12 characters.");
      } else {
        setMessage("This reset link is invalid or expired. Request a new one.");
      }
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="auth-shell">
      <section className="auth-card">
        <div className="auth-brand"><span className="brand-mark">G</span><strong>Growth OS</strong></div>
        <p className="eyebrow">Password recovery</p>
        {completed ? (
          <>
            <h1 className="auth-title">Password updated.</h1>
            <p className="auth-copy">Your password was changed successfully. You can sign in now.</p>
            <button className="auth-primary" type="button" onClick={onDone}>Continue to sign in</button>
          </>
        ) : (
          <>
            <h1 className="auth-title">Choose a new password.</h1>
            <p className="auth-copy">Use at least 12 characters. This one-time link expires after one hour.</p>
            <form className="auth-form" onSubmit={submit}>
              <label><span>New password</span><input autoComplete="new-password" type="password" minLength={12} value={password} onChange={(event) => setPassword(event.target.value)} required /></label>
              <label><span>Confirm password</span><input autoComplete="new-password" type="password" minLength={12} value={confirmation} onChange={(event) => setConfirmation(event.target.value)} required /></label>
              {message && <p className="auth-error" role="alert">{message}</p>}
              <button className="auth-primary" type="submit" disabled={submitting}>{submitting ? "Updating…" : "Update password"}</button>
            </form>
          </>
        )}
      </section>
    </main>
  );
}

function EmailVerificationScreen({ token, onDone }: { token: string; onDone: () => void }) {
  const [state, setState] = useState<"loading" | "verified" | "error">("loading");

  useEffect(() => {
    verifyEmail(token).then(() => setState("verified")).catch(() => setState("error"));
  }, [token]);

  return (
    <main className="auth-shell">
      <section className="auth-card">
        <div className="auth-brand"><span className="brand-mark">G</span><strong>Growth OS</strong></div>
        <p className="eyebrow">Email verification</p>
        {state === "loading" && <><h1 className="auth-title">Verifying your account…</h1><p className="auth-copy">The verification token is checked once and then consumed.</p></>}
        {state === "verified" && <><h1 className="auth-title">Your email is verified.</h1><p className="auth-copy">You can sign in now and create or select a workspace.</p><button className="auth-primary" type="button" onClick={onDone}>Continue to sign in</button></>}
        {state === "error" && <><h1 className="auth-title">This link is no longer valid.</h1><p className="auth-copy">The token may be expired or already used. Request a new verification email through the administrator.</p><button className="auth-secondary" type="button" onClick={onDone}>Back to sign in</button></>}
      </section>
    </main>
  );
}

function WorkspaceOnboardingScreen({
  session,
  onCreated,
  onSignOut
}: {
  session: AuthSessionResponse;
  onCreated: (session: AuthSessionResponse) => void;
  onSignOut: () => Promise<void>;
}) {
  const [name, setName] = useState("");
  const [market, setMarket] = useState("US");
  const [language, setLanguage] = useState("en-US");
  const [timezone, setTimezone] = useState("America/New_York");
  const [submitting, setSubmitting] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setSubmitting(true);
    setMessage(null);
    try {
      await createWorkspace({ name, defaultMarket: market, defaultLanguage: language, defaultTimezone: timezone });
      onCreated(await fetchAuthSession());
    } catch {
      setMessage("Growth OS could not create this workspace. Check the details and try again.");
    } finally {
      setSubmitting(false);
    }
  }

  return (
    <main className="auth-shell">
      <section className="auth-card">
        <div className="auth-brand"><span className="brand-mark">G</span><strong>Growth OS</strong></div>
        <p className="eyebrow">First workspace</p>
        <h1 className="auth-title">Give your growth system a home.</h1>
        <p className="auth-copy">This workspace becomes the tenant boundary for accounts, evidence, opportunities, and future publishing controls.</p>
        <form className="auth-form" onSubmit={submit}>
          <label><span>Workspace name</span><input value={name} onChange={(event) => setName(event.target.value)} required /></label>
          <label><span>Default market</span><input value={market} onChange={(event) => setMarket(event.target.value)} required /></label>
          <label><span>Default language</span><input value={language} onChange={(event) => setLanguage(event.target.value)} required /></label>
          <label><span>Default timezone</span><input value={timezone} onChange={(event) => setTimezone(event.target.value)} required /></label>
          {message && <p className="auth-error" role="alert">{message}</p>}
          <button className="auth-primary" type="submit" disabled={submitting}>{submitting ? "Creating…" : "Create workspace"}</button>
        </form>
        <button className="auth-secondary" type="button" onClick={() => void onSignOut()}>Sign out</button>
      </section>
    </main>
  );
}

function WorkspaceScreen({
  session,
  onSelected,
  onSignOut
}: {
  session: AuthSessionResponse;
  onSelected: (session: AuthSessionResponse) => void;
  onSignOut: () => Promise<void>;
}) {
  const [selecting, setSelecting] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);

  async function choose(id: string) {
    setSelecting(id);
    setMessage(null);
    try {
      onSelected(await selectWorkspace(id));
    } catch {
      setMessage("This workspace is no longer available to your account.");
    } finally {
      setSelecting(null);
    }
  }

  return (
    <main className="auth-shell">
      <section className="auth-card workspace-picker">
        <div className="auth-brand"><span className="brand-mark">G</span><strong>Growth OS</strong></div>
        <p className="eyebrow">Workspace</p>
        <h1 className="auth-title">Where do you want to grow?</h1>
        <p className="auth-copy">Every selection is checked against your current active membership before access is granted.</p>

        {session.workspaces.length === 0 ? (
          <div className="auth-empty">
            <strong>No active workspace is available.</strong>
            <p>Your account is signed in, but it does not currently have an active workspace membership.</p>
          </div>
        ) : (
          <div className="workspace-options">
            {session.workspaces.map((workspace) => (
              <button key={workspace.id} type="button" className="workspace-option" onClick={() => void choose(workspace.id)} disabled={selecting !== null}>
                <span><strong>{workspace.name}</strong><small>{titleCase(workspace.role)} · {workspace.default_market}</small></span>
                <span>{selecting === workspace.id ? "Selecting…" : "→"}</span>
              </button>
            ))}
          </div>
        )}
        {message && <p className="auth-error" role="alert">{message}</p>}
        <button className="auth-secondary" type="button" onClick={() => void onSignOut()}>Sign out</button>
      </section>
    </main>
  );
}

function RootApp() {
  const [state, setState] = useState<"loading" | "signed_out" | "signup" | "reset_request" | "reset_complete" | "verify" | "workspace" | "onboarding" | "ready" | "dev">("loading");
  const verificationToken = new URLSearchParams(window.location.search).get("token");
  const resetToken = verificationToken;
  const [session, setSession] = useState<AuthSessionResponse | null>(null);

  useEffect(() => {
    if (window.location.pathname === "/reset-password" && resetToken) {
      setState("reset_complete");
      return;
    }
    if (window.location.pathname === "/verify-email" && verificationToken) {
      setState("verify");
      return;
    }
    if (hasDevelopmentIdentity()) {
      setState("dev");
      return;
    }

    let active = true;
    fetchAuthSession()
      .then((result) => {
        if (!active) return;
        setSession(result);
        setState(result.selected_workspace ? "ready" : result.workspaces.length > 0 ? "workspace" : "onboarding");
      })
      .catch(() => {
        if (!active) return;
        setSession(null);
        setState("signed_out");
      });
    return () => { active = false; };
  }, [verificationToken, resetToken]);

  async function doSignOut() {
    try { await signOut(); } catch { /* local state still clears */ }
    setSession(null);
    setState("signed_out");
  }

  function acceptSession(result: AuthSessionResponse) {
    setSession(result);
    setState(result.selected_workspace ? "ready" : result.workspaces.length > 0 ? "workspace" : "onboarding");
  }

  if (state === "loading") return <AuthLoading />;
  if (state === "signed_out") return <SignInScreen onSignedIn={acceptSession} onCreateAccount={() => setState("signup")} onForgotPassword={() => setState("reset_request")} />;
  if (state === "signup") return <SignupScreen onBack={() => setState("signed_out")} />;
  if (state === "reset_request") return <PasswordResetRequestScreen onBack={() => setState("signed_out")} />;
  if (state === "reset_complete" && resetToken) {
    return <PasswordResetCompleteScreen token={resetToken} onDone={() => {
      window.history.replaceState({}, "", "/");
      setState("signed_out");
    }} />;
  }
  if (state === "verify" && verificationToken) {
    return <EmailVerificationScreen token={verificationToken} onDone={() => {
      window.history.replaceState({}, "", "/");
      setState("signed_out");
    }} />;
  }
  if (state === "onboarding" && session) {
    return <WorkspaceOnboardingScreen session={session} onCreated={acceptSession} onSignOut={doSignOut} />;
  }
  if (state === "workspace" && session) {
    return <WorkspaceScreen session={session} onSelected={acceptSession} onSignOut={doSignOut} />;
  }
  if (state === "dev") {
    return <RadarApp auth={null} onSignOut={null} onUnauthorized={() => setState("signed_out")} />;
  }
  if (state === "ready" && session) {
    return <RadarApp auth={session} onSignOut={doSignOut} onUnauthorized={() => void doSignOut()} />;
  }

  return <AuthLoading />;
}

createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <RootApp />
  </React.StrictMode>
);
