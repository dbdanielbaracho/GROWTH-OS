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


## 12. Reavaliação visual comparativa

**Data:** 05 de setembro de 2026

A proposta de tela mostrada na conversa foi reavaliada contra as referências públicas do Growth OS. O resultado anterior foi superestimado: a tela atual parece um dashboard genérico, com pouca identidade, pouca demonstração visual de inteligência, pouca profundidade de interação e ausência de preview/visualização rica do conteúdo e dos sinais. Ela não deve ser apresentada como visualmente superior aos concorrentes.

A avaliação preliminar, limitada às superfícies públicas e sem substituir auditoria autenticada, é:

- Doxa Viral: forte promessa visual e posicionamento direto de resultado/viralização.
- Sprout Social: maior maturidade de produto, inteligência em tempo real, navegação ampla e ligação clara entre sinal, insight e ação.
- Metricool: organização visual mais amigável, calendário, analytics, relatórios e workflow integrado.
- Hootsuite: maior amplitude de Social OS, com analytics, publicação, inbox e gestão conectados.
- Growth OS atual: conceito ainda insuficiente; não aprovado visualmente e abaixo do padrão de referência.

Consequência: a proposta anterior fica cancelada como direção visual. A próxima proposta deverá ser construída a partir de teardown tela a tela, três direções visuais alternativas, protótipo navegável, teste de tarefa e arbitragem independente.


## 13. Inspeção visual direta do Doxa Viral

**Data:** 05 de setembro de 2026

A página pública https://www.doxaviral.com/ foi aberta e inspecionada diretamente. Foram observados: fundo preto dominante, marca branca de alto contraste, navegação compacta, tipografia editorial de grande escala, promessa central muito forte (“Um milhão de views. Ou seu dinheiro de volta.”), demonstração visual de cases/conteúdo, prova social e CTA de conversão claro.

A comparação confirma que os mockups anteriores do Growth OS estavam em uma categoria visual errada: pareciam um painel SaaS genérico, enquanto o Doxa apresenta uma narrativa de produto com identidade, tensão comercial, prova visual e hierarquia muito mais marcante.

Limite da evidência: essa inspeção cobre a página pública e não a área interna autenticada do Doxa. Portanto, não se deve afirmar superioridade ou inferioridade da aplicação interna sem acesso equivalente. Mesmo assim, a proposta pública do Growth OS precisa atingir um nível equivalente de identidade, composição, tipografia, prova visual e clareza de promessa antes de qualquer nova aprovação.

Decisão: não criar outra variação de dashboard genérico. A próxima direção deve começar por uma estratégia visual de marca e produto, com referências reais, protótipo navegável e avaliação independente.


## 14. Rejeição integral das propostas visuais do assistente

**Data:** 05 de setembro de 2026

1. O usuário rejeitou integralmente as propostas visuais produzidas pelo assistente.
2. O usuário avaliou que o Doxa Viral é visualmente muito superior às telas apresentadas para o Growth OS.
3. As propostas do assistente ficam classificadas como inadequadas, genéricas e sem qualidade competitiva; nenhuma pode ser usada como baseline, direção aprovada ou referência de implementação.
4. O assistente não deve continuar definindo sozinho a linguagem visual do produto.
5. A próxima direção deverá ser construída por designer de produto/UI independente, com teardown real dos concorrentes, referências visuais documentadas, protótipo navegável, testes de usabilidade, acessibilidade e revisão adversarial.
6. O objetivo continua sendo superar os concorrentes, mas essa superioridade não pode ser declarada antes de evidência comparável.
7. Nenhum código, banco ou produção foi alterado; esta é uma correção documental e de governança do design.


## 15. Direção visual de trabalho adotada

**Data:** 05 de setembro de 2026

1. O usuário decidiu seguir a direção visual apresentada em `growth-os-doxa-inspired.html` como baseline de trabalho para o Growth OS.
2. A direção combina editorial premium, alto contraste, fundo preto, tipografia forte, dourado como sinal de oportunidade, narrativa visual e CTA claro.
3. O produto deve parecer uma experiência de inteligência e decisão, não um dashboard genérico de métricas.
4. A direção é inspirada em princípios visuais observados no Doxa Viral, mas não copia marca, textos, interface, código ou métodos proprietários.
5. A aplicação deverá conectar sinal, evidência, oportunidade e ação em uma experiência simples e global.
6. O Growth Brain deve aparecer como contexto da decisão, e não como painel separado.
7. Esta decisão cria um baseline de trabalho para a próxima implementação; não constitui freeze visual final.
8. Antes do freeze, será necessária revisão independente de designer/UI, validação de usabilidade, acessibilidade, responsividade, cross-browser e revisão adversarial.
9. Nenhum código de produção, banco ou deploy foi alterado por esta decisão documental.
