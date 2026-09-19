import type { PoolClient } from "pg";
import type { AuthPrincipal } from "./auth.js";
import { listMetricAnalyticsSummary, listMetricQualityAnomalies } from "./analytics.js";
import { getAutomationPolicy, listAutomationActionRequests } from "./automation.js";
import { listExperimentVariants, listExperiments } from "./experiments.js";
import { getOpportunityDetail, listInsights, listOpportunities } from "./intelligence.js";
import { listRecommendations } from "./recommendations.js";

export type CopilotIntent = "summary" | "metrics" | "evidence" | "actions" | "experiments" | "operations";

export type CopilotCitation = {
  kind: "opportunity" | "insight" | "evidence" | "metric" | "recommendation" | "experiment" | "automation";
  ref: string;
  label: string;
};

export type CopilotReply = {
  mode: "evidence_grounded";
  intent: CopilotIntent;
  answer: string;
  citations: CopilotCitation[];
  workspace_pulse: {
    opportunities: number;
    insights: number;
    metric_rows: number;
    quality_alerts: number;
    experiments: number;
    automation_needs_attention: number;
    automation_kill_switch: boolean;
  };
  suggested_prompts: string[];
  limitations: string[];
};

type CopilotData = {
  opportunities: Awaited<ReturnType<typeof listOpportunities>>;
  insights: Awaited<ReturnType<typeof listInsights>>;
  metrics: Awaited<ReturnType<typeof listMetricAnalyticsSummary>>;
  anomalies: Awaited<ReturnType<typeof listMetricQualityAnomalies>>;
  recommendations: Awaited<ReturnType<typeof listRecommendations>>;
  experiments: Awaited<ReturnType<typeof listExperiments>>;
  automationPolicy: Awaited<ReturnType<typeof getAutomationPolicy>>;
  automationRequests: Awaited<ReturnType<typeof listAutomationActionRequests>>;
  topOpportunityDetail: Awaited<ReturnType<typeof getOpportunityDetail>>;
  topExperimentVariants: Awaited<ReturnType<typeof listExperimentVariants>>;
};

function normalize(value: string): string {
  return value
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .toLowerCase();
}

export function classifyCopilotIntent(message: string): CopilotIntent {
  const text = normalize(message);
  if (/metric|analytics|performance|desempenho|view|reach|alcance|like|curtida|dado/.test(text)) return "metrics";
  if (/evidenc|prova|porque|por que|why|fonte|source/.test(text)) return "evidence";
  if (/experiment|teste|testar|variant|winner|vencedor|loser|perdedor/.test(text)) return "experiments";
  if (/automation|autopilot|operac|incident|alert|fila|queue|kill switch|worker/.test(text)) return "operations";
  if (/recomend|recommend|acao|action|fazer|next|proximo|criar|publish|publicar/.test(text)) return "actions";
  return "summary";
}

function numberValue(value: unknown): number {
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : 0;
}

function uniqueCitations(citations: CopilotCitation[]): CopilotCitation[] {
  const seen = new Set<string>();
  return citations.filter((citation) => {
    const key = `${citation.kind}:${citation.ref}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  }).slice(0, 12);
}

export function buildCopilotReply(message: string, data: CopilotData): CopilotReply {
  const intent = classifyCopilotIntent(message);
  const citations: CopilotCitation[] = [];
  const attentionRequests = data.automationRequests.filter((row) =>
    row.execution_status === "needs_input" || row.execution_status === "failed" || row.execution_status === "executing"
  );
  const pulse = {
    opportunities: data.opportunities.length,
    insights: data.insights.length,
    metric_rows: data.metrics.length,
    quality_alerts: data.anomalies.length,
    experiments: data.experiments.length,
    automation_needs_attention: attentionRequests.length,
    automation_kill_switch: data.automationPolicy.kill_switch
  };

  let answer = "";

  if (intent === "metrics") {
    if (data.metrics.length === 0) {
      answer = "I do not have stored provider observations for the current seven-day window, so I cannot make a factual performance claim.";
    } else {
      const leaders = [...data.metrics]
        .sort((a, b) => numberValue(b.total_value) - numberValue(a.total_value))
        .slice(0, 3);
      answer = `The current seven-day window contains ${data.metrics.length} metric group${data.metrics.length === 1 ? "" : "s"}. ${leaders.map((row) => `${row.handle || row.provider_account_id} · ${row.metric_name}: ${numberValue(row.total_value)}`).join("; ")}. ${data.anomalies.length > 0 ? `${data.anomalies.length} data-quality alert${data.anomalies.length === 1 ? " is" : "s are"} active, so interpret affected metrics cautiously.` : "No stored data-quality anomaly is active in this window."}`;
      for (const row of leaders) citations.push({ kind: "metric", ref: `${row.social_account_id}:${row.metric_name}`, label: `${row.handle || row.provider_account_id} · ${row.metric_name}` });
      for (const row of data.anomalies.slice(0, 3)) citations.push({ kind: "metric", ref: `${row.social_account_id}:${row.metric_name}:quality`, label: `${row.metric_name} · ${row.quality_status}` });
    }
  } else if (intent === "evidence") {
    const detail = data.topOpportunityDetail;
    if (!detail || detail.evidence.length === 0) {
      answer = "There is no persisted opportunity evidence available for me to cite in the current workspace. I will not invent a reason or causal explanation.";
    } else {
      const insight = detail.related_insights[0];
      answer = `The highest-ranked current opportunity has ${detail.evidence.length} persisted evidence item${detail.evidence.length === 1 ? "" : "s"}. ${insight ? `Its leading related insight is ${insight.state.replaceAll("_", " ")}: “${insight.claim}”.` : "There is no related insight strong enough to cite."} These records support the opportunity; they do not prove causality beyond their stored epistemic state.`;
      citations.push({ kind: "opportunity", ref: detail.opportunity.id, label: `${detail.opportunity.platform} · ${detail.opportunity.market}` });
      for (const row of detail.evidence.slice(0, 5)) citations.push({ kind: "evidence", ref: row.evidence_ref, label: `${row.source_class} evidence` });
      if (insight) {
        citations.push({ kind: "insight", ref: insight.id, label: insight.claim });
        for (const row of insight.evidence.slice(0, 3)) citations.push({ kind: "evidence", ref: row.evidence_ref, label: `${row.source_class} · ${row.evidence_type}` });
      }
    }
  } else if (intent === "actions") {
    const actionable = data.recommendations.filter((row) => row.status === "proposed" || row.status === "accepted").slice(0, 3);
    if (actionable.length === 0) {
      answer = data.opportunities.length > 0
        ? "There is a current opportunity, but no persisted recommendation is available yet. Review its evidence before creating a draft, experiment, or automation request. I will not manufacture an action that has not passed the evidence boundary."
        : "There is no current evidence-backed opportunity or persisted recommendation, so there is no factual next action for the Copilot to claim.";
    } else {
      answer = `There ${actionable.length === 1 ? "is" : "are"} ${actionable.length} stored evidence-linked next action${actionable.length === 1 ? "" : "s"}: ${actionable.map((row) => row.action_code.replaceAll("_", " ")).join(", ")}. Execution remains subject to the existing review, approval and Autopilot policy boundaries.`;
      for (const row of actionable) citations.push({ kind: "recommendation", ref: row.id, label: row.action_code.replaceAll("_", " ") });
    }
  } else if (intent === "experiments") {
    const experiment = data.experiments[0];
    if (!experiment) {
      answer = "No experiment is stored in this workspace yet. A winner or loser cannot be declared without a persisted experiment, variant and evidence-backed outcome.";
    } else {
      const winners = data.topExperimentVariants.filter((row) => row.status === "winner");
      const losers = data.topExperimentVariants.filter((row) => row.status === "loser");
      answer = `The latest experiment is “${experiment.name}” (${experiment.status}) with ${data.topExperimentVariants.length} stored variant${data.topExperimentVariants.length === 1 ? "" : "s"}. ${winners.length} winner${winners.length === 1 ? "" : "s"} and ${losers.length} loser${losers.length === 1 ? "" : "s"} are currently recorded. Outcomes are only treated as measured learning when an evidence reference was stored.`;
      citations.push({ kind: "experiment", ref: experiment.id, label: experiment.name });
      for (const row of data.topExperimentVariants.slice(0, 5)) citations.push({ kind: "experiment", ref: row.id, label: `${row.label} · ${row.status}` });
    }
  } else if (intent === "operations") {
    answer = `Autopilot is ${data.automationPolicy.mode.replaceAll("_", " ")}; the emergency stop is ${data.automationPolicy.kill_switch ? "ON" : "off"}; the daily request limit is ${data.automationPolicy.daily_request_limit}. ${attentionRequests.length} automation request${attentionRequests.length === 1 ? " needs" : "s need"} operational attention. ${data.anomalies.length} data-quality alert${data.anomalies.length === 1 ? " is" : "s are"} active in the current analytics window.`;
    citations.push({ kind: "automation", ref: data.automationPolicy.id ?? data.automationPolicy.workspace_id, label: "Autopilot policy" });
    for (const row of attentionRequests.slice(0, 5)) citations.push({ kind: "automation", ref: row.id, label: `${row.action_code} · ${row.execution_status}` });
  } else {
    const topOpportunity = data.opportunities[0];
    const topInsight = data.insights.find((row) => row.state === "confirmed_account") ?? data.insights[0];
    if (!topOpportunity && !topInsight && data.metrics.length === 0) {
      answer = "I do not have enough persisted workspace evidence to give a factual growth briefing yet. Connect or sync an authorized provider and I will summarize only what the stored evidence supports.";
    } else {
      const parts: string[] = [];
      if (topOpportunity) {
        parts.push(`Top current opportunity: ${topOpportunity.platform} / ${topOpportunity.market}, score ${topOpportunity.score ?? "unranked"}, backed by ${topOpportunity.evidence_count} evidence item${topOpportunity.evidence_count === 1 ? "" : "s"}.`);
        citations.push({ kind: "opportunity", ref: topOpportunity.id, label: `${topOpportunity.platform} · ${topOpportunity.market}` });
      }
      if (topInsight) {
        parts.push(`Latest ${topInsight.state.replaceAll("_", " ")} insight: “${topInsight.claim}”.`);
        citations.push({ kind: "insight", ref: topInsight.id, label: topInsight.claim });
      }
      parts.push(`${data.metrics.length} metric group${data.metrics.length === 1 ? "" : "s"}, ${data.anomalies.length} quality alert${data.anomalies.length === 1 ? "" : "s"}, and ${attentionRequests.length} automation item${attentionRequests.length === 1 ? "" : "s"} needing attention are visible in the current workspace pulse.`);
      answer = parts.join(" ");
    }
  }

  return {
    mode: "evidence_grounded",
    intent,
    answer,
    citations: uniqueCitations(citations),
    workspace_pulse: pulse,
    suggested_prompts: [
      "What changed in my metrics?",
      "What evidence supports the top opportunity?",
      "What should I do next?",
      "What is the latest experiment result?",
      "Is anything in operations blocked?"
    ],
    limitations: [
      "Answers use only persisted data available to the current workspace.",
      "Correlation is not presented as confirmed causality.",
      "Copilot does not publish or execute provider actions; those remain behind existing approval and Autopilot controls."
    ]
  };
}

export async function queryCopilot(
  client: PoolClient,
  principal: AuthPrincipal,
  message: string
): Promise<CopilotReply> {
  const now = new Date();
  const from = new Date(now.getTime() - 7 * 24 * 60 * 60 * 1000).toISOString();
  const to = now.toISOString();

  const opportunities = await listOpportunities(client, principal, 10);
  const insights = await listInsights(client, principal, 10);
  const metrics = await listMetricAnalyticsSummary(client, principal, from, to);
  const anomalies = await listMetricQualityAnomalies(client, principal, from, to);
  const recommendations = await listRecommendations(client, principal, null, 20);
  const experiments = await listExperiments(client, principal, 20);
  const automationPolicy = await getAutomationPolicy(client, principal);
  const automationRequests = await listAutomationActionRequests(client, principal, 20);
  const topOpportunityDetail = opportunities[0]
    ? await getOpportunityDetail(client, principal, opportunities[0].id)
    : null;
  const topExperimentVariants = experiments[0]
    ? await listExperimentVariants(client, principal, experiments[0].id)
    : [];

  return buildCopilotReply(message, {
    opportunities,
    insights,
    metrics,
    anomalies,
    recommendations,
    experiments,
    automationPolicy,
    automationRequests,
    topOpportunityDetail,
    topExperimentVariants
  });
}
