import type { FastifyInstance } from "fastify";
import { env } from "./config.js";

export async function registerDeploymentInfoRoute(app: FastifyInstance) {
  app.get("/v1/deployment", async () => ({
    name: "Growth OS",
    version: "0.1.0",
    environment: env.NODE_ENV,
    commit_sha: env.RAILWAY_GIT_COMMIT_SHA ?? null,
    deployment_id: env.RAILWAY_DEPLOYMENT_ID ?? null
  }));
}
