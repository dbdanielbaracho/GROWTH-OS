import assert from "node:assert/strict";
import test from "node:test";
import type { PoolClient } from "pg";
import { getOpportunityDetail, listOpportunities } from "./intelligence.js";

const principal = {
  userId: "a0000000-0000-4000-8000-000000000001",
  workspaceId: "b0000000-0000-4000-8000-000000000001"
};

function fakeClient(rowsByCall: unknown[][], calls: Array<{ text: string; values: unknown[] }>): PoolClient {
  let index = 0;
  return {
    query: async (text: string, values: unknown[]) => {
      calls.push({ text, values });
      const rows = rowsByCall[index++] ?? [];
      return { rows, rowCount: rows.length };
    }
  } as unknown as PoolClient;
}

test("listOpportunities is workspace-scoped and clamps the limit", async () => {
  const calls: Array<{ text: string; values: unknown[] }> = [];
  const client = fakeClient([[]], calls);

  await listOpportunities(client, principal, 500);

  assert.equal(calls.length, 1);
  assert.match(calls[0].text, /o\.workspace_id = \$1/);
  assert.match(calls[0].text, /opportunity_evidence/);
  assert.deepEqual(calls[0].values, [principal.workspaceId, 100]);
});

test("getOpportunityDetail returns null for missing, expired, or cross-tenant rows", async () => {
  const calls: Array<{ text: string; values: unknown[] }> = [];
  const client = fakeClient([[]], calls);
  const id = "c0000000-0000-4000-8000-000000000001";

  const detail = await getOpportunityDetail(client, principal, id);

  assert.equal(detail, null);
  assert.equal(calls.length, 1);
  assert.match(calls[0].text, /o\.workspace_id = \$1/);
  assert.match(calls[0].text, /o\.id = \$2/);
  assert.match(calls[0].text, /expires_at is null or o\.expires_at > now\(\)/);
  assert.deepEqual(calls[0].values, [principal.workspaceId, id]);
});

test("getOpportunityDetail returns stored evidence and does not invent related insights without an account", async () => {
  const calls: Array<{ text: string; values: unknown[] }> = [];
  const opportunity = {
    id: "c0000000-0000-4000-8000-000000000001",
    social_account_id: null,
    market: "US",
    platform: "example",
    status: "active",
    score: "90",
    confidence: { level: "high" },
    ranking_version: "v1",
    expires_at: null,
    created_at: "2026-09-03T00:00:00.000Z",
    evidence_count: 1
  };
  const evidence = {
    id: "d0000000-0000-4000-8000-000000000001",
    source_class: "owned",
    evidence_ref: "metric:engagement-rise",
    observed_at: "2026-09-03T00:00:00.000Z"
  };
  const client = fakeClient([[opportunity], [evidence]], calls);

  const detail = await getOpportunityDetail(client, principal, opportunity.id);

  assert.deepEqual(detail, {
    opportunity,
    evidence: [evidence],
    related_insights: []
  });
  assert.equal(calls.length, 2);
  assert.match(calls[1].text, /growth\.opportunity_evidence/);
  assert.deepEqual(calls[1].values, [principal.workspaceId, opportunity.id]);
});
