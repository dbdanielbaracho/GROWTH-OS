from pathlib import Path

path = Path("apps/web/src/main.tsx")
text = path.read_text()
old = 'setMessage("Execution stopped safely because the approved request did not contain every required binding.");'
new = 'setMessage("Execution stopped safely. Review the stored reason and result reference before creating a new bounded request; Growth OS did not mark an unconfirmed provider action as successful.");'
if old not in text:
    raise SystemExit("expected automation needs-input message not found")
path.write_text(text.replace(old, new, 1))
print("automation UI needs-input message patched")
