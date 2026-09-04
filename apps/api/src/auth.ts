import type { FastifyRequest } from "fastify";
import { z } from "zod";
import { env } from "./config.js";
import { resolveCookieSession } from "./identity-adapter.js";

const PrincipalSchema = z.object({
  userId: z.string().uuid(),
  workspaceId: z.string().uuid(),
  sessionId: z.string().uuid().optional()
});

export type AuthPrincipal = z.infer<typeof PrincipalSchema>;

function developmentHeaderPrincipal(request: FastifyRequest): AuthPrincipal | null {
  if (env.NODE_ENV === "production") return null;

  const parsed = PrincipalSchema.safeParse({
    userId: request.headers["x-user-id"],
    workspaceId: request.headers["x-workspace-id"]
  });
  return parsed.success ? parsed.data : null;
}

export async function resolvePrincipal(request: FastifyRequest): Promise<AuthPrincipal> {
  const developmentPrincipal = developmentHeaderPrincipal(request);
  if (developmentPrincipal) return developmentPrincipal;

  const view = await resolveCookieSession(request, {
    requireWorkspace: true,
    enforceCsrf: true
  });

  if (!view.selectedWorkspace) {
    throw new Error("authenticated session did not resolve a workspace");
  }

  return PrincipalSchema.parse({
    userId: view.session.userId,
    workspaceId: view.selectedWorkspace.id,
    sessionId: view.session.sessionId
  });
}
