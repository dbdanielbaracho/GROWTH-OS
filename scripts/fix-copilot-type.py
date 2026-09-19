from pathlib import Path

path = Path("apps/api/src/copilot.ts")
text = path.read_text()
old = '''  } else if (intent === "experiments") {
    if (data.experiments.length === 0) {
      answer = "No experiment is stored in this workspace yet. A winner or loser cannot be declared without a persisted experiment, variant and evidence-backed outcome.";
    } else {
      const experiment = data.experiments[0];
      const winners = data.topExperimentVariants.filter((row) => row.status === "winner");
      const losers = data.topExperimentVariants.filter((row) => row.status === "loser");
      answer = `The latest experiment is “${experiment.name}” (${experiment.status}) with ${data.topExperimentVariants.length} stored variant${data.topExperimentVariants.length === 1 ? "" : "s"}. ${winners.length} winner${winners.length === 1 ? "" : "s"} and ${losers.length} loser${losers.length === 1 ? "" : "s"} are currently recorded. Outcomes are only treated as measured learning when an evidence reference was stored.`;
      citations.push({ kind: "experiment", ref: experiment.id, label: experiment.name });
      for (const row of data.topExperimentVariants.slice(0, 5)) citations.push({ kind: "experiment", ref: row.id, label: `${row.label} · ${row.status}` });
    }
'''
new = '''  } else if (intent === "experiments") {
    const experiment = data.experiments[0];
    if (!experiment) {
      answer = "No experiment is stored in this workspace yet. A winner or loser cannot be declared without a persisted experiment, variant and evidence-backed outcome.";
    } else {
      const winners = data.topExperimentVariants.filter((row) => row.status === "winner");
      const losers = data.topExperimentVariants.filter((row) => row.status === "loser");
      answer = `The latest experiment is “${experiment.name}” (${experiment.status}) with ${data.topExperimentVariants.length} stored variant${data.topExperimentVariants.length === 1 ? "" : "s"}. ${winners.length} winner${winners.length === 1 ? "" : "s"} and ${losers.length} loser${losers.length === 1 ? "" : "s"} are currently recorded. Outcomes are only treated as measured learning when an evidence reference was stored.`;
      citations.push({ kind: "experiment", ref: experiment.id, label: experiment.name });
      for (const row of data.topExperimentVariants.slice(0, 5)) citations.push({ kind: "experiment", ref: row.id, label: `${row.label} · ${row.status}` });
    }
'''
if old not in text:
    raise SystemExit("expected copilot experiment block not found")
path.write_text(text.replace(old, new, 1))

memory = Path("docs/PROJECT_EXECUTION_MEMORY.md")
entry = '''\n- CI #1300 (`35454381986`) no head `7f21ed9eafcc6aef260eb656e26dd1d7437ce45f` passou Test Integrity e Release Hardening, mas o TypeScript rejeitou o acesso a `data.experiments[0]` como possivelmente `undefined`. A correção usa uma guarda explícita `if (!experiment)`; nenhum gate foi enfraquecido.\n'''
current = memory.read_text()
if "CI #1300 (`35454381986`)" not in current:
    memory.write_text(current + entry)
