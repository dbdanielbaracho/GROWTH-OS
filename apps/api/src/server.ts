import { buildApp } from "./app.js";
import { env } from "./config.js";
import { registerProductionWeb } from "./production-web.js";
import { registerYoutubeRoutes } from "./youtube-routes.js";
import { registerInstagramRoutes } from "./instagram-routes.js";
import {
  assertRailwayDeploymentIdentity,
  getDeploymentInfo,
  registerDeploymentInfoRoute
} from "./deployment-info.js";

const app = buildApp(true);
await registerDeploymentInfoRoute(app);
await registerYoutubeRoutes(app);
await registerInstagramRoutes(app);
await registerProductionWeb(app);

const deploymentInfo = getDeploymentInfo();
const isRailwayRuntime = Boolean(process.env.RAILWAY_PROJECT_ID || process.env.RAILWAY_SERVICE_ID);
assertRailwayDeploymentIdentity(deploymentInfo, isRailwayRuntime);

if (isRailwayRuntime && env.NODE_ENV === "production") {
  app.log.info({
    commit_sha: deploymentInfo.commit_sha,
    deployment_id: deploymentInfo.deployment_id
  }, "verified Railway deployment identity");
}

await app.listen({ port: env.PORT, host: "0.0.0.0" });
