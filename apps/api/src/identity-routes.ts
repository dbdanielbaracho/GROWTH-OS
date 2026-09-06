import type { FastifyInstance, FastifyReply, FastifyRequest } from "fastify";
import { randomBytes, createHash } from "node:crypto";
import { z } from "zod";
import { env } from "./config.js";
import { db } from "./db.js";
import {
  assertTrustedOrigin,
  IdentityCsrfError,
  hashIdentityPassword,
  hashIdentityToken,
  resolveCookieSession,
  requestClientIp,
  setWorkspaceCookie,
  type IdentitySessionView
} from "./identity-adapter.js";
import { withTenantTransaction, withUserTransaction } from "./tenant-db.js";
import { getActiveWorkspaceForUser } from "./workspaces.js";
import { IdentityEmailUnavailableError, sendIdentityEmail } from "./identity-email.js";

const SignupSchema = z.object({
  email: z.string().trim().min(3).max(320).email(),
  password: z.string().min(12).max(1024)
});

const TokenSchema = z.object({
  token: z.string().min(32).max(512)
});

const WorkspaceCreateSchema = z.object({
  name: z.string().trim().min(2).max(160),
  defaultMarket: z.string().trim().min(2).max(16),
  defaultLanguage: z.string().trim().min(2).max(16),
  defaultTimezone: z.string().trim().min(1).max(80)
});

const InvitationSchema = z.object({
  email: z.string().trim().min(3).max(320).email(),
  role: z.enum(["admin", "editor", "viewer"]),
  canPublish: z.boolean().default(false)
});

const PasswordResetRequestSchema = z.object({
  email: z.string().trim().min(3).max(320).email()
});

const PasswordResetCompleteSchema = z.object({
  token: z.string().min(32).max(512),
  password: z.string().min(12).max(1024)
});

function oneTimeToken(): { raw: string; hash: string } {
  const raw = randomBytes(32).toString("base64url");
  return { raw, hash: hashIdentityToken(raw) };
}

function errorStatus(error: unknown): { code: number; status: string } {
  if (error instanceof IdentityCsrfError) {
    return { code: 403, status: "forbidden" };
  }
  if (error instanceof IdentityEmailUnavailableError) {
    return { code: 503, status: "identity_email_unavailable" };
  }
  if (error instanceof Error && /already|duplicate|invalid|expired|denied|required|verified/.test(error.message)) {
    return { code: 409, status: "identity_request_rejected" };
  }
  return { code: 500, status: "internal_error" };
}

function verificationUrl(token: string): string {
  const url = new URL("/verify-email", env.APP_ORIGIN);
  url.searchParams.set("token", token);
  return url.toString();
}

function passwordResetUrl(token: string): string {
  const url = new URL("/reset-password", env.APP_ORIGIN);
  url.searchParams.set("token", token);
  return url.toString();
}

async function requireSessionWithoutWorkspace(
  request: FastifyRequest,
  enforceCsrf: boolean
): Promise<IdentitySessionView> {
  return resolveCookieSession(request, { requireWorkspace: false, enforceCsrf });
}

export function registerIdentityRoutes(app: FastifyInstance): void {
  app.post("/v1/auth/signup", async (request, reply) => {
    const parsed = SignupSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });
    if (env.NODE_ENV === "production") assertTrustedOrigin(request);

    const passwordHash = await hashIdentityPassword(parsed.data.password);
    const token = oneTimeToken();
    const expiresAt = new Date(Date.now() + 24 * 60 * 60 * 1000);

    try {
      const result = await db.query<{ user_id: string; verification_id: string }>(
        `select * from growth.identity_signup_with_verification($1,$2,$3,$4,$5)`,
        [parsed.data.email, passwordHash, 19, token.hash, expiresAt.toISOString()]
      );
      const created = result.rows[0];
      if (!created) return reply.code(500).send({ status: "internal_error" });

      await sendIdentityEmail({
        to: parsed.data.email,
        subject: "Verify your Growth OS email",
        html: `<p>Verify your Growth OS account:</p><p><a href="${verificationUrl(token.raw)}">Verify email</a></p>`
      });

      return reply.code(202).send({ status: "verification_required" });
    } catch (error) {
      const mapped = errorStatus(error);
      if (mapped.code === 500) app.log.error(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/auth/verify-email", async (request, reply) => {
    const parsed = TokenSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });
    if (env.NODE_ENV === "production") assertTrustedOrigin(request);

    try {
      const result = await db.query<{ user_id: string }>(
        "select growth.identity_consume_email_verification($1) as user_id",
        [hashIdentityToken(parsed.data.token)]
      );
      return { status: "verified", user_id: result.rows[0]?.user_id };
    } catch (error) {
      const mapped = errorStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.get("/v1/workspaces", async (request, reply) => {
    try {
      const view = await requireSessionWithoutWorkspace(request, false);
      return { status: "ok", workspaces: view.workspaces };
    } catch {
      return reply.code(401).send({ status: "unauthorized" });
    }
  });

  app.post("/v1/workspaces", async (request, reply) => {
    const parsed = WorkspaceCreateSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const view = await requireSessionWithoutWorkspace(request, true);
      const created = await withUserTransaction(view.session.userId, async (client) => {
        const result = await client.query<{ workspace_id: string }>(
          `select growth.identity_create_workspace($1,$2,$3,$4) as workspace_id`,
          [
            parsed.data.name,
            parsed.data.defaultMarket,
            parsed.data.defaultLanguage,
            parsed.data.defaultTimezone
          ]
        );
        return result.rows[0]?.workspace_id ?? null;
      });
      if (!created) return reply.code(500).send({ status: "internal_error" });
      setWorkspaceCookie(reply, created, view.session.absoluteExpiresAt);
      return { status: "created", workspace_id: created };
    } catch (error) {
      const mapped = errorStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/workspaces/:workspaceId/invitations", async (request, reply) => {
    const parsed = InvitationSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const view = await requireSessionWithoutWorkspace(request, true);
      const workspaceIdResult = z.string().uuid().safeParse((request.params as { workspaceId?: string }).workspaceId);
      if (!workspaceIdResult.success) return reply.code(400).send({ status: "invalid_request" });
      const workspaceId = workspaceIdResult.data;
      if (view.selectedWorkspace?.id !== workspaceId) {
        return reply.code(403).send({ status: "forbidden" });
      }
      const token = oneTimeToken();
      const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

      const invitationId = await withTenantTransaction(
        { userId: view.session.userId, workspaceId },
        async (client) => {
          const result = await client.query<{ invitation_id: string }>(
            `select growth.identity_issue_invitation($1,$2,$3,$4,$5,$6) as invitation_id`,
            [
              workspaceId,
              parsed.data.email,
              parsed.data.role,
              parsed.data.canPublish,
              token.hash,
              expiresAt.toISOString()
            ]
          );
          return result.rows[0]?.invitation_id ?? null;
        }
      );
      if (!invitationId) return reply.code(500).send({ status: "internal_error" });

      await sendIdentityEmail({
        to: parsed.data.email,
        subject: "You were invited to Growth OS",
        html: `<p>You were invited to Growth OS.</p><p>Use this token in the invitation acceptance screen:</p><p><code>${token.raw}</code></p>`
      });

      return reply.code(202).send({ status: "invitation_sent" });
    } catch (error) {
      const mapped = errorStatus(error);
      if (mapped.code === 500) app.log.error(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/auth/invitations/accept", async (request, reply) => {
    const parsed = TokenSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });

    try {
      const view = await requireSessionWithoutWorkspace(request, true);
      const workspaceId = await withUserTransaction(view.session.userId, async (client) => {
        const result = await client.query<{ workspace_id: string }>(
          "select growth.identity_accept_invitation($1) as workspace_id",
          [hashIdentityToken(parsed.data.token)]
        );
        return result.rows[0]?.workspace_id ?? null;
      });
      if (!workspaceId) return reply.code(409).send({ status: "identity_request_rejected" });
      setWorkspaceCookie(reply, workspaceId, view.session.absoluteExpiresAt);
      return { status: "accepted", workspace_id: workspaceId };
    } catch (error) {
      const mapped = errorStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/auth/password-reset/request", async (request, reply) => {
    const parsed = PasswordResetRequestSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });
    if (env.NODE_ENV === "production") assertTrustedOrigin(request);

    const token = oneTimeToken();
    const expiresAt = new Date(Date.now() + 60 * 60 * 1000);

    try {
      const result = await db.query<{ reset_id: string | null }>(
        `select growth.identity_request_password_reset($1,$2,$3,$4::inet,$5) as reset_id`,
        [
          parsed.data.email,
          token.hash,
          expiresAt.toISOString(),
          requestClientIp(request),
          request.headers["user-agent"] ?? null
        ]
      );
      if (result.rows[0]?.reset_id) {
        try {
          await sendIdentityEmail({
            to: parsed.data.email,
            subject: "Reset your Growth OS password",
            html: `<p>Reset your Growth OS password:</p><p><a href="${passwordResetUrl(token.raw)}">Reset password</a></p>`
          });
        } catch (error) {
          if (error instanceof IdentityEmailUnavailableError) {
            app.log.error(error);
            return reply.code(202).send({ status: "password_reset_if_account_exists" });
          }
          throw error;
        }
      }
      return reply.code(202).send({ status: "password_reset_if_account_exists" });
    } catch (error) {
      const mapped = errorStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });

  app.post("/v1/auth/password-reset/complete", async (request, reply) => {
    const parsed = PasswordResetCompleteSchema.safeParse(request.body);
    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });
    if (env.NODE_ENV === "production") assertTrustedOrigin(request);

    try {
      const result = await db.query<{ user_id: string }>(
        "select growth.identity_complete_password_reset($1,$2,$3) as user_id",
        [hashIdentityToken(parsed.data.token), await hashIdentityPassword(parsed.data.password), 19]
      );
      clearCookiesAfterReset(reply);
      return { status: "password_reset_completed", user_id: result.rows[0]?.user_id };
    } catch (error) {
      const mapped = errorStatus(error);
      return reply.code(mapped.code).send({ status: mapped.status });
    }
  });
}

function clearCookiesAfterReset(reply: FastifyReply): void {
  reply.clearCookie("__Host-growth_session", { path: "/" });
  reply.clearCookie("growth_session", { path: "/" });
  reply.clearCookie("__Host-growth_workspace", { path: "/" });
  reply.clearCookie("growth_workspace", { path: "/" });
}
