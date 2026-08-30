import type { FastifyRequest } from "fastify";
import { z } from "zod";
import { env } from "./config.js";

const PrincipalSchema = z.object({
  userId: z.string().uuid(),
  workspaceId: z.string().uuid()
});

export type AuthPrincipal = z.infer<typeof PrincipalSchema>;

export function resolvePrincipal(request: FastifyRequest): AuthPrincipal {
  // Production must use a real identity adapter. Header-based identity is intentionally
  // restricted to non-production environments so it cannot become an accidental auth path.
  if (env.NODE_ENV === "production") {
    throw new Error("Production identity adapter is not configured");
  }

  return PrincipalSchema.parse({
    userId: request.headers["x-user-id"],
    workspaceId: request.headers["x-workspace-id"]
  });
}
