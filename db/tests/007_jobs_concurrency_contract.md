# Jobs operation-key concurrency contract

Required executable cases on PostgreSQL 18.x:

1. Two tenants insert same `(job_type, operation_key)` with different `workspace_id`: BOTH must succeed.
2. Same tenant inserts duplicate `(workspace_id, job_type, operation_key)`: second must fail/resolve to existing job.
3. Two global jobs (`workspace_id IS NULL`) with same `(job_type, operation_key)`: second must fail/resolve to existing job.
4. Normal API runtime role must have no direct SELECT/INSERT/UPDATE/DELETE privilege on `growth.jobs`.
5. Worker role can claim cross-tenant jobs according to the worker security model and never derives tenant context from request input.
