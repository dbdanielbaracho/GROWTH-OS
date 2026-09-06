import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { resolvePrincipal } from "./auth.js";
import {
  IdentityAuthenticationError,
  IdentityCsrfError,
  IdentityWorkspaceRequiredError
} from "./identity-adapter.js";
import { withTenantTransaction } from "./tenant-db.js";
import {
  InstagramAuthorizeSchema,
  InstagramCallbackQuerySchema,
  InstagramConnectorError,
  beginInstagramAuthorization,
  completeInstagramAuthorizationFromCallback,
  instagramConnectorConfigured
} from "./instagram-connector.js";

type InstagramStatusRow = {
  managed_account_id: string;
  owner_type: string;
  authority_status: string;
  contribution_eligibility: string;
  connection_id: string | null;
  connection_state: string | null;
  connection_updated_at: string | null;
  social_account_id: string | null;
  provider_account_id: string | null;
  handle: string | null;
  account_type: string | null;
  market: string | null;
  source_timezone: string | null;
};

async function principalOrReply(request: FastifyRequest, reply: FastifyReply) {
  try {
    return await resolvePrincipal(request);
  } catch (error) {
    if (error instanceof IdentityCsrfError) {
      await reply.code(403).send({ status: "forbidden" });
      return null;
    }
    if (error instanceof IdentityWorkspaceRequiredError) {
      await reply.code(409).send({ status: "workspace_required" });
      return null;
    }
    if (error instanceof IdentityAuthenticationError) {
      await reply.code(401).send({ status: "unauthorized" });
      return null;
    }
    await reply.code(401).send({ status: "unauthorized" });
    return null;
  }
}

async function integrationError(app: FastifyInstance, reply: FastifyReply, error: unknown) {
  if (error instanceof InstagramConnectorError) {
    return reply.code(error.httpStatus).send({ status: error.code });
  }
  const pgCode = error && typeof error === "object" && "code" in error
    ? String((error as { code?: unknown }).code ?? "")
    : "";
  if (pgCode === "P0001" || pgCode === "23505" || pgCode === "23503") {
    return reply.code(409).send({ status: "instagram_integration_conflict" });
  }
  if (pgCode === "42501") return reply.code(403).send({ status: "forbidden" });
  app.log.error(error);
  return reply.code(500).send({ status: "internal_error" });
}

export async function registerInstagramRoutes(app: FastifyInstance): Promise<void> {
  app.get("/v1/integrations/instagram/status", async (request, reply) => {
    const principal = await principalOrReply(request, reply);
    if (!principal) return;
    try {
      const integrations = await withTenantTransaction(principal, async (client) => {
        const result = await client.query<InstagramStatusRow>(
          "select * from growth.instagram_integration_status()"
        );
        return result.rows;
      });
      reply.header("cache-control", "no-store");
      return {
        status: "ok",
        configured: instagramConnectorConfigured(),
        integrations
      };
    } catch (error) {
      return integrationError(app, reply, error);
    }
  });

  app.post("/v1/integrations/instagram/authorize", async (request, reply) => {
    const principal = await principalOrReply(request, reply);
    if (!principal) return;
    const parsed = InstagramAuthorizeSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });
    try {
      const result = await withTenantTransaction(principal, (client) =>
        beginInstagramAuthorization(client, principal, parsed.data.managedAccountId)
      );
      return { status: "ok", ...result };
    } catch (error) {
      return integrationError(app, reply, error);
    }
  });

  app.get("/v1/integrations/instagram/callback", async (request, reply) => {
    const parsed = InstagramCallbackQuerySchema.safeParse(request.query);
    if (!parsed.success) return reply.code(400).send({ status: "instagram_callback_invalid" });
    if (parsed.data.error) return reply.redirect("/?instagram=denied", 303);
    if (!parsed.data.code) {
      return reply.code(400).send({ status: "instagram_authorization_code_missing" });
    }
    try {
      await completeInstagramAuthorizationFromCallback(parsed.data.state, parsed.data.code);
      return reply.redirect("/?instagram=connected", 303);
    } catch (error) {
      return integrationError(app, reply, error);
    }
  });
}
