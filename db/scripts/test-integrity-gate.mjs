#!/usr/bin/env node
// Growth OS — Test Integrity Gate.
//
// Statically scans every .mts/.ts test file and SQL file in the repository
// (excluding node_modules and dist) for classes of false-green assertions:
// patterns that make a test report PASS without actually proving the
// condition its name claims. Exits non-zero — failing CI — if any REAL
// DEFECT pattern is found in live code (not inside a comment).
//
// Origin: this gate exists because two vacuous assertions
// (`.every((r) => true)`, a bare `check(..., true)`) were physically found
// in apps/api/rc9-integration/identity-bootstrap.mts during a security
// review, and both had been silently reporting PASS. The fix to those two
// lines was necessary but not sufficient — this script is the fix to the
// METHOD that let them exist undetected, run once as part of every CI run,
// not just once as a manual pass.
//
// Design constraints:
// - Zero false positives on the current, already-corrected codebase is a
//   hard requirement — verified by running this script against the repo
//   before it is committed.
// - Matches are line-based and skip lines that are themselves comments
//   (a line whose trimmed content starts with `//` or `*` inside a block
//   comment), so this script's own doc-comments about vacuous patterns
//   (like the one above) do not trigger it.
// - This is intentionally conservative: some categories from the audit
//   (catches that swallow real failures, negative tests that don't verify
//   rejection state, fake concurrency) are not reliably detectable by
//   static pattern matching alone and are handled by manual review +
//   physical execution instead, documented in
//   db/TEST_INTEGRITY_METHOD_HARDENING.md. This script covers exactly the
//   classes that ARE reliably, mechanically detectable: literal-true
//   assertions, vacuous predicates, disabled/skipped tests,
//   self-comparison tautologies, and ignored psql quit status arguments.

import { readdirSync, readFileSync, statSync } from "node:fs";
import { join, extname } from "node:path";

const ROOT = process.cwd();
const SKIP_DIRS = new Set(["node_modules", "dist", ".git", "coverage"]);
const TEST_EXTENSIONS = new Set([".mts", ".ts"]);
const SQL_EXTENSION = ".sql";

/** @type {{file: string, line: number, pattern: string, text: string}[]} */
const findings = [];

const RULES = [
  {
    name: "literal-true-assertion",
    // check(..., true) / assert(true) / expect(true) as the ENTIRE
    // condition argument — a hardcoded pass, not a computed one.
    regex: /\b(check|assert)\s*\([^,()]*,\s*true\s*[,)]|expect\s*\(\s*true\s*\)/,
  },
  {
    name: "vacuous-every-true",
    // .every((x) => true) or .every(() => true) — always true regardless
    // of array contents, the classic disguised no-op predicate.
    regex: /\.every\s*\(\s*(\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>\s*true\s*\)/,
  },
  {
    name: "vacuous-some-false",
    // .some((x) => false) — the inverse disguise, always false.
    regex: /\.some\s*\(\s*(\([^)]*\)|[A-Za-z_$][\w$]*)\s*=>\s*false\s*\)/,
  },
  {
    name: "disabled-test",
    // .skip(...), xit(...), xdescribe(...), .todo(...) — a test that
    // never runs at all, silently absent from the pass count.
    regex: /\.(skip|todo)\s*\(|(^|[^A-Za-z0-9_])xit\s*\(|(^|[^A-Za-z0-9_])xdescribe\s*\(/,
  },
  {
    name: "self-comparison-tautology",
    // x === x / x == x — always true (or, negated, always false),
    // comparing a value against itself rather than an expected value.
    regex: /\b([A-Za-z_$][\w$]*(?:\.[A-Za-z_$][\w$]*)*)\s*===?\s*\1\b/,
  },
];

function isCommentLine(line) {
  const trimmed = line.trim();
  return trimmed.startsWith("//") || trimmed.startsWith("*") || trimmed.startsWith("/*");
}

function walk(dir) {
  for (const entry of readdirSync(dir)) {
    if (SKIP_DIRS.has(entry)) continue;
    const full = join(dir, entry);
    const st = statSync(full);
    if (st.isDirectory()) {
      walk(full);
    } else if (TEST_EXTENSIONS.has(extname(entry))) {
      scanFile(full);
    } else if (extname(entry) === SQL_EXTENSION) {
      scanSqlFile(full);
    }
  }
}

function scanSqlFile(path) {
  const text = readFileSync(path, "utf8");
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const trimmed = lines[i].trim();
    if (trimmed.startsWith("--")) continue;
    if (/^\\(?:q|quit)\s+\d+\s*$/.test(trimmed)) {
      findings.push({
        file: path.replace(ROOT + "/", ""),
        line: i + 1,
        pattern: "psql-quit-status-is-ignored",
        text: trimmed,
      });
    }
  }
}

function scanFile(path) {
  const text = readFileSync(path, "utf8");
  const lines = text.split("\n");
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    if (isCommentLine(line)) continue;
    for (const rule of RULES) {
      if (rule.regex.test(line)) {
        findings.push({
          file: path.replace(ROOT + "/", ""),
          line: i + 1,
          pattern: rule.name,
          text: line.trim(),
        });
      }
    }
  }
}

walk(ROOT);

if (findings.length > 0) {
  console.error(`TEST INTEGRITY GATE: FAILED — ${findings.length} suspicious pattern(s) found in live code:\n`);
  for (const f of findings) {
    console.error(`  ${f.file}:${f.line}  [${f.pattern}]\n    ${f.text}\n`);
  }
  console.error(
    "Each of these looks like a false-green pattern: an assertion that can pass\n" +
    "regardless of the actual condition it claims to test. If this is a genuine\n" +
    "positive (e.g. a documented, reviewed exception), move the pattern out of\n" +
    "live code — comments are not scanned — or replace it with a real,\n" +
    "computed assertion.\n"
  );
  process.exit(1);
} else {
  console.log("TEST INTEGRITY GATE: PASSED — no false-green patterns found in live test code.");
  process.exit(0);
}
