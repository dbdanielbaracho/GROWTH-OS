# RC5 membership concurrency contract

Target: PostgreSQL 18.6, canonical RC5 schema, real `app_runtime` role.

## C1 — concurrent first-owner bootstrap

1. Create a workspace with zero membership rows.
2. Session A sets `app.user_id=A`, `app.workspace_id=W` and inserts `(W,A,owner,active)`.
3. Session B concurrently sets `app.user_id=B`, `app.workspace_id=W` and inserts `(W,B,owner,active)` before A commits.
4. Both operations traverse the same workspace advisory lock in `membership_write_guard`.
5. Expected: exactly one bootstrap succeeds. The second transaction wakes, recounts memberships, sees a non-empty workspace and fails because the actor is not an owner/admin of W.
6. Assert exactly one active owner row exists.

## C2 — two owners concurrently try to leave

1. Workspace W has exactly two active owners A and B.
2. Session A deletes its own membership; Session B concurrently deletes its own membership.
3. Both operations serialize on the same workspace advisory lock.
4. Expected: first delete succeeds; second wakes, sees it is now the last active owner, and fails.
5. Assert exactly one active owner remains.

## C3 — owner demotion races owner deletion

1. Workspace W has exactly two active owners A and B.
2. Session A attempts to demote A to admin while Session B deletes B.
3. Expected: operations serialize; only one can remove an active owner. The second attempt must fail if it would leave zero active owners.
4. Assert at least one active owner remains and no partial state is committed.

## C4 — admin takeover race

1. Workspace W has owner O and admin A.
2. A concurrently tries to (a) promote itself to owner and (b) delete O in separate sessions.
3. RLS + trigger hierarchy must reject both independently; serialization must not create an order in which either becomes legal.
4. Assert O remains active owner and A remains admin.

Every scenario must be reported PASS / FAIL / NOT EXECUTED with timestamps and exact SQL/logs. Deduction is not PASS.
