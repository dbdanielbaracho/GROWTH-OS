import type { PoolClient } from "pg";
import type { AuthPrincipal } from "./auth.js";

export type WorkspaceSummary = {
  id: string;
  name: string;
  default_market: string;
  default_language: string;
  default_timezone: string;
  status: "active" | "suspended" | "deleting";
  role: "owner" | "admin" | "editor" | "viewer";
  can_publish: boolean;
  membership_status: "active" | "invited" | "revoked";
};

export async function getCurrentWorkspace(
  client: PoolClient,
  principal: AuthPrincipal
): Promise<WorkspaceSummary | null> {
  const result = await client.query<WorkspaceSummary>(
    `select
       w.id,
       w.name,
       w.default_market,
       w.default_language,
       w.default_timezone,
       w.status,
       m.role,
       m.can_publish,
       m.status as membership_status
     from growth.workspaces w
     join growth.memberships m
       on m.workspace_id = w.id
      and m.user_id = $1
     where w.id = $2
     limit 1`,
    [principal.userId, principal.workspaceId]
  );

  return result.rows[0] ?? null;
}

export type MembershipSummary = {
  workspace_id: string;
  user_id: string;
  role: "owner" | "admin" | "editor" | "viewer";
  can_publish: boolean;
  status: "active" | "invited" | "revoked";
  created_at: string;
};

export async function getCurrentMembership(
  client: PoolClient,
  principal: AuthPrincipal
): Promise<MembershipSummary | null> {
  const result = await client.query<MembershipSummary>(
    `select workspace_id, user_id, role, can_publish, status, created_at
       from growth.memberships
      where workspace_id = $1
        and user_id = $2
      limit 1`,
    [principal.workspaceId, principal.userId]
  );

  return result.rows[0] ?? null;
}
