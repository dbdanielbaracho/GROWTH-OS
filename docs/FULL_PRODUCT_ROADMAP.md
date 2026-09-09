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


## Addendum — janela de evidência e design do sync YouTube — 2026-09-08

A interface do conector YouTube foi evoluída para permitir janelas de 7 e 30 dias no mesmo fluxo de sincronização. O endpoint já aceitava uma janela de 1–30 dias; a UI agora expõe essa capacidade sem alterar o contrato do provedor.

A resposta visual mostra a janela efetivamente usada, as linhas retornadas, o último dia disponível e as observações reais processadas. Quando o provedor não devolve dados suficientes, o sistema continua exibindo no-op verdadeiro e não cria sinal, insight ou oportunidade artificial.

Essa entrega também registra a aplicação do design editorial do Growth OS ao controle: baixa fricção, leitura imediata do estado, contraste de seleção e preservação de estados de erro, carregamento e insuficiência de evidência. Ela avança a experiência da Phase 3, mas não congela a fase nem conclui o produto.


## Addendum — correção do typecheck da janela YouTube — 2026-09-08

O primeiro CI da entrega de janela de evidência encontrou uma incompatibilidade real entre a UI e o contrato tipado de `YoutubeSyncResponse`. A interface foi corrigida para manter a janela solicitada localmente, sem inventar um campo inexistente no contrato da API. A validação do novo SHA exato permanece obrigatória antes da promoção.



## Addendum — PR #60 publicado e Production Truth básico — 2026-09-08

O PR #60 foi validado no SHA `537642969f117a551b34a0a80255061c75138fab`, mergeado no commit `ec2fb72d8878312699a07b2a224b823d3f9663ed` e publicado no serviço canônico `growth-os` pelo deployment `adcffef5-684b-410f-980f-484f668b897c`, SUCCESS.

A entrega adiciona a seleção de janela YouTube de 7 ou 30 dias e o controle visual correspondente. O smoke test público passou nos dois domínios canônicos: health e system retornaram 200; os endpoints autenticados retornaram 401 sem sessão. O projeto continua incompleto e a validação visual autenticada do novo controle ainda é parte do próximo teste operacional.


## Addendum — Phase 4: primeiro fluxo CREATE utilizável — 2026-09-08

O primeiro slice de CREATE foi implementado na branch `feat/content-authoring-panel`, partindo do commit `6721983d232f67e8239ae3e49d4048f7f32da641`.

A interface principal agora expõe um painel autenticado de Content Authoring que cria rascunhos manuais com objetivo, mercado, idioma, plataforma e texto. O rascunho é persistido pelo contrato existente de `POST /v1/content`, recebe versão e checksum, e não é publicado automaticamente. O painel usa o design editorial preto/dourado do Growth OS e mantém o fluxo dentro da superfície principal.

Esta entrega avança a Phase 4 de fundação de API para a primeira jornada de usuário de CREATE, mas não congela a fase. Ainda faltam, entre outros itens, edição/versionamento completo, geração assistida com proveniência, aprovação, calendário, publicação segura, reconciliação, analytics, experimentos e os gates das demais fases do produto.

Pendente para este slice: CI no SHA exato, merge, deploy canônico, smoke test e validação autenticada de produção. O estado vazio continua sendo verdadeiro; nenhum dado sintético foi introduzido.


## Addendum — Phase 4: CREATE publicado no produto — 2026-09-08

O primeiro fluxo autenticado de CREATE foi integrado pelo PR #62 e publicado no serviço canônico. O CI passou nos runs #400 e #401 no SHA exato `edb64a60c73d2abd01c0afa231aca535952cfddb`; o merge criou o commit `349559a10b18743993da70f672d6c41c0a64bdd2`; o deployment Railway `382ee1c8-7888-4ead-bd7c-dd7f587779d6` terminou em SUCCESS.

O smoke test comprovou health, system, entrega do shell com `content-authoring-root` e proteção de `/v1/content` sem sessão. O estado não autoriza afirmar criação autenticada no navegador nem conclusão da Phase 4. O próximo gate operacional desta jornada é validar com sessão real; depois a execução continua para versionamento/edição, aprovação, publicação e demais fases do roadmap.


## Addendum — Phase 4: biblioteca e versionamento de rascunhos — 2026-09-08

O CREATE agora avança de gravação isolada para retomada de trabalho: o painel lista rascunhos do workspace e permite carregar um item para salvar uma nova versão sem sobrescrever a anterior.

A nova rota autenticada `POST /v1/content/:id/versions` usa o contrato existente, isolamento por workspace e lock da linha do conteúdo. Cada edição gera novo `version_no` e checksum. O fluxo segue fail-closed: continua sem publicação automática e sem dados sintéticos.

Este bloco ainda não congela a Phase 4. Permanecem pendentes aprovação, edição completa de metadados, geração assistida com proveniência, publicação, reconciliação e os gates das fases seguintes.


## Correção limpa pós-PR #64 — 2026-09-08

O caminho de versionamento está sendo reaplicado em uma branch limpa a partir da main para remover o INSERT direto e chamar o helper canônico `growth.content_new_version`. O PR #65 não pôde ser integrado por conflito de histórico; isso não foi tratado como aprovação implícita. A nova branch precisa passar CI e merge antes de atualizar a produção.


## Revalidação após CI #421 — 2026-09-08

O CI #421 encontrou novamente a exportação `contentChecksum` ausente após a limpeza do follow-up. A função foi restaurada e o próximo SHA será o candidato final para CI do PR #66. Nenhuma mudança de produção ocorreu durante a falha.


## Addendum — Phase 4: correção canônica publicada — 2026-09-08

O PR #66 corrigiu o caminho de novas versões para usar o helper canônico `growth.content_new_version`, passou no CI #423, foi mergeado no commit `4aee0d8803378066d6d0154ff51ccc01b55b3e4e` e publicado com sucesso no Railway.

O healthcheck interno do serviço confirmou banco e processo saudáveis. A validação externa adicional ficou limitada por bloqueio de autorização de rede do ambiente, e a validação autenticada no navegador continua explicitamente pendente. Nenhum desses limites autoriza marcar a Phase 4 como Frozen.


## Addendum — Phase 4: revisão e aprovação de conteúdo — 2026-09-08

O fluxo CREATE passa a ter controles de governança: versões em `ready_for_review` podem ser aprovadas ou devolvidas para alterações através dos helpers canônicos e do histórico append-only de decisões.

A aprovação não publica conteúdo. A publicação continua sendo uma etapa controlada e independente, conforme o roadmap. Este bloco ainda não congela a Phase 4 e aguarda CI, deploy e validação operacional.


## Addendum — Phase 4: governança de revisão publicada — 2026-09-08

O PR #68 adicionou e publicou os controles de aprovação e solicitação de alterações para versões `ready_for_review`, usando os helpers canônicos e o histórico append-only de decisões. CI #434/#435 passou, o merge gerou `50ff3cd887f09f1aa04a41eee02511dbffd46615` e o Railway confirmou deploy SUCCESS `df7c068d-cfcf-477b-b8e2-de3a096d0519`.

A aprovação não publica conteúdo e a validação autenticada da jornada continua pendente; a Phase 4 ainda não está Frozen.


## Addendum — Phase 5: intenção de publicação controlada — 2026-09-08

Foi iniciada a primeira entrega da Phase 5: criação de uma intenção auditável somente para conteúdo aprovado e conta conectada. O contrato usa idempotência, tenant isolation, estado inicial `ready` e helper SECURITY DEFINER.

Esta entrega não publica conteúdo e não congela a Phase 5. Ainda faltam seleção/validação de assets, agendamento, workers, chamadas reais aos provedores, retries, reconciliação, cancelamento e notificações.


## Phase 5 — PR #70 integrado: intenção de publicação controlada — 2026-09-08

O PR #70 foi validado no SHA 22a8bd64f97a756a7a532b8720f1a6073d66b2c0, com CI #444 e #445 em success, e integrado no commit 9b51762b1000a46bcff32b89a2c61113744a53a1. O deploy do serviço canônico successful-embrace / growth-os foi confirmado como success pelo status do commit, no deployment 134bb6fa-05f9-4fd0-bbb4-057df3e9a10d, domínio growos.predibeacon.com.

Essa fatia colocou em produção a fronteira de intenção auditável para conteúdo aprovado e conta conectada. A rota autenticada POST /v1/publication-intents usa a migration 022 e o helper growth.create_publication_intent, com tenant isolation, idempotência e estado inicial ready.

A Phase 5 continua **In Progress**. A intenção não publica por si só. Ainda faltam claim/execução idempotente, assets válidos, agendamento, workers Instagram/YouTube, chamadas reais, retries, reconciliação, cancelamento, notificações e validação com publicação real. O próximo bloco é o contrato seguro de claim/transition da intenção, sem acoplar ainda o worker externo.



## Phase 5 — contrato de claim da intenção de publicação — candidato

A branch feat/publication-intent-claim-contract implementa a migration 023 e o gate SQL 040 para o contrato de claim/lease da publication_intents. O claim é tenant-bound, idempotente, serializado, revalida aprovação e conexão e recupera claims expirados após 10 minutos.

Essa fatia permanece candidata até passar CI no SHA exato, ser integrada e publicada. Ela não chama provedores externos e não conclui a publicação. O próximo limite, depois da promoção, será a finalização auditável do resultado externo, incluindo persistência de attempt imutável e transições seguras de sucesso, retryable, needs_user_action e confirmed.


## Bloqueio de produção — migration 023

A implementação do claim de publicação foi integrada pelo PR #72, mas sua aplicação no Postgres canônico ainda está bloqueada. O Railway não autorizou o acesso ao projeto successful-embrace durante a tentativa de operação do migrator: primeiro ocorreu timeout HTTP 504 e depois o canal informou que falta o papel member.

A Phase 5 não avança para produção nesta condição. O CI isolado passou, porém migration 023, lease de claim e função growth.claim_publication_intent ainda não podem ser marcados como disponíveis no ambiente real. O próximo gate é exclusivamente recuperar a permissão Railway, executar a migration uma única vez pelo migrator canônico e obter prova SQL direta.



## Phase 5 — finalização auditável de publicação — candidato

A migration 024 e o gate 041 implementam o limite de finalização da publicação: attempt imutável, transições de resultado, fechamento do lease e replay idempotente. O código não chama Instagram/YouTube; ele recebe o resultado produzido por um worker futuro.

O bloco permanece candidato até o CI exato passar e a cadeia de migrations 023–024 ser aplicada e confirmada no Postgres canônico. O próximo desenvolvimento posterior será o worker/adapter de provedor, ainda separado da governança de intenção e dos registros imutáveis.


### Correção após CI #465

O gate 041 foi ajustado para eliminar a ambiguidade PL/pgSQL/coluna e respeitar a fronteira sem acesso direto do app_runtime às tabelas de publicação. O novo SHA precisa passar o CI completo antes de qualquer integração.


### Correção após CI #469

O gate 041 recebeu a declaração explícita do alias da tabela de attempts. O próximo SHA deve repetir o CI completo antes da integração.


### Correção após CI #474

O gate 041 agora declara o rótulo usado para qualificar o workspace do caso de teste. A validação integral será repetida no novo SHA.


### Correção após CI #478

O gate 041 passou a validar a persistência do attempt por replay idempotente através do helper, sem ampliar privilégios diretos em tabelas de publicação. O novo SHA aguarda CI completo.


## Phase 5 — PR #74 integrado; aplicação em produção pendente

O contrato de finalização auditável foi integrado pelo PR #74 no commit 3cd448f78f758116a130c68d4f441a0af81f7385 após o CI #482 passar no SHA 8275e6ee15811c5b87331520ee795c6f9cb8a628. A migration 024 e o gate 041 estão no repositório principal.

A aplicação de 023–024 no banco canônico permanece pendente por bloqueio de permissão do Railway. Portanto, a Phase 5 não pode ser considerada disponível em produção. O próximo gate é operacional: executar ambas, nesta ordem, pelo migrator canônico e comprovar as funções/colunas diretamente no banco.


## Phase 5 — contrato de execução de provedor — candidato — 2026-09-08

A execução continuou na branch `feat/publication-provider-execution-contract`, a partir do main após o PR #75.

- Foi criado `apps/api/src/publication-execution.ts` como contrato provider-neutral para o worker futuro.
- O hash de request é determinístico e inclui provedor, conta, versão, tentativa, corpo, estrutura e referências de assets.
- Resultados 2xx só são `confirmed` quando trazem `provider_content_id`; respostas incompletas permanecem retryable.
- 401/403/404/409/422 são classificados como `needs_user_action`; falhas transitórias permanecem `failed_retryable`.
- O payload bruto nunca é encaminhado à finalização: somente um digest `sha256:` é produzido para `raw_payload_ref`.
- Testes unitários cobrem estabilidade do hash, mudança factual, classificação fail-closed e ausência de dados sensíveis no resultado.

Este bloco não chama Instagram ou YouTube e não marca publicação como concluída. Ele prepara a fronteira para o worker/adaptadores reais, que continuarão separados do claim/finalização SQL. A aplicação das migrations 023–024 em produção segue pendente pelo bloqueio de permissão do Railway.


### Correção do CI #491 — relógio fixo do gate 041 — 2026-09-08

O CI #491 falhou no gate 041 porque o teste usava `fixed_now = 2026-09-08T16:30:00Z`. Quando o runner executou às 16:45Z, a claim de 10 minutos já estava expirada antes da finalização. O erro foi determinístico do fixture temporal, não do contrato de finalização nem da implementação TypeScript.

O fixture foi corrigido para `now() + interval '1 hour'`, mantendo a autoridade temporal controlada pelo próprio teste e evitando dependência de horário absoluto. O novo SHA exige o CI completo novamente; nenhuma produção foi afetada.


## Phase 5 — orquestração do worker de publicação — candidato — 2026-09-08

A execução avançou na branch `feat/publication-worker-orchestration`, partindo do main após o PR #76.

- O worker agora orquestra `claim -> adapter -> finalização` por meio de interfaces injetáveis.
- Uma exceção de provedor é convertida em resultado auditável; 429/5xx permanecem retryable e falhas de autorização viram `needs_user_action`.
- O worker finaliza exatamente uma vez por execução e reutiliza o hash determinístico do contrato anterior.
- Mensagens de erro não entram no resultado; somente a classe do erro e o digest do payload controlado são encaminhados.
- Testes cobrem sucesso, falha transitória, falha de autorização, chamada única do adapter e finalização única.

Este bloco ainda não conecta os adaptadores Instagram/YouTube nem cria um serviço Railway. A migração 023/024 continua sem prova de produção por bloqueio de permissão; nenhum deploy foi feito neste bloco.


### Correção do CI #503 — narrowing do resultado do worker — 2026-09-08

O typecheck do PR #77 encontrou acessos possivelmente `undefined` em `finalized[0]` nos testes do orquestrador. A implementação não foi executada pelo CI além do typecheck. Os testes foram corrigidos com narrowing explícito após confirmar que a coleção possui um resultado. Nenhuma produção foi afetada.


## Phase 5 — PR #77 integrado; Railway ainda bloqueado — 2026-09-08

O PR #77 foi validado no SHA exato `ce154abb2984159c3c29894cceed61a9d8721106`, após a correção registrada do CI #503, e integrado por squash no commit `4863f5dc3d5895ec4fb07773232d4b09f3f951bc`. O CI #508 terminou com sucesso.

A entrega adiciona o orquestrador provider-neutral `claim -> adapter -> finalização`, com hash determinístico, uma finalização por execução e conversão segura de falhas do provedor. Ainda não chama Instagram/YouTube reais e não cria o serviço worker no Railway.

Após a integração, uma nova consulta ao projeto canônico `successful-embrace` continuou retornando `required role (viewer)`. Migrations 023–024 permanecem não confirmadas no Postgres de produção. Nenhuma alteração de segredo, OAuth, serviço ou deploy foi inferida.

O próximo gate continua sendo restaurar a permissão Railway, aplicar 023 e 024 pelo migrator canônico, obter prova SQL direta e somente então ligar adaptadores/worker real.


## Phase 5 — builders de requests dos provedores — candidato — 2026-09-08

A execução avançou na branch `feat/publication-provider-request-builders`, partindo do main após o PR #78.

- Instagram: builder para criação de container de imagem/reel e publicação por `creation_id`.
- YouTube: builder para upload resumable de vídeo com metadados de título, descrição, tags e privacidade.
- Assets externos são aceitos somente por HTTPS.
- Tokens ficam exclusivamente no header `Authorization`, nunca na URL ou no corpo.
- YouTube inicia com `private` por padrão para evitar publicação pública acidental.
- Testes unitários verificam URLs, método, headers, corpo, validação de asset e validação de metadados.

O bloco prepara as chamadas oficiais, mas ainda não as executa contra contas reais nem as conecta ao worker/credenciais. A produção continua bloqueada pela falta de acesso Railway e as migrations 023–024 permanecem sem prova no banco canônico.


### Correção do CI #517 — tipos de inputs com defaults — 2026-09-08

O typecheck do PR #79 encontrou que `z.default()` altera o tipo de saída, mas não torna os campos opcionais no tipo de entrada inferido automaticamente. Os testes omitindo `caption`, `tags` e `privacyStatus` falharam por isso. Os tipos públicos dos builders foram corrigidos para usar `z.input`, preservando os defaults em runtime. Nenhuma produção foi afetada.


## Phase 5 — PR #79 integrado; builders de provedor publicados no main — 2026-09-08

O PR #79 foi validado no SHA exato `2a5dc17a959fcc45ff394313d2eb04fe6f316d76`, após a correção registrada do CI #517, e integrado por squash no commit `182353c179ca9f7a004e56a52052305e2bacbec3`. O CI #522 terminou com sucesso.

A entrega adiciona builders controlados para container/publicação do Instagram e upload resumable do YouTube, exige assets HTTPS, mantém tokens somente no header Authorization e inicia uploads do YouTube com privacidade `private`. O bloco não chama provedores reais e não publica conteúdo.

O Railway canônico continua sem acesso viewer/member para aplicar e provar as migrations 023–024. Nenhuma conclusão de produção foi inferida.


## Phase 5 — PR #81 integrado; adaptadores HTTP de publicação — 2026-09-08

O PR #81 foi validado no SHA exato `bc47a617908c3d5080dbfa0065634531c0e1faad`, com CI #531 em success, e integrado por squash no commit `1593316ad70c81e5ad9dd25ad2b7b94da286d841`.

A entrega adiciona adaptadores HTTP controlados para os provedores:

- Instagram: criação de container e chamada posterior de `media_publish`;
- YouTube: iniciação de upload resumable e envio binário;
- classificação preservada de erros via HTTP status e provider request id;
- localização de upload do YouTube limitada a HTTPS em hosts Google permitidos;
- tokens somente em headers, sem persistência em payloads de evidência;
- testes de sucesso, autorização negada, SSRF e divergência de bytes.

Esta entrega ainda não lê `media_assets`, não liga um worker operacional às credenciais e não faz publicação real. O contrato de asset publicável, a resolução segura do conteúdo, retries/reconciliação e a ativação dependem das migrations 023–024 e de prova direta no Railway. A permissão canônica continua bloqueando essa validação; nenhuma conclusão de produção foi inferida.


## Phase 5 — PR #83 integrado; contrato de asset publicável — 2026-09-08

O PR #83 foi validado no SHA exato `d4e86150b991fe5f7e3a371f8d634224b73c8087`, com CI #539 em success, e integrado por squash no commit `e574af6befd1d0deea9e17859d37ab92d2a98604`.

A migration forward-only 025 adiciona `publication_intents.media_asset_id` e uma FK composta pelo workspace. O helper de seis argumentos só aceita asset `publishable` da mesma `content_version`, com `storage_ref` e `rights_status` declarados. O helper antigo de cinco argumentos permanece compatível. A rota `POST /v1/publication-intents` aceita `mediaAssetId` opcional.

O gate SQL 042 verifica a fronteira `SECURITY DEFINER`, owner/grants, persistência do vínculo válido e rejeição de asset não publicável. Ainda não há leitura de bytes, worker operacional ou publicação real; migrations 023–025 continuam sem prova no Railway por falta de permissão viewer.


## Addendum — Phase 5: contexto protegido e composição dos adapters — 2026-09-08

PR #85 foi integrado no commit `5e014e4205b499f6d418e90d8a99a5a1d5cc3b13`, com CI #547 SUCCESS. O bloco estabeleceu o contexto protegido de execução da publicação: claim ativo, conteúdo aprovado, asset publicável, conta conectada e credencial cifrada são reunidos por helper `SECURITY DEFINER`, sem expor leitura direta de credenciais ao runtime.

PR #86 foi integrado no commit `b90170917766446307303b04c5d5d61721eaa1db`, após CI final #565 SUCCESS no SHA `1ca1e9ab3e6df88c833547862c13e4d7f9071fff`. O bloco compõe esse contexto com os adapters HTTP de Instagram e YouTube: descriptografa a credencial apenas em memória, exige host HTTPS allowlisted para assets, executa os requests específicos do provedor e mantém falhas fail-closed. A migration 026 e o gate SQL 043 foram validados no banco isolado do CI.

O histórico de validação foi preservado: CI #559 falhou por uma edição automática que quebrou a linha da regex em `config.ts` (TS1005); o arquivo foi restaurado integralmente. CI #561 passou typecheck, build e gates, mas encontrou uma asserção de teste incorreta que usava credencial inválida antes de testar a allowlist; o fixture foi corrigido para usar envelope cifrado válido. O CI #565 então passou com 42/42 testes.

Limites: este bloco ainda não constitui publicação real em produção. O worker operacional ainda precisa ser ligado ao store de banco, as migrations 023–026 continuam sem confirmação no Postgres canônico enquanto o Railway exigir o papel `viewer`, e ainda faltam fila/agenda, retry durável, reconciliação, cancelamento, notificações e prova com contas reais. Phase 5 permanece In Progress, não Frozen.


## Addendum — Phase 5: execução autenticada da intenção — 2026-09-08

PR #88 foi integrado no commit `8d38ac68ac8f174913eb8e6a00114941541619ab`, após CI #577 SUCCESS no SHA `225a29779ebcc79e93cf933e7516752099659e03`.

A entrega adiciona a rota autenticada `POST /v1/publication-intents/:id/execute`. O caminho faz claim no banco, monta o adapter somente depois de receber o contexto protegido, executa Instagram/YouTube por meio dos adapters já validados e finaliza pelo helper canônico. O worker passou a aceitar uma factory de adapter para impedir construção fora do contexto de claim.

O bloco inclui o primeiro caminho integrado de execução, mas não equivale a publicação real comprovada: migrations 023–026 ainda não têm confirmação no Postgres canônico por bloqueio de permissão Railway; não existe ainda agenda/fila de seleção automática de intenções, retry durável/dead-letter, reconciliação, cancelamento, notificações ou prova com contas reais. Phase 5 permanece In Progress, não Frozen.


## Addendum — Phase 5: retry durável e backoff — 2026-09-08

PR #90 foi integrado no commit `1e0bbd392833421a877e0d76dd95cd2d166e40aa`, após CI final #594 SUCCESS no SHA `583eae10d406e5bc815437912adbde613f0c4e07`.

A migration 027 e o gate 044 adicionam a política persistente de retry: somente intenções em `failed_retryable` podem ser reagendadas, com contador, próximo horário, classe de erro sanitizada, backoff exponencial limitado e transição para `needs_user_action` depois do limite. O worker finaliza a tentativa imutável antes de solicitar o reagendamento.

O CI #590 bloqueou no typecheck por narrowing de fixture; após correção, CI #592 passou todos os gates mas revelou uma expectativa matemática errada no teste (1600000ms em vez de 960000ms para 2⁴×60s). A correção do teste levou ao CI #594 verde. Nenhuma produção foi alterada.

Phase 5 permanece In Progress: ainda faltam seleção automática de fila/agenda, dead-letter operacional, reconciliação, cancelamento, notificações, confirmação das migrations no Postgres canônico e publicação real.


## Addendum — Phase 5: cancelamento seguro — 2026-09-08

PR #92 foi integrado no commit `7417fd9181de0046a344d30b0415abc66794182b`, após CI #606 SUCCESS no SHA `cab8bea1e2e19b49aa8f841da770e6282daf6d9a`.

A migration 028 e o gate 045 adicionam cancelamento actor-bound para intenções ainda não enviadas. O helper exige tenant e usuário ativos, bloqueia `sending` e `confirmed`, limpa lease/agendamento e registra `cancelled_at/cancelled_by`. A API expõe `POST /v1/publication-intents/:id/cancel`; nenhuma chamada externa é feita.

O CI #604 falhou antes dos gates por declaração duplicada de `PublicationIntentParamsSchema` no `app.ts`; a correção removeu somente a segunda declaração. A produção não foi alterada.

Phase 5 continua In Progress: faltam reconciliação de resultados ambíguos, fila/agenda automática, dead-letter operacional, notificações, confirmação das migrations 023–028 no banco canônico e publicação real com conta conectada.


## Addendum — Phase 5: reconciliação controlada — 2026-09-08

PR #94 foi integrado no commit `65246d3035698113c65cea3d7343ee2a7fd72918`, após CI #616 SUCCESS no SHA `24f75db6f7e3c83af7071de1b47c82da709b6c02`.

A migration 029 e o gate 046 adicionam registro de reconciliação por método, confiança e estado, sem persistir payload bruto. A correspondência exige confiança forte e ID do provedor antes de confirmar uma intenção; estados ambíguos/escalados não viram sucesso e podem exigir ação do usuário. A API autenticada expõe `POST /v1/publication-intents/:id/reconcile`.

Este bloco fornece a recuperação controlada, mas não é reconciliação automática contra o provedor: ainda faltam um worker de fila com principal de serviço explícito, agenda automática, dead-letter operacional, notificações, confirmação das migrations 023–029 no banco canônico e prova real.


## Addendum — Phase 5: principal de serviço e claim da fila — 2026-09-08

Foi implementado na branch `feat/publication-worker-service-principal` o contrato que faltava para uma fila de publicação operar sem identidade anônima:

- migration `030_publication_worker_service_principal.sql`;
- tabela interna `growth.worker_service_principals`, com estado `active/revoked` e tipos de job autorizados;
- vínculo explícito `jobs.service_principal_id`;
- helper `growth.enqueue_publication_job` com idempotência por intenção, validação do principal e rejeição de estados terminais;
- helper `growth.claim_due_publication_job` com `FOR UPDATE SKIP LOCKED`, ordenação determinística, lease de 30–900 segundos e incremento de tentativas;
- papel separado `growth_worker`, sem acesso direto às tabelas internas, com execução somente dos helpers;
- gate SQL `047_publication_worker_service_principal.sql`;
- provisionamento do papel worker no CI isolado e no bootstrap administrativo de produção.

O bloco resolve o requisito arquitetural de que todo job carregue um principal de serviço explícito. Ele ainda não cria o processo Railway que consome a fila nem habilita execução cross-tenant em produção: a conexão Railway canônica continua bloqueada por falta do papel mínimo, e as migrations 023–030 ainda precisam de aplicação e prova SQL no banco canônico. Portanto Phase 5 permanece In Progress, não Frozen.


## Addendum — Phase 5/Phase 4: status de publicação na superfície web — 2026-09-08

A branch `feat/publication-status-surface` adiciona a primeira projeção user-facing do ciclo de publicação:

- migration `031_publication_status_projection.sql`;
- helper `growth.list_publication_intents(uuid,integer)` com limite bounded e contexto tenant;
- endpoint autenticado `GET /v1/publication-intents`;
- cliente web tipado;
- painel Content Authoring com status de publicação, tentativa, retry e indicação de ID do provedor;
- gate SQL `048_publication_status_projection.sql`.

A projeção não expõe credenciais, payloads, leases ou tabelas internas diretamente. Ela torna visível o estado auditável que já existe no backend, mas não cria publicação nem altera o contrato de execução. O bloco ainda depende do CI, da aplicação das migrations 023–031 no banco canônico e da implementação do consumidor worker para fechar a jornada operacional.


## Addendum — PR #96 integrado: principal de serviço e fila — 2026-09-08

O PR #96 foi validado no CI #635 no SHA `9dfc3509f8e3cc234dc73cb0ecd26b1d67e4babb` e integrado por squash no commit `74a83ef909e32f409bd784a20d64902249302de0`.

A entrega criou a fronteira de principal de serviço para jobs de publicação: tabela interna de principals, vínculo `jobs.service_principal_id`, enqueue idempotente, claim due com `SKIP LOCKED`, lease bounded, papel `growth_worker` sem leitura direta de `growth.jobs`, migration 030 e gate 047. A falha inicial do CI ocorreu porque o gate foi executado com o papel errado; a correção provisionou o papel de testes e executou a chamada somente como `growth_worker`. O CI final confirmou a separação.

Ainda falta o consumidor Railway e a adaptação do contexto tenant para execução por principal de serviço. Migrations 023–030 continuam sem prova no Postgres canônico enquanto a permissão Railway estiver bloqueada.

## Addendum — PR #97 integrado: projeção de status de publicação — 2026-09-08

O PR #97 foi validado no CI #647 no SHA `165cd001e5792a14a770c83a33f790220c57783b` e integrado por squash no commit `81b3ef7dc3070e6d776d010821df92768c1ffc27`.

A entrega adicionou migration 031, gate 048, helper autenticado e bounded `growth.list_publication_intents`, endpoint `GET /v1/publication-intents`, cliente web tipado e status de publicação no Content Authoring. A projeção é somente leitura e não expõe credenciais, payloads ou leases.

Phase 5 segue In Progress. O próximo bloco deve ligar a seleção da fila ao contexto de principal de serviço e ao executor, com recuperação operacional e evidência de produção.


## Addendum — Phase 5: contexto e runner do worker — candidato — 2026-09-08

A branch `feat/publication-worker-runtime-context` implementa a ligação controlada entre o job leased e a execução da publicação:

- migration `032_publication_worker_runtime_context.sql`;
- `tenant_context_valid` passa a aceitar contexto de principal de serviço somente quando há principal ativo, workspace atual e job de publicação em estado `leased`;
- helper `growth.complete_publication_job` encerra jobs como `done`, `retry_wait` ou `dead`, rejeitando leases expirados;
- transações TypeScript próprias para contexto de worker;
- store de execução de publicação compatível com o contexto de principal de serviço;
- runner `runPublicationQueueOnce` que faz claim, executa o intent e encerra o job;
- gate SQL `049_publication_worker_runtime_context.sql`.

Este é um candidato de implementação e ainda não está validado, mergeado ou publicado. O runner usa o papel/credencial do worker, mas não cria automaticamente um serviço Railway nesta etapa. Também permanece pendente a prova do contexto em banco canônico e a publicação com conta real.


## Addendum — PR #99 integrado: contexto e runner do worker — 2026-09-08

O PR #99 foi validado no CI #660 no SHA `31ef308c94cc78e8572d2eccc440331e13494e90` e integrado por squash no commit `4577fc6f6487fb7c3823c59e4c5a3145facecda6`.

A entrega conecta o job leased ao contexto de principal de serviço, rejeita leases expirados na conclusão e adiciona `runPublicationQueueOnce` para claim → execução → encerramento. O contexto de worker mantém workspace, principal e job juntos durante claim, leitura protegida de publicação, finalização e retry.

O consumidor ainda não foi transformado em processo Railway permanente nem recebeu uma credencial operacional separada. A prova do banco canônico e a publicação em conta real continuam pendentes pelo bloqueio de permissão Railway e pelas configurações reais de provedor.


## Addendum — Phase 5: processo consumidor do worker — candidato — 2026-09-08

A branch `feat/publication-worker-process` adiciona o processo contínuo `worker:publication`, que:

- exige `PUBLICATION_WORKER_SERVICE_PRINCIPAL_ID`;
- exige `PUBLICATION_WORKER_DATABASE_URL` e nunca cai silenciosamente na credencial do API;
- executa `runPublicationQueueOnce` em intervalo bounded;
- registra somente classe de erro e identificadores operacionais não secretos;
- encerra de forma graciosa em SIGTERM/SIGINT;
- mantém o fluxo claim → execução → completion/retry já validado nos blocos anteriores.

Este bloco ainda é candidato. Não cria o serviço Railway, não provisiona a credencial nem configura o principal real. A ativação exige revisão de configuração, criação controlada do serviço/worker e prova de lease/retry em ambiente canônico.


## Registro de execução — PR #101 integrado — processo consumidor do worker — 2026-09-08

- PR: #101.
- Branch: `feat/publication-worker-process`.
- CI final: #672 SUCCESS no SHA `005bc09d69d48db4a059b48d145b9bb6c5c527d8`.
- Merge: `06a998e64fa3c4d83c6f76d0e63e9f83e6f653d5`.
- Entrega: processo contínuo `worker:publication`, validação obrigatória do principal de serviço e da URL de banco dedicada, intervalo e lease limitados, consumo por `runPublicationQueueOnce` e shutdown gracioso.
- Correção registrada: o CI #670 encontrou narrowing incorreto de variáveis de ambiente opcionais no TypeScript; a validação foi reescrita com variáveis configuradas explicitamente e o CI #672 passou.
- Limites: nenhum serviço Railway foi criado ou publicado, nenhum segredo/OAuth foi alterado e nenhuma migration 023–032 foi confirmada no banco canônico. O Railway continua bloqueado por `You don't have the required role (viewer) on this resource.`.
- Próximo bloco: preparar o contrato operacional do worker e a integração da superfície de publicação com execução/recuperação, mantendo a prova de produção condicionada à liberação do Railway e ao provisionamento explícito do principal/URL dedicada.


## Registro de execução — PR #103 integrado — superfície operacional de publicação — 2026-09-08

- PR: #103.
- Branch: `feat/publication-operations-surface`.
- CI final: #680 SUCCESS no SHA `c2342ecbe739a0e5b8ea9b1017115c6d3a06158f`.
- Merge: `4765d5994f361354ad3c615ec3e190d5989bd5b3`.
- Entrega: cliente web tipado para criar, executar e cancelar intents; seleção de conta social conectada; preparação de publicação disponível somente para conteúdo aprovado; chave idempotente por versão/conta; ações de execução e cancelamento com estados permitidos e confirmação para cancelamento.
- Segurança preservada: o clique de preparação cria a intenção, mas não publica automaticamente; execução permanece ação separada e autenticada; tokens, payloads brutos, OAuth e segredos não entram na interface.
- Limites: a reconciliação continua explícita e ainda não há prova de publicação real. Nenhum serviço Railway foi criado/publicado e nenhuma migration 023–032 foi confirmada no Postgres canônico devido ao bloqueio de permissão.
- Próximo bloco: fechar a integração operacional do worker com configuração documentada, observabilidade e validação dos estados de execução; depois avançar para analytics e demais fases do roadmap.


## Registro de execução — PR #105 integrado — contrato operacional do worker — 2026-09-08

- PR: #105.
- Branch: `feat/publication-worker-operational-contract`.
- CI final: #690 SUCCESS no SHA `9ec3593246acf18d30356b9d0e851be2411d2ff7`.
- Merge: `8d4acb61faa0840513e221b9d92cabf2eba76a47`.
- Entrega: `loadPublicationWorkerConfig` separado e testável; validação obrigatória do principal de serviço, URL PostgreSQL dedicada e limites do intervalo; derivação bounded do lease; processo contínuo refatorado para usar o contrato.
- Testes: ausência de principal/URL, URL não PostgreSQL, intervalo mínimo/máximo e valor padrão cobertos no pacote da API.
- Documentação: `docs/PUBLICATION_WORKER_RUNBOOK.md` registra configuração, processo, evidência, reinício seguro e checklist de implantação sem valores secretos.
- Limites: serviço worker ainda não foi criado/deployado no Railway; nenhum segredo/OAuth foi alterado; migrations 023–032 continuam sem confirmação no banco canônico por falta de permissão viewer/member.
- Próximo bloco: avançar a cobertura de analytics/reporting e observabilidade da jornada de dados, preservando provenance e estados vazios quando não houver evidência real.


## Registro de execução — PR #107 integrado — analytics de métricas — 2026-09-08

- PR: #107.
- Branch: `feat/publication-analytics-summary`.
- CI final: #704 SUCCESS no SHA `184d58983c460f3218fa00298d4888a9dd689546`.
- Merge: `afae517b849d0d3286f7e534e4ea892eeaa19e50`.
- Migration/gate: 033/050.
- Entrega de dados: helper `growth.list_metric_analytics_summary(uuid,timestamptz,timestamptz)` agrega observações por conta e métrica, preserva contagem, total, última observação, última efetividade e contagens de completude/freshness.
- Segurança: helper `SECURITY DEFINER` com owner `growth_migrator`, contexto tenant obrigatório, janela máxima de 366 dias, execução apenas por `app_runtime` e sem SELECT direto do runtime em `metric_observations`.
- Entrega web: endpoint autenticado `GET /v1/analytics/metrics` e painel Analytics com janela padrão de 7 dias, dados agrupados e estado explícito quando não existem observações reais.
- Limites: não há valores sintéticos, atribuição, experimentos, OGI, anomalia ou exportação nesta etapa. Migrations 023–033 ainda não têm confirmação no Postgres canônico; o Railway permanece bloqueado por falta de permissão viewer/member.
- Próximo bloco: ampliar analytics com frescor/anomalias e exportação auditável antes de avançar para experimentos e inteligência complementar.


## Registro de execução — PR #109 integrado — qualidade e exportação de analytics — 2026-09-08

- PR: #109.
- Branch: `feat/analytics-quality-export`.
- CI final: #713 SUCCESS no SHA `b98e97574d40c84c196d2acfeaad8d09fb8a1ef8`.
- Merge: `c47abae475b938174e90240c3ae10a9970f1e814`.
- Entrega: Analytics classifica cada linha como Complete, Stale ou Incomplete a partir das contagens de completude/freshness retornadas pelo helper; o painel permite baixar o snapshot JSON autenticado com `from`, `to` e as métricas exibidas.
- Limites: o snapshot não substitui dados ausentes nem produz anomalias estatísticas, atribuição, OGI ou experimento. Produção continua sem confirmação das migrations 023–033 porque o Railway canônico ainda nega o papel viewer/member.
- Próximo bloco: implementar a camada de anomalias determinísticas e a leitura de insights/opportunities com explicação de evidência, mantendo o fail-closed.


## Registro de execução — PR #111 integrado — Radar para Content Authoring — 2026-09-08

- PR: #111.
- Branch: `feat/radar-to-content-authoring`.
- CI final: #721 SUCCESS no SHA `ca533ab8ac8340a6461f6b1f442211f937af52ec`.
- Merge: `eec3256ec26d6131f2a491fcacee0508a897a40f`.
- Entrega: o detalhe de uma oportunidade pode abrir um novo rascunho com mercado, plataforma e objetivo derivados do registro selecionado.
- Segurança e verdade: nenhum texto é gerado automaticamente, nenhuma oportunidade é convertida em publicação e a exigência de escrita, revisão e aprovação permanece intacta.
- Correção registrada: o listener de atualização do Content Authoring passou a declarar todas as dependências usadas.
- Limites: ainda faltam recomendações de ação armazenadas, experimentos, automação, billing/enterprise e prova de produção; Railway canônico continua sem acesso viewer/member.
- Próximo bloco: fechar os contratos de avaliação/feedback das recomendações e preparar os módulos de experimentação sem perder lineage.


## Correction — canonical Railway promotion and current status — 2026-09-09

The previously recorded Railway permission blocker is superseded by the canonical production evidence below.

- Canonical project: Railway `successful-embrace`, production environment.
- Migrator service source: `dbdanielbaracho/GROWTH-OS`, branch `main`; database reference is the canonical Postgres service.
- Migrator deployment `cab9600f-49e4-41ec-aafc-7392439dedbb` reached `SUCCESS` from commit `e1d991807bc23ade6791cf6541de57286a9649a7` and logged successful application of migrations 030, 031, 032 and 033 to database `railway`.
- Application deployment `dd50fa5b-1893-4bc8-bd11-7a229863a2de` reached `SUCCESS` from the same commit.
- Live Railway evidence: `GET /health/ready` returned 200 with database `ok`; `GET /` and `GET /v1/system` returned 200; unauthenticated session and tenant routes returned 401. Railway HTTP logs confirmed the responses.
- The deployment rule is now explicit: GitHub `main` SHA → Railway source promotion → build/deploy success → live HTTP evidence → documentation. Local execution is not accepted as production proof.
- PR #113, “deterministic analytics quality anomalies”, has CI #751 `SUCCESS` on head SHA `72d8e9ee5abc86dc8bb06e62cee8490d66c44e01`. It adds migration 034, gate 051, an authenticated anomaly endpoint and real-data quality alerts. It is not merged or promoted yet; adversarial Claude review remains the freeze gate.
