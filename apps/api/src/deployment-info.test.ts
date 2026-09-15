import assert from "node:assert/strict";
import test from "node:test";

// deployment-info.ts reads the canonical environment at module load time.
// This test exercises only pure deployment-identity validation, but it still
// must provide the one required config variable before importing the module.
// No database connection is opened.
process.env.DATABASE_URL ??= "postgresql://growth_test:growth_test@127.0.0.1:5432/growth_test";

const { assertRailwayDeploymentIdentity } = await import("./deployment-info.js");

type TestDeploymentInfo = Parameters<typeof assertRailwayDeploymentIdentity>[0];

const validInfo: TestDeploymentInfo = {
  name: "Growth OS",
  version: "0.1.0",
  environment: "production",
  commit_sha: "57c7e12e9afbd3295a10d260572b44c024a57541",
  deployment_id: "da0df9ae-445d-470e-812f-484cb82e9f3e"
};

test("Railway production requires complete deployment identity", () => {
  assert.doesNotThrow(() => assertRailwayDeploymentIdentity(validInfo, true));

  assert.throws(
    () => assertRailwayDeploymentIdentity({ ...validInfo, commit_sha: null }, true),
    /deployment identity is incomplete/
  );

  assert.throws(
    () => assertRailwayDeploymentIdentity({ ...validInfo, deployment_id: null }, true),
    /deployment identity is incomplete/
  );
});

test("non-Railway execution does not require Railway metadata", () => {
  assert.doesNotThrow(() => assertRailwayDeploymentIdentity({
    ...validInfo,
    commit_sha: null,
    deployment_id: null
  }, false));
});
