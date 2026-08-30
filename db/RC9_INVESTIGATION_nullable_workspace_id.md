# RC9 Investigation — nullable workspace_id in provider_usage / audit_events

## Question

`growth.provider_usage` and `growth.audit_events` both declare `workspace_id uuid`
(nullable, no `NOT NULL`), yet both fall under the generic tenant-isolation RLS
loop, whose single policy is `workspace_id = growth.current_workspace_id()`.
Since `NULL = anything` is never true in SQL, any row with `workspace_id IS NULL`
is structurally invisible through that policy to every ordinary tenant session.

## Evidence found

`db/tests/011_rc8_six_fail_regressions.md`, R1:

> Insert a tenant audit event with a random non-existent `workspace_id`.
> Expected: FK violation. A NULL `workspace_id` system event may remain valid
> under the system-role contract.

This is direct, unambiguous textual evidence that a NULL `workspace_id` in
`audit_events` is **intentional** — the RC8 authors explicitly anticipated
system-level (non-tenant) events coexisting with tenant-scoped ones in the
same table.

No equivalent explicit statement was found for `provider_usage`, but it shares
the identical column shape (`workspace_id uuid REFERENCES workspaces(id)`, no
FK-required, in the same generic RLS loop) and the same plausible use case
(system/global provider usage not tied to one tenant, e.g. platform-level AI
calls). Treated as the same pattern by inference, not by an equally explicit
citation.

## The follow-on problem

R1's own phrase — "under the **system-role contract**" — names a role/access
path that, like the "canonical deployment contract" investigated in the prior
RC9 gate, **does not exist anywhere in the delivered RC8 package**. Searched
the full schema file, every test file, and the RC8 zip's `.md` documents:
no `CREATE ROLE` for anything resembling a system/audit role, no RLS policy
covering `workspace_id IS NULL` rows, no function that would let any
non-bypassing role read them.

Practical consequence: NULL-workspace rows in these two tables can currently
be written (nothing blocks the INSERT), but can only ever be **read** by a
role that bypasses RLS entirely (schema owner, superuser) — never through the
generic tenant policy, and never through any role RC9 has defined
(`app_runtime` has no grant on either table at all, by the approved matrix,
so this is moot for `app_runtime` specifically, but would apply to any future
"system reporting" role that reused the same generic policy pattern).

## Classification

- **NULL workspace_id existing at all**: `INTENTIONAL DESIGN` — confirmed by
  file (R1 text) for `audit_events`; inferred by structural analogy for
  `provider_usage`.
- **A working read path for those NULL-workspace rows**: `CONFIRMED ISSUE` —
  the "system-role contract" is named but not delivered in this package,
  identical in kind to the missing "canonical deployment contract" already
  tracked in the RC9 grant-matrix work. No RC9 grant currently depends on
  this (neither table is in the approved matrix), so it does not block the
  current freeze — but it is a real, evidenced gap that will resurface the
  moment any system-level reporting/audit-reading role is designed.

## Disposition

Not fixed silently. Not blocking this RC9 Security Freeze Gate, since no
approved grant touches either table. Recorded as an open, named risk for
whoever designs the eventual system/reporting role: that design will need
either a dedicated RLS policy for `workspace_id IS NULL` rows, or a role that
legitimately bypasses the generic policy for this specific, narrow case.
