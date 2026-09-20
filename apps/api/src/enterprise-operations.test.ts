import assert from "node:assert/strict";
import test from "node:test";
import type { PoolClient } from "pg";
import {
  createDeletionRequest,
  recordWorkspaceConsent,
  setAgencyClient,
  tombstoneDeletionRequest
} from "./enterprise-operations.js";

const principal = {
  userId: "a0000000-0000-4000-8000-000000000001",
  workspaceId: "b0000000-0000-4000-8000-000000000001",
  role: "owner",
  canPublish: true
} as const;

function capturingClient(row: Record<string, unknown> = { id: "row-1" }) {
  const calls: Array<{ sql: string; params: unknown[] }> = [];
  const client = {
    query: async (sql: string, params: unknown[]) => {
      calls.push({ sql, params });
      return { rows: [row] };
    }
  } as unknown as PoolClient;
  return { client, calls };
}

test("agency client management passes both explicit workspace ids to the bounded helper", async () => {
  const { client, calls } = capturingClient();
  await setAgencyClient(client, principal, {
    clientWorkspaceId: "b0000000-0000-4000-8000-000000000002",
    label: "Client North",
    state: "active"
  });
  assert.match(calls[0]?.sql ?? "", /growth\.set_agency_client/);
  assert.deepEqual(calls[0]?.params, [
    principal.workspaceId,
    "b0000000-0000-4000-8000-000000000002",
    "Client North",
    "active"
  ]);
});

test("consent recording is append-only and preserves the policy version", async () => {
  const { client, calls } = capturingClient();
  await recordWorkspaceConsent(client, principal, {
    consentType: "ai_processing",
    decision: "granted",
    policyVersion: "privacy-v1"
  });
  assert.match(calls[0]?.sql ?? "", /growth\.record_workspace_consent/);
  assert.deepEqual(calls[0]?.params, [
    principal.workspaceId, null, "ai_processing", "granted", "privacy-v1"
  ]);
});

test("deletion remains a two-step request and tombstone workflow", async () => {
  const { client, calls } = capturingClient();
  await createDeletionRequest(client, principal, {
    scope: "workspace",
    targetId: principal.workspaceId,
    manifestVersion: "deletion-v1"
  });
  await tombstoneDeletionRequest(client, principal, "d0000000-0000-4000-8000-000000000001");
  assert.match(calls[0]?.sql ?? "", /growth\.create_deletion_request/);
  assert.match(calls[1]?.sql ?? "", /growth\.tombstone_deletion_request/);
});
