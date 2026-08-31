# Content Authoring v0.1

This increment adds the first write path for Growth OS content while preserving the frozen RC8 database contract.

## API

- `GET /v1/content` lists tenant-visible content items with their latest version.
- `POST /v1/content` creates a draft `content_items` row and version 1 in `content_versions` inside one tenant transaction.

## Invariants

- Workspace and user context are transaction-local through `app.workspace_id` and `app.user_id`.
- PostgreSQL RLS remains authoritative for tenant isolation.
- New content starts in `draft` status.
- A SHA-256 checksum is generated from the body and structured content for version deduplication.
- The frozen RC8 baseline is not rewritten by this application change.

## Security boundary

Development header identity is still forbidden when `NODE_ENV=production`; production identity remains a separate adapter/gate.
