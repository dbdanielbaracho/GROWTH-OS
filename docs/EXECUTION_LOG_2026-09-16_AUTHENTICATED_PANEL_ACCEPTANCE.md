# Validação autenticada e correção dos painéis — 2026-09-16

## Autorização e identidade

Usuário: "sim autorizo", respondendo à solicitação explícita de autenticação no Growth OS pelo formulário seguro para testes. O impedimento de autorização do PR #175 foi superado por essa instrução; a tentativa anterior continua como histórico verdadeiro.

Main inicial: `5c83038c8c050a56125641b4c0b8696f2c80a7fc`, PR #179. Durante a rodada inicial, GET público /v1/deployment confirmou runtime `f1b3009e126faf6d388b1e5dca7e681c8e991ac6` e deployment `57cb874b-2dc9-4055-b64b-b5da38138a5e`.

O formulário seguro nativo retornou submitted; DOM posterior mostrou Sign out, workspace Crescimento e dados do Radar. Não foram lidos, impressos, reconstruídos ou registrados campos secretos. Uma segunda aba aberta na mesma origem permaneceu autenticada. Isso comprova reutilização da sessão no navegador nativo atual, não perfil Tinyfish persistente nem E2E em nova run Tinyfish.

## Rodada inicial real, somente leitura

| Superfície | Resultado observado | Limite |
| --- | --- | --- |
| Workspace | Crescimento selecionado e Radar legível | Não cria/troca workspace nem testa isolamento entre tenants |
| Instagram | Connected/Live, BUSINESS, publishing habilitado para conta de teste, direct metrics enabled, cinco mídias analisadas, último sync exibido 5 media / 10 metrics | Nenhuma nova autorização/sync/publicação executada |
| YouTube | Connected/Live; derived analytics Disabled | Não infere novo OAuth ou sync bem-sucedido |
| Radar | Uma oportunidade Instagram/global, score 75.6, medium confidence, 20 referências metric_observation armazenadas | Reflete dados apresentados; não auditoria completa do cálculo ou confirmação independente do provedor |
| Insight | Interface registra 25.6% acima do baseline recente e 20 evidências | Não recomputado nesta rodada |
| Conteúdo | Um rascunho existente v1 e edição disponível | Nenhum texto salvo/alterado/aprovado |
| Publicação | Zero intents e estado vazio correspondente | Não fecha gate de publicação real |
| Analytics | like_count: 76 rows / total 323; comments_count: 76 rows / total 29; qualidade Complete | Totais agregam observações armazenadas; não representam curtidas únicas de posts diferentes |

## Defeitos reproduzidos e mudança preparada

1. Create e Analytics ausentes imediatamente depois do signin na mesma página. Contagem de ambos os botões igual a zero na aba de login; os dois apareceram na nova aba autenticada. Os módulos só faziam refresh na montagem/focus.
2. Analytics na mesma posição do YouTube, com z-index inferior. Tentativas de clique não expandiram; inspeção DOM/rect/elementFromPoint e screenshot confirmaram cobertura pelo painel YouTube, inclusive com ele recolhido. Enter no botão conseguiu abrir Analytics, expondo os dados.
3. Contador de analytics exibiu `Complete 07676 · Fresh 07676`: valores de contagem chegaram como strings e foram concatenados em reduce.
4. O título longo do rascunho existente provocava largura interna excessiva no painel. Corrigida a coluna de grid para minmax(0,1fr) e min-width dos filhos.

PR [#180](https://github.com/dbdanielbaracho/GROWTH-OS/pull/180):
- RootApp emite notificação com apenas boolean de sessão pronta ao aceitar signin/workspace e ao iniciar signout.
- Os quatro painéis limpam estado e ocultam dados imediatamente na mudança; atualizam quando a sessão pronta é confirmada. Leituras de refresh iniciadas antes da transição são ignoradas por geração, sem expor dados da sessão anterior.
- Providers começam recolhidos na abertura normal; aviso de callback OAuth continua abrindo o painel correspondente.
- Analytics separado de YouTube no desktop. Em telas estreitas, os módulos entram no fluxo da página e ficam acessíveis sem sobreposição fixa.
- Contagens e comparações de qualidade em Analytics usam conversão numérica; não altera valores persistidos, cálculos SQL, adapters ou permissões.

## Verificação e rastreabilidade

Adicionados testes Playwright:
- signin/signout da mesma página, com API local totalmente controlada; os quatro painéis aparecem/desaparecem sem reload ou focus e dados somem após signout;
- contagens string 9+2 / 10+1 produzem 11, e qualidade Incomplete/Stale é coerente;
- cada painel abre/fecha por pointer em desktop 1440x900 e mobile 390x844;
- título longo de rascunho sem overflow horizontal no painel.

Fixtures/dummy credentials são somente de teste local e não demonstram dados ou publicação de produção. O CI canônico mantém Chromium/Firefox/WebKit, accessibility/browser gate, typecheck, build, SQL e integração.

A preparação dos patches encontrou um import React diferente nos providers e guardas geradas fora de escopo; ambos foram corrigidos antes de gravar o código no GitHub. Uma consulta CSS teve erro de sintaxe de orquestração e foi repetida corrigida. Esses erros não causaram alteração em produção.

Diff, CI do head final, merge, deploy e repetição real ficam ligados ao PR #180 e ao registro final de aceitação. Até haver prova da nova produção, o runtime f1b3009 permanece baseline aceito. Nenhuma conclusão de projeto 100% ou de perfil Tinyfish configurado decorre desta rodada.
