import { readdir, readFile } from "node:fs/promises";
import { join } from "node:path";

const root = process.cwd();
const migrationDir = join(root, "db", "migrations");
const files = await readdir(migrationDir);
const migrationNumbers = files
  .map((file) => /^([0-9]{3})_.*\.sql$/.exec(file)?.[1])
  .filter((value) => value !== undefined);

for (let number = 1; number <= 38; number += 1) {
  const expected = String(number).padStart(3, "0");
  if (!migrationNumbers.includes(expected)) {
    throw new Error("release hardening: missing canonical migration " + expected);
  }
}

const workflow = await readFile(join(root, ".github", "workflows", "ci.yml"), "utf8");
for (const gate of ["053_experiment_lineage.sql", "054_automation_policy_control.sql", "055_commercial_entitlements.sql"]) {
  if (!workflow.includes(gate)) {
    throw new Error("release hardening: CI is missing " + gate);
  }
}

const automationGate = await readFile(join(root, "db", "tests", "054_automation_policy_control.sql"), "utf8");
if (!automationGate.includes("069_automation_action_execution.sql")) {
  throw new Error("release hardening: canonical automation CI step does not chain execution gate 069");
}

const automationExecution = await readFile(join(migrationDir, "068_automation_action_execution.sql"), "utf8");
for (const marker of ["execution_status", "claim_automation_action_execution", "finalize_automation_action_execution", "kill switch"]) {
  if (!automationExecution.includes(marker)) {
    throw new Error("release hardening: automation execution marker missing " + marker);
  }
}


const youtubeReauthorization = await readFile(join(migrationDir, "069_youtube_reauthorization_cleanup.sql"), "utf8");
for (const marker of ["youtube_begin_authorization", "DELETE FROM growth.platform_connections", "authorizing"]) {
  if (!youtubeReauthorization.includes(marker)) {
    throw new Error("release hardening: YouTube reauthorization marker missing " + marker);
  }
}

const commercial = await readFile(join(migrationDir, "038_commercial_entitlements.sql"), "utf8");
for (const marker of ["provider_customer_ref", "monthly_action_limit", "enterprise_policies"]) {
  if (!commercial.includes(marker)) {
    throw new Error("release hardening: commercial marker missing " + marker);
  }
}

console.log("RELEASE HARDENING GATE: PASSED — migrations, governance gates and commercial markers are present.");
