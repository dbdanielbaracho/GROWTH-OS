-- Provision the canonical principal used by the isolated publication worker.
-- The worker remains disabled until Railway supplies both this principal id and
-- a dedicated PostgreSQL credential through PUBLICATION_WORKER_DATABASE_URL.

insert into growth.worker_service_principals (
  id,
  name,
  status,
  allowed_job_types
)
values (
  '5d3f0c0e-7a6e-4b4b-9d8e-2e8f7f2a6c11'::uuid,
  'growth-os-publication-worker',
  'active',
  array['publication_intent']::text[]
)
on conflict (id) do update
set name = excluded.name,
    status = excluded.status,
    allowed_job_types = excluded.allowed_job_types;
