import React, { useEffect, useMemo, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  fetchOpportunities,
  fetchOpportunityDetail,
  RadarApiError,
  type OpportunityDetail,
  type OpportunitySummary,
  type RelatedInsight
} from "./api.js";
import "./styles.css";

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
    if (error.httpStatus === 401) return "Your authenticated workspace context is not available in this environment.";
    if (error.httpStatus === 403) return "This workspace is not allowed to read the requested opportunity data.";
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

function DetailPanel({ detail, loading }: { detail: OpportunityDetail | null; loading: boolean }) {
  if (loading) {
    return (
      <section className="detail-panel loading-panel" aria-live="polite">
        <div className="skeleton wide" />
        <div className="skeleton" />
        <div className="skeleton tall" />
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
          <span>{evidence.length}</span>
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
              </article>
            ))}
          </div>
        )}
      </section>

      <section className="detail-section action-section">
        <p className="section-kicker">Recommended action</p>
        <h3>No approved action is stored yet</h3>
        <p>
          This opportunity currently contains ranking and evidence, but the database does not yet store a verified action prescription for it.
          Growth OS therefore leaves this area explicit rather than generating an unsupported instruction.
        </p>
      </section>
    </section>
  );
}

function App() {
  const [opportunities, setOpportunities] = useState<OpportunitySummary[]>([]);
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [detail, setDetail] = useState<OpportunityDetail | null>(null);
  const [listState, setListState] = useState<"loading" | "ready" | "error">("loading");
  const [detailLoading, setDetailLoading] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

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
        setMessage(errorMessage(error));
        setListState("error");
      });
    return () => { active = false; };
  }, []);

  useEffect(() => {
    if (!selectedId) {
      setDetail(null);
      return;
    }

    let active = true;
    setDetailLoading(true);
    fetchOpportunityDetail(selectedId)
      .then((result) => {
        if (!active) return;
        setDetail(result);
        setDetailLoading(false);
      })
      .catch((error) => {
        if (!active) return;
        setDetail(null);
        setMessage(errorMessage(error));
        setDetailLoading(false);
      });
    return () => { active = false; };
  }, [selectedId]);

  const evidenceTotal = useMemo(
    () => opportunities.reduce((sum, opportunity) => sum + opportunity.evidence_count, 0),
    [opportunities]
  );

  return (
    <main className="app-shell">
      <header className="topbar">
        <a className="brand" href="/" aria-label="Growth OS home">
          <span className="brand-mark">G</span>
          <span>Growth OS</span>
        </a>
        <div className="product-label"><span className="live-dot" /> Opportunity Radar</div>
      </header>

      <section className="hero">
        <div>
          <p className="eyebrow">Organic growth intelligence</p>
          <h1>See the opportunity before it becomes obvious.</h1>
          <p className="lede">
            Ranked opportunities from your workspace, with the evidence and confidence that actually exist behind them.
          </p>
        </div>
        <div className="hero-proof" aria-label="Current Radar data">
          <div><strong>{opportunities.length}</strong><span>available opportunities</span></div>
          <div><strong>{evidenceTotal}</strong><span>evidence items</span></div>
        </div>
      </section>

      {message && listState === "error" && (
        <section className="truthful-empty error-state">
          <p className="eyebrow">Radar unavailable</p>
          <h2>We could not load your workspace opportunities.</h2>
          <p>{message}</p>
          <button type="button" onClick={() => window.location.reload()}>Try again</button>
        </section>
      )}

      {listState !== "error" && (
        <section className="radar-layout">
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
                  onSelect={() => {
                    setMessage(null);
                    setSelectedId(opportunity.id);
                  }}
                />
              ))}
            </div>
          </aside>

          <DetailPanel detail={detail} loading={detailLoading} />
        </section>
      )}

      <footer>
        <span>Growth OS</span>
        <span>Evidence first. No synthetic production opportunities.</span>
      </footer>
    </main>
  );
}

createRoot(document.getElementById("root")!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
);
