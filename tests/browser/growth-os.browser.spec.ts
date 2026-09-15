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

async function mockApi(page: Page, mode: "signed_out" | "authenticated") {
  const unhandled: string[] = [];

  await page.route("**/v1/**", async (route) => {
    const url = new URL(route.request().url());
    const path = url.pathname;

    if (path === "/v1/auth/session") {
      if (mode === "signed_out") return json(route, 401, { status: "unauthorized" });
      return json(route, 200, session);
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
