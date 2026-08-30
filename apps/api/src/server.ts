import Fastify from "fastify";
import { checkDatabase } from "./db.js";
import { env } from "./config.js";

const app = Fastify({ logger: true });

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

await app.listen({ port: env.PORT, host: "0.0.0.0" });
