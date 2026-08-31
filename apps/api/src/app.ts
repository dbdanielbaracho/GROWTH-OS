import Fastify from "fastify";
import { checkDatabase } from "./db.js";
import { env } from "./config.js";
import { resolvePrincipal } from "./auth.js";
import { withTenantTransaction } from "./tenant-db.js";
import { getCurrentMembership, getCurrentWorkspace } from "./workspaces.js";
import { listInsights, listOpportunities } from "./intelligence.js";
import { CreateContentSchema, createContent, listContent } from "./content.js";
import {
  CreateCreativeRequestSchema, createCreativeRequest,
  CreateCreativeGenerationSchema, createCreativeGeneration,
  transitionGeneration, reconcileAmbiguousGeneration,
  CreateMediaAssetSchema, createMediaAsset,
  CreateLineageEdgeSchema, createLineageEdge,
  SourceContextNotFoundError
} from "./creative.js";
import { z } from "zod";

function databaseStatus(error: unknown): { code: number; status: string } {
  const pgCode =
    error && typeof error === "object" && "code" in error
      ? String((error as { code?: unknown }).code ?? "")
      : "";

  if (pgCode === "42501") return { code: 403, status: "forbidden" };
  if (pgCode === "23505" || pgCode === "23503") return { code: 409, status: "conflict" };
  if (pgCode === "P0001") return { code: 409, status: "conflict" }; // business-rule RAISE EXCEPTION (cycle guard, state machine guard)
  if (["08000", "08001", "08003", "08004", "08006", "08007", "08P01", "57P01", "53300"].includes(pgCode)) {
    return { code: 503, status: "service_unavailable" };
  }
  return { code: 500, status: "internal_error" };
}

export function buildApp(logger = false) {
  const app = Fastify({ logger });

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

  app.get("/v1/context", async (request, reply) => {
    try {
      const principal = resolvePrincipal(request);
      const context = await withTenantTransaction(principal, async (client) => {
        const result = await client.query<{ workspace_id: string; user_id: string }>(
          `select current_setting('app.workspace_id', true) as workspace_id,
                  current_setting('app.user_id', true) as user_id`
        );
        return result.rows[0];
      });
      return { status: "ok", context };
    } catch (error) {
      app.log.warn(error);
      return reply.code(401).send({ status: "unauthorized" });
    }
  });

  app.get("/v1/workspace", async (request, reply) => {
    try {
      const principal = resolvePrincipal(request);
      const workspace = await withTenantTransaction(principal, (client) =>
        getCurrentWorkspace(client, principal)
      );
      if (!workspace) return reply.code(404).send({ status: "not_found" });
      return { status: "ok", workspace };
    } catch (error) {
      app.log.warn(error);
      return reply.code(401).send({ status: "unauthorized" });
    }
  });

  app.get("/v1/membership", async (request, reply) => {
    try {
      const principal = resolvePrincipal(request);
      const membership = await withTenantTransaction(principal, (client) =>
        getCurrentMembership(client, principal)
      );
      if (!membership) return reply.code(404).send({ status: "not_found" });
      return { status: "ok", membership };
    } catch (error) {
      app.log.warn(error);
      return reply.code(401).send({ status: "unauthorized" });
    }
  });

  app.get("/v1/opportunities", async (request, reply) => {
    try {
      const principal = resolvePrincipal(request);
      const opportunities = await withTenantTransaction(principal, (client) =>
        listOpportunities(client, principal)
      );
      return { status: "ok", opportunities };
    } catch (error) {
      app.log.warn(error);
      return reply.code(401).send({ status: "unauthorized" });
    }
  });

  app.get("/v1/insights", async (request, reply) => {
    try {
      const principal = resolvePrincipal(request);
      const insights = await withTenantTransaction(principal, (client) =>
        listInsights(client, principal)
      );
      return { status: "ok", insights };
    } catch (error) {
      app.log.warn(error);
      return reply.code(401).send({ status: "unauthorized" });
    }
  });

  app.get("/v1/content", async (request, reply) => {
    let principal;
    try {
      principal = resolvePrincipal(request);
    } catch (error) {
      app.log.warn(error);
      return reply.code(401).send({ status: "unauthorized" });
    }

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
    let principal;
    try {
      principal = resolvePrincipal(request);
    } catch (error) {
      app.log.warn(error);
      return reply.code(401).send({ status: "unauthorized" });
    }

    const parsed = CreateContentSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ status: "invalid_request" });
    }

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

  app.post("/v1/creative/requests", async (request, reply) => {
    let principal;
    try {
      principal = resolvePrincipal(request);
    } catch (error) {
      app.log.warn(error);
      return reply.code(401).send({ status: "unauthorized" });
    }

    const parsed = CreateCreativeRequestSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ status: "invalid_request" });
    }

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
    let principal;
    try {
      principal = resolvePrincipal(request);
    } catch (error) {
      app.log.warn(error);
      return reply.code(401).send({ status: "unauthorized" });
    }

    const parsed = CreateCreativeGenerationSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ status: "invalid_request" });
    }

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
    let principal;
    try {
      principal = resolvePrincipal(request);
    } catch (error) {
      app.log.warn(error);
      return reply.code(401).send({ status: "unauthorized" });
    }

    const parsed = TransitionSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ status: "invalid_request" });
    }

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
    let principal;
    try {
      principal = resolvePrincipal(request);
    } catch (error) {
      app.log.warn(error);
      return reply.code(401).send({ status: "unauthorized" });
    }

    const parsed = ReconcileSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ status: "invalid_request" });
    }

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
    let principal;
    try {
      principal = resolvePrincipal(request);
    } catch (error) {
      app.log.warn(error);
      return reply.code(401).send({ status: "unauthorized" });
    }

    const parsed = CreateMediaAssetSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ status: "invalid_request" });
    }

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
    let principal;
    try {
      principal = resolvePrincipal(request);
    } catch (error) {
      app.log.warn(error);
      return reply.code(401).send({ status: "unauthorized" });
    }

    const parsed = CreateLineageEdgeSchema.safeParse(request.body);
    if (!parsed.success) {
      return reply.code(400).send({ status: "invalid_request" });
    }

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
