import Fastify from "fastify";
import { checkDatabase } from "./db.js";
import { env } from "./config.js";
import { resolvePrincipal } from "./auth.js";
import { withTenantTransaction } from "./tenant-db.js";
import { getCurrentMembership, getCurrentWorkspace } from "./workspaces.js";
import { listInsights, listOpportunities } from "./intelligence.js";

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

  return app;
}
