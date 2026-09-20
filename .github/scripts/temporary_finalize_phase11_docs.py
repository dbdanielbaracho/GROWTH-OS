from pathlib import Path

memory_path = Path('docs/PROJECT_EXECUTION_MEMORY.md')
state_path = Path('PROJECT_CURRENT_STATE.md')
roadmap_path = Path('docs/ROADMAP_STATUS_RECONCILIATION_2026-09-15.md')

memory_heading = '## Continuação — fechamento interno, documentação e execução até o último gate possível — 2026-09-20'
memory_section = r'''## Continuação — fechamento interno, documentação e execução até o último gate possível — 2026-09-20

**Pedidos exatos do usuário nesta retomada:**
- `"o que falta fazer para terminar o projeto"`;
- `"precisamos terminar tudo executar até o final para terminar tudo execute entao até o final"`.

**Ponto real verificado de retomada:** PR #207 já estava mesclado. O runtime aceito é o merge `d1e3296c5a431a7443584e84e52cb7bff081f994`; o PR head aceito foi `d00f6fb8303f75be70a07c863eac0dcc5744a99e`. O PR CI #1362 (`35526433434`) e o CI de `main` #1363 (`35526788270`) concluíram `SUCCESS`. Railway canônico `successful-embrace` / `production`: migrator `f6f228ac-58fc-4e47-be5e-975321af6c2a`, app `9778659d-92ce-4bde-906a-4610b7d9a7c4` e publication worker `752da9cb-2e27-4991-b523-1cfcf865dd76` estavam `SUCCESS` nessa linhagem; o app verificou identidade de deploy e healthcheck `/health/ready` HTTP 200.

**Correção final da Fase 11:** o terceiro CI anterior, head `5bdcb63f8342365529478bf743cdd1f8a8bd3540`, run `35525488384`, havia falhado somente no restore drill com `permission denied for table content_items` ao executar o read path restaurado. O restore já funcionava; faltavam no snapshot os grants canônicos de runtime. O commit `d00f6fb8303f75be70a07c863eac0dcc5744a99e` passou a aplicar `db/provisioning/production/02_runtime_grants.sql` antes do fixture/dump. Não foi criado grant ad hoc. O CI subsequente passou integralmente, incluindo bounded load/resilience e backup/restore físico em Postgres de quarentena com replay de tombstone/read denial.

**Resultado interno:** a Fase 11 de hardening está aceita e não deve ser reaberta sem regressão. O projeto possui telemetria operacional sem payload/credenciais/tenant IDs, SLOs/condições de alerta documentados, gates de carga/resiliência, restore drill físico controlado, exata linhagem CI -> merge -> Railway e healthcheck canônico.

**Regra operacional reafirmada:** TinyFish não deve ser usado no Growth OS. O usuário já havia determinado `"nao vou usar o tinyfish"`; nesta retomada não houve uso de TinyFish.

**Gates que continuam necessariamente externos ou dependentes de autorização humana real:**
1. Google/YouTube: concluir autorização/reautorização humana e provar um sync real de sete dias pós-PR #200 com dados persistidos;
2. publicação real em provider: somente com conta e conteúdo concretos explicitamente autorizados, seguida de confirmação do provider e medição;
3. encadear numa única evidência real a linhagem `provider data -> observations -> evidence/signal -> insight/opportunity -> recommendation/content -> approval -> confirmed publication -> measurement -> learning`;
4. concluir as jornadas autenticadas de produção ainda aplicáveis, sem substituir por fixtures;
5. comparação visual competitiva same-task e freeze visual final;
6. revisão adversarial final por revisor externo real no SHA/pacote final; não substituir essa revisão por autoaprovação;
7. Production Truth Gate final, freeze e fechamento da issue #26 somente após os gates aplicáveis acima.

**Limite de evidência:** o restore drill de CI prova mecânica de recuperação em quarentena descartável; não prova política/retensão de backup do Railway. Nenhum OAuth, publicação externa, medição de post real ou parecer de revisor externo é inventado.

**Próximo ponto de execução:** manter `d1e3296c5a431a7443584e84e52cb7bff081f994` como runtime aceito enquanto alterações forem apenas documentais. Executar automaticamente todos os gates que não exigem humano; quando chegar a OAuth/publicação/revisor externo, registrar o gate como dependência externa real e não como defeito interno.'''

memory = memory_path.read_text(encoding='utf-8')
if memory_heading not in memory:
    memory = memory.rstrip() + '\n\n\n' + memory_section.strip() + '\n'
    memory_path.write_text(memory, encoding='utf-8')

state_heading = '## Current accepted checkpoint — 2026-09-20 — PR #207 Phase 11 operational hardening'
state_section = r'''## Current accepted checkpoint — 2026-09-20 — PR #207 Phase 11 operational hardening

This section supersedes the PR #206 accepted checkpoint below while preserving it as historical evidence.

- Repository and accepted runtime SHA: `d1e3296c5a431a7443584e84e52cb7bff081f994`, squash merge of PR #207.
- PR head `d00f6fb8303f75be70a07c863eac0dcc5744a99e`; PR CI #1362 (`35526433434`): SUCCESS, including bounded load/resilience and the physical PostgreSQL backup/restore quarantine drill.
- Merged-main CI #1363 (`35526788270`): SUCCESS on the exact merge SHA, including the same Phase 11 gates and final Test.
- Railway canonical `successful-embrace` / `production`, exact merge lineage:
  - migrator `f6f228ac-58fc-4e47-be5e-975321af6c2a`: SUCCESS;
  - app `9778659d-92ce-4bde-906a-4610b7d9a7c4`: SUCCESS; exact deployment identity verified; `/health/ready` healthcheck HTTP 200;
  - publication worker `752da9cb-2e27-4991-b523-1cfcf865dd76`: SUCCESS.
- Phase 11 internal operational hardening is accepted: payload-free normalized request telemetry, measurable SLO/alert criteria, bounded load/resilience gate and controlled custom-format backup/restore drill with deletion-ledger replay/read denial.
- Evidence boundary: the CI restore drill proves recoverability mechanics in disposable quarantine; it does not claim Railway production backup retention or provider purge completion.
- TinyFish operational rule remains mandatory: do not use TinyFish for Growth OS going forward.
- Remaining work is external/final rather than an unimplemented internal Phase 11 block: real YouTube human authorization/seven-day sync, explicitly authorized real-provider publication and full measured loop, remaining authenticated production acceptance where applicable, same-task visual freeze, final evidence package/adversarial review, then Production Truth Gate/freeze and issue #26 closure only after the applicable gates.
'''
state = state_path.read_text(encoding='utf-8')
if state_heading not in state:
    marker = '\n## Current accepted checkpoint — 2026-09-20 — PR #206 enterprise/privacy operations\n'
    if marker not in state:
        raise SystemExit('expected PR #206 checkpoint marker not found')
    state = state.replace(marker, '\n' + state_section.strip() + '\n\n' + marker.lstrip('\n'), 1)
    state_path.write_text(state, encoding='utf-8')

roadmap_marker = 'The active internal candidate is `feat/phase11-hardening`: bounded load/resilience, payload-free operational telemetry, SLO/alert rules and a PostgreSQL quarantine restore drill that replays deletion tombstones before serving restored data.'
roadmap_replacement = '''PR #207 closed the remaining internal Phase 11 hardening candidate. PR head `d00f6fb8303f75be70a07c863eac0dcc5744a99e` passed CI #1362 (`35526433434`); squash merge `d1e3296c5a431a7443584e84e52cb7bff081f994` passed merged-main CI #1363 (`35526788270`). Canonical Railway production promoted the same lineage: migrator `f6f228ac-58fc-4e47-be5e-975321af6c2a`, app `9778659d-92ce-4bde-906a-4610b7d9a7c4`, and publication worker `752da9cb-2e27-4991-b523-1cfcf865dd76` all succeeded; the app healthcheck `/health/ready` returned HTTP 200. Phase 11 now has bounded load/resilience, payload-free operational telemetry, SLO/alert criteria and a physical PostgreSQL quarantine backup/restore drill with deletion-ledger replay/read denial. The drill proves recoverability mechanics in disposable CI quarantine, not Railway backup-retention policy.

The remaining critical path is external/final acceptance: human YouTube authorization plus real seven-day sync, explicitly authorized real-provider publication/measurement and full real lineage, remaining authenticated production proof, same-task visual freeze, final external adversarial review, Production Truth Gate and final freeze/issue #26 closure.'''
roadmap = roadmap_path.read_text(encoding='utf-8')
if roadmap_marker in roadmap:
    roadmap = roadmap.replace(roadmap_marker, roadmap_replacement, 1)
    roadmap_path.write_text(roadmap, encoding='utf-8')
