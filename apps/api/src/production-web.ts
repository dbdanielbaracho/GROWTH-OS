import { access } from "node:fs/promises";
import { constants } from "node:fs";
import { join } from "node:path";
import { fileURLToPath } from "node:url";
import fastifyStatic from "@fastify/static";
import type { FastifyInstance } from "fastify";
import { env } from "./config.js";

const WEB_ROOT = fileURLToPath(new URL("../../web/dist/", import.meta.url));
const CSP = [
  "default-src 'self'",
  "base-uri 'self'",
  "object-src 'none'",
  "frame-ancestors 'none'",
  "form-action 'self'",
  "script-src 'self'",
  "style-src 'self'",
  "img-src 'self' data:",
  "font-src 'self' data:",
  "connect-src 'self'",
  "manifest-src 'self'",
  "worker-src 'self'",
  "upgrade-insecure-requests"
].join("; ");

export async function registerProductionWeb(app: FastifyInstance): Promise<void> {
  if (env.NODE_ENV !== "production") return;

  // A production API process without the reviewed web build must fail startup
  // rather than silently expose API-only auth on a different-origin topology.
  await access(join(WEB_ROOT, "index.html"), constants.R_OK);

  await app.register(async function productionWebScope(scope) {
    scope.addHook("onSend", async (request, reply, payload) => {
      reply.header("Content-Security-Policy", CSP);
      reply.header("Strict-Transport-Security", "max-age=31536000; includeSubDomains");
      reply.header("X-Content-Type-Options", "nosniff");
      reply.header("X-Frame-Options", "DENY");
      reply.header("Referrer-Policy", "strict-origin-when-cross-origin");
      reply.header("Permissions-Policy", "camera=(), microphone=(), geolocation=()");
      reply.header("Cross-Origin-Opener-Policy", "same-origin");
      reply.header("Cross-Origin-Resource-Policy", "same-origin");

      if (request.url === "/" || request.url.endsWith(".html")) {
        reply.header("Cache-Control", "no-store");
      } else if (request.url.startsWith("/assets/")) {
        reply.header("Cache-Control", "public, max-age=31536000, immutable");
      }

      return payload;
    });

    await scope.register(fastifyStatic, {
      root: WEB_ROOT,
      prefix: "/",
      index: ["index.html"]
    });
  });
}
