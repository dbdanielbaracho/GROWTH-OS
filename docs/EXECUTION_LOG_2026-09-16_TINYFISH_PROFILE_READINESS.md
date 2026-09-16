# Continuação Growth OS — Tinyfish e sessão persistente — 2026-09-16

## Pedido e baseline

Pedido exato: "continuar". Data de registro: 2026-09-16 conforme o contexto atual da sessão; sem horário individual inventado.

Base main relida: `d6b3c3612d51b7f6af623629f5af8384a7b43892` (PR #178). O histórico anterior enviado em DOCX já integra main e inclui PR #176 e a regra de registrar cada continuação. O histórico não prova uma sessão atualmente autenticada.

## Execução realizada

- Lidas a memória central e `PROJECT_CURRENT_STATE.md`; conferida main ao vivo.
- Lidas as instruções de continuidade e os contratos disponíveis do Tinyfish. Não foi necessária nova busca de conversas: o histórico operacional relevante já está disponível no checkpoint e no documento importado.
- Tinyfish disponível e respondendo: executadas chamadas gratuitas de Search/Fetch, sem run de automação, vault, credenciais ou perfil autenticado.
- Leitura pública, TTL zero: `/health/ready` retornou `{"status":"ready","database":"ok"}`; a página raiz renderizou Growth OS e o convite para entrar. Essa extração não prova os controles interativos ou sessão autenticada.
- `/v1/system/info` retornou page_not_found / HTTP 404. Consultado código `apps/api/src/server.ts` e `apps/api/src/deployment-info.ts`: o contrato canônico é `GET /v1/deployment`. O 404 do endpoint antigo já havia sido registrado no log do PR #175; não é nova regressão ou motivo para criar uma rota compatível sem requisito.
- Leitura pública correta, TTL zero: [`/v1/deployment`](https://growos.predibeacon.com/v1/deployment) retornou name Growth OS, version 0.1.0, environment production, commit_sha `f1b3009e126faf6d388b1e5dca7e681c8e991ac6`, deployment_id `57cb874b-2dc9-4055-b64b-b5da38138a5e`. Identidade servida continua correspondente ao runtime aceito. Não foi executado deploy.
- Busca oficial Tinyfish e leitura das três páginas abaixo; confirmados ciclo create/setup/login/save e parâmetros de reutilização. Lido também o registro exato da rejeição de autenticação no PR #175.
- Preparados este procedimento e a matriz inicial de validação; atualizados memória e checkpoint. Diff/CI/merge final desta continuação são rastreáveis no PR #179, cujo encerramento complementa esta entrada com resultados efetivos.

## Procedimento correto de persistência

Fontes oficiais lidas nesta execução:
- [Browser Context Profiles](https://docs.tinyfish.ai/key-concepts/browser-context-profiles).
- [API de perfis](https://docs.tinyfish.ai/agent-api/browser-context-profiles).
- [Integração MCP](https://docs.tinyfish.ai/mcp-integration).

O setup deve ser salvo antes de expirar. Um login numa sessão Browser API efêmera não configura automaticamente perfil persistente.

1. No dashboard Tinyfish, abrir Browser Context Profiles; a documentação também indica o atalho no Playground: ícone de perfil, Use Browser Context Profile, Go to Browser Context Profiles quando nenhum existe. Não foi inventada uma URL direta nem inspecionado o dashboard privado nesta continuação.
2. Criar perfil específico Growth OS Production, marcar default se adequado e usar Create and set up. Entrar no domínio exato `https://growos.predibeacon.com` pelo fluxo seguro e salvar a sessão de setup. A autorização de autenticação continua pendente; esse passo está preparado, não executado.
3. Executar uma validação com `use_profile: true`; se necessário, selecionar o ID concreto via `profile_id`. Browser profile lite/stealth é modo do navegador, diferente de Browser Context Profile.
4. Confirmar identidade/workspace sem registrar valores de cookies/tokens. Executar uma segunda validação independente com o mesmo perfil e confirmar que a sessão se mantém. Somente essa repetição pode evidenciar a resolução da perda de sessão.
5. Se a sessão expirar, registrar esse estado e utilizar somente o fluxo de autenticação autorizado. Não habilitar vault amplo como contorno.

A API oficial oferece list/create/setup/save de perfis com autenticação por chave. Esses métodos de gestão não constam entre os métodos Tinyfish expostos nesta sessão. Portanto não se afirma perfil criado, default definido ou ID recuperado. `use_profile: true` sem default pode retornar 400, e o contrato do conector informa que o opt-in pode ser ignorado se a feature estiver desabilitada. O teste deve conferir o resultado real. Não pedir chave ou cookies pelo chat.

## Matriz preparada — leitura autenticada inicial

| Jornada | Verificação real requerida | Estado atual |
| --- | --- | --- |
| Sessão persistente | Abrir com perfil, confirmar sessão, repetir em nova execução | Pendente de autenticação/perfil |
| Workspace | Workspace visível e autorização coerente; sem troca durante a rodada inicial | Pendente |
| Instagram | Status e observações retornadas; estados de indisponibilidade/escassez corretamente exibidos | Pendente |
| YouTube | Estado de autorização/provedor e mensagens; não inferir sucesso externo | Pendente |
| Opportunity Radar | Oportunidades sustentadas por dados reais ou ausência explicitamente indicada | Pendente |
| Analytics | Dados/estado vazio coerentes com origem e período real | Pendente |
| Conteúdo/publicação | Ler estados existentes, aprovações e fila; sem publicação externa nesta rodada | Pendente |

A rodada inicial somente lê estados autenticados existentes. Criar conteúdo, testar mudanças de estado e confirmar publicação externa são etapas distintas, com dados/conta/conteúdo e evidência adequados. Não trocar fixture por evidência real.

## Impedimento concreto

O PR #175 registra rejeição automática da solicitação/submissão de credenciais de produção: o pedido genérico de continuação foi considerado autorização insuficiente para essa etapa de autenticação. O bloqueio não foi removido pelo DOCX ou pelo novo "continuar". Não foi repetida a chamada nem usado Tinyfish para contornar a rejeição.

Próximo passo dependente: obter autorização explícita para autenticar em growos.predibeacon.com pelo formulário seguro para validar o Growth OS. O usuário fornece credenciais somente nesse formulário, nunca no texto do chat. Depois, executor continua as verificações, sem atribuir os testes ao usuário.

Resultado desta continuação: saúde pública e runtime reconfirmados; procedimento atual Tinyfish preparado e documentado. E2E autenticado, sessão persistente, publicação real, comparação visual final e Claude final ainda não concluídos.
