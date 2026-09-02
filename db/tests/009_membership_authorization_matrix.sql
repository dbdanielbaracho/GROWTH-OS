-- Growth OS RC7 membership authorization matrix.
-- Requires canonical schema applied and app_runtime role provisioned/granted table privileges.
-- This file is intended to be executed on PostgreSQL 18.6 with a privileged harness role
-- that can seed fixtures, then SET ROLE app_runtime for adversarial operations.
\set ON_ERROR_STOP on

-- Per-run fixture IDs make this matrix safe to execute again even when a
-- previous run's rows remain in a long-lived validation database.
SELECT gen_random_uuid() AS ws,
       gen_random_uuid() AS owner1,
       gen_random_uuid() AS owner2,
       gen_random_uuid() AS admin1,
       gen_random_uuid() AS editor1,
       gen_random_uuid() AS viewer1,
       gen_random_uuid() AS outsider
\gset

SET search_path = growth, public;

-- Seed as privileged harness.
INSERT INTO growth.users(id,email,status) VALUES
  (:'owner1','rc7-owner1-' || :'owner1' || '@example.test','active'),
  (:'owner2','rc7-owner2-' || :'owner2' || '@example.test','active'),
  (:'admin1','rc7-admin1-' || :'admin1' || '@example.test','active'),
  (:'editor1','rc7-editor1-' || :'editor1' || '@example.test','active'),
  (:'viewer1','rc7-viewer1-' || :'viewer1' || '@example.test','active'),
  (:'outsider','rc7-outsider-' || :'outsider' || '@example.test','active');

INSERT INTO growth.workspaces(id,name,default_market,default_language,default_timezone,status)
VALUES (:'ws','RC7 membership auth','US','en','UTC','active');

SELECT set_config('app.workspace_id', :'ws', false);
SELECT set_config('app.user_id', :'owner1', false);
INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status) VALUES
  (:'ws',:'owner1','owner',true,'active');
INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status) VALUES
  (:'ws',:'admin1','admin',true,'active'),
  (:'ws',:'editor1','editor',false,'active'),
  (:'ws',:'viewer1','viewer',false,'active');

-- Helper: runtime viewer must not self-promote.
SET ROLE app_runtime;
SELECT set_config('app.workspace_id', :'ws', false);
SELECT set_config('app.user_id', :'viewer1', false);
UPDATE growth.memberships SET role='owner', can_publish=true
 WHERE workspace_id=:'ws' AND user_id=:'viewer1';
RESET ROLE;
SELECT count(*) AS bad FROM growth.memberships WHERE workspace_id=:'ws'::uuid AND user_id=:'viewer1'::uuid AND role='owner' \gset
\if :bad
  \echo 'FAIL viewer self-promotion succeeded'
  SELECT 1 / 0;
\endif

-- Viewer must not delete owner.
SET ROLE app_runtime;
SELECT set_config('app.workspace_id', :'ws', false);
SELECT set_config('app.user_id', :'viewer1', false);
DELETE FROM growth.memberships WHERE workspace_id=:'ws' AND user_id=:'owner1';
RESET ROLE;
SELECT count(*) AS ok FROM growth.memberships WHERE workspace_id=:'ws'::uuid AND user_id=:'owner1'::uuid \gset
\if :ok
\else
  \echo 'FAIL viewer deleted owner'
  SELECT 1 / 0;
\endif

-- Viewer may leave self.
SET ROLE app_runtime;
SELECT set_config('app.workspace_id', :'ws', false);
SELECT set_config('app.user_id', :'viewer1', false);
DELETE FROM growth.memberships WHERE workspace_id=:'ws' AND user_id=:'viewer1';
RESET ROLE;
SELECT count(*) AS bad FROM growth.memberships WHERE workspace_id=:'ws'::uuid AND user_id=:'viewer1'::uuid \gset
\if :bad
  \echo 'FAIL viewer self-leave was blocked'
  SELECT 1 / 0;
\endif

-- Owner can promote editor to admin.
SET ROLE app_runtime;
SELECT set_config('app.workspace_id', :'ws', false);
SELECT set_config('app.user_id', :'owner1', false);
UPDATE growth.memberships SET role='admin' WHERE workspace_id=:'ws' AND user_id=:'editor1';
RESET ROLE;
SELECT count(*) AS ok FROM growth.memberships WHERE workspace_id=:'ws'::uuid AND user_id=:'editor1'::uuid AND role='admin' \gset
\if :ok
\else
  \echo 'FAIL owner could not promote editor to admin'
  SELECT 1 / 0;
\endif

-- Restore editor for admin boundary test.
UPDATE growth.memberships SET role='editor' WHERE workspace_id=:'ws' AND user_id=:'editor1';

-- Admin promotion to admin/owner MUST fail at trigger. We deliberately expect an error, so temporarily disable ON_ERROR_STOP.
\set ON_ERROR_STOP off
SET ROLE app_runtime;
SELECT set_config('app.workspace_id', :'ws', false);
SELECT set_config('app.user_id', :'admin1', false);
UPDATE growth.memberships SET role='admin' WHERE workspace_id=:'ws' AND user_id=:'editor1';
\set admin_promote_sqlstate :SQLSTATE
RESET ROLE;
\set ON_ERROR_STOP on
\if :{?admin_promote_sqlstate}
\else
  \echo 'FAIL: no SQLSTATE captured for forbidden admin promotion'
  SELECT 1 / 0;
\endif
SELECT count(*) AS bad FROM growth.memberships WHERE workspace_id=:'ws'::uuid AND user_id=:'editor1'::uuid AND role='admin' \gset
\if :bad
  \echo 'FAIL admin promoted editor to admin'
  SELECT 1 / 0;
\endif

-- Admin cannot delete owner.
\set ON_ERROR_STOP off
SET ROLE app_runtime;
SELECT set_config('app.workspace_id', :'ws', false);
SELECT set_config('app.user_id', :'admin1', false);
DELETE FROM growth.memberships WHERE workspace_id=:'ws' AND user_id=:'owner1';
RESET ROLE;
\set ON_ERROR_STOP on
SELECT count(*) AS ok FROM growth.memberships WHERE workspace_id=:'ws'::uuid AND user_id=:'owner1'::uuid \gset
\if :ok
\else
  \echo 'FAIL admin deleted owner'
  SELECT 1 / 0;
\endif

-- Membership identity keys are immutable.
\set ON_ERROR_STOP off
SET ROLE app_runtime;
SELECT set_config('app.workspace_id', :'ws', false);
SELECT set_config('app.user_id', :'owner1', false);
UPDATE growth.memberships SET user_id=:'outsider' WHERE workspace_id=:'ws' AND user_id=:'editor1';
RESET ROLE;
\set ON_ERROR_STOP on
SELECT count(*) AS bad FROM growth.memberships WHERE workspace_id=:'ws'::uuid AND user_id=:'outsider'::uuid \gset
\if :bad
  \echo 'FAIL membership user_id mutation succeeded'
  SELECT 1 / 0;
\endif

-- Last-owner guard: with only owner1 as owner, demotion/delete must fail.
\set ON_ERROR_STOP off
SET ROLE app_runtime;
SELECT set_config('app.workspace_id', :'ws', false);
SELECT set_config('app.user_id', :'owner1', false);
UPDATE growth.memberships SET role='admin' WHERE workspace_id=:'ws' AND user_id=:'owner1';
DELETE FROM growth.memberships WHERE workspace_id=:'ws' AND user_id=:'owner1';
RESET ROLE;
\set ON_ERROR_STOP on
SELECT count(*) AS ok FROM growth.memberships WHERE workspace_id=:'ws'::uuid AND user_id=:'owner1'::uuid AND role='owner' AND status='active' \gset
\if :ok
\else
  \echo 'FAIL last active owner was demoted/deleted'
  SELECT 1 / 0;
\endif

-- With a second owner, owner1 may leave.
INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status)
VALUES (:'ws',:'owner2','owner',true,'active');
SET ROLE app_runtime;
SELECT set_config('app.workspace_id', :'ws', false);
SELECT set_config('app.user_id', :'owner1', false);
DELETE FROM growth.memberships WHERE workspace_id=:'ws' AND user_id=:'owner1';
RESET ROLE;
SELECT count(*) AS bad FROM growth.memberships WHERE workspace_id=:'ws'::uuid AND user_id=:'owner1'::uuid \gset
\if :bad
  \echo 'FAIL owner could not self-leave with another active owner'
  SELECT 1 / 0;
\endif
SELECT count(*) AS ok FROM growth.memberships WHERE workspace_id=:'ws'::uuid AND user_id=:'owner2'::uuid AND role='owner' AND status='active' \gset
\if :ok
\else
  \echo 'FAIL workspace lost all active owners'
  SELECT 1 / 0;
\endif

-- RC7 regression: unaffiliated outsider must not self-bootstrap into non-empty workspace.
\set ON_ERROR_STOP off
SET ROLE app_runtime;
SELECT set_config('app.workspace_id', :'ws', false);
SELECT set_config('app.user_id', :'outsider', false);
INSERT INTO growth.memberships(workspace_id,user_id,role,can_publish,status)
VALUES (:'ws',:'outsider','owner',true,'active');
RESET ROLE;
\set ON_ERROR_STOP on
SELECT count(*) AS bad FROM growth.memberships WHERE workspace_id=:'ws'::uuid AND user_id=:'outsider'::uuid AND role='owner' \gset
\if :bad
  \echo 'FAIL outsider self-created owner membership in non-empty workspace'
  SELECT 1 / 0;
\endif

\echo 'PASS: RC7 membership authorization matrix'
