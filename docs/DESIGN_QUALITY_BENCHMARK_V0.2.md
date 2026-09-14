# Growth OS — Design Quality Benchmark and Acceptance v0.2

**Status:** active design-quality requirement  
**Scope:** Growth OS user-facing product experience  
**Baseline:** editorial, high-contrast Growth OS shell merged through PR #39  
**Rule:** an implemented visual direction is a working baseline, not proof that Growth OS is superior to competitors.

## 1. Objective

Build a user experience that is demonstrably better than the relevant competitors for the core job:

> identify the next credible organic-growth opportunity, understand why it matters, and take the next safe action with minimal friction.

“Better design” combines visual quality with product effectiveness:

- clear primary decision;
- low interaction friction;
- understandable evidence and uncertainty;
- fast movement from opportunity to action;
- strong desktop and mobile behavior;
- accessibility and recovery;
- visual coherence and trust;
- a distinctive intelligence-first position.

## 2. Adopted visual direction

The active working direction is the editorial baseline already implemented in Growth OS:

- graphite/black high-contrast foundation;
- strong editorial typography and hierarchy;
- gold used as an opportunity/action accent;
- evidence-first surfaces and truthful empty/degraded states;
- signal → evidence → opportunity → action as the narrative flow;
- Growth Brain shown as context for a decision, not as a separate complexity panel;
- no copied brand, text, interface, code or proprietary method from Doxa Viral or another benchmark.

This direction supersedes the earlier generic dashboard proposals. It is a working baseline, not a visual freeze.

## 3. Product design principles

1. One intelligent feed is the default surface; advanced views remain secondary.
2. The product must make the outcome and next safe action clear.
3. Internal model, scoring and orchestration complexity stays hidden unless needed by the user.
4. Every recommendation must expose only evidence and confidence that actually exist.
5. Loading, empty, error, denied, degraded and recovery states are first-class design states.
6. No synthetic opportunity, explanation, metric or action may be used to make the interface appear complete.
7. Language must be simple, outcome-oriented and global-ready.
8. Desktop and mobile are both primary surfaces.
9. Security, consent, tenant boundaries and provider limitations must be understandable without exposing backend complexity.
10. A visually strong surface must not obscure factual limitations or unsupported provider capabilities.

## 4. Competitive scope

### Direct benchmark

- Doxa Viral — organic-growth / viral-outcome positioning and visual reference.

### Adjacent benchmarks

- Sprout Social and Hootsuite — social operations, publishing, monitoring and reporting.
- Metricool — planning, analytics, publishing and multichannel management.
- Later and Buffer — content workflow and publishing.
- Brandwatch, Meltwater, Sprinklr and Emplifi — listening and enterprise intelligence.
- Semrush, Rival IQ and Exploding Topics — growth, competitive and trend intelligence.

Creator Commerce OS competitors remain outside this benchmark because that is a separate product.

## 5. Evaluation dimensions

Every design review uses a five-star scale with evidence for each score.

| Dimension | Acceptance question |
|---|---|
| Visual hierarchy | Can the user see what matters first? |
| Primary-task clarity | Is the next decision obvious without training? |
| Friction | Are unnecessary steps, fields and choices removed? |
| Evidence trust | Can the user distinguish confirmed evidence, hypothesis and general practice? |
| Action continuity | Can the user move from insight to action without losing context? |
| Information density | Does the interface avoid both clutter and empty decoration? |
| Responsive quality | Does the experience remain strong at mobile and desktop widths? |
| Accessibility | Can users operate and understand it with keyboard and assistive technology, with adequate contrast? |
| Recovery | Are loading, empty, error, denied and degraded states useful and truthful? |
| Differentiation | Does it feel like growth intelligence rather than another scheduler/dashboard? |

Competitor scores remain preliminary until the relevant surface is directly audited. Growth OS scores are not final until the real build is tested.

## 6. Review method

Before declaring the design superior:

- compare the same primary task in Growth OS and each accessible benchmark;
- use comparable desktop/mobile viewport classes;
- inspect first-use, populated, loading, empty, error, denied and recovery states;
- test the path from opportunity discovery to recommended action;
- record steps, ambiguity, time-to-understanding, errors and recovery;
- verify keyboard navigation, focus, contrast and screen-reader semantics where applicable;
- record findings as evidence rather than unsupported opinion;
- distinguish public-site evidence from authenticated-product evidence;
- revise the build and repeat the comparison when material losses remain.

## 7. Acceptance gate

The design is not “best” and must not be frozen until all of the following are true:

- no critical accessibility or responsive defects remain;
- the primary task is clear without explaining the product;
- users can tell what is evidence, hypothesis and general practice;
- no core state relies on fake or ambiguous data;
- context is preserved from intelligence to action;
- the design system is reused consistently across foundational journeys;
- the final comparison names where Growth OS wins, ties or loses;
- losses are corrected or explicitly accepted as a product decision;
- the comparison is against the implemented build, not only a mockup;
- provider/market limitations remain visible and truthful;
- final project review includes adversarial consistency review before visual freeze.

## 8. Independent evidence required for final freeze

The final design package should include evidence from the relevant disciplines:

1. product/UI review of composition, typography, spacing and design-system consistency;
2. task-based usability evidence with intended creators, brands or marketers;
3. WCAG 2.2 AA / keyboard / assistive-technology review;
4. responsive and cross-browser review;
5. same-task competitive comparison;
6. adversarial review of consistency between product claims, evidence model and implementation.

No single reviewer, including the assistant, is the sole authority for final aesthetic approval.

## 9. Doxa evidence boundary

The Doxa Viral public experience previously established a useful visual benchmark: dark high-contrast presentation, large editorial typography, strong promise hierarchy, visual proof and clear conversion action.

That evidence does **not** establish what Doxa’s authenticated internal product does. Any comparison of internal product capabilities must be based on direct equivalent evidence. Growth OS must never claim superiority from a public landing-page comparison alone.

## 10. Current position

- The earlier generic dashboard direction is rejected as the product baseline.
- The editorial baseline selected by the user was implemented and merged through PR #39.
- The current product can be iterated from that baseline without reopening the rejected generic direction.
- Visual superiority is still an open acceptance claim and requires the evidence package above.
- Product completion, design freeze and Claude adversarial review remain separate final gates; Claude is not required as a micro-correction gate for every intermediate PR.

## 11. Version history

- **v0.1 (branch-only historical draft):** introduced the competitive design-quality framework and documented rejection of the earlier generic direction.
- **v0.2:** restores the benchmark onto current `main` lineage, aligns it with the already-merged editorial baseline, preserves evidence boundaries, and aligns review governance with the current project rule that adversarial review is a final/freeze gate rather than a per-PR micro-gate.
