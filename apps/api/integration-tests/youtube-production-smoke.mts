import { randomUUID } from "node:crypto";
import pg from "pg";
import { db } from "../src/db.js";
import {
  YoutubeConnectorError,
  syncYoutubeAnalytics
} from "../src/youtube-connector.js";

const { Pool } = pg;

function required(name: string): string {
  const value = process.env[name]?.trim();
  if (!value) throw new Error(`${name} is required`);
  return value;
}

if (process.env.ALLOW_REAL_YOUTUBE_SYNC !== "true") {
  throw new Error("real YouTube production smoke is disabled; set ALLOW_REAL_YOUTUBE_SYNC=true explicitly");
}

const workspaceName = required("TARGET_WORKSPACE_NAME");
const admin = new Pool({ connectionString: required("ADMIN_DATABASE_URL"), max: 1 });

let safeResult: Record<string, unknown> = {
  status: "not_run",
  workspace: workspaceName,
  connectionFound: false
};

try {
  const targetSummary = await admin.query<{
    connection_state: string;
    connection_count: number;
    credential_count: number;
    social_account_count: number;
    error_class: string | null;
  }>(
    `select
       pc.state as connection_state,
       count(distinct pc.id)::int as connection_count,
       count(distinct pcd.platform_connection_id)::int as credential_count,
       count(distinct sa.id)::int as social_account_count,
       max(pc.error_class) as error_class
     from growth.workspaces w
     join growth.platform_connections pc
       on pc.workspace_id = w.id
      and pc.platform = 'youtube'
     left join growth.provider_credentials pcd
       on pcd.workspace_id = pc.workspace_id
      and pcd.platform_connection_id = pc.id
      and pcd.provider = 'youtube'
     left join growth.social_accounts sa
       on sa.workspace_id = pc.workspace_id
      and sa.platform_connection_id = pc.id
      and sa.platform = 'youtube'
     where lower(w.name) = lower($1)
     group by pc.state
     order by pc.state`,
    [workspaceName]
  );

  const discovered = await admin.query<{
    workspace_id: string;
    user_id: string;
    connection_id: string;
    connection_state: string;
  }>(
    `with candidates as (
       select
         w.id as workspace_id,
         m.user_id,
         m.role,
         pc.id as connection_id,
         pc.state as connection_state,
         pc.updated_at,
         row_number() over (
           partition by pc.id
           order by case when m.role = 'owner' then 0 else 1 end, m.created_at
         ) as membership_rank
       from growth.workspaces w
       join growth.memberships m
         on m.workspace_id = w.id
        and m.status = 'active'
        and m.role in ('owner','admin')
       join growth.platform_connections pc
         on pc.workspace_id = w.id
        and pc.platform = 'youtube'
       where lower(w.name) = lower($1)
         and w.status = 'active'
         and pc.state = 'connected'
     )
     select workspace_id, user_id, connection_id, connection_state
       from candidates
      where membership_rank = 1
      order by updated_at desc
      limit 1`,
    [workspaceName]
  );

  const target = discovered.rows[0];
  if (!target) {
    const youtubeWorkspaces = await admin.query<{ workspace_name: string; states: string[] }>(
      `select w.name as workspace_name, array_agg(distinct pc.state order by pc.state) as states
         from growth.workspaces w
         join growth.platform_connections pc
           on pc.workspace_id = w.id
          and pc.platform = 'youtube'
        where w.status = 'active'
        group by w.id, w.name
        order by w.name`,
      []
    );

    safeResult = {
      status: "no_connected_connection",
      workspace: workspaceName,
      connectionFound: false,
      targetConnectionStates: targetSummary.rows,
      youtubeWorkspaces: youtubeWorkspaces.rows,
      reauthorizationRequired: targetSummary.rows.some((row) => row.connection_state === "reauth_required")
    };
  } else {
    try {
      const result = await syncYoutubeAnalytics(
        { userId: target.user_id, workspaceId: target.workspace_id },
        target.connection_id,
        randomUUID(),
        7
      );

      safeResult = {
        status: "ok",
        workspace: workspaceName,
        connectionFound: true,
        connectionStateBefore: target.connection_state,
        rowsReceived: result.rowsReceived,
        observationsProcessed: result.observationsProcessed,
        returnedThroughDate: result.returnedThroughDate,
        requestedStartDate: result.requestedStartDate,
        requestedEndDate: result.requestedEndDate,
        derivedAnalyticsPolicyAccepted: result.derivedAnalyticsPolicyAccepted,
        intelligenceStatus: result.intelligenceStatus,
        intelligenceObservationsUsed: result.intelligenceObservationsUsed,
        signalPresent: Boolean(result.signalId),
        insightPresent: Boolean(result.insightId),
        opportunityPresent: Boolean(result.opportunityId),
        reauthorizationRequired: false
      };
    } catch (error) {
      if (error instanceof YoutubeConnectorError) {
        safeResult = {
          status: "provider_error",
          workspace: workspaceName,
          connectionFound: true,
          connectionStateBefore: target.connection_state,
          code: error.code,
          httpStatus: error.httpStatus,
          providerOperation: error.providerOperation,
          providerHttpStatus: error.providerHttpStatus,
          reauthorizationRequired: error.code === "youtube_reauthorization_required"
        };
      } else {
        throw error;
      }
    }
  }
} catch (error) {
  safeResult = {
    status: "internal_error",
    workspace: workspaceName,
    connectionFound: false,
    errorClass: error instanceof Error ? error.name : "unknown_error"
  };
  process.exitCode = 1;
} finally {
  console.log(`YOUTUBE_PRODUCTION_SMOKE=${JSON.stringify(safeResult)}`);
  await admin.end().catch(() => undefined);
  await db.end().catch(() => undefined);
}
