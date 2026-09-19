import { expect, test, type Page, type Route } from "@playwright/test";
import AxeBuilder from "@axe-core/playwright";

const workspace = {
  id: "b0000000-0000-4000-8000-000000000001",
  name: "Browser Quality Workspace",
  default_market: "US",
  default_language: "en-US",
  default_timezone: "America/Los_Angeles",
  status: "active",
  role: "owner",
  can_publish: true,
  membership_status: "active"
};

const session = {
  status: "ok",
  session: {
    user_id: "a0000000-0000-4000-8000-000000000001",
    amr: ["pwd"],
    absolute_expires_at: "2026-09-16T02:00:00.000Z",
    idle_expires_at: "2026-09-15T03:00:00.000Z"
  },
  workspaces: [workspace],
  selected_workspace: workspace,
  csrf_token: "browser-quality-csrf"
};

const opportunity = {
  id: "c0000000-0000-4000-8000-000000000001",
  social_account_id: "d0000000-0000-4000-8000-000000000001",
  market: "US",
  platform: "instagram",
  status: "open",
  score: "87.5",
  confidence: 0.86,
  ranking_version: "browser-quality-v1",
  expires_at: null,
  created_at: "2026-09-15T01:00:00.000Z",
  evidence_count: 1
};

const opportunityDetail = {
  status: "ok",
  opportunity,
  evidence: [
    {
      id: "e0000000-0000-4000-8000-000000000001",
      source_class: "owned",
      evidence_ref: "browser-quality-controlled-fixture",
      observed_at: "2026-09-15T01:00:00.000Z"
    }
  ],
  related_insights: []
};

function json(route: Route, status: number, body: unknown) {
  return route.fulfill({
    status,
    contentType: "application/json",
    body: JSON.stringify(body)
  });
}

async function mockApi(
  page: Page,
  initialMode: "signed_out" | "authenticated",
  metrics: unknown[] = [],
  content: unknown[] = [],
  publicationIntents: unknown[] = []
) {
  let mode = initialMode;
  const unhandled: string[] = [];

  await page.route("**/v1/**", async (route) => {
    const url = new URL(route.request().url());
    const path = url.pathname;

    if (path === "/v1/auth/signin" && route.request().method() === "POST") {
      mode = "authenticated";
      return json(route, 200, session);
    }
    if (path === "/v1/auth/signout" && route.request().method() === "POST") {
      mode = "signed_out";
      return route.fulfill({ status: 204 });
    }

    // Known authenticated reads can still be in flight when signout finishes.
    if (mode === "signed_out" && [
      "/v1/integrations/youtube/status", "/v1/integrations/instagram/status",
      "/v1/analytics/metrics", "/v1/analytics/anomalies", "/v1/content", "/v1/publication-intents",
      "/v1/opportunities", `/v1/opportunities/${opportunity.id}`,
      "/v1/recommendations", "/v1/experiments", "/v1/automation/policy", "/v1/automation/requests",
      "/v1/commercial/entitlements", "/v1/commercial/enterprise-policy"
    ].includes(path)) return json(route, 401, { status: "unauthorized" });

    if (path === "/v1/auth/session") {
      if (mode === "signed_out") return json(route, 401, { status: "unauthorized" });
      return json(route, 200, session);
    }

    if (mode === "authenticated" && path === "/v1/integrations/youtube/status") {
      return json(route, 200, {
        status: "ok",
        configured: false,
        derived_analytics_policy_accepted: false,
        integrations: []
      });
    }

    if (mode === "authenticated" && path === "/v1/integrations/instagram/status") {
      return json(route, 200, {
        status: "ok",
        configured: false,
        integrations: []
      });
    }

    if (mode === "authenticated" && path === "/v1/analytics/metrics") {
      return json(route, 200, {
        status: "ok",
        from: "2026-09-08T00:00:00.000Z",
        to: "2026-09-15T00:00:00.000Z",
        metrics
      });
    }

    if (mode === "authenticated" && path === "/v1/analytics/anomalies") {
      return json(route, 200, {
        status: "ok",
        from: "2026-09-08T00:00:00.000Z",
        to: "2026-09-15T00:00:00.000Z",
        anomalies: []
      });
    }

    if (mode === "authenticated" && path === "/v1/copilot/query" && route.request().method() === "POST") {
      return json(route, 200, {
        status: "ok",
        reply: {
          mode: "evidence_grounded",
          intent: "evidence",
          answer: "The controlled opportunity is supported by one persisted evidence reference. This browser fixture proves only the Copilot interface and evidence boundary.",
          citations: [{
            kind: "evidence",
            ref: "browser-quality-controlled-fixture",
            label: "owned evidence"
          }],
          workspace_pulse: {
            opportunities: 1,
            insights: 0,
            metric_rows: metrics.length,
            quality_alerts: 0,
            experiments: 0,
            automation_needs_attention: 0,
            automation_kill_switch: false
          },
          suggested_prompts: ["What evidence supports the top opportunity?"],
          limitations: [
            "Answers use only persisted data available to the current workspace.",
            "Correlation is not presented as confirmed causality.",
            "Copilot does not publish or execute provider actions; those remain behind existing approval and Autopilot controls."
          ]
        }
      });
    }

    if (mode === "authenticated" && path === "/v1/content") {
      return json(route, 200, { status: "ok", content });
    }

    if (mode === "authenticated" && path === "/v1/publication-intents") {
      return json(route, 200, { status: "ok", publicationIntents });
    }

    if (mode === "authenticated" && path === "/v1/opportunities") {
      return json(route, 200, { status: "ok", opportunities: [opportunity] });
    }

    if (mode === "authenticated" && path === `/v1/opportunities/${opportunity.id}`) {
      return json(route, 200, opportunityDetail);
    }

    if (mode === "authenticated" && path === "/v1/recommendations") {
      return json(route, 200, { status: "ok", recommendations: [] });
    }

    if (mode === "authenticated" && path === "/v1/experiments") {
      return json(route, 200, { status: "ok", experiments: [] });
    }


    if (mode === "authenticated" && path === "/v1/automation/policy") {
      return json(route, 200, {
        status: "ok",
        policy: {
          id: "f0000000-0000-4000-8000-000000000001",
          workspace_id: workspace.id,
          mode: "approval_required",
          daily_request_limit: 10,
          kill_switch: false,
          created_at: "2026-09-15T01:00:00.000Z",
          updated_at: "2026-09-15T01:00:00.000Z"
        }
      });
    }

    if (mode === "authenticated" && path === "/v1/automation/requests") {
      return json(route, 200, { status: "ok", requests: [] });
    }

    if (mode === "authenticated" && path === "/v1/commercial/entitlements") {
      return json(route, 200, {
        status: "ok",
        entitlements: {
          plan_code: "pro",
          plan_name: "Pro",
          subscription_status: "active",
          monthly_action_limit: 1000,
          used_automation_requests: 4,
          period_start: "2026-09-01T00:00:00.000Z",
          period_end: "2026-10-01T00:00:00.000Z"
        }
      });
    }

    if (mode === "authenticated" && path === "/v1/commercial/enterprise-policy") {
      return json(route, 200, {
        status: "ok",
        policy: {
          id: null,
          workspace_id: workspace.id,
          data_retention_days: 365,
          support_tier: "standard",
          legal_acceptance_ref: null,
          deletion_requested_at: null,
          created_at: "2026-09-15T01:00:00.000Z",
          updated_at: "2026-09-15T01:00:00.000Z"
        }
      });
    }

    unhandled.push(`${route.request().method()} ${path}`);
    return json(route, 501, { status: "browser_quality_unhandled" });
  });

  return unhandled;
}

async function expectNoHorizontalOverflow(page: Page) {
  const dimensions = await page.evaluate(() => ({
    viewport: window.innerWidth,
    document: document.documentElement.scrollWidth,
    body: document.body.scrollWidth
  }));
  expect(dimensions.document, JSON.stringify(dimensions)).toBeLessThanOrEqual(dimensions.viewport + 1);
  expect(dimensions.body, JSON.stringify(dimensions)).toBeLessThanOrEqual(dimensions.viewport + 1);
}

async function expectNoSeriousAccessibilityViolations(page: Page) {
  const results = await new AxeBuilder({ page })
    .withTags(["wcag2a", "wcag2aa", "wcag21aa"])
    .analyze();
  const blocking = results.violations.filter((violation) =>
    violation.impact === "serious" || violation.impact === "critical"
  );
  expect(blocking, JSON.stringify(blocking, null, 2)).toEqual([]);
}

test("signed-out identity journeys are keyboard-accessible and responsive", async ({ page }) => {
  const unhandled = await mockApi(page, "signed_out");
  await page.goto("/");

  await expect(page.getByRole("heading", { name: "Sign in to see your next opportunity." })).toBeVisible();
  await expect(page.getByLabel("Email")).toBeVisible();
  await expect(page.getByLabel("Password")).toBeVisible();

  await page.keyboard.press("Tab");
  await expect(page.getByLabel("Email")).toBeFocused();
  await page.keyboard.press("Tab");
  await expect(page.getByLabel("Password")).toBeFocused();

  await expectNoHorizontalOverflow(page);
  await expectNoSeriousAccessibilityViolations(page);

  await page.getByRole("button", { name: "Create a new account" }).click();
  await expect(page.getByRole("heading", { name: "Start with a verified identity." })).toBeVisible();
  await expect(page.getByLabel("Confirm password")).toBeVisible();

  await page.getByRole("button", { name: "Back to sign in" }).click();
  await page.getByRole("button", { name: "Forgot password?" }).click();
  await expect(page.getByRole("heading", { name: "Reset your password." })).toBeVisible();

  await page.setViewportSize({ width: 390, height: 844 });
  await expectNoHorizontalOverflow(page);
  await expectNoSeriousAccessibilityViolations(page);
  expect(unhandled).toEqual([]);
});

test("authenticated Radar shell remains accessible across desktop and mobile", async ({ page }) => {
  const unhandled = await mockApi(page, "authenticated");
  await page.goto("/");

  await expect(page.getByRole("heading", { name: "See what is beginning to move." })).toBeVisible();
  await expect(page.getByText("Browser Quality Workspace")).toBeVisible();
  await expect(page.getByRole("button", { name: /US opportunity/i })).toBeVisible();
  await expect(page.getByRole("heading", { name: "Instagram · US" })).toBeVisible();
  await expect(page.getByText("browser-quality-controlled-fixture")).toBeVisible();

  await expectNoHorizontalOverflow(page);
  await expectNoSeriousAccessibilityViolations(page);

  await page.setViewportSize({ width: 390, height: 844 });
  await expect(page.getByRole("heading", { name: "See what is beginning to move." })).toBeVisible();
  await expectNoHorizontalOverflow(page);
  await expectNoSeriousAccessibilityViolations(page);
  expect(unhandled).toEqual([]);
});

test("Copilot stays evidence-grounded, accessible and read-only in the authenticated shell", async ({ page }) => {
  const unhandled = await mockApi(page, "authenticated");
  const copilotWrites: Record<string, unknown>[] = [];
  await page.route("**/v1/copilot/query", async (route, request) => {
    if (request.method() !== "POST") return route.fallback();
    copilotWrites.push(request.postDataJSON());
    return json(route, 200, {
      status: "ok",
      reply: {
        mode: "evidence_grounded",
        intent: "evidence",
        answer: "The controlled opportunity is supported by one persisted evidence reference. No provider action is executed.",
        citations: [{ kind: "evidence", ref: "browser-quality-controlled-fixture", label: "owned evidence" }],
        workspace_pulse: {
          opportunities: 1, insights: 0, metric_rows: 0, quality_alerts: 0,
          experiments: 0, automation_needs_attention: 0, automation_kill_switch: false
        },
        suggested_prompts: ["What evidence supports the top opportunity?"],
        limitations: [
          "Answers use only persisted data available to the current workspace.",
          "Correlation is not presented as confirmed causality.",
          "Copilot does not publish or execute provider actions; those remain behind existing approval and Autopilot controls."
        ]
      }
    });
  });

  await page.goto("/");
  const toggle = page.getByRole("button", { name: /Copilot.*Evidence grounded/i });
  await expect(toggle).toBeVisible();
  await toggle.click();
  await expect(page.getByRole("heading", { name: "Ask what the evidence supports" })).toBeVisible();
  await page.getByRole("button", { name: "What evidence supports the top opportunity?", exact: true }).click();
  const copilotAnswer = page.getByRole("region", { name: "Copilot answer" });
  await expect(copilotAnswer.getByText("The controlled opportunity is supported by one persisted evidence reference. No provider action is executed.", { exact: true })).toBeVisible();
  await expect(copilotAnswer.getByText("browser-quality-controlled-fixture", { exact: true })).toBeVisible();
  expect(copilotWrites).toEqual([{ message: "What evidence supports the top opportunity?" }]);

  await expectNoHorizontalOverflow(page);
  await expectNoSeriousAccessibilityViolations(page);
  await page.setViewportSize({ width: 390, height: 844 });
  await expectNoHorizontalOverflow(page);
  await expectNoSeriousAccessibilityViolations(page);
  expect(unhandled).toEqual([]);
});


// Controlled fixtures exercise browser behavior only, never factual production data.
const stringCountMetrics = [
  {
    social_account_id: opportunity.social_account_id, platform: "instagram",
    provider_account_id: "browser-quality-account", handle: "browser-quality",
    metric_name: "like_count", observation_count: "10", total_value: "32",
    latest_observed_at: "2026-09-15T01:00:00.000Z",
    latest_effective_at: "2026-09-15T01:00:00.000Z",
    complete_observations: "9", fresh_observations: "10"
  },
  {
    social_account_id: opportunity.social_account_id, platform: "instagram",
    provider_account_id: "browser-quality-account", handle: "browser-quality",
    metric_name: "comments_count", observation_count: "2", total_value: "4",
    latest_observed_at: "2026-09-15T01:00:00.000Z",
    latest_effective_at: "2026-09-15T01:00:00.000Z",
    complete_observations: "2", fresh_observations: "1"
  }
];

test("an evidence-linked recommendation opens the content handoff without auto-creating a draft", async ({ page }) => {
  const unhandled = await mockApi(page, "authenticated");
  const recommendationWrites: Record<string, unknown>[] = [];

  await page.route(`**/v1/opportunities/${opportunity.id}/recommendations`, async (route, request) => {
    if (request.method() !== "POST") return route.fallback();
    recommendationWrites.push(request.postDataJSON());
    return json(route, 200, {
      status: "created",
      recommendation: {
        id: "f0000000-0000-4000-8000-000000000030",
        opportunity_id: opportunity.id,
        action_code: "draft_content",
        status: "proposed",
        rationale: {
          source: "opportunity_radar",
          rule_version: "recommendation.action.v2",
          evidence_count: 1,
          autonomous_execution: false
        },
        feedback_count: 0,
        created_at: "2026-09-15T01:00:00.000Z",
        updated_at: "2026-09-15T01:00:00.000Z"
      }
    });
  });

  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Instagram · US" })).toBeVisible();
  await page.getByRole("button", { name: "Start a content draft", exact: true }).click();

  const authoring = page.locator("#content-authoring-root");
  await expect(authoring.getByRole("button", { name: "Create Content Authoring", exact: true })).toHaveAttribute("aria-expanded", "true");
  await expect(authoring.getByLabel("Objective optional", { exact: true })).toHaveValue(
    "Evidence-linked Instagram opportunity from Opportunity Radar"
  );
  await expect(authoring.getByLabel("Market", { exact: true })).toHaveValue("US");
  await expect(authoring.getByLabel("Platform", { exact: true })).toHaveValue("Instagram");
  await expect(authoring.getByLabel("Draft text", { exact: true })).toHaveValue("");
  await expect(authoring.getByRole("status")).toHaveText(
    "Opportunity context loaded. Add the draft text before saving."
  );
  expect(recommendationWrites).toEqual([{ action_code: "draft_content" }]);
  expect(unhandled).toEqual([]);
  await expectNoHorizontalOverflow(page);
  await expectNoSeriousAccessibilityViolations(page);
});


test("signin and signout update all secondary panels without reload or focus", async ({ page }) => {
  const unhandled = await mockApi(page, "signed_out", stringCountMetrics);
  let documents = 0;
  page.on("request", (request) => { if (request.resourceType() === "document") documents += 1; });
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Sign in to see your next opportunity." })).toBeVisible();

  // Non-secret test-only credentials supplied to a fully mocked, local API.
  await page.getByLabel("Email").fill("browser-quality@example.invalid");
  await page.getByLabel("Password").fill("controlled-browser-quality-password");
  await page.getByRole("button", { name: "Sign in", exact: true }).click();

  const create = page.getByRole("button", { name: "Create Content Authoring", exact: true });
  const analytics = page.getByRole("button", { name: "Analytics Real observations", exact: true });
  await expect(create).toBeVisible();
  await expect(analytics).toBeVisible();
  await expect(page.getByRole("button", { name: "YouTube Data source", exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Instagram Data source", exact: true })).toBeVisible();

  await analytics.click();
  await expect(page.getByRole("heading", { name: "Metric summary", exact: true })).toBeVisible();
  await expect(page.getByText("Complete 11 · Fresh 11", { exact: true })).toBeVisible();
  await expect(page.getByRole("table", { name: "Metric summary" }).getByText("Incomplete", { exact: true })).toBeVisible();
  await expect(page.getByRole("table", { name: "Metric summary" }).getByText("Stale", { exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Sign out", exact: true }).click();

  await expect(page.getByRole("heading", { name: "Sign in to see your next opportunity." })).toBeVisible();
  for (const name of ["Create Content Authoring", "Analytics Real observations", "YouTube Data source", "Instagram Data source"]) {
    await expect(page.getByRole("button", { name, exact: true })).toHaveCount(0);
  }
  await expect(page.getByRole("table", { name: "Metric summary" })).toHaveCount(0);
  expect(documents).toBe(1);
  expect(unhandled).toEqual([]);
});

test("secondary panels can each be opened and closed by pointer on desktop and mobile", async ({ page }) => {
  const unhandled = await mockApi(page, "authenticated", [], [{
    id: "b0000000-0000-4000-8000-000000000002",
    objective: "Controlled long draft title ".repeat(20),
    market: "US", language: "en-US", platform_target: "Instagram",
    source_type: "user", status: "draft", current_version_id: null,
    version_no: 1, body: "Controlled draft body for browser layout verification.",
    created_at: "2026-09-15T01:00:00.000Z"
  }]);
  await page.goto("/");
  for (const size of [{ width: 1440, height: 900 }, { width: 390, height: 844 }]) {
    await page.setViewportSize(size);
    for (const name of ["Create Content Authoring", "Analytics Real observations", "Instagram Data source", "YouTube Data source"]) {
      const toggle = page.getByRole("button", { name, exact: true });
      await expect(toggle).toHaveAttribute("aria-expanded", "false");
      await toggle.click();
      await expect(toggle).toHaveAttribute("aria-expanded", "true");
      await expectNoHorizontalOverflow(page);
      if (name === "Create Content Authoring") {
        const overflow = await page.locator(".content-panel-body").evaluate((panel) => panel.scrollWidth - panel.clientWidth);
        expect(overflow).toBeLessThanOrEqual(1);
      }
      await toggle.click();
      await expect(toggle).toHaveAttribute("aria-expanded", "false");
    }
  }
  expect(unhandled).toEqual([]);
});


test("publication preparation requires an explicit connected account for the draft platform", async ({ page }) => {
  const draftId = "b0000000-0000-4000-8000-000000000003";
  const versionId = "b0000000-0000-4000-8000-000000000004";
  const instagramAccount = "d0000000-0000-4000-8000-000000000002";
  const youtubeAccount = "d0000000-0000-4000-8000-000000000003";
  const unhandled = await mockApi(page, "authenticated", [], [{
    id: draftId, objective: "Controlled publication selection fixture",
    market: "US", language: "en-US", platform_target: "Instagram",
    source_type: "manual", status: "approved", current_version_id: versionId,
    version_no: 2, body: "Test-only draft. No provider request is executed.",
    created_at: "2026-09-15T01:00:00.000Z"
  }]);
  const preparations: Record<string, unknown>[] = [];
  await page.route("**/v1/integrations/instagram/status", (route) => json(route, 200, {
    status: "ok", configured: true, integrations: [{
      connection_state: "connected", social_account_id: instagramAccount,
      handle: "controlled-instagram-account"
    }]
  }));
  await page.route("**/v1/integrations/youtube/status", (route) => json(route, 200, {
    status: "ok", configured: true, derived_analytics_policy_accepted: false,
    integrations: [{ connection_state: "connected", social_account_id: youtubeAccount,
      handle: "controlled-youtube-account" }]
  }));
  await page.route("**/v1/publication-intents", async (route, request) => {
    if (request.method() !== "POST") return route.fallback();
    preparations.push(request.postDataJSON());
    return json(route, 200, { status: "ok", publicationIntent: { id: "controlled-intent" } });
  });
  await page.goto("/");
  const create = page.getByRole("button", { name: "Create Content Authoring", exact: true });
  await expect(create).toBeVisible();
  await create.click();
  await expect(page.getByText(/Saving a draft does not publish it\./)).toBeVisible();
  const account = page.getByRole("combobox", { name: "Publication account", exact: true });
  const prepare = page.getByRole("button", { name: "Prepare publish", exact: true });
  await expect(account).toHaveValue("");
  await expect(prepare).toBeDisabled();
  await expect(account.locator("option")).toHaveCount(2);
  await expect(account.locator("option")).toHaveText(["Choose account", "controlled-instagram-account"]);
  expect(preparations).toEqual([]);
  await account.selectOption(instagramAccount);
  await expect(prepare).toBeEnabled();
  await account.selectOption("");
  await expect(prepare).toBeDisabled();
  expect(preparations).toEqual([]);
  await account.selectOption(instagramAccount);
  await prepare.click();
  await expect(page.getByText("Publication intent created. Execute it from Publishing status when ready.", { exact: true })).toBeVisible();
  expect(preparations).toHaveLength(1);
  expect(preparations[0]).toMatchObject({ socialAccountId: instagramAccount, contentVersionId: versionId });
  // A second authenticated session must require a new account choice.
  await page.getByRole("button", { name: "Sign out", exact: true }).click();
  await expect(page.getByLabel("Email")).toBeVisible();
  await page.getByLabel("Email").fill("browser-quality@example.invalid");
  await page.getByLabel("Password").fill("controlled-browser-quality-password");
  await page.getByRole("button", { name: "Sign in", exact: true }).click();
  await expect(create).toBeVisible();
  await create.click();
  await expect(account).toHaveValue("");
  await expect(prepare).toBeDisabled();
  expect(preparations).toHaveLength(1);
  expect(unhandled).toEqual([]);
});


test("content authoring preserves save acknowledgements through review and approval", async ({ page }) => {
  const unhandled = await mockApi(page, "authenticated");
  const draftId = "b0000000-0000-4000-8000-000000000005";
  const versions = [
    "",
    "b0000000-0000-4000-8000-000000000006",
    "b0000000-0000-4000-8000-000000000007",
    "b0000000-0000-4000-8000-000000000008"
  ];
  const objective = "Controlled editorial lifecycle fixture";
  const rejectedBody = "Controlled rejected version";
  let created = false;
  let version = 1;
  let status = "draft";
  let body = "";
  const writes: { path: string; payload: Record<string, unknown> }[] = [];
  const draft = () => ({
    id: draftId, objective, market: "US", language: "en-US",
    platform_target: "Instagram", source_type: "manual", status,
    current_version_id: versions[version], version_no: version, body,
    created_at: "2026-09-15T01:00:00.000Z"
  });
  const mutationResponse = () => ({
    status: "ok", item: draft(),
    version: { id: versions[version], version_no: version, checksum: "b".repeat(64) }
  });

  await page.route("**/v1/content", async (route, request) => {
    if (request.method() === "GET") return json(route, 200, {
      status: "ok", content: created ? [draft()] : []
    });
    if (request.method() !== "POST") return route.fallback();
    const payload = request.postDataJSON();
    writes.push({ path: "/v1/content", payload });
    body = payload.body;
    created = true;
    return json(route, 200, mutationResponse());
  });
  await page.route(`**/v1/content/${draftId}/versions`, async (route, request) => {
    if (request.method() !== "POST") return route.fallback();
    const payload = request.postDataJSON();
    writes.push({ path: new URL(request.url()).pathname, payload });
    if (payload.body === rejectedBody) return json(route, 400, { status: "validation_failed" });
    version += 1;
    body = payload.body;
    status = "draft";
    return json(route, 200, mutationResponse());
  });
  await page.route("**/v1/content/versions/*/submit-review", async (route, request) => {
    if (request.method() !== "POST") return route.fallback();
    const path = new URL(request.url()).pathname;
    writes.push({ path, payload: request.postDataJSON() });
    if (status !== "draft" || !path.includes(versions[version])) {
      return json(route, 409, { status: "invalid_content_transition" });
    }
    status = "ready_for_review";
    return json(route, 200, {
      status: "ok",
      item: draft(),
      submission: {
        id: "b0000000-0000-4000-8000-000000000099",
        content_version_id: versions[version],
        note: null
      }
    });
  });
  for (const action of ["approve", "request-changes"]) {
    await page.route(`**/v1/content/versions/*/${action}`, async (route, request) => {
      if (request.method() !== "POST") return route.fallback();
      const path = new URL(request.url()).pathname;
      writes.push({ path, payload: request.postDataJSON() });
      if (status !== "ready_for_review" || !path.includes(versions[version])) {
        return json(route, 409, { status: "invalid_content_transition" });
      }
      status = action === "approve" ? "approved" : "draft";
      return json(route, 200, { status: "ok", item: draft(), approval: { decision: action } });
    });
  }

  await page.goto("/");
  await page.getByRole("button", { name: "Create Content Authoring", exact: true }).click();
  await expect(page.getByText("No drafts saved in this workspace yet.", { exact: true })).toBeVisible();
  await page.getByLabel("Objective", { exact: false }).fill(objective);
  await page.getByLabel("Draft text", { exact: true }).fill("Controlled first version.");
  await page.getByRole("button", { name: "Save draft", exact: true }).click();
  await expect(page.getByRole("status")).toContainText("Draft saved · version 1");
  await expect(page.getByLabel("Draft text", { exact: true })).toHaveValue("");
  await expect(page.getByText("Instagram · v1", { exact: true })).toBeVisible();
  expect(writes[0]).toMatchObject({
    path: "/v1/content",
    payload: { objective, market: "US", language: "en-US",
      platformTarget: "Instagram", sourceType: "manual", body: "Controlled first version." }
  });

  await expect(page.getByRole("button", { name: "Approve", exact: true })).toHaveCount(0);
  await page.getByRole("button", { name: "Submit for review", exact: true }).click();
  await expect(page.getByRole("status")).toHaveText(
    "Draft submitted for review. Approval is now available as a separate decision."
  );
  await expect(page.getByRole("button", { name: "Approve", exact: true })).toBeVisible();
  await page.getByRole("button", { name: "Changes", exact: true }).click();
  await expect(page.getByRole("status")).toHaveText("Changes requested. The item returned to draft.");
  await expect(page.getByRole("button", { name: "Approve", exact: true })).toHaveCount(0);

  await page.getByRole("button", { name: "Edit", exact: true }).click();
  await expect(page.getByLabel("Draft text", { exact: true })).toHaveValue("Controlled first version.");
  await expect(page.getByLabel("Platform", { exact: true })).toHaveValue("Instagram");
  await page.getByLabel("Draft text", { exact: true }).fill("Controlled second version.");
  await page.getByRole("button", { name: "Save new version", exact: true }).click();
  await expect(page.getByRole("status")).toContainText("Draft version saved · version 2");
  await expect(page.getByText("Instagram · v2", { exact: true })).toBeVisible();
  await expect(page.getByRole("button", { name: "Approve", exact: true })).toHaveCount(0);
  await page.getByRole("button", { name: "Submit for review", exact: true }).click();
  await page.getByRole("button", { name: "Approve", exact: true }).click();
  await expect(page.getByRole("status")).toHaveText("Version approved. Publishing remains a separate controlled step.");
  await expect(page.getByText("Connect Instagram first.", { exact: true })).toBeVisible();
  await expect(page.getByText("No publication intents exist in this workspace yet.", { exact: true })).toBeVisible();
  expect(writes.map(write => write.path)).toEqual([
    "/v1/content",
    `/v1/content/versions/${versions[1]}/submit-review`,
    `/v1/content/versions/${versions[1]}/request-changes`,
    `/v1/content/${draftId}/versions`,
    `/v1/content/versions/${versions[2]}/submit-review`,
    `/v1/content/versions/${versions[2]}/approve`
  ]);
  expect(writes[1]?.payload).toEqual({});
  expect(writes[4]?.payload).toEqual({});

  // A rejected save keeps the typed text and the last acknowledged version.
  await page.getByRole("button", { name: "Edit", exact: true }).click();
  await page.getByLabel("Draft text", { exact: true }).fill(rejectedBody);
  await page.getByRole("button", { name: "Save new version", exact: true }).click();
  await expect(page.getByRole("status")).toHaveText("Complete the required content fields before saving.");
  await expect(page.getByLabel("Draft text", { exact: true })).toHaveValue(rejectedBody);
  await expect(page.getByRole("heading", { name: "Edit this draft", exact: true })).toBeVisible();
  await expect(page.getByText("Instagram · v2", { exact: true })).toBeVisible();
  expect(version).toBe(2);
  expect(status).toBe("approved");
  expect(writes).toHaveLength(7);
  expect(unhandled).toEqual([]);
  await expectNoHorizontalOverflow(page);
  await expectNoSeriousAccessibilityViolations(page);
});


test("a provider match resolves needs-user-action without sending a second post", async ({ page }) => {
  const publicationIntentId = "f0000000-0000-4000-8000-000000000010";
  const publicationIntent = {
    id: publicationIntentId,
    social_account_id: "d0000000-0000-4000-8000-000000000010",
    content_version_id: "b0000000-0000-4000-8000-000000000010",
    status: "needs_user_action",
    scheduled_for: null,
    current_attempt_no: 3,
    retry_count: 3,
    last_error_class: "provider_timeout",
    provider_content_id: null as string | null,
    provider_permalink: null,
    created_at: "2026-09-15T01:00:00.000Z",
    updated_at: "2026-09-15T01:03:00.000Z",
    cancelled_at: null
  };
  const unhandled = await mockApi(page, "authenticated", [], [], [publicationIntent]);
  const reconciliations: Record<string, unknown>[] = [];

  await page.route(`**/v1/publication-intents/${publicationIntentId}/reconcile`, async (route, request) => {
    if (request.method() !== "POST") return route.fallback();
    const payload = request.postDataJSON() as Record<string, unknown>;
    reconciliations.push(payload);
    publicationIntent.status = "confirmed";
    publicationIntent.provider_content_id = String(payload.candidateProviderContentId);
    return json(route, 200, {
      status: "reconciled",
      reconciliation: { publication_intent_id: publicationIntentId, reconciliation_status: "matched" }
    });
  });

  await page.goto("/");
  await page.getByRole("button", { name: "Create Content Authoring", exact: true }).click();

  const providerId = page.getByLabel("Provider content ID for attempt 3", { exact: true });
  const evidence = page.getByLabel("Evidence reference for attempt 3", { exact: true });
  const confirm = page.getByRole("button", { name: "Confirm provider match", exact: true });

  await expect(page.getByText(/This records existing provider content and never sends a second post./)).toBeVisible();
  await expect(confirm).toBeDisabled();
  await providerId.fill("provider-post-controlled-001");
  await expect(confirm).toBeDisabled();
  await evidence.fill("https://provider.example.invalid/posts/provider-post-controlled-001");
  await expect(confirm).toBeEnabled();
  await confirm.click();

  await expect(page.getByRole("status")).toHaveText(
    "Provider match confirmed. The existing provider content is now recorded; no second post was sent."
  );
  await expect(page.getByText("confirmed", { exact: true }).first()).toBeVisible();
  await expect(providerId).toHaveCount(0);
  expect(reconciliations).toEqual([{
    attemptNo: 3,
    method: "manual",
    confidence: "high",
    reconciliationStatus: "matched",
    candidateProviderContentId: "provider-post-controlled-001",
    evidenceRef: "https://provider.example.invalid/posts/provider-post-controlled-001"
  }]);

  await expectNoHorizontalOverflow(page);
  await expectNoSeriousAccessibilityViolations(page);
  expect(unhandled).toEqual([]);
});


test("stored experiment outcomes survive reload and close the learning step", async ({ page }) => {
  const experimentId = "f0000000-0000-4000-8000-000000000020";
  const variantId = "f0000000-0000-4000-8000-000000000021";
  const experiment = {
    id: experimentId,
    opportunity_id: opportunity.id,
    name: "Controlled learning fixture",
    hypothesis: "A measured variant improves the primary signal.",
    decision_rule: "Select a winner only from stored outcome evidence.",
    status: "running",
    variant_count: 1,
    created_at: "2026-09-15T01:00:00.000Z",
    updated_at: "2026-09-15T01:05:00.000Z"
  };
  const variant = {
    id: variantId,
    experiment_id: experimentId,
    label: "Evidence-backed variant A",
    lineage: { source_opportunity_id: opportunity.id, autonomous_publishing: false },
    status: "active",
    created_at: "2026-09-15T01:02:00.000Z",
    latest_outcome: null as string | null,
    latest_evidence_ref: null as string | null,
    feedback_created_at: null as string | null
  };
  const recommendation = {
    id: "f0000000-0000-4000-8000-000000000022",
    opportunity_id: opportunity.id,
    action_code: "draft_content",
    status: "proposed",
    rationale: {
      source: "opportunity_radar",
      rule_version: "recommendation.action.v2",
      evidence_count: 1,
      autonomous_execution: false,
      learning: {
        rule_version: "opportunity.learning.v1",
        completed_experiment_count: 0,
        winner_count: 0,
        recommendation_feedback: { accepted: 0, completed: 0, dismissed: 0, irrelevant: 0 },
        latest_winner: null as null | {
          experiment_id: string;
          variant_id: string;
          label: string;
          evidence_ref: string;
          recorded_at: string;
        }
      }
    },
    feedback_count: 0,
    created_at: "2026-09-15T01:00:00.000Z",
    updated_at: "2026-09-15T01:05:00.000Z"
  };
  const feedbackWrites: Record<string, unknown>[] = [];
  const unhandled = await mockApi(page, "authenticated");

  await page.route(/\/v1\/recommendations\?/, async (route, request) => {
    if (request.method() !== "GET") return route.fallback();
    return json(route, 200, { status: "ok", recommendations: [recommendation] });
  });
  await page.route("**/v1/experiments", async (route, request) => {
    if (request.method() !== "GET") return route.fallback();
    return json(route, 200, { status: "ok", experiments: [experiment] });
  });
  await page.route(`**/v1/experiments/${experimentId}/variants`, async (route, request) => {
    if (request.method() !== "GET") return route.fallback();
    return json(route, 200, { status: "ok", variants: [variant] });
  });
  await page.route(`**/v1/experiments/${experimentId}/feedback`, async (route, request) => {
    if (request.method() !== "POST") return route.fallback();
    const payload = request.postDataJSON() as Record<string, unknown>;
    feedbackWrites.push(payload);
    experiment.status = "completed";
    variant.status = "winner";
    variant.latest_outcome = "winner";
    variant.latest_evidence_ref = String(payload.evidence_ref);
    variant.feedback_created_at = "2026-09-15T01:10:00.000Z";
    recommendation.updated_at = "2026-09-15T01:10:00.000Z";
    recommendation.rationale.learning.completed_experiment_count = 1;
    recommendation.rationale.learning.winner_count = 1;
    recommendation.rationale.learning.latest_winner = {
      experiment_id: experimentId,
      variant_id: variantId,
      label: variant.label,
      evidence_ref: String(payload.evidence_ref),
      recorded_at: "2026-09-15T01:10:00.000Z"
    };
    return json(route, 200, { status: "recorded", feedback: { outcome: "winner" } });
  });

  await page.goto("/");
  await expect(page.getByRole("heading", { name: "Plan, measure and learn" })).toBeVisible();
  await expect(page.getByText("Controlled learning fixture", { exact: true })).toBeVisible();
  await expect(page.getByText(/Active · awaiting outcome/)).toBeVisible();

  const recordOutcome = page.getByRole("button", { name: "Record outcome", exact: true });
  await expect(recordOutcome).toBeDisabled();
  await page.getByLabel("Outcome evidence", { exact: true }).fill("controlled-metric-snapshot://variant-a");
  await page.getByLabel("Learning note", { exact: false }).fill("Retain the measured winning structure.");
  await expect(recordOutcome).toBeEnabled();
  await recordOutcome.click();

  await expect(page.getByRole("status")).toHaveText(
    "Outcome recorded from evidence. Growth OS will preserve this result for the next decision."
  );
  await expect(page.getByText(/Completed · A measured variant improves/)).toBeVisible();
  await expect(page.getByText(/Winner · latest outcome: Winner/)).toBeVisible();
  await expect(page.getByLabel("Measured learning applied")).toContainText("Winner: Evidence-backed variant A");
  await expect(page.getByLabel("Measured learning applied")).toContainText("Evidence: controlled-metric-snapshot://variant-a");
  await expect(page.getByRole("button", { name: "Record outcome", exact: true })).toHaveCount(0);
  expect(feedbackWrites).toEqual([{
    variant_id: variantId,
    outcome: "winner",
    evidence_ref: "controlled-metric-snapshot://variant-a",
    note: "Retain the measured winning structure."
  }]);

  await page.reload();
  await expect(page.getByText("Controlled learning fixture", { exact: true })).toBeVisible();
  await expect(page.getByText(/Winner · latest outcome: Winner/)).toBeVisible();
  await expect(page.getByLabel("Measured learning applied")).toContainText("Winner: Evidence-backed variant A");
  await expectNoHorizontalOverflow(page);
  await expectNoSeriousAccessibilityViolations(page);
  expect(unhandled).toEqual([]);
});



test("controlled full Growth OS loop carries evidence through publish, measure, learn and recommend", async ({ page }) => {
  const unhandled = await mockApi(page, "authenticated");
  const draftId = "b0000000-0000-4000-8000-000000000110";
  const versionId = "b0000000-0000-4000-8000-000000000111";
  const instagramAccount = "d0000000-0000-4000-8000-000000000110";
  const publicationIntentId = "f0000000-0000-4000-8000-000000000110";
  const experimentId = "f0000000-0000-4000-8000-000000000120";
  const variantId = "f0000000-0000-4000-8000-000000000121";
  const metricEvidence = "controlled-provider-metrics://provider-post-full-loop-001";

  let recommendationCreated = false;
  let draftCreated = false;
  let draftStatus = "draft";
  let draftBody = "";
  const writes: { path: string; payload: Record<string, unknown> }[] = [];
  let metrics: unknown[] = [];

  const draft = () => ({
    id: draftId,
    objective: "Evidence-linked Instagram opportunity from Opportunity Radar",
    market: "US",
    language: "en-US",
    platform_target: "Instagram",
    source_type: "manual",
    status: draftStatus,
    current_version_id: versionId,
    version_no: 1,
    body: draftBody,
    created_at: "2026-09-15T01:00:00.000Z"
  });

  const publicationIntent = {
    id: publicationIntentId,
    social_account_id: instagramAccount,
    content_version_id: versionId,
    status: "ready",
    scheduled_for: null,
    current_attempt_no: null as number | null,
    retry_count: 0,
    last_error_class: null,
    provider_content_id: null as string | null,
    provider_permalink: null as string | null,
    created_at: "2026-09-15T01:06:00.000Z",
    updated_at: "2026-09-15T01:06:00.000Z",
    cancelled_at: null
  };
  let publicationCreated = false;

  const experiment = {
    id: experimentId,
    opportunity_id: opportunity.id,
    name: "Full-loop measured outcome",
    hypothesis: "Provider-observed engagement supports retaining the tested structure.",
    decision_rule: "Select a winner only from stored provider metric evidence.",
    status: "running",
    variant_count: 1,
    created_at: "2026-09-15T01:07:00.000Z",
    updated_at: "2026-09-15T01:07:00.000Z"
  };
  const variant = {
    id: variantId,
    experiment_id: experimentId,
    label: "Provider-measured variant",
    lineage: { source_opportunity_id: opportunity.id, autonomous_publishing: false },
    status: "active",
    created_at: "2026-09-15T01:07:00.000Z",
    latest_outcome: null as string | null,
    latest_evidence_ref: null as string | null,
    feedback_created_at: null as string | null
  };
  const recommendation = {
    id: "f0000000-0000-4000-8000-000000000122",
    opportunity_id: opportunity.id,
    action_code: "draft_content",
    status: "proposed",
    rationale: {
      source: "opportunity_radar",
      rule_version: "recommendation.action.v2",
      evidence_count: 1,
      autonomous_execution: false,
      learning: {
        rule_version: "opportunity.learning.v1",
        completed_experiment_count: 0,
        winner_count: 0,
        recommendation_feedback: { accepted: 0, completed: 0, dismissed: 0, irrelevant: 0 },
        latest_winner: null as null | {
          experiment_id: string;
          variant_id: string;
          label: string;
          evidence_ref: string;
          recorded_at: string;
        }
      }
    },
    feedback_count: 0,
    created_at: "2026-09-15T01:00:00.000Z",
    updated_at: "2026-09-15T01:00:00.000Z"
  };

  await page.route(new RegExp("/v1/recommendations\\?"), async (route, request) => {
    if (request.method() !== "GET") return route.fallback();
    return json(route, 200, {
      status: "ok",
      recommendations: recommendationCreated ? [recommendation] : []
    });
  });
  await page.route("**/v1/opportunities/" + opportunity.id + "/recommendations", async (route, request) => {
    if (request.method() !== "POST") return route.fallback();
    const payload = request.postDataJSON() as Record<string, unknown>;
    writes.push({ path: new URL(request.url()).pathname, payload });
    recommendationCreated = true;
    return json(route, 200, { status: "created", recommendation });
  });

  await page.route("**/v1/content", async (route, request) => {
    if (request.method() === "GET") {
      return json(route, 200, { status: "ok", content: draftCreated ? [draft()] : [] });
    }
    if (request.method() !== "POST") return route.fallback();
    const payload = request.postDataJSON() as Record<string, unknown>;
    writes.push({ path: "/v1/content", payload });
    draftBody = String(payload.body);
    draftCreated = true;
    draftStatus = "draft";
    return json(route, 200, {
      status: "ok",
      item: draft(),
      version: { id: versionId, version_no: 1, checksum: "c".repeat(64) }
    });
  });
  await page.route("**/v1/content/versions/" + versionId + "/submit-review", async (route, request) => {
    if (request.method() !== "POST") return route.fallback();
    writes.push({ path: new URL(request.url()).pathname, payload: request.postDataJSON() });
    if (draftStatus !== "draft") return json(route, 409, { status: "invalid_content_transition" });
    draftStatus = "ready_for_review";
    return json(route, 200, {
      status: "ok",
      item: draft(),
      submission: { id: "b0000000-0000-4000-8000-000000000112", content_version_id: versionId, note: null }
    });
  });
  await page.route("**/v1/content/versions/" + versionId + "/approve", async (route, request) => {
    if (request.method() !== "POST") return route.fallback();
    writes.push({ path: new URL(request.url()).pathname, payload: request.postDataJSON() });
    if (draftStatus !== "ready_for_review") return json(route, 409, { status: "invalid_content_transition" });
    draftStatus = "approved";
    return json(route, 200, { status: "ok", item: draft(), approval: { decision: "approve" } });
  });

  await page.route("**/v1/integrations/instagram/status", (route) => json(route, 200, {
    status: "ok",
    configured: true,
    integrations: [{
      connection_state: "connected",
      social_account_id: instagramAccount,
      handle: "controlled-full-loop-instagram"
    }]
  }));

  await page.route("**/v1/publication-intents", async (route, request) => {
    if (request.method() === "GET") {
      return json(route, 200, {
        status: "ok",
        publicationIntents: publicationCreated ? [publicationIntent] : []
      });
    }
    if (request.method() !== "POST") return route.fallback();
    const payload = request.postDataJSON() as Record<string, unknown>;
    writes.push({ path: "/v1/publication-intents", payload });
    publicationCreated = true;
    return json(route, 200, { status: "created", publicationIntent });
  });
  await page.route("**/v1/publication-intents/" + publicationIntentId + "/execute", async (route, request) => {
    if (request.method() !== "POST") return route.fallback();
    writes.push({ path: new URL(request.url()).pathname, payload: {} });
    publicationIntent.status = "confirmed";
    publicationIntent.current_attempt_no = 1;
    publicationIntent.provider_content_id = "provider-post-full-loop-001";
    publicationIntent.provider_permalink = "https://provider.example.invalid/posts/provider-post-full-loop-001";
    publicationIntent.updated_at = "2026-09-15T01:08:00.000Z";
    metrics = [{
      social_account_id: instagramAccount,
      platform: "instagram",
      provider_account_id: "controlled-full-loop-instagram",
      handle: "controlled-full-loop-instagram",
      metric_name: "like_count",
      observation_count: 1,
      total_value: 24,
      latest_observed_at: "2026-09-15T01:09:00.000Z",
      latest_effective_at: "2026-09-15T01:09:00.000Z",
      complete_observations: 1,
      fresh_observations: 1
    }];
    return json(route, 200, { status: "processed", publicationIntent });
  });
  await page.route("**/v1/analytics/metrics**", async (route, request) => {
    if (request.method() !== "GET") return route.fallback();
    return json(route, 200, {
      status: "ok",
      from: "2026-09-08T00:00:00.000Z",
      to: "2026-09-15T02:00:00.000Z",
      metrics
    });
  });

  await page.route("**/v1/experiments", async (route, request) => {
    if (request.method() !== "GET") return route.fallback();
    return json(route, 200, { status: "ok", experiments: [experiment] });
  });
  await page.route("**/v1/experiments/" + experimentId + "/variants", async (route, request) => {
    if (request.method() !== "GET") return route.fallback();
    return json(route, 200, { status: "ok", variants: [variant] });
  });
  await page.route("**/v1/experiments/" + experimentId + "/feedback", async (route, request) => {
    if (request.method() !== "POST") return route.fallback();
    const payload = request.postDataJSON() as Record<string, unknown>;
    writes.push({ path: new URL(request.url()).pathname, payload });
    experiment.status = "completed";
    variant.status = "winner";
    variant.latest_outcome = "winner";
    variant.latest_evidence_ref = String(payload.evidence_ref);
    variant.feedback_created_at = "2026-09-15T01:10:00.000Z";
    recommendation.updated_at = "2026-09-15T01:10:00.000Z";
    recommendation.rationale.learning.completed_experiment_count = 1;
    recommendation.rationale.learning.winner_count = 1;
    recommendation.rationale.learning.latest_winner = {
      experiment_id: experimentId,
      variant_id: variantId,
      label: variant.label,
      evidence_ref: String(payload.evidence_ref),
      recorded_at: "2026-09-15T01:10:00.000Z"
    };
    return json(route, 200, { status: "recorded", feedback: { outcome: "winner" } });
  });

  await page.goto("/");
  await page.getByRole("button", { name: "Start a content draft", exact: true }).click();
  const authoring = page.locator("#content-authoring-root");
  await expect(authoring.getByLabel("Objective optional", { exact: true })).toHaveValue(
    "Evidence-linked Instagram opportunity from Opportunity Radar"
  );
  await authoring.getByLabel("Draft text", { exact: true }).fill("Controlled full-loop content body.");
  await authoring.getByRole("button", { name: "Save draft", exact: true }).click();
  await expect(authoring.getByRole("status")).toContainText("Draft saved · version 1");

  await authoring.getByRole("button", { name: "Submit for review", exact: true }).click();
  await expect(authoring.getByRole("button", { name: "Approve", exact: true })).toBeVisible();
  await authoring.getByRole("button", { name: "Approve", exact: true }).click();
  await expect(authoring.getByRole("status")).toHaveText(
    "Version approved. Publishing remains a separate controlled step."
  );

  const account = authoring.getByRole("combobox", { name: "Publication account", exact: true });
  await account.selectOption(instagramAccount);
  await authoring.getByRole("button", { name: "Prepare publish", exact: true }).click();
  await expect(authoring.getByRole("status")).toHaveText(
    "Publication intent created. Execute it from Publishing status when ready."
  );
  await authoring.getByRole("button", { name: "Execute", exact: true }).click();
  await expect(authoring.getByRole("status")).toHaveText(
    "Publication attempt processed. Review the resulting status and provider id."
  );
  await expect(authoring.getByText("Provider content id recorded.", { exact: true })).toBeVisible();

  await page.reload();
  await page.getByRole("button", { name: "Analytics Real observations", exact: true }).click();
  const metricTable = page.getByRole("table", { name: "Metric summary" });
  await expect(metricTable.getByText("like_count", { exact: true })).toBeVisible();
  await expect(page.getByText("Complete 1 · Fresh 1", { exact: true })).toBeVisible();

  await expect(page.getByRole("heading", { name: "Plan, measure and learn" })).toBeVisible();
  await page.getByLabel("Outcome evidence", { exact: true }).fill(metricEvidence);
  await page.getByLabel("Learning note", { exact: false }).fill(
    "Retain the structure because the provider metric evidence supports it."
  );
  await page.getByRole("button", { name: "Record outcome", exact: true }).click();

  await expect(page.getByLabel("Measured learning applied")).toContainText(
    "Winner: Provider-measured variant"
  );
  await expect(page.getByLabel("Measured learning applied")).toContainText(
    "Evidence: " + metricEvidence
  );

  expect(writes.map((write) => write.path)).toEqual([
    "/v1/opportunities/" + opportunity.id + "/recommendations",
    "/v1/content",
    "/v1/content/versions/" + versionId + "/submit-review",
    "/v1/content/versions/" + versionId + "/approve",
    "/v1/publication-intents",
    "/v1/publication-intents/" + publicationIntentId + "/execute",
    "/v1/experiments/" + experimentId + "/feedback"
  ]);
  expect(writes[0]?.payload).toEqual({ action_code: "draft_content" });
  expect(writes[4]?.payload).toMatchObject({
    socialAccountId: instagramAccount,
    contentVersionId: versionId
  });
  expect(writes[6]?.payload).toEqual({
    variant_id: variantId,
    outcome: "winner",
    evidence_ref: metricEvidence,
    note: "Retain the structure because the provider metric evidence supports it."
  });

  await expectNoHorizontalOverflow(page);
  await expectNoSeriousAccessibilityViolations(page);
  expect(unhandled).toEqual([]);
});

test("team owners can invite and update members from the product surface", async ({ page }) => {
  const unhandled = await mockApi(page, "authenticated");
  const memberId = "a0000000-0000-4000-8000-000000000002";
  const invitations: Record<string, unknown>[] = [];
  const updates: Record<string, unknown>[] = [];
  let member = {
    user_id: memberId,
    role: "editor",
    can_publish: false,
    status: "active",
    created_at: "2026-09-15T01:00:00.000Z"
  };

  await page.route(`**/v1/workspaces/${workspace.id}/members`, async (route, request) => {
    if (request.method() !== "GET") return route.fallback();
    return json(route, 200, {
      status: "ok",
      members: [{
        user_id: session.session.user_id,
        role: "owner",
        can_publish: true,
        status: "active",
        created_at: "2026-09-15T00:00:00.000Z"
      }, member]
    });
  });
  await page.route(`**/v1/workspaces/${workspace.id}/invitations`, async (route, request) => {
    if (request.method() !== "POST") return route.fallback();
    invitations.push(request.postDataJSON());
    return json(route, 202, { status: "invitation_sent" });
  });
  await page.route(`**/v1/workspaces/${workspace.id}/members/${memberId}`, async (route, request) => {
    if (request.method() !== "PATCH") return route.fallback();
    const payload = request.postDataJSON();
    updates.push(payload);
    member = { ...member, ...{
      role: payload.role,
      can_publish: payload.canPublish,
      status: payload.status
    }};
    return json(route, 200, { status: "ok", member });
  });

  await page.goto("/");
  await page.getByRole("button", { name: "Manage team" }).click();
  const dialog = page.getByRole("dialog", { name: "Team and invitations" });
  await expect(dialog).toBeVisible();
  await dialog.getByLabel("Email", { exact: true }).fill("teammate@example.invalid");
  await dialog.getByLabel("Invitation role", { exact: true }).selectOption("viewer");
  await dialog.getByLabel("Allow controlled publishing").check();
  await dialog.getByRole("button", { name: "Send invitation" }).click();
  await expect(dialog.getByRole("status")).toHaveText("Invitation sent to teammate@example.invalid.");
  expect(invitations).toEqual([{
    email: "teammate@example.invalid",
    role: "viewer",
    canPublish: true
  }]);

  await dialog.getByLabel("Role for Member a0000000").selectOption("viewer");
  await dialog.getByLabel("Publishing permission for Member a0000000").check();
  await dialog.getByRole("button", { name: "Save" }).click();
  await expect(dialog.getByRole("status")).toHaveText("Member a0000000 updated.");
  expect(updates).toEqual([{ role: "viewer", canPublish: true, status: "active" }]);

  await expectNoHorizontalOverflow(page);
  await expectNoSeriousAccessibilityViolations(page);
  await dialog.getByRole("button", { name: "Close team management" }).click();
  await expect(dialog).toHaveCount(0);
  expect(unhandled).toEqual([]);
});

test("a signed-in invited user can accept a one-time workspace link", async ({ page }) => {
  const unhandled = await mockApi(page, "authenticated");
  const accepted: Record<string, unknown>[] = [];
  await page.route("**/v1/auth/invitations/accept", async (route, request) => {
    if (request.method() !== "POST") return route.fallback();
    accepted.push(request.postDataJSON());
    return json(route, 200, { status: "accepted", workspace_id: workspace.id });
  });

  const token = "controlled-browser-invitation-token-1234567890";
  await page.goto(`/accept-invitation?token=${token}`);
  await expect(page.getByRole("heading", { name: "Join the workspace securely." })).toBeVisible();
  await expect(page.getByText("invitation token hidden")).toBeVisible();
  await page.getByRole("button", { name: "Accept invitation" }).click();
  await expect(page).toHaveURL("/");
  await expect(page.getByRole("heading", { name: "See what is beginning to move." })).toBeVisible();
  expect(accepted).toEqual([{ token }]);
  expect(unhandled).toEqual([]);
});
