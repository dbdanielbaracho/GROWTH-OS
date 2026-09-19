import type { AuthPrincipal } from "./auth.js";
import {
  claimAutomationActionExecution,
  finalizeAutomationActionExecution,
  type AutomationActionRequest
} from "./automation.js";
import { dispatchApprovedAutomationAction } from "./automation-execution.js";
import { withTenantTransaction } from "./tenant-db.js";
import { createContent } from "./content.js";
import { createExperiment, addExperimentVariant } from "./experiments.js";
import { getOpportunityDetail } from "./intelligence.js";
import { createPublicationIntent, listPublicationIntents } from "./publishing.js";
import { createDatabasePublicationExecutionStore } from "./publication-store.js";
import { createPublicationProviderAdapter } from "./publication-adapter-composition.js";
import { executePublicationIntent } from "./publication-worker.js";

class AutomationPublicationNeedsInputError extends Error {}

function safeExecutionErrorClass(request: AutomationActionRequest): string {
  switch (request.action_code) {
    case "publish_content":
      return "publication_execution_failed";
    case "draft_content":
      return "draft_execution_failed";
    case "plan_experiment":
      return "experiment_execution_failed";
    case "multiply_variant":
      return "variant_execution_failed";
    default:
      return "evidence_review_failed";
  }
}

export async function executeApprovedAutomationRequest(
  principal: AuthPrincipal,
  requestId: string
): Promise<AutomationActionRequest> {
  const claimed = await withTenantTransaction(principal, (client) =>
    claimAutomationActionExecution(client, principal, requestId)
  );

  try {
    const outcome = await dispatchApprovedAutomationAction(claimed, {
      reviewEvidence: async ({ targetRef, evidenceRef }) => {
        const detail = await withTenantTransaction(principal, (client) =>
          getOpportunityDetail(client, principal, targetRef)
        );
        const stored = detail?.evidence.some(
          (evidence) => evidence.evidence_ref === evidenceRef || evidence.id === evidenceRef
        );
        if (!stored) throw new Error("automation_evidence_unavailable");
        return `evidence:${evidenceRef}`;
      },
      draftContent: async (payload) => {
        const created = await withTenantTransaction(principal, (client) =>
          createContent(client, principal, {
            objective: payload.objective,
            market: payload.market,
            language: payload.language,
            platformTarget: payload.platform_target,
            sourceType: "automation",
            body: payload.body,
            structure: {
              ...(payload.structure ?? {}),
              source_opportunity_id: claimed.target_ref,
              source_evidence_ref: claimed.evidence_ref,
              automation_request_id: claimed.id
            },
            aiProvenance: {
              mode: "approval_gated_automation",
              automation_request_id: claimed.id,
              evidence_ref: claimed.evidence_ref
            }
          })
        );
        return `content_version:${created.version.id}`;
      },
      planExperiment: async (payload) => {
        const experiment = await withTenantTransaction(principal, (client) =>
          createExperiment(
            client,
            principal,
            payload.opportunityId,
            payload.name,
            payload.hypothesis,
            payload.decision_rule
          )
        );
        return `experiment:${experiment.id}`;
      },
      publishContent: async (payload) => {
        const intent = await withTenantTransaction(principal, (client) =>
          createPublicationIntent(client, principal, {
            socialAccountId: payload.social_account_id,
            contentVersionId: payload.content_version_id,
            mediaAssetId: payload.media_asset_id,
            requestNonce: payload.request_nonce,
            idempotencyKey: payload.idempotency_key
          })
        );

        const store = createDatabasePublicationExecutionStore(principal, intent.id);
        await executePublicationIntent({
          store,
          adapterFactory: (publication) => createPublicationProviderAdapter(publication)
        });

        const publicationIntents = await withTenantTransaction(principal, (client) =>
          listPublicationIntents(client, principal, 100)
        );
        const processed = publicationIntents.find((candidate) => candidate.id === intent.id);
        if (!processed) throw new Error("automation_publication_result_missing");

        if (processed.status === "confirmed") {
          return `publication_intent:${intent.id}`;
        }

        if (
          processed.status === "needs_user_action"
          || processed.status === "cancelled"
          || processed.status === "superseded"
        ) {
          throw new AutomationPublicationNeedsInputError("publication_needs_user_action");
        }

        throw new Error("automation_publication_not_confirmed");
      },
      multiplyVariant: async (payload) => {
        const variant = await withTenantTransaction(principal, (client) =>
          addExperimentVariant(client, principal, payload.experiment_id, payload.label, {
            ...(payload.lineage ?? {}),
            source_opportunity_id: payload.opportunityId,
            automation_request_id: claimed.id,
            autonomous_publishing: false
          })
        );
        return `experiment_variant:${variant.id}`;
      }
    });

    return await withTenantTransaction(principal, (client) =>
      finalizeAutomationActionExecution(client, principal, claimed.id, {
        executionStatus: outcome.status,
        resultRef: outcome.resultRef,
        errorClass: outcome.errorClass
      })
    );
  } catch (error) {
    if (error instanceof AutomationPublicationNeedsInputError) {
      return await withTenantTransaction(principal, (client) =>
        finalizeAutomationActionExecution(client, principal, claimed.id, {
          executionStatus: "needs_input",
          errorClass: "publication_needs_user_action"
        })
      );
    }

    return await withTenantTransaction(principal, (client) =>
      finalizeAutomationActionExecution(client, principal, claimed.id, {
        executionStatus: "failed",
        errorClass: safeExecutionErrorClass(claimed)
      })
    );
  }
}
