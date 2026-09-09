# Growth OS — release hardening and Railway runbook

This document is the release gate for the complete material cycle. It is evidence-based and must be executed against the exact GitHub SHA being promoted.

## Before Claude review

1. Confirm the PR head SHA is the exact candidate SHA and GitHub CI is green.
2. Confirm all migrations and gates are present through migration 038 / gate 055.
3. Confirm no synthetic opportunity, observation, recommendation, experiment outcome or automation request is used as production proof.
4. Confirm automation requests are evidence-bound, pending by default, quota-limited and kill-switchable.
5. Confirm commercial state is internal/auditable and no external charge is implied without a configured billing provider.
6. Confirm Railway production still points at GitHub main and that no local branch is used as a promotion source.

## Railway production promotion after APPROVE only

1. Merge the reviewed PR into GitHub main.
2. Update the canonical migrator service start command to apply migrations 034 through 038 after the already-applied 030 through 033 sequence.
3. Redeploy the migrator from the GitHub main source and wait for SUCCESS.
4. Confirm the app service still uses the GitHub main source, then redeploy the app from main.
5. Verify /health/live, /health/ready and /v1/system.
6. Verify the real deployment SHA in Railway metadata and record it in the execution memory.
7. Run the tenant-isolation, approval, quota, kill-switch and entitlement checks against production.
8. If any migration or health gate fails, stop promotion and restore service availability before retrying.

## Operational recovery

- Kill switch: set the workspace automation policy to kill_switch=true before investigating an automation incident.
- Provider safety: an approved request is still only an auditable request; provider execution requires a separately reviewed worker contract.
- Data safety: retain production backups and perform a restore drill before declaring Phase 11 Frozen.
- Commercial safety: do not mark a subscription active unless its provider reference and internal audit record are both present.
- Privacy: deletion and retention changes require an owner/admin actor and an audit record.

## Freeze evidence

The project is complete only when the exact final SHA has green CI, Claude has returned APPROVE, Railway has promoted from GitHub main with SUCCESS deployments, production-truth checks pass, recovery evidence is recorded, and the release freeze is documented.
