from pathlib import Path

path = Path("tests/browser/growth-os.browser.spec.ts")
text = path.read_text()
old = '''  await expect(page.getByText("The controlled opportunity is supported by one persisted evidence reference. No provider action is executed.", { exact: true })).toBeVisible();
  await expect(page.getByText("browser-quality-controlled-fixture", { exact: true })).toBeVisible();
'''
new = '''  const copilotAnswer = page.getByRole("region", { name: "Copilot answer" });
  await expect(copilotAnswer.getByText("The controlled opportunity is supported by one persisted evidence reference. No provider action is executed.", { exact: true })).toBeVisible();
  await expect(copilotAnswer.getByText("browser-quality-controlled-fixture", { exact: true })).toBeVisible();
'''
if old not in text:
    raise SystemExit("Copilot browser assertion anchor not found")
path.write_text(text.replace(old, new, 1))
