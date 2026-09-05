# Growth OS — Design Quality Benchmark and Acceptance v0.1

**Status:** design quality requirement  
**Scope:** Growth OS user-facing web experience  
**Rule:** the current Opportunity Radar screen is a foundation, not proof that the product has the best design.

## 1. Objective

Build a user experience that is demonstrably better than the relevant competitors for the core job:

> identify the next credible organic-growth opportunity, understand why it matters, and take the next safe action with minimal friction.

“Better design” must mean more than visual polish. It must combine:

- clarity of the primary decision;
- low interaction friction;
- evidence and uncertainty that users can understand;
- fast movement from opportunity to action;
- consistent behavior across desktop and mobile;
- accessibility and recovery;
- visual coherence and product trust;
- a distinctive intelligence-first position.

## 2. Product design principles

These requirements derive from the frozen conceptual and technical baselines:

1. One intelligent feed is the default surface; advanced views remain secondary.
2. The product must make the outcome and next action clear.
3. Internal model, scoring and orchestration complexity stays hidden unless the user needs it.
4. Every recommendation must expose the evidence and confidence that actually exist.
5. Empty, loading, error, denied, degraded and recovery states are first-class design states.
6. No synthetic opportunity, explanation or action may be used to make the interface appear full.
7. Language must be simple, outcome-oriented and global-ready.
8. Desktop and mobile are both primary surfaces.
9. Security, consent, tenant boundaries and provider limitations must be understandable without exposing backend complexity.

## 3. Competitive scope

### Direct benchmark

- Doxa Viral — organic-growth and viral-outcome reference.

### Adjacent benchmarks

- Sprout Social and Hootsuite — social operations, publishing, monitoring and reporting.
- Metricool — planning, analytics, publishing and multichannel management.
- Later and Buffer — visual planning, content workflow and publishing.
- Brandwatch, Meltwater, Sprinklr and Emplifi — listening and enterprise intelligence.
- Semrush, Rival IQ and Exploding Topics — growth, competitive and trend intelligence.

Creator Commerce OS competitors are excluded from this benchmark.

## 4. Evaluation dimensions

Every design review uses a five-star scale for each dimension:

| Dimension | Question |
|---|---|
| Visual hierarchy | Can the user see what matters first? |
| Primary-task clarity | Is the next decision obvious without training? |
| Friction | How many unnecessary steps, fields or choices exist? |
| Evidence trust | Can the user distinguish fact, hypothesis and general practice? |
| Action continuity | Can the user move from insight to execution without losing context? |
| Information density | Does the interface avoid both clutter and empty decoration? |
| Responsive quality | Does the experience remain excellent at mobile and desktop widths? |
| Accessibility | Can users operate and understand it with keyboard, assistive technology and adequate contrast? |
| Recovery | Are loading, empty, error, denied and degraded states useful and truthful? |
| Differentiation | Does the interface feel like a growth-intelligence system rather than another scheduler? |

A competitor rating is a preliminary benchmark until its relevant product surfaces are audited. A Growth OS rating is not considered final until the implementation is tested.

## 5. Required reviewers

The visual/product gate requires independent evidence from:

1. Product/UI designer — composition, typography, color, spacing and design system.
2. UX researcher — task-based tests with target creators, brands and marketers.
3. Accessibility reviewer — WCAG 2.2 AA and keyboard/screen-reader behavior.
4. Front-end and cross-browser reviewer — responsive behavior, interaction states and runtime quality.
5. Competitive product analyst — same-task comparison against the defined competitor set.
6. Claude adversarial review — consistency between requirements, evidence model and implementation; not the sole authority for aesthetic judgment.

## 6. Required review method

Before declaring the design superior:

- compare the same primary task in Growth OS and each accessible competitor;
- capture desktop and mobile states at the same viewport classes;
- review first-use, populated, loading, empty, error, denied and recovery states;
- test the core path from opportunity discovery to recommended action;
- record observed steps, ambiguity, time-to-understanding, errors and recovery;
- run accessibility checks and keyboard navigation;
- record every finding as evidence, not as an unsupported opinion;
- revise the design and repeat the comparison.

## 7. Acceptance gate

The design is not “best” until all of the following are true:

- no critical accessibility or responsive defects remain;
- the primary user task is clear without explaining the product;
- users can tell what is evidence, hypothesis and general practice;
- no core state relies on fake or ambiguous data;
- the interface preserves context from intelligence to action;
- the design system is reused consistently across foundational journeys;
- the final comparison names where Growth OS wins, ties or loses;
- losses are either corrected or explicitly accepted as a product decision;
- the comparison is reviewed against the actual build, not a speculative mockup.

## 8. Current position

The existing Opportunity Radar UI has a promising foundation: focused hierarchy, evidence-first detail, explicit confidence, truthful empty states and responsive structure. This is not yet a validated claim of visual superiority.

The current implementation remains incomplete because the application shell, design system, onboarding, navigation, connectors, publishing, experiments and full action loop are not finished. The roadmap and competitive gap matrix remain the authority for that maturity status.

## 9. Design authority and arbitration

The assistant may propose flows, wireframes and visual alternatives, but it is not the final design authority and may not approve its own design.

The earlier simplified mockups produced during this conversation are **exploratory and unapproved**. They must not be treated as the product baseline or as evidence of competitive quality.

Final arbitration requires:

- an independent senior product/UI designer or design lead with authority to reject the proposal;
- a same-task, same-viewport competitor teardown;
- an actual interactive prototype or implemented build, not only a static sketch;
- a design system specification covering tokens, typography, color, spacing, components and all states;
- WCAG 2.2 AA review, keyboard navigation and responsive/cross-browser checks;
- task-based usability evidence with the intended audience;
- a written decision log listing wins, ties, losses, defects and accepted trade-offs.

No design is approved until the evidence package is complete and the required reviewers sign off. The assistant can help prepare the package and revise the proposal, but cannot be the sole judge.

## 10. Applicable practices and standards

- Use [W3C WCAG 2.2](https://www.w3.org/WAI/standards-guidelines/wcag/) as the accessibility baseline; compliance is necessary but does not by itself prove visual quality.
- Use [Material Design 3 foundations](https://m3.material.io/foundations) and its principles for layout, interaction and accessibility as a reference where useful, without forcing Growth OS to copy its visual style.
- Define reusable [design tokens](https://m3.material.io/foundations/design-tokens) and explicit [component states](https://m3.material.io/foundations/interaction/states).
- Validate the real build at desktop and mobile widths, including loading, empty, error, denied and recovery states.
- Treat competitor stars as measured findings, not intuition; record the task, viewport, evidence and reviewer for every score.

## 11. Decision

The current design direction is rejected as a final visual direction because it was too simplistic and has not demonstrated competitive quality. The project continues with a design-quality gate, independent arbitration and evidence-based iteration before any visual freeze or production approval.
