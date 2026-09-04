import { buildApp } from "./app.js";
import { env } from "./config.js";
import { registerProductionWeb } from "./production-web.js";

const app = buildApp(true);
await registerProductionWeb(app);

await app.listen({ port: env.PORT, host: "0.0.0.0" });
