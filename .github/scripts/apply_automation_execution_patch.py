from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    if old not in text:
        raise SystemExit(f"missing patch anchor in {path}: {old[:100]!r}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


# API wiring.
replace_once(
    "apps/api/src/app.ts",
    '} from "./automation.js";\nimport {\n  getEnterprisePolicy,',
    '} from "./automation.js";\nimport { executeApprovedAutomationRequest } from "./automation-runner.js";\nimport {\n  getEnterprisePolicy,'
)
replace_once(
    "apps/api/src/app.ts",
    '  evidence_ref: z.string().trim().min(1).max(1000),\n  note: z.string().trim().max(1000).nullable().optional()\n});',
    '  evidence_ref: z.string().trim().min(1).max(1000),\n  action_payload: z.record(z.string().max(200), z.unknown()).optional(),\n  note: z.string().trim().max(1000).nullable().optional()\n});'
)
replace_once(
    "apps/api/src/app.ts",
    '          evidenceRef: parsed.data.evidence_ref,\n          note: parsed.data.note ?? null\n        })',
    '          evidenceRef: parsed.data.evidence_ref,\n          note: parsed.data.note ?? null,\n          actionPayload: parsed.data.action_payload ?? {}\n        })'
)
commercial_anchor = '\n\n  app.get("/v1/commercial/entitlements", async (request, reply) => {'
execution_route = '''\n\n  app.post("/v1/automation/requests/:id/execute", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const params = AutomationRequestParamsSchema.safeParse(request.params);
    if (!params.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const executed = await executeApprovedAutomationRequest(principal, params.data.id);
      return { status: "processed", request: executed };
    } catch (error) {
      app.log.error({ automationRequestId: params.data.id }, "automation execution claim/finalization failed");
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });
'''
replace_once("apps/api/src/app.ts", commercial_anchor, execution_route + commercial_anchor)

# Web API model and endpoint.
replace_once(
    "apps/web/src/api.ts",
    'export type AutomationActionRequest = {\n  id: string;\n  policy_id: string;',
    'export type AutomationActionRequest = {\n  id: string;\n  workspace_id: string;\n  policy_id: string;'
)
replace_once(
    "apps/web/src/api.ts",
    '  approved_by: string | null;\n  note: string | null;\n  created_at: string;',
    '  approved_by: string | null;\n  note: string | null;\n  action_payload: Record<string, unknown>;\n  execution_status: "not_ready" | "ready" | "executing" | "succeeded" | "needs_input" | "failed";\n  execution_result_ref: string | null;\n  execution_error_class: string | null;\n  execution_started_at: string | null;\n  executed_at: string | null;\n  execution_attempts: number;\n  created_at: string;'
)
replace_once(
    "apps/web/src/api.ts",
    '  evidenceRef: string;\n  note?: string;\n}): Promise<AutomationActionRequest> {',
    '  evidenceRef: string;\n  actionPayload?: Record<string, unknown>;\n  note?: string;\n}): Promise<AutomationActionRequest> {'
)
replace_once(
    "apps/web/src/api.ts",
    '      evidence_ref: input.evidenceRef,\n      note: input.note',
    '      evidence_ref: input.evidenceRef,\n      action_payload: input.actionPayload ?? {},\n      note: input.note'
)
workspace_marker = '\n\nexport type WorkspaceEntitlements = {'
execute_client = '''\n\nexport async function executeAutomationRequest(
  requestId: string
): Promise<AutomationActionRequest> {
  const response = await requestJson<{ status: "processed"; request: AutomationActionRequest }>(
    "/v1/automation/requests/" + encodeURIComponent(requestId) + "/execute",
    { method: "POST" }
  );
  return response.request;
}
'''
replace_once("apps/web/src/api.ts", workspace_marker, execute_client + workspace_marker)

# Web UI import.
replace_once(
    "apps/web/src/main.tsx",
    '  createAutomationRequest,\n  decideAutomationRequest,',
    '  createAutomationRequest,\n  decideAutomationRequest,\n  executeAutomationRequest,'
)

# Replace the automation panel with an executable, explicit-payload UI.
p = Path("apps/web/src/main.tsx")
text = p.read_text(encoding="utf-8")
start = text.index('function AutomationPanel(')
end = text.index('\nfunction CommercialPanel()', start)
new_panel = r'''function AutomationPanel({
  opportunityId,
  evidenceRef,
  market,
  platform,
  socialAccountId
}: {
  opportunityId: string;
  evidenceRef: string | null;
  market: string;
  platform: string;
  socialAccountId: string | null;
}) {
  const [policy, setPolicy] = useState<AutomationPolicy | null>(null);
  const [requests, setRequests] = useState<AutomationActionRequest[]>([]);
  const [actionCode, setActionCode] = useState<AutomationActionRequest["action_code"]>("plan_experiment");
  const [draftLanguage, setDraftLanguage] = useState("");
  const [draftBody, setDraftBody] = useState("");
  const [experimentName, setExperimentName] = useState("");
  const [experimentHypothesis, setExperimentHypothesis] = useState("");
  const [experimentRule, setExperimentRule] = useState("");
  const [publicationContentVersionId, setPublicationContentVersionId] = useState("");
  const [variantExperimentId, setVariantExperimentId] = useState("");
  const [variantLabel, setVariantLabel] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [messageIsError, setMessageIsError] = useState(false);

  async function load() {
    try {
      const [nextPolicy, nextRequests] = await Promise.all([
        fetchAutomationPolicy(),
        fetchAutomationRequests()
      ]);
      setPolicy(nextPolicy);
      setRequests(nextRequests.filter((request) => request.target_ref === opportunityId));
    } catch {
      setMessageIsError(true);
      setMessage("Automation controls are unavailable; no action was queued.");
    }
  }

  useEffect(() => {
    void load();
  }, [opportunityId]);

  function actionPayload(): Record<string, unknown> | null {
    if (actionCode === "review_evidence") return {};
    if (actionCode === "draft_content") {
      if (!draftLanguage.trim() || !draftBody.trim()) {
        setMessage("Draft execution needs a language and an explicit draft brief/body before approval.");
        return null;
      }
      return {
        market,
        language: draftLanguage.trim(),
        platform_target: platform,
        body: draftBody.trim(),
        objective: "Evidence-linked opportunity draft"
      };
    }
    if (actionCode === "plan_experiment") {
      if (!experimentName.trim() || !experimentHypothesis.trim() || !experimentRule.trim()) {
        setMessage("Experiment execution needs a name, hypothesis and decision rule before approval.");
        return null;
      }
      return {
        name: experimentName.trim(),
        hypothesis: experimentHypothesis.trim(),
        decision_rule: experimentRule.trim()
      };
    }
    if (actionCode === "publish_content") {
      if (!socialAccountId || !publicationContentVersionId.trim()) {
        setMessage("Publishing requires this opportunity to be bound to a social account and an explicit approved content version ID.");
        return null;
      }
      return {
        social_account_id: socialAccountId,
        content_version_id: publicationContentVersionId.trim(),
        request_nonce: crypto.randomUUID(),
        idempotency_key: `automation-${opportunityId}-${crypto.randomUUID()}`
      };
    }
    if (!variantExperimentId.trim() || !variantLabel.trim()) {
      setMessage("Variant multiplication needs an explicit experiment ID and variant label.");
      return null;
    }
    return {
      experiment_id: variantExperimentId.trim(),
      label: variantLabel.trim(),
      lineage: { source_opportunity_id: opportunityId, autonomous_publishing: false }
    };
  }

  async function queueRequest() {
    if (!evidenceRef) {
      setMessageIsError(true);
      setMessage("An action needs a stored evidence item before it can be queued.");
      return;
    }
    setMessage(null);
    setMessageIsError(false);
    const payload = actionPayload();
    if (payload === null) {
      setMessageIsError(true);
      return;
    }
    setBusy(true);
    try {
      const created = await createAutomationRequest({
        actionCode,
        targetRef: opportunityId,
        evidenceRef,
        actionPayload: payload,
        note: "Requested from the evidence-linked opportunity view."
      });
      setRequests((current) => [created, ...current]);
      setMessage("Action queued with its execution parameters frozen for approval.");
    } catch {
      setMessageIsError(true);
      setMessage("The request was blocked by policy, evidence, quota, or tenant controls.");
    } finally {
      setBusy(false);
    }
  }

  async function decide(requestId: string, decision: "approve" | "reject") {
    setBusy(true);
    setMessage(null);
    setMessageIsError(false);
    try {
      const updated = await decideAutomationRequest(requestId, decision);
      setRequests((current) => current.map((item) => item.id === updated.id ? updated : item));
      setMessage(decision === "approve"
        ? "Approved. A second explicit Execute action is still required."
        : "Request rejected; it cannot execute.");
    } catch {
      setMessageIsError(true);
      setMessage("Only an owner or admin can approve or reject, and the kill switch always wins.");
    } finally {
      setBusy(false);
    }
  }

  async function execute(requestId: string) {
    setBusy(true);
    setMessage(null);
    setMessageIsError(false);
    try {
      const updated = await executeAutomationRequest(requestId);
      setRequests((current) => current.map((item) => item.id === updated.id ? updated : item));
      if (updated.execution_status === "succeeded") {
        setMessage("Approved action executed. Its result reference is stored in the audit trail.");
      } else if (updated.execution_status === "needs_input") {
        setMessageIsError(true);
        setMessage("Execution stopped safely because the approved request did not contain every required binding.");
      } else if (updated.execution_status === "failed") {
        setMessageIsError(true);
        setMessage("Execution failed safely. No retry is automatic; create a new bounded request after review.");
      }
    } catch {
      setMessageIsError(true);
      setMessage("Execution was blocked because the request was not approved/ready, policy changed, or the kill switch is active.");
    } finally {
      setBusy(false);
    }
  }

  return (
    <section className="detail-section automation-panel">
      <p className="section-kicker">Automation control</p>
      <h3>Approve, then execute a bounded action</h3>
      <p>Approval and execution are separate. Every action keeps its evidence and parameters; provider publishing requires an explicit social account and approved content version.</p>
      <div className="automation-status">
        <span>Mode: {policy ? titleCase(policy.mode) : "Loading"}</span>
        <span>Daily limit: {policy?.daily_request_limit ?? "—"}</span>
        <span className={policy?.kill_switch ? "automation-stop" : "automation-ready"}>
          {policy?.kill_switch ? "Kill switch active" : "Kill switch off"}
        </span>
      </div>
      <div className="automation-request-form">
        <select aria-label="Automation action" value={actionCode} onChange={(event) => setActionCode(event.target.value as AutomationActionRequest["action_code"])}>
          <option value="draft_content">Draft content</option>
          <option value="review_evidence">Review evidence</option>
          <option value="plan_experiment">Plan experiment</option>
          <option value="publish_content">Publish approved content</option>
          <option value="multiply_variant">Multiply variant</option>
        </select>
        {actionCode === "draft_content" && (
          <div className="automation-action-fields">
            <label><span>Language</span><input value={draftLanguage} onChange={(event) => setDraftLanguage(event.target.value)} placeholder="pt-BR, en-US…" maxLength={20} /></label>
            <label><span>Draft brief/body</span><textarea value={draftBody} onChange={(event) => setDraftBody(event.target.value)} maxLength={100000} /></label>
          </div>
        )}
        {actionCode === "plan_experiment" && (
          <div className="automation-action-fields">
            <label><span>Experiment name</span><input value={experimentName} onChange={(event) => setExperimentName(event.target.value)} maxLength={160} /></label>
            <label><span>Hypothesis</span><textarea value={experimentHypothesis} onChange={(event) => setExperimentHypothesis(event.target.value)} maxLength={2000} /></label>
            <label><span>Decision rule</span><textarea value={experimentRule} onChange={(event) => setExperimentRule(event.target.value)} maxLength={2000} /></label>
          </div>
        )}
        {actionCode === "publish_content" && (
          <div className="automation-action-fields">
            <p className="recommendation-muted">Account: {socialAccountId ?? "No account bound to this opportunity"}</p>
            <label><span>Approved content version ID</span><input value={publicationContentVersionId} onChange={(event) => setPublicationContentVersionId(event.target.value)} placeholder="UUID" /></label>
          </div>
        )}
        {actionCode === "multiply_variant" && (
          <div className="automation-action-fields">
            <label><span>Experiment ID</span><input value={variantExperimentId} onChange={(event) => setVariantExperimentId(event.target.value)} placeholder="UUID" /></label>
            <label><span>Variant label</span><input value={variantLabel} onChange={(event) => setVariantLabel(event.target.value)} maxLength={120} /></label>
          </div>
        )}
        <button className="detail-action-button" type="button" disabled={busy || !evidenceRef} onClick={() => void queueRequest()}>
          {busy ? "Saving…" : "Queue for approval"}
        </button>
      </div>
      {requests.length > 0 && (
        <div className="automation-request-list">
          {requests.map((request) => (
            <article className="automation-request-card" key={request.id}>
              <div>
                <strong>{titleCase(request.action_code)}</strong>
                <span>{titleCase(request.status)} · {titleCase(request.execution_status)} · evidence stored</span>
                {request.execution_result_ref && <small>{request.execution_result_ref}</small>}
                {request.execution_error_class && <small>{titleCase(request.execution_error_class)}</small>}
              </div>
              {request.status === "pending" && (
                <div className="recommendation-feedback">
                  <button type="button" disabled={busy} onClick={() => void decide(request.id, "approve")}>Approve</button>
                  <button type="button" disabled={busy} onClick={() => void decide(request.id, "reject")}>Reject</button>
                </div>
              )}
              {request.status === "approved" && request.execution_status === "ready" && (
                <button className="detail-action-button" type="button" disabled={busy} onClick={() => void execute(request.id)}>
                  Execute approved action
                </button>
              )}
            </article>
          ))}
        </div>
      )}
      {!evidenceRef && <p className="recommendation-muted">No stored evidence is available, so automation remains unavailable.</p>}
      {message && <p className={messageIsError ? "recommendation-error" : "experiment-success"} role={messageIsError ? "alert" : "status"}>{message}</p>}
    </section>
  );
}
'''
text = text[:start] + new_panel + text[end:]
p.write_text(text, encoding="utf-8")

# Pass the opportunity binding into the automation surface.
replace_once(
    "apps/web/src/main.tsx",
    '<AutomationPanel opportunityId={opportunity.id} evidenceRef={evidence[0]?.evidence_ref ?? null} />',
    '<AutomationPanel\n        opportunityId={opportunity.id}\n        evidenceRef={evidence[0]?.evidence_ref ?? null}\n        market={opportunity.market}\n        platform={opportunity.platform}\n        socialAccountId={opportunity.social_account_id}\n      />'
)

# Production migration reconciler: recognize forward-only migration 068.
p = Path("db/scripts/apply-production-migrations.mjs")
text = p.read_text(encoding="utf-8")
anchor = "  {\n    file: '067_experiment_variant_status_qualification.sql',"
idx = text.index(anchor)
end_idx = text.index("\n  },", idx) + len("\n  },")
addition = r'''
  {
    file: '068_automation_action_execution.sql',
    present: async () => {
      const claimSignature = 'growth.claim_automation_action_execution(uuid,uuid)';
      const finalizeSignature = 'growth.finalize_automation_action_execution(uuid,uuid,text,text,text)';
      return (await columnExists('automation_action_requests', 'action_payload'))
        && (await columnExists('automation_action_requests', 'execution_status'))
        && (await functionExists(claimSignature))
        && (await functionExists(finalizeSignature));
    },
  },'''
text = text[:end_idx] + "\n" + addition + text[end_idx:]
p.write_text(text, encoding="utf-8")

# CI: make the execution boundary an explicit gate.
ci_anchor = '''      - name: Run automation policy control gate
        env:
          PGPASSWORD: growth_migrator
        run: |
          psql --host=127.0.0.1 --port=5432 --username=growth_migrator --dbname="$CI_DATABASE_NAME" --set=ON_ERROR_STOP=1 --file=db/tests/054_automation_policy_control.sql
'''
ci_add = ci_anchor + '''
      - name: Run automation action execution gate
        env:
          PGPASSWORD: growth_migrator
        run: |
          psql --host=127.0.0.1 --port=5432 --username=growth_migrator --dbname="$CI_DATABASE_NAME" --set=ON_ERROR_STOP=1 --file=db/tests/069_automation_action_execution.sql
'''
replace_once(".github/workflows/ci.yml", ci_anchor, ci_add)

# Release-hardening gate: require the new DB gate and migration safety markers.
replace_once(
    "db/scripts/release-hardening-gate.mjs",
    'for (const gate of ["053_experiment_lineage.sql", "054_automation_policy_control.sql", "055_commercial_entitlements.sql"]) {',
    'for (const gate of ["053_experiment_lineage.sql", "054_automation_policy_control.sql", "055_commercial_entitlements.sql", "069_automation_action_execution.sql"]) {'
)
replace_once(
    "db/scripts/release-hardening-gate.mjs",
    'const commercial = await readFile(join(migrationDir, "038_commercial_entitlements.sql"), "utf8");',
    'const automationExecution = await readFile(join(migrationDir, "068_automation_action_execution.sql"), "utf8");\nfor (const marker of ["execution_status", "claim_automation_action_execution", "finalize_automation_action_execution", "kill switch"]) {\n  if (!automationExecution.includes(marker)) {\n    throw new Error("release hardening: automation execution marker missing " + marker);\n  }\n}\n\nconst commercial = await readFile(join(migrationDir, "038_commercial_entitlements.sql"), "utf8");'
)

print("automation execution patch applied")
