import type { FastifyInstance, FastifyRequest } from "fastify";

export type OperationalSloClass = "health" | "identity" | "provider" | "tenant_api" | "unmatched";

export function operationalRoute(request: Pick<FastifyRequest, "routeOptions">): string {
  const configured = request.routeOptions?.url;
  return typeof configured === "string" && configured.startsWith("/") ? configured : "unmatched";
}

export function operationalSloClass(route: string): OperationalSloClass {
  if (route.startsWith("/health/") || route === "/v1/deployment" || route === "/v1/system") return "health";
  if (route.startsWith("/v1/auth/") || route.startsWith("/v1/identity/")) return "identity";
  if (route.startsWith("/v1/integrations/") || route.startsWith("/v1/publication-intents")) return "provider";
  if (route.startsWith("/v1/")) return "tenant_api";
  return "unmatched";
}

export function operationalSeverity(statusCode: number): "info" | "warn" | "error" {
  if (statusCode >= 500) return "error";
  if (statusCode >= 400) return "warn";
  return "info";
}

export function registerOperationalTelemetry(app: FastifyInstance): void {
  const starts = new WeakMap<FastifyRequest, bigint>();

  app.addHook("onRequest", async (request) => {
    starts.set(request, process.hrtime.bigint());
  });

  app.addHook("onResponse", async (request, reply) => {
    const startedAt = starts.get(request);
    const durationMs = startedAt
      ? Number(process.hrtime.bigint() - startedAt) / 1_000_000
      : 0;
    const route = operationalRoute(request);
    const fields = {
      event: "operational_request",
      method: request.method,
      route,
      status_code: reply.statusCode,
      duration_ms: Number(durationMs.toFixed(3)),
      slo_class: operationalSloClass(route)
    };
    const severity = operationalSeverity(reply.statusCode);
    app.log[severity](fields, "operational request completed");
  });
}
