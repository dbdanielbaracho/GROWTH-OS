import type { FastifyInstance } from "fastify";
import { env } from "./config.js";

export type DeploymentInfo = {
  name: "Growth OS";
  version: "0.1.0";
  environment: typeof env.NODE_ENV;
  commit_sha: string | null;
  deployment_id: string | null;
};

export function getDeploymentInfo(): DeploymentInfo {
  return {
    name: "Growth OS",
    version: "0.1.0",
    environment: env.NODE_ENV,
    commit_sha: env.RAILWAY_GIT_COMMIT_SHA ?? null,
    deployment_id: env.RAILWAY_DEPLOYMENT_ID ?? null
  };
}

export function assertRailwayDeploymentIdentity(
  info: DeploymentInfo,
  isRailwayRuntime: boolean
) {
  if (!isRailwayRuntime || info.environment !== "production") return;

  if (!info.commit_sha || !info.deployment_id) {
    throw new Error("Railway production deployment identity is incomplete");
  }
}

export async function registerDeploymentInfoRoute(app: FastifyInstance) {
  app.get("/v1/deployment", async () => getDeploymentInfo());
}
