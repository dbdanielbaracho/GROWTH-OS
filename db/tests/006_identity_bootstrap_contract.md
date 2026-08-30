# Identity / workspace bootstrap RLS execution contract

Run with the actual runtime role and actual connection pool/driver.

Required sequence:
1. Authenticate User A and set transaction-local `app.user_id=A`; do NOT set `app.workspace_id` yet.
2. `SELECT memberships` returns only User A memberships.
3. `SELECT workspaces` returns only active workspaces for User A memberships.
4. Set `app.workspace_id` to Workspace A; selected-workspace tenant tables become visible only for A.
5. Attempt to set `app.workspace_id` to Workspace B for which User A has no membership. The application authorization layer must reject selection before issuing tenant queries; DB tests must demonstrate that bootstrap workspace discovery does not expose B.
6. User B cannot enumerate User A memberships or workspaces.
7. Pool reuse clears BOTH `app.user_id` and `app.workspace_id` before the next request.

Threat-model note: custom GUCs are trusted server-side context, not an authentication primitive against arbitrary SQL execution. The runtime role must not expose raw SQL to end users, and SQL injection remains a separate security boundary.
