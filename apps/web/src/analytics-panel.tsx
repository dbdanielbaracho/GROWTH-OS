import React, { useCallback, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import {
  fetchAuthSession,
  fetchMetricAnalyticsSummary,
  fetchMetricAnalyticsSnapshot,
  RadarApiError,
  type MetricAnalyticsSummary
} from "./api.js";
import "./analytics-panel.css";

function analyticsError(error: unknown): string {
  if (error instanceof RadarApiError) {
    if (error.httpStatus === 401) return "Your Growth OS session expired. Sign in again.";
    if (error.httpStatus === 403) return "This workspace is not allowed to read analytics.";
    if (error.httpStatus === 400) return "Choose a valid analytics window.";
  }
  return "Analytics could not load. No synthetic values were substituted.";
}

function formatNumber(value: number): string {
  return new Intl.NumberFormat(undefined, { maximumFractionDigits: 2 }).format(value);
}

function qualityLabel(row: MetricAnalyticsSummary): string {
  if (row.complete_observations < row.observation_count) return "Incomplete";
  if (row.fresh_observations < row.observation_count) return "Stale";
  return "Complete";
}

function AnalyticsPanel() {
  const [authenticated, setAuthenticated] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [loading, setLoading] = useState(false);
  const [rows, setRows] = useState<MetricAnalyticsSummary[]>([]);
  const [message, setMessage] = useState<string | null>(null);
  const [exporting, setExporting] = useState(false);

  const refresh = useCallback(async () => {
    setLoading(true);
    try {
      await fetchAuthSession();
      setAuthenticated(true);
      setRows(await fetchMetricAnalyticsSummary());
      setMessage(null);
    } catch (error) {
      if (error instanceof RadarApiError && error.httpStatus === 401) {
        setAuthenticated(false);
        setRows([]);
      } else {
        setMessage(analyticsError(error));
      }
    } finally {
      setLoading(false);
    }
  }, []);

  async function exportSnapshot() {
    setExporting(true);
    setMessage(null);
    try {
      const snapshot = await fetchMetricAnalyticsSnapshot();
      const blob = new Blob([JSON.stringify(snapshot, null, 2)], { type: "application/json" });
      const url = URL.createObjectURL(blob);
      const anchor = document.createElement("a");
      anchor.href = url;
      anchor.download = `growth-os-metrics-${snapshot.from.slice(0, 10)}-${snapshot.to.slice(0, 10)}.json`;
      anchor.click();
      URL.revokeObjectURL(url);
    } catch (error) {
      setMessage(analyticsError(error));
    } finally {
      setExporting(false);
    }
  }

  useEffect(() => {
    void refresh();
    const onRefresh = () => void refresh();
    window.addEventListener("focus", onRefresh);
    window.addEventListener("growth-os:radar-refresh", onRefresh);
    return () => {
      window.removeEventListener("focus", onRefresh);
      window.removeEventListener("growth-os:radar-refresh", onRefresh);
    };
  }, [refresh]);

  if (!authenticated) return null;

  return (
    <aside className="analytics-panel" aria-live="polite">
      <button className="analytics-panel-toggle" type="button" onClick={() => setExpanded((value) => !value)} aria-expanded={expanded}>
        <span className="analytics-mark" aria-hidden="true">↗</span>
        <span><strong>Analytics</strong><small>Real observations</small></span>
        <span className="analytics-chevron" aria-hidden="true">{expanded ? "×" : "+"}</span>
      </button>
      {expanded && (
        <div className="analytics-panel-body">
          <p className="analytics-kicker">Data evidence</p>
          <h2>Metric summary</h2>
          <p className="analytics-copy">Last 7 days of stored provider observations. Totals are grouped by account and metric; missing data stays visible as empty.</p>
          <button className="analytics-export" type="button" onClick={() => void exportSnapshot()} disabled={exporting}>
            {exporting ? "Exporting…" : "Export JSON snapshot"}
          </button>
          {loading && <p className="analytics-muted">Loading analytics…</p>}
          {message && <div className="analytics-error" role="alert">{message}</div>}
          {!loading && !message && rows.length === 0 && (
            <div className="analytics-empty">
              <strong>No real observations in this window.</strong>
              <span>Connect a provider and run a sync before interpreting performance.</span>
            </div>
          )}
          {!loading && rows.length > 0 && (
            <div className="analytics-table" role="table" aria-label="Metric summary">
              <div className="analytics-table-row analytics-table-head" role="row">
                <span>Account</span><span>Metric</span><span>Rows</span><span>Total</span><span>Quality</span>
              </div>
              {rows.slice(0, 20).map((row) => (
                <div className="analytics-table-row" role="row" key={row.social_account_id + ":" + row.metric_name}>
                  <span>{row.handle || row.provider_account_id}</span>
                  <span>{row.metric_name}</span>
                  <span>{row.observation_count}</span>
                  <span>{formatNumber(row.total_value)}</span>
                  <span>{qualityLabel(row)}</span>
                </div>
              ))}
            </div>
          )}
          <p className="analytics-note">Complete {rows.reduce((total, row) => total + row.complete_observations, 0)} · Fresh {rows.reduce((total, row) => total + row.fresh_observations, 0)}</p>
        </div>
      )}
    </aside>
  );
}

const root = document.getElementById("analytics-panel-root");
if (root) {
  createRoot(root).render(
    <React.StrictMode>
      <AnalyticsPanel />
    </React.StrictMode>
  );
}
