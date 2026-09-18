import { z } from "zod";
import type { AutomationActionRequest } from "./automation.js";

const DraftContentPayloadSchema = z.object({
  market: z.string().trim().min(1).max(100),
  language: z.string().trim().min(2).max(20),
  platform_target: z.string().trim().min(1).max(50).optional(),
  objective: z.string().trim().min(1).max(500).optional(),
  body: z.string().min(1).max(100_000),
  structure: z.record(z.string(), z.unknown()).optional()
}).strict();

const PlanExperimentPayloadSchema = z.object({
  name: z.string().trim().min(1).max(160),
  hypothesis: z.string().trim().min(1).max(2000),
  decision_rule: z.string().trim().min(1).max(2000)
}).strict();

const PublishContentPayloadSchema = z.object({
  social_account_id: z.string().uuid(),
  content_version_id: z.string().uuid(),
  media_asset_id: z.string().uuid().optional(),
  request_nonce: z.string().uuid(),
  idempotency_key: z.string().trim().min(1).max(200)
}).strict();

const MultiplyVariantPayloadSchema = z.object({
  experiment_id: z.string().uuid(),
  label: z.string().trim().min(1).max(120),
  lineage: z.record(z.string(), z.unknown()).optional()
}).strict();

export type DraftContentAutomationPayload = z.infer<typeof DraftContentPayloadSchema>;
export type PlanExperimentAutomationPayload = z.infer<typeof PlanExperimentPayloadSchema>;
export type PublishContentAutomationPayload = z.infer<typeof PublishContentPayloadSchema>;
export type MultiplyVariantAutomationPayload = z.infer<typeof MultiplyVariantPayloadSchema>;

export type AutomationExecutionEffects = {
  reviewEvidence(input: { targetRef: string; evidenceRef: string }): Promise<string>;
  draftContent(input: DraftContentAutomationPayload): Promise<string>;
  planExperiment(input: PlanExperimentAutomationPayload & { opportunityId: string }): Promise<string>;
  publishContent(input: PublishContentAutomationPayload): Promise<string>;
  multiplyVariant(input: MultiplyVariantAutomationPayload & { opportunityId: string }): Promise<string>;
};

export type AutomationExecutionOutcome =
  | { status: "succeeded"; resultRef: string; errorClass: null }
  | { status: "needs_input"; resultRef: null; errorClass: "invalid_action_payload" | "evidence_unavailable" };

function payloadNeedsInput(): AutomationExecutionOutcome {
  return { status: "needs_input", resultRef: null, errorClass: "invalid_action_payload" };
}

export async function dispatchApprovedAutomationAction(
  request: AutomationActionRequest,
  effects: AutomationExecutionEffects
): Promise<AutomationExecutionOutcome> {
  if (request.status !== "approved" || request.execution_status !== "executing") {
    throw new Error("automation_request_not_claimed");
  }

  const payload = request.action_payload ?? {};

  if (request.action_code === "review_evidence") {
    if (!request.evidence_ref) {
      return { status: "needs_input", resultRef: null, errorClass: "evidence_unavailable" };
    }
    const resultRef = await effects.reviewEvidence({
      targetRef: request.target_ref,
      evidenceRef: request.evidence_ref
    });
    return { status: "succeeded", resultRef, errorClass: null };
  }

  if (request.action_code === "draft_content") {
    const parsed = DraftContentPayloadSchema.safeParse(payload);
    if (!parsed.success) return payloadNeedsInput();
    const resultRef = await effects.draftContent(parsed.data);
    return { status: "succeeded", resultRef, errorClass: null };
  }

  if (request.action_code === "plan_experiment") {
    const parsed = PlanExperimentPayloadSchema.safeParse(payload);
    if (!parsed.success) return payloadNeedsInput();
    const resultRef = await effects.planExperiment({
      ...parsed.data,
      opportunityId: request.target_ref
    });
    return { status: "succeeded", resultRef, errorClass: null };
  }

  if (request.action_code === "publish_content") {
    const parsed = PublishContentPayloadSchema.safeParse(payload);
    if (!parsed.success) return payloadNeedsInput();
    const resultRef = await effects.publishContent(parsed.data);
    return { status: "succeeded", resultRef, errorClass: null };
  }

  const parsed = MultiplyVariantPayloadSchema.safeParse(payload);
  if (!parsed.success) return payloadNeedsInput();
  const resultRef = await effects.multiplyVariant({
    ...parsed.data,
    opportunityId: request.target_ref
  });
  return { status: "succeeded", resultRef, errorClass: null };
}
