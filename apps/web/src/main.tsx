import React, { useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  fetchAuthSession,
  createWorkspace,
  signUp,
  verifyEmail,
  fetchOpportunities,
  fetchOpportunityDetail,
  hasDevelopmentIdentity,
  selectWorkspace,
  signIn,
  signOut,
  RadarApiError,
  type AuthSessionResponse,
  type OpportunityDetail,
  type OpportunitySummary,
  type RelatedInsight
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

function SignInScreen({ onSignedIn, onCreateAccount }: {
  onSignedIn: (session: AuthSessionResponse) => void;
  onCreateAccount: () => void;
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
  const [state, setState] = useState<"loading" | "signed_out" | "signup" | "verify" | "workspace" | "onboarding" | "ready" | "dev">("loading");
  const verificationToken = new URLSearchParams(window.location.search).get("token");
  const [session, setSession] = useState<AuthSessionResponse | null>(null);

  useEffect(() => {
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
  }, [verificationToken]);

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
  if (state === "signed_out") return <SignInScreen onSignedIn={acceptSession} onCreateAccount={() => setState("signup")} />;
  if (state === "signup") return <SignupScreen onBack={() => setState("signed_out")} />;
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
