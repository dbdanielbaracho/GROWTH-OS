import assert from "node:assert/strict";
import test from "node:test";
import { randomUUID } from "node:crypto";
import {
  dispatchApprovedAutomationAction,
  type AutomationExecutionEffects
} from "./automation-execution.js";
import type { AutomationActionRequest } from "./automation.js";

function request(overrides: Partial<AutomationActionRequest> = {}): AutomationActionRequest {
  return {
    id: randomUUID(),
    workspace_id: randomUUID(),
    policy_id: randomUUID(),
    action_code: "review_evidence",
    target_ref: randomUUID(),
    evidence_ref: "provider:metric:1",
    status: "approved",
    requested_by: randomUUID(),
    approved_by: randomUUID(),
    note: null,
    action_payload: {},
    execution_status: "executing",
    execution_result_ref: null,
    execution_error_class: null,
    execution_started_at: new Date().toISOString(),
    executed_at: null,
    execution_attempts: 1,
    created_at: new Date().toISOString(),
    decided_at: new Date().toISOString(),
    ...overrides
  };
}

function effects(overrides: Partial<AutomationExecutionEffects> = {}): AutomationExecutionEffects {
  return {
    reviewEvidence: async ({ evidenceRef }) => `evidence:${evidenceRef}`,
    draftContent: async () => `content_version:${randomUUID()}`,
    planExperiment: async () => `experiment:${randomUUID()}`,
    publishContent: async () => `publication_intent:${randomUUID()}`,
    multiplyVariant: async () => `experiment_variant:${randomUUID()}`,
    ...overrides
  };
}

test("review_evidence succeeds only from an approved claimed request", async () => {
  const result = await dispatchApprovedAutomationAction(request(), effects());
  assert.equal(result.status, "succeeded");
  assert.equal(result.resultRef, "evidence:provider:metric:1");

  await assert.rejects(
    () => dispatchApprovedAutomationAction(request({ execution_status: "ready" }), effects()),
    /automation_request_not_claimed/
  );
});

test("draft_content requires a bounded explicit payload", async () => {
  const missing = await dispatchApprovedAutomationAction(
    request({ action_code: "draft_content", action_payload: {} }),
    effects()
  );
  assert.deepEqual(missing, {
    status: "needs_input",
    resultRef: null,
    errorClass: "invalid_action_payload"
  });

  let seenBody = "";
  const valid = await dispatchApprovedAutomationAction(
    request({
      action_code: "draft_content",
      action_payload: {
        market: "BR",
        language: "pt-BR",
        platform_target: "instagram",
        body: "Evidence-linked draft"
      }
    }),
    effects({
      draftContent: async (input) => {
        seenBody = input.body;
        return "content_version:v1";
      }
    })
  );
  assert.equal(valid.status, "succeeded");
  assert.equal(valid.resultRef, "content_version:v1");
  assert.equal(seenBody, "Evidence-linked draft");
});

test("publish_content cannot execute without explicit account/content binding", async () => {
  const missing = await dispatchApprovedAutomationAction(
    request({ action_code: "publish_content", action_payload: {} }),
    effects()
  );
  assert.equal(missing.status, "needs_input");

  const socialAccountId = randomUUID();
  const contentVersionId = randomUUID();
  let publishCalled = false;
  const valid = await dispatchApprovedAutomationAction(
    request({
      action_code: "publish_content",
      action_payload: {
        social_account_id: socialAccountId,
        content_version_id: contentVersionId,
        request_nonce: randomUUID(),
        idempotency_key: "automation-test"
      }
    }),
    effects({
      publishContent: async (input) => {
        publishCalled = input.social_account_id === socialAccountId
          && input.content_version_id === contentVersionId;
        return "publication_intent:published";
      }
    })
  );
  assert.equal(valid.status, "succeeded");
  assert.equal(publishCalled, true);
});

test("plan_experiment and multiply_variant preserve opportunity lineage", async () => {
  const opportunityId = randomUUID();
  let plannedOpportunity = "";
  const planned = await dispatchApprovedAutomationAction(
    request({
      action_code: "plan_experiment",
      target_ref: opportunityId,
      action_payload: {
        name: "Hook test",
        hypothesis: "The evidence-linked change improves the measured signal.",
        decision_rule: "Use provider observations; no winner without evidence."
      }
    }),
    effects({
      planExperiment: async (input) => {
        plannedOpportunity = input.opportunityId;
        return "experiment:e1";
      }
    })
  );
  assert.equal(planned.status, "succeeded");
  assert.equal(plannedOpportunity, opportunityId);

  let variantOpportunity = "";
  const multiplied = await dispatchApprovedAutomationAction(
    request({
      action_code: "multiply_variant",
      target_ref: opportunityId,
      action_payload: {
        experiment_id: randomUUID(),
        label: "Variant B"
      }
    }),
    effects({
      multiplyVariant: async (input) => {
        variantOpportunity = input.opportunityId;
        return "experiment_variant:v2";
      }
    })
  );
  assert.equal(multiplied.status, "succeeded");
  assert.equal(variantOpportunity, opportunityId);
});
