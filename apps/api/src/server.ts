import { buildApp } from "./app.js";
import { env } from "./config.js";
import { registerProductionWeb } from "./production-web.js";
import { registerYoutubeRoutes } from "./youtube-routes.js";

const app = buildApp(true);
await registerYoutubeRoutes(app);
await registerProductionWeb(app);

await app.listen({ port: env.PORT, host: "0.0.0.0" });
