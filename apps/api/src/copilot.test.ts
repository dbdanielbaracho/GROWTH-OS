import assert from "node:assert/strict";
import test from "node:test";
import { buildCopilotReply, classifyCopilotIntent } from "./copilot.js";

const baseData = {
  opportunities: [],
  insights: [],
  metrics: [],
  anomalies: [],
  recommendations: [],
  experiments: [],
  automationPolicy: {
    id: null,
    workspace_id: "00000000-0000-0000-0000-000000000001",
    mode: "approval_required" as const,
    daily_request_limit: 10,
    kill_switch: false,
    created_at: "2026-09-19T00:00:00.000Z",
    updated_at: "2026-09-19T00:00:00.000Z"
  },
  automationRequests: [],
  topOpportunityDetail: null,
  topExperimentVariants: []
};

test("classifies Portuguese and English workspace questions", () => {
  assert.equal(classifyCopilotIntent("o que mudou no desempenho?"), "metrics");
  assert.equal(classifyCopilotIntent("qual evidência suporta isso?"), "evidence");
  assert.equal(classifyCopilotIntent("what should I do next?"), "actions");
  assert.equal(classifyCopilotIntent("tem algum incidente no autopilot?"), "operations");
  assert.equal(classifyCopilotIntent("qual experimento venceu?"), "experiments");
});

test("fails closed when no persisted evidence exists", () => {
  const reply = buildCopilotReply("what is happening?", baseData as never);
  assert.equal(reply.mode, "evidence_grounded");
  assert.equal(reply.citations.length, 0);
  assert.match(reply.answer, /do not have enough persisted workspace evidence/i);
  assert.equal(reply.workspace_pulse.opportunities, 0);
});

test("uses persisted evidence and never bypasses approval controls", () => {
  const reply = buildCopilotReply("what evidence supports the top opportunity?", {
    ...baseData,
    opportunities: [{
      id: "11111111-1111-1111-1111-111111111111",
      social_account_id: "22222222-2222-2222-2222-222222222222",
      market: "US",
      platform: "instagram",
      status: "open",
      score: "91",
      confidence: { label: "high" },
      ranking_version: "test",
      expires_at: null,
      created_at: "2026-09-19T00:00:00.000Z",
      evidence_count: 1
    }],
    insights: [],
    topOpportunityDetail: {
      opportunity: {
        id: "11111111-1111-1111-1111-111111111111",
        social_account_id: "22222222-2222-2222-2222-222222222222",
        market: "US",
        platform: "instagram",
        status: "open",
        score: "91",
        confidence: { label: "high" },
        ranking_version: "test",
        expires_at: null,
        created_at: "2026-09-19T00:00:00.000Z",
        evidence_count: 1
      },
      evidence: [{
        id: "33333333-3333-3333-3333-333333333333",
        source_class: "owned",
        evidence_ref: "metric-observation:test",
        observed_at: "2026-09-19T00:00:00.000Z"
      }],
      related_insights: []
    }
  } as never);

  assert.match(reply.answer, /1 persisted evidence item/i);
  assert.ok(reply.citations.some((citation) => citation.ref === "metric-observation:test"));
  assert.ok(reply.limitations.some((line) => /does not publish or execute/i.test(line)));
});
