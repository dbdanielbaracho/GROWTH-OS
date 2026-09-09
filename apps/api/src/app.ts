import Fastify from "fastify";
import cookie from "@fastify/cookie";
import { checkDatabase } from "./db.js";
import { env } from "./config.js";
import { resolvePrincipal, type AuthPrincipal } from "./auth.js";
import { withTenantTransaction } from "./tenant-db.js";
import { getCurrentMembership, getCurrentWorkspace } from "./workspaces.js";
import { getOpportunityDetail, listInsights, listOpportunities } from "./intelligence.js";
import { AppendContentVersionSchema, ContentDecisionSchema, ContentNotFoundError, ContentVersionNotFoundError, CreateContentSchema, appendContentVersion, approveContent, createContent, listContent, requestContentChanges } from "./content.js";
import {
  CreateCreativeRequestSchema, createCreativeRequest,
  CreateCreativeGenerationSchema, createCreativeGeneration,
  transitionGeneration, reconcileAmbiguousGeneration,
  CreateMediaAssetSchema, createMediaAsset,
  CreateLineageEdgeSchema, createLineageEdge,
  SourceContextNotFoundError
} from "./creative.js";
import {
  SignInSchema,
  WorkspaceSelectionSchema,
  IdentityAuthenticationError,
  IdentityCsrfError,
  IdentityRateLimitedError,
  IdentityWorkspaceRequiredError,
  signInWithPassword,
  resolveCookieSession,
  selectSessionWorkspace,
  revokeCurrentSession,
  revokeAllSessions,
  setSessionCookies,
  setWorkspaceCookie,
  clearIdentityCookies,
  type IdentitySessionView
} from "./identity-adapter.js";
import { z } from "zod";
import { registerIdentityRoutes } from "./identity-routes.js";
import { CreatePublicationIntentSchema, PublicationReconciliationSchema, cancelPublicationIntent, createPublicationIntent, listPublicationIntents, recordPublicationReconciliation } from "./publishing.js";
import { createDatabasePublicationExecutionStore } from "./publication-store.js";
import { createPublicationProviderAdapter } from "./publication-adapter-composition.js";
import { listMetricAnalyticsSummary, listMetricQualityAnomalies } from "./analytics.js";
import { createRecommendation, listRecommendations, recordRecommendationFeedback } from "./recommendations.js";
import { addExperimentVariant, createExperiment, listExperiments, recordExperimentFeedback } from "./experiments.js";
import { executePublicationIntent } from "./publication-worker.js";

function databaseStatus(error: unknown): { code: number; status: string } {
  const pgCode =
    error && typeof error === "object" && "code" in error
      ? String((error as { code?: unknown }).code ?? "")
      : "";

  if (pgCode === "42501") return { code: 403, status: "forbidden" };
  if (pgCode === "23505" || pgCode === "23503") return { code: 409, status: "conflict" };
  if (pgCode === "P0001") return { code: 409, status: "conflict" };
  if (["08000", "08001", "08003", "08004", "08006", "08007", "08P01", "57P01", "53300"].includes(pgCode)) {
    return { code: 503, status: "service_unavailable" };
  }
  return { code: 500, status: "internal_error" };
}

function identityStatus(error: unknown): { code: number; status: string } | null {
  if (error instanceof IdentityRateLimitedError) return { code: 429, status: "rate_limited" };
  if (error instanceof IdentityCsrfError) return { code: 403, status: "forbidden" };
  if (error instanceof IdentityWorkspaceRequiredError) return { code: 409, status: "workspace_required" };
  if (error instanceof IdentityAuthenticationError) {
    if (error.message === "password_change_required") {
      return { code: 403, status: "password_change_required" };
    }
    return { code: 401, status: "unauthorized" };
  }
  return null;
}

function publicSession(view: IdentitySessionView) {
  return {
    user_id: view.session.userId,
    amr: view.session.amr,
    absolute_expires_at: view.session.absoluteExpiresAt,
    idle_expires_at: view.session.idleExpiresAt
  };
}

const OpportunityParamsSchema = z.object({
  id: z.string().uuid()
});

const PublicationIntentParamsSchema = z.object({
  id: z.string().uuid()
});

const AnalyticsQuerySchema = z.object({
  from: z.string().trim().optional(),
  to: z.string().trim().optional()
});

const RecommendationQuerySchema = z.object({
  opportunity_id: z.string().uuid().optional()
});

const RecommendationParamsSchema = z.object({
  id: z.string().uuid()
});

const RecommendationCreateSchema = z.object({
  action_code: z.enum(["draft_content", "review_evidence", "plan_experiment"])
});

const RecommendationFeedbackSchema = z.object({
  feedback: z.enum(["accepted", "dismissed", "completed", "irrelevant"]),
  note: z.string().trim().max(1000).nullable().optional()
});

const ExperimentCreateSchema = z.object({
  opportunity_id: z.string().uuid().nullable().optional(),
  name: z.string().trim().min(1).max(160),
  hypothesis: z.string().trim().min(1).max(2000),
  decision_rule: z.string().trim().min(1).max(2000)
});

const ExperimentVariantSchema = z.object({
  label: z.string().trim().min(1).max(120),
  lineage: z.record(z.string(), z.unknown())
});

const ExperimentFeedbackSchema = z.object({
  variant_id: z.string().uuid(),
  outcome: z.enum(["winner", "loser", "inconclusive"]),
  evidence_ref: z.string().trim().max(1000).nullable().optional(),
  note: z.string().trim().max(1000).nullable().optional()
});

export function buildApp(logger = false) {
  const app = Fastify({
    logger: logger ? {
      redact: {
        paths: [
          "req.headers.cookie",
          "req.headers.authorization",
          "req.headers.x-csrf-token",
          "req.body.password",
          "req.body.token",
          "res.headers.set-cookie"
        ],
        censor: "[Redacted]"
      }
    } : false
  });

  app.register(cookie);
  registerIdentityRoutes(app);

  async function requestPrincipal(request: Parameters<typeof resolvePrincipal>[0], reply: any): Promise<AuthPrincipal | null> {
    try {
      return await resolvePrincipal(request);
    } catch (error) {
      app.log.warn(error);
      const mapped = identityStatus(error) ?? { code: 401, status: "unauthorized" };
      await reply.code(mapped.code).send({ status: mapped.status });
      return null;
    }
  }

  app.get("/health/live", async () => ({ status: "ok" }));

  app.get("/health/ready", async (_request, reply) => {
    try {
      await checkDatabase();
      return { status: "ready", database: "ok" };
    } catch (error) {
      app.log.error(error);
      return reply.code(503).send({ status: "not_ready", database: "unavailable" });
    }
  });

  app.get("/v1/system", async () => ({
    name: "Growth OS",
    version: "0.1.0",
    environment: env.NODE_ENV
  }));

  app.post("/v1/auth/signin", async (request, reply) => {
    const parsed = SignInSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const signedIn = await signInWithPassword(parsed.data.email, parsed.data.password, request);
      setSessionCookies(
        reply,
        signedIn.rawSessionToken,
        signedIn.session.absoluteExpiresAt,
        signedIn.selectedWorkspace?.id ?? null
      );
      return {
        status: "ok",
        session: publicSession(signedIn),
        workspaces: signedIn.workspaces,
        selected_workspace: signedIn.selectedWorkspace,
        csrf_token: signedIn.csrfToken
      };
    } catch (error) {
      const mapped = identityStatus(error);
      if (mapped) return reply.code(mapped.code).send({ status: mapped.status });
      app.log.error(error);
      return reply.code(500).send({ status: "internal_error" });
    }
  });

  app.get("/v1/auth/session", async (request, reply) => {
    try {
      const view = await resolveCookieSession(request, { requireWorkspace: false, enforceCsrf: false });
      return {
        status: "ok",
        session: publicSession(view),
        workspaces: view.workspaces,
        selected_workspace: view.selectedWorkspace,
        csrf_token: view.csrfToken
      };
    } catch (error) {
      const mapped = identityStatus(error) ?? { code: 401, status: "unauthorized" };
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/auth/workspace", async (request, reply) => {
    const parsed = WorkspaceSelectionSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const view = await selectSessionWorkspace(request, parsed.data.workspaceId);
      if (!view.selectedWorkspace) throw new IdentityAuthenticationError("workspace_not_authorized");
      setWorkspaceCookie(reply, view.selectedWorkspace.id, view.session.absoluteExpiresAt);
      return {
        status: "ok",
        session: publicSession(view),
        workspaces: view.workspaces,
        selected_workspace: view.selectedWorkspace,
        csrf_token: view.csrfToken
      };
    } catch (error) {
      const mapped = identityStatus(error) ?? { code: 401, status: "unauthorized" };
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/auth/signout", async (request, reply) => {
    try {
      await revokeCurrentSession(request);
      clearIdentityCookies(reply);
      return reply.code(204).send();
    } catch (error) {
      clearIdentityCookies(reply);
      const mapped = identityStatus(error) ?? { code: 401, status: "unauthorized" };
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/auth/signout-all", async (request, reply) => {
    try {
      const revoked = await revokeAllSessions(request);
      clearIdentityCookies(reply);
      return { status: "ok", revoked_sessions: revoked };
    } catch (error) {
      clearIdentityCookies(reply);
      const mapped = identityStatus(error) ?? { code: 401, status: "unauthorized" };
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.get("/v1/context", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    try {
      const context = await withTenantTransaction(principal, async (client) => {
        const result = await client.query<{ workspace_id: string; user_id: string }>(
          `select current_setting('app.workspace_id', true) as workspace_id,
                  current_setting('app.user_id', true) as user_id`
        );
        return result.rows[0];
      });
      return { status: "ok", context };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.get("/v1/workspace", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    try {
      const workspace = await withTenantTransaction(principal, (client) =>
        getCurrentWorkspace(client, principal)
      );
      if (!workspace) return reply.code(404).send({ status: "not_found" });
      return { status: "ok", workspace };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.get("/v1/membership", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    try {
      const membership = await withTenantTransaction(principal, (client) =>
        getCurrentMembership(client, principal)
      );
      if (!membership) return reply.code(404).send({ status: "not_found" });
      return { status: "ok", membership };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.get("/v1/opportunities", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    try {
      const opportunities = await withTenantTransaction(principal, (client) =>
        listOpportunities(client, principal)
      );
      return { status: "ok", opportunities };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.get("/v1/opportunities/:id", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = OpportunityParamsSchema.safeParse(request.params);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const detail = await withTenantTransaction(principal, (client) =>
        getOpportunityDetail(client, principal, parsed.data.id)
      );
      if (!detail) return reply.code(404).send({ status: "not_found" });
      return { status: "ok", ...detail };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });



  app.get("/v1/recommendations", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = RecommendationQuerySchema.safeParse(request.query);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const recommendations = await withTenantTransaction(principal, (client) =>
        listRecommendations(client, principal, parsed.data.opportunity_id ?? null)
      );
      return { status: "ok", recommendations };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/opportunities/:id/recommendations", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const params = RecommendationParamsSchema.safeParse(request.params);
    const body = RecommendationCreateSchema.safeParse(request.body);
    if (!params.success || !body.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const recommendation = await withTenantTransaction(principal, (client) =>
        createRecommendation(client, principal, params.data.id, body.data.action_code)
      );
      return reply.code(201).send({ status: "created", recommendation });
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/recommendations/:id/feedback", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const params = RecommendationParamsSchema.safeParse(request.params);
    const body = RecommendationFeedbackSchema.safeParse(request.body);
    if (!params.success || !body.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const feedback = await withTenantTransaction(principal, (client) =>
        recordRecommendationFeedback(
          client,
          principal,
          params.data.id,
          body.data.feedback,
          body.data.note ?? null
        )
      );
      return { status: "recorded", feedback };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });



  app.get("/v1/experiments", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    try {
      const experiments = await withTenantTransaction(principal, (client) =>
        listExperiments(client, principal)
      );
      return { status: "ok", experiments };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/experiments", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = ExperimentCreateSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const experiment = await withTenantTransaction(principal, (client) =>
        createExperiment(
          client,
          principal,
          parsed.data.opportunity_id ?? null,
          parsed.data.name,
          parsed.data.hypothesis,
          parsed.data.decision_rule
        )
      );
      return reply.code(201).send({ status: "created", experiment });
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/experiments/:id/variants", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const params = RecommendationParamsSchema.safeParse(request.params);
    const parsed = ExperimentVariantSchema.safeParse(request.body);
    if (!params.success || !parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const variant = await withTenantTransaction(principal, (client) =>
        addExperimentVariant(client, principal, params.data.id, parsed.data.label, parsed.data.lineage)
      );
      return reply.code(201).send({ status: "created", variant });
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/experiments/:id/feedback", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const params = RecommendationParamsSchema.safeParse(request.params);
    const parsed = ExperimentFeedbackSchema.safeParse(request.body);
    if (!params.success || !parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const feedback = await withTenantTransaction(principal, (client) =>
        recordExperimentFeedback(
          client,
          principal,
          params.data.id,
          parsed.data.variant_id,
          parsed.data.outcome,
          parsed.data.evidence_ref ?? null,
          parsed.data.note ?? null
        )
      );
      return { status: "recorded", feedback };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.get("/v1/insights", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    try {
      const insights = await withTenantTransaction(principal, (client) =>
        listInsights(client, principal)
      );
      return { status: "ok", insights };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.get("/v1/analytics/metrics", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = AnalyticsQuerySchema.safeParse(request.query);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    const to = parsed.data.to ? new Date(parsed.data.to) : new Date();
    const from = parsed.data.from
      ? new Date(parsed.data.from)
      : new Date(to.getTime() - 7 * 24 * 60 * 60 * 1000);
    const windowMs = to.getTime() - from.getTime();

    if (
      Number.isNaN(from.getTime()) ||
      Number.isNaN(to.getTime()) ||
      windowMs <= 0 ||
      windowMs > 366 * 24 * 60 * 60 * 1000
    ) {
      return reply.code(400).send({ status: "invalid_analytics_window" });
    }

    try {
      const metrics = await withTenantTransaction(principal, (client) =>
        listMetricAnalyticsSummary(client, principal, from.toISOString(), to.toISOString())
      );
      return {
        status: "ok",
        from: from.toISOString(),
        to: to.toISOString(),
        metrics
      };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });


  app.get("/v1/analytics/anomalies", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = AnalyticsQuerySchema.safeParse(request.query);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    const to = parsed.data.to ? new Date(parsed.data.to) : new Date();
    const from = parsed.data.from
      ? new Date(parsed.data.from)
      : new Date(to.getTime() - 7 * 24 * 60 * 60 * 1000);
    const windowMs = to.getTime() - from.getTime();

    if (
      Number.isNaN(from.getTime()) ||
      Number.isNaN(to.getTime()) ||
      windowMs <= 0 ||
      windowMs > 366 * 24 * 60 * 60 * 1000
    ) {
      return reply.code(400).send({ status: "invalid_analytics_window" });
    }

    try {
      const anomalies = await withTenantTransaction(principal, (client) =>
        listMetricQualityAnomalies(client, principal, from.toISOString(), to.toISOString())
      );
      return {
        status: "ok",
        from: from.toISOString(),
        to: to.toISOString(),
        anomalies
      };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.get("/v1/content", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    try {
      const content = await withTenantTransaction(principal, (client) =>
        listContent(client, principal)
      );
      return { status: "ok", content };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/content", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = CreateContentSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const created = await withTenantTransaction(principal, (client) =>
        createContent(client, principal, parsed.data)
      );
      return reply.code(201).send({ status: "created", ...created });
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/content/:id/versions", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = AppendContentVersionSchema.safeParse({
      ...(request.body as Record<string, unknown>),
      contentItemId: (request.params as { id: string }).id
    });
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const created = await withTenantTransaction(principal, (client) =>
        appendContentVersion(client, principal, parsed.data)
      );
      return reply.code(201).send({ status: "created", ...created });
    } catch (error) {
      if (error instanceof ContentNotFoundError) {
        return reply.code(404).send({ status: "not_found" });
      }
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/content/versions/:id/approve", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = ContentDecisionSchema.safeParse({
      ...(request.body as Record<string, unknown>),
      contentVersionId: (request.params as { id: string }).id
    });
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const decision = await withTenantTransaction(principal, (client) =>
        approveContent(client, principal, parsed.data)
      );
      return { status: "ok", ...decision };
    } catch (error) {
      if (error instanceof ContentVersionNotFoundError) {
        return reply.code(404).send({ status: "not_found" });
      }
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/content/versions/:id/request-changes", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = ContentDecisionSchema.safeParse({
      ...(request.body as Record<string, unknown>),
      contentVersionId: (request.params as { id: string }).id
    });
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const decision = await withTenantTransaction(principal, (client) =>
        requestContentChanges(client, principal, parsed.data)
      );
      return { status: "ok", ...decision };
    } catch (error) {
      if (error instanceof ContentVersionNotFoundError) {
        return reply.code(404).send({ status: "not_found" });
      }
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.get("/v1/publication-intents", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    try {
      const publicationIntents = await withTenantTransaction(principal, (client) =>
        listPublicationIntents(client, principal)
      );
      return { status: "ok", publicationIntents };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/publication-intents", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = CreatePublicationIntentSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const intent = await withTenantTransaction(principal, (client) =>
        createPublicationIntent(client, principal, parsed.data)
      );
      return reply.code(201).send({ status: "created", publicationIntent: intent });
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/publication-intents/:id/execute", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = PublicationIntentParamsSchema.safeParse(request.params);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const store = createDatabasePublicationExecutionStore(
        principal,
        parsed.data.id
      );
      const publicationIntent = await executePublicationIntent({
        store,
        adapterFactory: (claimed) => createPublicationProviderAdapter(claimed)
      });
      return { status: "processed", publicationIntent };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/publication-intents/:id/cancel", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = PublicationIntentParamsSchema.safeParse(request.params);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const publicationIntent = await withTenantTransaction(principal, (client) =>
        cancelPublicationIntent(client, principal, parsed.data.id)
      );
      return { status: "cancelled", publicationIntent };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/publication-intents/:id/reconcile", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const params = PublicationIntentParamsSchema.safeParse(request.params);
    const parsed = PublicationReconciliationSchema.safeParse(request.body);
    if (!params.success || !parsed.success) {
      return reply.code(400).send({ status: "invalid_request" });
    }

    try {
      const reconciliation = await withTenantTransaction(principal, (client) =>
        recordPublicationReconciliation(
          client,
          principal,
          params.data.id,
          parsed.data
        )
      );
      return { status: "reconciled", reconciliation };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/creative/requests", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = CreateCreativeRequestSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const created = await withTenantTransaction(principal, (client) =>
        createCreativeRequest(client, principal, parsed.data)
      );
      return reply.code(201).send({ status: "created", creativeRequest: created });
    } catch (error) {
      if (error instanceof SourceContextNotFoundError) {
        return reply.code(422).send({ status: "invalid_source_context" });
      }
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/creative/generations", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = CreateCreativeGenerationSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const created = await withTenantTransaction(principal, (client) =>
        createCreativeGeneration(client, principal, parsed.data)
      );
      return reply.code(201).send({ status: "created", creativeGeneration: created });
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  const TransitionSchema = z.object({
    status: z.enum(["requested", "queued", "processing", "succeeded", "failed", "cancelled", "ambiguous"]),
    externalHandle: z.string().max(500).optional(),
    errorClass: z.string().max(200).optional()
  });

  app.patch("/v1/creative/generations/:id", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = TransitionSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const updated = await withTenantTransaction(principal, (client) =>
        transitionGeneration(client, principal, (request.params as { id: string }).id, parsed.data.status, {
          externalHandle: parsed.data.externalHandle,
          errorClass: parsed.data.errorClass
        })
      );
      return { status: "ok", creativeGeneration: updated };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  const ReconcileSchema = z.object({
    resolvedStatus: z.enum(["succeeded", "failed"])
  });

  app.post("/v1/creative/generations/:id/reconcile", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = ReconcileSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const resolved = await withTenantTransaction(principal, (client) =>
        reconcileAmbiguousGeneration(
          client, principal, (request.params as { id: string }).id, parsed.data.resolvedStatus, principal.userId
        )
      );
      return { status: "ok", creativeGeneration: resolved };
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/media-assets", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = CreateMediaAssetSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const created = await withTenantTransaction(principal, (client) =>
        createMediaAsset(client, principal, parsed.data)
      );
      return reply.code(201).send({ status: "created", mediaAsset: created });
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/media-assets/lineage", async (request, reply) => {
    const principal = await requestPrincipal(request, reply);
    if (!principal) return;

    const parsed = CreateLineageEdgeSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const created = await withTenantTransaction(principal, (client) =>
        createLineageEdge(client, principal, parsed.data)
      );
      return reply.code(201).send({ status: "created", lineageEdge: created });
    } catch (error) {
      app.log.error(error);
      const mapped = databaseStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  return app;
}
