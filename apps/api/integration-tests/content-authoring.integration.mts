import { withTenantTransaction } from "../src/tenant-db.js";
import { createContent, listContent } from "../src/content.js";

const legitOwner = { userId: "a0000000-0000-4000-8000-000000000001", workspaceId: "b0000000-0000-4000-8000-000000000001" };

let failures = 0;
function check(name: string, ok: boolean, detail?: unknown) {
  if (ok) console.log(`PASS: ${name}`);
  else { failures++; console.error(`FAIL: ${name}`, detail ?? ""); }
}

const created = await withTenantTransaction(legitOwner, (client) =>
  createContent(client, legitOwner, {
    market: "US", language: "en", sourceType: "manual",
    body: "post-creative-production merge live check", structure: { hook: "audit" }
  })
);
check("(1) content.ts createContent still works against the current schema", !!created.item?.id && created.item.status === 'draft', created);

const listed = await withTenantTransaction(legitOwner, (client) => listContent(client, legitOwner));
check("(2) listContent returns it back", listed.some((r: any) => r.id === created.item.id), listed);

await import("../src/db.js").then((m) => m.db.end());
process.exit(failures > 0 ? 1 : 0);
