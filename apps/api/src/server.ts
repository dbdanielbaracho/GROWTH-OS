import { buildApp } from "./app.js";
import { env } from "./config.js";
import { registerProductionWeb } from "./production-web.js";
import { registerYoutubeRoutes } from "./youtube-routes.js";
import { registerInstagramRoutes } from "./instagram-routes.js";
import { registerDeploymentInfoRoute } from "./deployment-info.js";

const app = buildApp(true);
await registerDeploymentInfoRoute(app);
await registerYoutubeRoutes(app);
await registerInstagramRoutes(app);
await registerProductionWeb(app);

await app.listen({ port: env.PORT, host: "0.0.0.0" });
