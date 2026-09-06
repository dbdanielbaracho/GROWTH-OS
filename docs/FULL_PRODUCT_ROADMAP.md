# Growth OS — Full Product Roadmap

Status: execution baseline  
Scope: complete production application, not an MVP  
Official evidence chain: GitHub main SHA -> CI -> Railway -> live tests -> evidence -> freeze

## 1. Verified current state

Official main at audit start: e68f5896264e6062c96a22689af200f314a04047.

Implemented foundations:
- npm workspaces with React/Vite web application and Fastify API;
- PostgreSQL connection, tenant context and health endpoints;
- initial APIs for authentication context, workspaces, content, intelligence and Creative Production;
- database baselines RC8 and RC9;
- Content Authoring v0.1;
- Creative Production v0.5.3, validated and frozen;
- permanent test-integrity gate and CI;
- Railway permanent databases growth_os_797f0a3 and growth_os_test.

Material gaps:
- the web application is still an initial shell;
- identity and onboarding are not complete user-facing journeys;
- external channel connectors are not production-ready;
- publishing, metrics ingestion and recovery workflows are incomplete;
- advanced intelligence modules, automation, billing, enterprise administration and operations are absent or partial;
- no full production proof with real connected accounts exists yet.

## 2. Definition of complete application

Growth OS is complete only when every module below is implemented, integrated, secured, observable, documented, deployed and validated with live evidence. A partial user journey is a milestone, not project completion.

## 3. Execution order

### Phase 0 — Program control and platform contracts

- canonical product requirements and module ownership;
- architecture decision records;
- API and event contracts;
- environment, secret and data-classification policy;
- release, rollback, backup and disaster-recovery contracts;
- traceability from requirement to test and freeze record.

Exit gate: every planned module has dependencies, acceptance criteria and evidence requirements.

### Phase 1 — Identity, tenancy and access

**Status: In progress.** Technical design for Block 1a (`db/IDENTITY_V1_DESIGN.md`) was
adversarially reviewed and approved on 2026-09-02 at commit
`2e04e011596cc938a267dc61c792abad44ab63ba`, then merged through PR #10 as
`f678c3886010514277ef64e96927b9307466911f`. No migration has been written and no database has
been altered. Migration `006` must be implemented in a separate PR with SQL, integration,
concurrency and security evidence before any Railway or database application.

- sign-up, sign-in, sign-out and session lifecycle;
- users, organizations, workspaces and invitations;
- roles and permissions;
- workspace switching;
- onboarding for zero-history and existing-history accounts;
- audit log and tenant-isolation tests;
- account recovery and security controls.

Exit gate: a real user can securely create and operate multiple isolated workspaces.

### Phase 2 — Application shell and design system

- routing, layouts and responsive navigation;
- authentication screens;
- onboarding screens;
- workspace and team administration;
- reusable design system;
- loading, empty, error and recovery states;
- accessibility and browser coverage.

Exit gate: all foundational journeys operate through the web interface without database or CLI intervention.

### Phase 3 — Channel connectors

- Instagram and YouTube production contracts;
- OAuth initiation, callback, refresh, revocation and reconnect;
- encrypted token handling;
- channel/account selection;
- permission validation and degraded states;
- provider rate limits, webhooks and audit trail;
- connector contract tests and real-account proof.

Exit gate: supported accounts connect, refresh and recover safely under real provider behavior.

### Phase 4 — Content operations

- Content Intelligence;
- Content Authoring;
- AI Content Studio;
- Creative Production;
- asset library and lineage;
- review, comments, approval and versioning;
- calendar and campaign organization;
- complete user-facing generate, edit and approve journeys.

Exit gate: a workspace can manage an auditable content lifecycle end to end.

### Phase 5 — Publishing and orchestration

- scheduling and calendar;
- idempotent publishing;
- provider-specific validation;
- queues, retries and dead-letter handling;
- cancellation and reconciliation;
- partial-failure recovery;
- operational status and notifications.

Exit gate: approved content publishes reliably to real accounts and can be reconciled after failures.

### Phase 6 — Data and analytics

- raw metrics ingestion;
- normalized metrics and provenance;
- attribution and experiment measurement;
- dashboards, reporting and exports;
- OGI calculations with versioned definitions;
- freshness, completeness and anomaly monitoring.

Exit gate: every displayed metric is traceable to raw evidence and refresh behavior is observable.

### Phase 7 — Intelligence platform

- Growth Brain;
- Opportunity Radar;
- Global Trend Migration;
- Competitor Intelligence;
- Viral DNA;
- recommendations with evidence, uncertainty and provenance;
- feedback and evaluation datasets;
- model/provider abstraction, cost controls and safety evaluation.

Exit gate: intelligence outputs are explainable, measurable and tied to actionable workflows.

### Phase 8 — Experiments and multiplication

- experiment design and hypotheses;
- variants and originality controls;
- MULTIPLY workflows;
- lineage and cross-channel adaptation;
- assignment, measurement and decision rules;
- promotion of winners and archival of losers.

Exit gate: experiments and variants can be created, published and evaluated without losing provenance.

### Phase 9 — Copilot, Autopilot and operations

- conversational Copilot grounded in workspace evidence;
- approval-aware action execution;
- Autopilot policies, limits and emergency stop;
- command center;
- alerts, incidents and operational runbooks;
- background workers, schedules and cost controls.

Exit gate: automated actions are bounded, reversible where possible and fully auditable.

### Phase 10 — Commercial and enterprise platform

- plans, subscriptions, billing and entitlements;
- usage metering and limits;
- agency multi-client operations;
- enterprise administration;
- compliance, consent, retention and deletion;
- support tooling and administrative console;
- legal disclosures and provider-policy compliance.

Exit gate: the platform can sell, provision, support and govern real customers.

### Phase 11 — Production hardening and launch

- end-to-end and cross-browser suites;
- load, resilience and security testing;
- observability, SLOs and alerting;
- backups and restore drills;
- privacy and security review;
- production deployment on Railway;
- controlled real-account pilots;
- final full-product release freeze.

Exit gate: all critical journeys pass production-truth gates and operational recovery is proven.

## 4. Cross-cutting acceptance criteria

Every module must include:
- database migration or explicit proof that none is required;
- tenant isolation and authorization;
- typed API contracts and validation;
- user-facing interface and recovery states;
- unit, integration and end-to-end tests;
- observability and audit events;
- documentation and operational runbook;
- GitHub CI evidence;
- Railway validation against the exact GitHub SHA;
- adversarial review before freeze.

## 5. Immediate execution block

The first implementation block is Identity, Tenancy and Application Shell because every connector, content workflow, intelligence result, billing rule and automation action depends on a real authenticated user and workspace context.

Deliverables:
1. audit the existing auth.ts, workspaces.ts, tenant-db.ts and identity database schema;
2. freeze the identity/session/workspace API contract;
3. implement missing session and membership behaviors;
4. build sign-in, workspace selection, onboarding and team screens;
5. add API, database and end-to-end tests;
6. deploy the exact SHA to Railway and validate tenant isolation;
7. create the Identity v1 freeze record.

## 6. Progress accounting

Progress is measured by accepted deliverables, not lines of code or files. Each phase receives status Not started, In progress, Validated or Frozen. The complete application reaches 100% only after Phase 11 is Frozen.


## 7. Live execution addendum — 06 September 2026

The Identity v1 block is implemented on PR #40, branch `feat/growth-os-identity-v1`, pending CI and adversarial review. The block covers atomic signup with email verification issuance, server-side identity routes, workspace creation/onboarding, invitation and password-reset APIs, and the corresponding web journeys.

This does not mark Phase 1 or Phase 2 as complete. The exit gates still require:
- successful CI on the exact final SHA;
- independent Claude review;
- production secret provisioning for identity email delivery;
- merge/deploy and live tenant-isolation evidence;
- remaining team administration, recovery and connector journeys.

Instagram, publishing, analytics, experiments, Copilot/Autopilot, commercial/enterprise modules and final production hardening remain future phases. The project is not complete until Phase 11 is Frozen.


## 8. Identity v1 status after merge

**Status:** Validated and deployed, with one operational dependency pending.

Identity v1 is now merged into `main` and deployed through Railway. The code and CI gates are complete. Production signup and email verification remain disabled operationally until `RESEND_API_KEY` and `IDENTITY_EMAIL_FROM` are configured as Railway secrets.

The next implementation block is Phase 3 channel connectors, beginning with Instagram under the same tenant, provenance, consent, idempotency and adversarial-review rules. This does not change the full-product completion rule: Growth OS remains incomplete until all phases, including publishing, analytics, intelligence, experiments, automation, commercial controls and Phase 11 hardening, are frozen.


## 9. Instagram connector foundation — PR #41

**Status:** implementation complete for the foundation slice; not yet frozen or deployed.

The branch `feat/growth-os-instagram-connector-v1` implements the first secure Instagram Login contract:

- encrypted, expiring and tenant-bound OAuth state;
- short-lived to long-lived token exchange;
- professional-account profile validation;
- encrypted provider credential persistence;
- tenant-scoped SECURITY DEFINER helpers;
- status, authorize and callback routes;
- capability registry with content publishing and insights fail-closed;
- SQL gate 035 and OAuth-state unit tests.

The candidate `046a643aba6904499f0a1a16c3a9ac9e484610e6` passed CI run #209, including migrations 001–017, gates 033–035, Growth Intelligence integration, idempotency, no-op behavior, typecheck, build, unit tests and production web shell. The execution memory records the intermediate failures and corrections in full.

This advances Phase 3 from Not started to In progress. It does not complete Phase 3. The remaining Instagram work includes refresh/reconnect/revocation, media and metrics sync, publishing, reconciliation, webhooks, complete web UI, provider configuration and proof with a real professional account. YouTube also still requires the complete real-account loop, and Phases 4–11 remain incomplete.

Required next gate for PR #41: re-run CI after this roadmap/memory commit, send the exact final SHA to Claude for adversarial review, then decide merge/deploy only after APPROVE. Production remains unchanged until those gates pass.


## 10. Claude review correction — Instagram configuration validation

The adversarial review of PR #41 identified a real configuration blocker: the Graph API version regex rejected the default `v24.0`. The connector and central Zod configuration were corrected, and tests now exercise both acceptance of `v24.0` and rejection of malformed versions. CI run #220 passed all gates on code SHA `f1ea71096aa06ab9edea67f3dd21629441597056` before this documentation update.

The documentation update creates a new branch head, so the final candidate SHA and CI must be revalidated before Claude reviews again. The Instagram foundation remains In progress, not Frozen.


## 11. PR #41 integrado — Instagram foundation em produção

PR #41 foi aprovado pelo Claude no SHA exato `55f2d879055baf949d5abb803da429088afd9f78`, mergeado no commit `63a8eec9d0bb8986f2653f1fad67dc1c60e35a6d` e publicado pelo Railway com deployment SUCCESS. O shell web, health e system endpoints passaram o Production Truth Gate.

A classificação correta é: Phase 3 — Instagram foundation **In Progress**, não Frozen. O código está publicado, mas a migration 017 ainda precisa de confirmação controlada no banco de produção; as credenciais Meta também não estão configuradas. Refresh/reconnect, sincronização, publicação, métricas, webhooks, UI completa e prova com conta real continuam pendentes.

O histórico completo, incluindo a limitação operacional de acesso ao banco e o serviço temporário staged para remoção por 2FA, está em `docs/PROJECT_EXECUTION_MEMORY.md`.


## 12. Instagram lifecycle block — implementation candidate

**Status:** In progress; not validated, frozen or deployed.  
**Branch:** `feat/growth-os-instagram-lifecycle-v1`

The next Phase 3 slice adds the safe token lifecycle around the approved Instagram foundation:

- long-lived token refresh through Meta's official `refresh_access_token` endpoint;
- encrypted credential replacement with tenant-bound AAD;
- reconnect that reuses revoked/disconnected connections and updates the existing social projection;
- local revocation that removes provider credentials and marks the connection `revoked`;
- explicit SQL gate 036 for helper ownership, `SECURITY DEFINER`, grants and least privilege;
- unit coverage for the refresh URL contract and secret non-disclosure.

This block does not enable publishing or insights, does not configure Meta credentials and does not prove migration 017 or 018 in the production database. It remains incomplete until exact-SHA CI, Claude adversarial review, merge/deploy controls, production migration evidence and real-account validation pass.


### CI evidence for the lifecycle candidate

The lifecycle candidate reached a complete green CI in run #250 at intermediate SHA `d07fbeea19edbce4c47e2fe73d3bbe4ef088b910`. Subsequent hardening changes reject invalid token expiry values, assert exact helper signatures in gate 036 and correct Markdown formatting; therefore the intermediate SHA is not the review SHA. The final candidate must rerun CI after these changes, then undergo Claude adversarial review before any merge or deploy.


### Final code-candidate CI

After the documented hardening, CI run #262 passed for code SHA `cf5b260d5a1c87cd05f5e0b34a3c39ccdf6910d6`, including migration 018 and gates 033–036. This roadmap update creates a new branch head; that new exact SHA must pass CI before Claude review. The lifecycle block remains In progress and not deployed.


## 13. PR #42 integrado — lifecycle Instagram e migrations de produção

**Data:** 06 de setembro de 2026

O PR #42 foi aprovado pelo Claude no SHA exato `faeb19b89c38c77ac912b19ef23cbd4a6440783a`, mergeado por squash no commit `08f10e046b8e0b6e708a5dfd262fc34daeec3ae8` e publicado pelo Railway no serviço `growth-os` com deployment SUCCESS `ea1275fc-48ab-4846-95c6-3231fd3183d3`.

A aplicação das migrations não foi inferida do deploy web. Após corrigir problemas de snapshot do Railway, quoting de shell, execução explícita com `sh -c` e normalização de whitespace no precheck, o deployment `34ee4800-3550-4e1f-adb3-e2097a39ee81` confirmou diretamente em produção:

- migration 017 aplicada;
- migration 018 aplicada;
- `instagram_integration_status` presente;
- `instagram_revoke_connection` presente;
- 3 capabilities Instagram presentes;
- nenhum erro SQL;
- operação idempotente e com `ON_ERROR_STOP=1`.

O comando temporário do migrator foi removido. O comando original foi restaurado e confirmado pelo deployment SUCCESS `dd14e33f-c5b6-450e-9f76-a97ebd08903a`, com função Instagram presente e CI do SHA aprovado em estado success.

### Estado atualizado da Phase 3

**Phase 3 — In Progress, não Frozen.**

Concluído neste bloco:

- fundação segura do Instagram;
- lifecycle de token;
- refresh/reconnect/revoke no código;
- migrations 017–018 aplicadas em produção;
- grants, helpers e capabilities registradas;
- CI, gates SQL e revisão adversarial do Claude;
- código mergeado e publicado.

Ainda falta para congelar Phase 3:

- configurar credenciais Meta reais;
- conectar e validar uma conta profissional real;
- comprovar refresh, reconnect e revoke contra comportamento real do provedor;
- sincronização de mídia e métricas;
- publicação real, reconciliação e webhooks;
- UI completa, estados degradados e recuperação;
- evidência operacional e revisão final do conector.

O projeto completo continua incompleto. Fases 4–11 — conteúdo completo, publicação/orquestração, analytics, inteligência, experimentos, Copilot/Autopilot, comercial/enterprise e hardening/launch — permanecem pendentes conforme a definição de completude da seção 2.


## 14. PR #43 — Instagram lifecycle web surface

O PR #43 adiciona a primeira superfície web utilizável para o ciclo Instagram: status autenticado, autorização/reconexão, refresh de token, revogação local e estados fail-closed. O CI inicial passou no SHA `5d70754b973c9f67460e0e9a034f09f576024913`; o bloco ainda aguarda revisão adversarial final antes de merge/deploy.

Isso avança a usabilidade da integração, mas não congela a Phase 3. Continuam pendentes: credenciais Meta e conta profissional real, prova do OAuth real, sync de mídia/métricas, publicação, reconciliação, webhooks, insights autorizados, testes de jornada real e as fases 4–11.



---

## Addendum 15 — Instagram media and direct metrics sync v0.1 — 2026-09-06

### Concluído neste bloco

- Migration forward-only 019 criada e aplicada no CI isolado.
- Tabela `growth.instagram_media` com RLS + FORCE RLS, sem acesso direto do `app_runtime`.
- Helpers `SECURITY DEFINER` para persistência de mídia e observações métricas, com owner/grants auditáveis.
- Endpoint autenticado `POST /v1/integrations/instagram/sync`.
- Paginação limitada, janela de lookback de 1–30 dias, rejeição de timestamp inválido e digest SHA-256 de payload.
- Métricas diretas implementadas: `like_count` e `comments_count`.
- Idempotência por workspace/request nonce/media/metric/semantic version.
- UI com ação “Sync media & metrics” e retorno da contagem processada.
- Gate SQL 037 e testes de contrato adicionados.
- CI run 294: SHA `2a34b96d5136cac7fc55d794b433252295982341`, conclusão `success`, todos os gates existentes e o gate 037 aprovados.

### Aprendizados incorporados

- Typecheck de frontend é executado antes de qualquer migration gate; o primeiro CI encontrou e corrigiu o narrowing opcional da UI.
- Assinaturas SQL de criação, alteração, REVOKE, GRANT e gates devem ser mantidas como uma única lista verificável; o segundo CI encontrou a divergência de um parâmetro `timestamptz`.
- O CI oficial isolado permanece a autoridade para o conjunto completo; testes locais continuam úteis, mas limitações do ambiente local devem ser registradas separadamente.

### Limites explícitos

Este bloco não habilita publicação, insights avançados, comentários/moderação, webhooks, reconciliação, nem validação com conta Instagram real. O SHA aguarda revisão final adversarial do Claude antes de merge/deploy.

### Próximo bloco

Após aprovação: integrar/deployar com smoke test sem dados sintéticos; depois implementar insights avançados com contrato de métricas por tipo de mídia, seguido de publicação e reconciliação em blocos independentes.


---

## Addendum 16 — correção de idempotência do Instagram — 2026-09-06

A revisão adversarial do Claude encontrou uma regressão material na primeira implementação do sync de métricas do Instagram: a função de gravação aceitava a mesma idempotency key quando campos factuais/proveniência, como unit, mudavam. O exemplo reproduzido foi 120 seconds seguido de 120 minutes, com retorno silencioso da mesma UUID.

A correção foi implementada como migration forward-only 020, sem alterar a migration 019 já validada no branch. O contrato agora compara todos os campos estáveis de identidade factual e origem com ROW(...) IS NOT DISTINCT FROM ROW(...), seguindo o padrão comprovado da migration 013 do YouTube. Retry idêntico permanece idempotente; mudança material gera conflito explícito.

Foi adicionado o gate comportamental 038. Ele cria fixtures somente no PostgreSQL isolado do CI, confirma retry idêntico, exige conflito para unidade diferente e termina com ROLLBACK. O CI foi atualizado para executá-lo sob a role de harness de teste.

A sequência de execução foi registrada integralmente na memória operacional:

- run 304 falhou por referência regprocedure com uma assinatura SQL incompleta;
- run 307 falhou por SELECT set_config sem destino dentro de PL/pgSQL;
- run 309 passou integralmente no SHA f0136c15253f00def2fdbd73ae72127d83b9ce2d.

O bloco Instagram media/metrics continua In Progress, não Frozen. O PR #44 ainda não foi mergeado nem deployado, e a produção permanece intocada. O próximo gate obrigatório é uma nova revisão adversarial do Claude no SHA exato f0136c15253f00def2fdbd73ae72127d83b9ce2d.
