# GROW OS — Memória Completa de Execução do Projeto

**Repositório:** dbdanielbaracho/GROWTH-OS  
**Documento:** memória operacional completa, versionada no GitHub  
**Data desta consolidação:** 05 de setembro de 2026  
**Última atualização coberta:** revisão independente do PR #29, SHA 05bc516df3479b0ab338efe0ad991877d80812dd

## 1. Finalidade

Este arquivo registra a execução do projeto Growth OS de forma contínua e auditável. O objetivo é permitir que o trabalho continue mesmo quando uma conversa fique lenta, seja trocada ou não carregue todo o histórico.

O registro inclui:

- ações executadas;
- comandos e configurações aplicadas;
- arquivos, migrations, testes, commits e branches;
- deploys, serviços, bancos, URLs e identificadores;
- erros, tentativas que falharam, desvios e falsos negativos;
- correções de entendimento;
- decisões do usuário;
- evidências confirmadas;
- itens pendentes e o próximo ponto exato de retomada.

Este documento não é um resumo executivo. Quando um fato é conhecido, ele deve ser registrado mesmo que pareça pequeno ou repetitivo em relação a outro documento.

### 1.1 Limite de completude

Este registro reúne tudo que foi comprovado nos dois documentos fornecidos pelo usuário e na continuação executada nesta conversa. Ele não pode recuperar mensagens de outra conversa que nunca tenham sido anexadas, coladas ou verificadas em GitHub, Railway, banco, CI ou logs.

Quando a origem for apenas relato histórico, isso fica indicado. Quando houver evidência externa, a evidência é identificada. Nenhum fato deve ser inventado para preencher lacunas.

### 1.2 Classificação

- CONFIRMADO: verificado diretamente em GitHub, Railway, banco, CI, log, arquivo ou teste.
- HISTÓRICO: informado nos documentos/conversas fornecidos, sem nova verificação nesta consolidação.
- CORREÇÃO: entendimento anterior que foi alterado por evidência posterior.
- PENDENTE: ainda precisa de execução, confirmação ou decisão.
- RISCO ACEITO: risco explicitamente conhecido e aceito pelo usuário naquele momento.

### 1.3 Segurança

Segredos e credenciais não são reproduzidos. Isso inclui valores de OAuth Client Secret, CSRF_SECRET, DATABASE_URL, PGPASSWORD, senhas, tokens e links assinados/temporários. Os nomes das variáveis, o fato de terem sido configuradas, os riscos e as ações relacionadas continuam registrados.

---

## 2. Estado atual no momento desta consolidação

- Repositório canônico: dbdanielbaracho/GROWTH-OS.
- Branch canônica: main.
- Issue #26: aberta.
- PR #28: mergeado.
- PR #29: aberto, draft e mergeable.
- PR #29 SHA atual: 05bc516df3479b0ab338efe0ad991877d80812dd.
- CI do PR #29: run #93, SUCCESS.
- Validação Railway do SHA exato do PR #29: SUCCESS.
- Banco de validação do PR #29: growth_os_test.
- Produção: não alterada pela validação da migration 014.
- Revisão adversarial formal do Claude para o PR #29: pendente.
- Merge/deploy final do PR #29: não executado.
- Ambiente Railway canônico: projeto successful-embrace, serviço growth-os.
- Deploy canônico verificado: 7fa19ad4-a200-4a96-821b-091e5a94acd3, SUCCESS.
- Ambiente grateful-courage: desvio secundário, não é fonte da verdade.
- Próximo gate de produto: autenticação canônica, OAuth YouTube real, primeiro sync real e caminho observação -> sinal -> insight -> oportunidade -> Radar.

---

## 3. Linha do tempo completa da execução

### 3.1 Troca de conversa por lentidão

1. A conversa/projeto anterior chamado “Bloqueio da migração Grow OS” ficou lenta.
2. O usuário abriu uma nova conversa para continuar.
3. Foi identificado que uma conversa separada não é aberta automaticamente como se fosse o mesmo histórico.
4. Foi estabelecido que GitHub, Railway, bancos e arquivos continuam existindo, mas o histórico textual completo da conversa anterior pode não estar disponível.
5. A regra definida foi continuar a partir da última evidência real, sem reiniciar o projeto, repetir migrations, criar um estado paralelo ou declarar conclusão sem comprovação.
6. O usuário anexou/colou documentos de histórico para reconstruir a continuidade.
7. A classificação confirmado / histórico / correção / pendente passou a ser usada para evitar confundir hipótese com fato.
8. Nesta conversa, os seguintes arquivos foram usados como fontes:
   - GROW_OS_Historico_Chat_2026-09-05.md
   - GROW_OS_Registro_Completo_Conversa_2026-09-05.docx
9. Os dois documentos foram consolidados em um relatório único e depois em uma memória ampliada, incluindo a continuação do PR #29.
10. Após o usuário esclarecer que a memória deveria permanecer no GitHub, foi decidido criar este arquivo em docs/PROJECT_EXECUTION_MEMORY.md.

### 3.2 Estado inicial do serviço secundário

1. Foi criado um serviço novo @growth-os/api no Railway no projeto grateful-courage.
2. Foi criado/associado um Postgres novo no mesmo projeto para manter a comunicação privada.
3. O Postgres permaneceu sem Public Access.
4. Foi criado o domínio https://growth-osapi-production-0df6.up.railway.app.
5. O primeiro problema de deploy estava relacionado ao Start Command não ser detectado/persistido pelo Railpack.
6. Depois de configurar o deploy, a aplicação ficou online.
7. A tela de login do Growth OS abriu no domínio secundário.
8. A tela disponível era Sign in; não havia uma conta conhecida para usar.
9. Inicialmente o problema foi interpretado como ausência de um primeiro usuário.
10. Logs posteriores mostraram que a causa era mais profunda: POST /v1/auth/signin -> 500 schema "growth" does not exist.
11. A conclusão foi corrigida: o Postgres secundário não estava apenas sem usuário; ele não tinha o schema canônico do produto, suas migrations e sua Identity.

### 3.3 Google Cloud, MFA e OAuth

1. O acesso ao Google Cloud foi bloqueado por exigência de verificação em duas etapas.
2. O usuário ativou MFA/2SV.
3. O acesso ao console foi retomado.
4. Houve navegação entre seleção/criação de projeto e Google Auth Platform.
5. Foram vistos os nomes Growth OS e Sistema Operacional de Crescimento; ficou registrada a necessidade de confirmar visualmente qual projeto contém o cliente final antes de futuras alterações.
6. Foi configurado um aplicativo OAuth com nome Growth OS, audiência External e e-mail de contato.
7. Foi criado o cliente OAuth Web Growth OS Web, do tipo Web application.
8. O usuário recusou iniciar Free Trial/Start free e recusou cadastrar cartão com risco de cobrança.
9. O Client Secret apareceu no histórico/print.
10. Foi recomendado rotacionar o segredo.
11. O usuário decidiu não criar outro segredo naquele momento.
12. Esse risco foi preservado no registro sem reproduzir o valor secreto.
13. Origem canônica discutida: https://growth-os-production-d120.up.railway.app.
14. Callback canônico discutido: https://growth-os-production-d120.up.railway.app/v1/integrations/youtube/callback.
15. Origem secundária adicionada durante o desvio: https://growth-osapi-production-0df6.up.railway.app.
16. Callback secundário adicionado durante o desvio: https://growth-osapi-production-0df6.up.railway.app/v1/integrations/youtube/callback.
17. A confirmação final de que o cliente Growth OS Web mantém origem e callback canônicos ficou pendente.
18. A URL secundária deve ser removida quando não houver mais dependência de teste.

### 3.4 Primeira configuração Railway

1. No serviço secundário @growth-os/api, foram inicialmente adicionadas GOOGLE_CLIENT_ID e GOOGLE_CLIENT_SECRET.
2. A revisão do código mostrou que o conector usa YOUTUBE_OAUTH_CLIENT_ID e YOUTUBE_OAUTH_CLIENT_SECRET.
3. Os nomes GOOGLE_* foram identificados como incorretos para a configuração do projeto.
4. Houve uma tentativa de criar um serviço @growth-os/web separado.
5. O serviço separado usaria npm run dev em produção.
6. O entendimento foi corrigido: a topologia canônica é same-origin; o serviço API serve o build web em produção.
7. O serviço web separado não é necessário para a topologia canônica.
8. Foram discutidas/ajustadas variáveis de ambiente, incluindo NODE_ENV, APP_ORIGIN, CSRF_SECRET e DATABASE_URL.
9. Um CSRF_SECRET aleatório foi gerado durante a execução.
10. O valor foi omitido do registro por segurança.

### 3.5 Falha de deploy por DATABASE_URL

1. O primeiro deploy do API falhou no startup.
2. O erro de configuração retornado pelo Zod foi: Invalid input: expected string, received undefined.
3. O campo ausente era DATABASE_URL.
4. Foi procurado um Postgres para referenciar.
5. O Postgres encontrado estava em outro projeto Railway.
6. Foi usada uma URL privada apontando para postgres.railway.internal.
7. O runtime falhou com getaddrinfo ENOTFOUND postgres.railway.internal.
8. A evidência demonstrou que o hostname/rede privada do Railway não atravessa projetos diferentes.
9. A correção de rede exigia que API e banco estivessem no mesmo projeto ou que fosse usado acesso público.
10. A alternativa de acesso público foi analisada e recusada.

### 3.6 Recusa do Public Access e criação do desvio

1. Na tela Networking -> Public Access, foi informado que habilitar acesso público criaria DATABASE_PUBLIC_URL.
2. Também foi informado que o tráfego público poderia gerar custo de egress.
3. O usuário recusou explicitamente ativar Public Access, aceitar custo de egress público ou alterar a proteção do banco.
4. Para manter a comunicação privada, foi criado o API no mesmo projeto do Postgres encontrado: grateful-courage.
5. O domínio secundário foi criado.
6. O Google OAuth foi atualizado para aceitar a URL secundária durante o teste.
7. O Railpack falhou repetidamente ao detectar/persistir o Start Command.
8. A configuração que finalmente funcionou foi:
   - Build: npm run build;
   - Start: node apps/api/dist/server.js;
   - Healthcheck: /health/ready;
   - Watch Path: /apps/**.
9. O deployment secundário ficou SUCCESS.
10. A tela do Growth OS abriu.
11. O login falhou depois porque o banco novo não possuía schema growth.
12. A decisão foi não criar usuário nesse banco e não migrar o produto para ele.

### 3.7 Reconstrução do ambiente canônico

1. O GitHub foi consultado diretamente para corrigir informações antigas.
2. O PR #28 foi confirmado como fechado e mergeado.
3. O PR #28 não estava mais draft/open.
4. O ambiente Railway canônico foi identificado como successful-embrace.
5. O serviço canônico foi identificado como growth-os.
6. O Postgres canônico estava no mesmo projeto do serviço.
7. O ambiente canônico continha serviço growth-os, Postgres canônico, migrator, node-integration-tests, Postgres-Validation e validators relacionados ao Issue #26.
8. Foi confirmada a URL canônica: https://growth-os-production-d120.up.railway.app.
9. A conclusão arquitetural foi continuar no ambiente canônico, preservar o Postgres canônico, não provisionar usuário no Postgres vazio, não migrar o produto para grateful-courage e não tratar o ambiente secundário como fonte da verdade.

### 3.8 PR #28 e revisão adversarial

1. O PR #28 tinha o título feat(issue-26): add YouTube connector foundation.
2. Repositório: dbdanielbaracho/GROWTH-OS.
3. Issue relacionada: #26 — Build real signal ingestion and Growth Intelligence Engine.
4. A Issue #26 permaneceu aberta.
5. O SHA final aprovado foi 9bf5e78ea883093a0e52b547193ef891e869c5ba.
6. O merge commit confirmado foi d68bcf0430d181e456e30523c46a590142560704.
7. A base anterior ao PR era e24f9daf6cbcd869b120c3c98dd6928e8aa7d362.
8. O CI final foi run #88, run id 33905183596, SUCCESS.
9. O Claude fez revisão adversarial formal.
10. O Claude aprovou o primeiro slice do conector YouTube.
11. O Claude não executou merge/deploy; o merge ocorreu depois.
12. O escopo aprovado incluiu YouTube OAuth, YouTube Data API, YouTube Analytics, migrations 010-013, testes 029-031, technical design v0.1-v0.3, provenance, isolamento de credenciais, idempotência, semântica de dias Pacific e DST.
13. A migration 013 corrigiu conflito/aliasing por campos materiais.
14. O gate SQL 031 passou.
15. A semântica de dia Pacific usa America/Los_Angeles.
16. Os intervalos são [start,end).
17. Dias DST de 23, 24 e 25 horas foram considerados.
18. O último dia Pacific completo foi preservado.
19. Para views, o boundary efetivo era 24/08/2026 no instante UTC real.
20. Para engagedViews, effectiveFrom = null porque permaneceu unchanged.
21. OAuth state usa AES-256-GCM.
22. Foram revisados replay e TTL.
23. Foi preservado isolamento de credenciais.
24. RLS/FORCE foram preservados.
25. Não foi permitido BYPASSRLS indevido.
26. derived_analytics permaneceu fail-closed.
27. A revisão não encerrou o Issue #26.
28. Ainda faltava o loop observação real -> sinal determinístico -> insight/evidence -> oportunidade ranqueada -> Opportunity Radar.
29. Também faltava o Production Truth Gate com conta autenticada, autorização real do YouTube e dado real do provedor.

### 3.9 Variáveis e redeploy canônico

1. No serviço canônico growth-os, foram adicionadas/configuradas YOUTUBE_OAUTH_CLIENT_ID, YOUTUBE_OAUTH_CLIENT_SECRET, PROVIDER_CREDENTIALS_KEY_B64URL, PROVIDER_CREDENTIALS_KEY_VERSION e YOUTUBE_DERIVED_ANALYTICS_POLICY_ACCEPTED.
2. Os valores secretos não são reproduzidos.
3. YOUTUBE_DERIVED_ANALYTICS_POLICY_ACCEPTED permaneceu em modo fail-closed.
4. Scores, rankings e benchmarks derivados não foram liberados antes da aceitação formal da política.
5. Foi disparado redeploy do serviço canônico.
6. O deployment verificado foi 7fa19ad4-a200-4a96-821b-091e5a94acd3.
7. O estado do deployment foi SUCCESS.
8. Esse deploy não copiou o Postgres vazio do ambiente secundário.
9. Public Access do Postgres não foi ativado.

### 3.10 Continuação executada depois da consolidação: PR #29

1. Depois dos relatórios anteriores, a conversa continuou com o pedido continuar.
2. Foi identificado o PR #29.
3. Branch: feat/issue-26-youtube-integration-ux.
4. Título: feat(issue-26): add YouTube connection and sync UX.
5. SHA inicial: dcf8c0dfe992be7fff33c07efcbee7ac6aa58e7b.
6. CI inicial: run #90, SUCCESS.
7. O PR estava aberto, draft e mergeable.
8. No começo da validação não havia review formal nem comentários relevantes.
9. Arquivos principais identificados: youtube-routes.ts, api.ts, youtube-integration.tsx, migration 014 e teste 032.
10. A validação antiga estava presa ao SHA anterior 9bf5e78 e não validava o PR #29.
11. Uma versão inicial do validator procurou growth.schema_migrations.
12. Foi confirmado que essa tabela não existe no projeto.
13. A verificação foi corrigida para procurar diretamente growth.youtube_integration_status() em pg_proc.
14. A migration 014 ainda não estava aplicada em growth_os_test.
15. O serviço migrator não foi usado porque apontava para o banco incorreto growth_os_797f0a3.
16. O banco correto de validação era growth_os_test.

### 3.11 Aplicação controlada da migration 014

1. A migration 014 foi buscada no SHA exato do PR.
2. Foi criado/usado o serviço de aplicação controlada pr29-014-apply.
3. Foram usadas as referências VAL_PGHOST, VAL_PGPORT, VAL_PGUSER, VAL_PGPASSWORD e VAL_PGDATABASE.
4. As referências vieram do serviço issue-26-post012-smoke-v2.
5. O deployment da aplicação da migration foi 04f665e9-baf5-4531-ac04-3cda080fac55.
6. O deployment terminou SUCCESS.
7. O banco conectado foi growth_os_test.
8. A migration 014 foi executada com sucesso.
9. A função foi criada com owner growth_migrator.
10. A função usa SECURITY DEFINER.
11. PUBLIC foi revogado.
12. EXECUTE foi concedido a app_runtime.
13. A produção não foi alterada.
14. A migration foi aplicada apenas no banco de teste necessário à validação do PR.

### 3.12 Falso negativo do teste SQL 032

1. Depois da aplicação da migration, o teste 032 falhou com helper lost tenant/authority/provider filters.
2. A investigação comparou o SQL esperado com o retorno de pg_get_functiondef.
3. Foi descoberto que pg_get_functiondef normaliza o SQL e remove/transforma espaçamentos.
4. O teste comparava strings com espaçamento literal.
5. A falha era um falso negativo do teste, não uma perda real dos filtros semânticos.
6. O teste foi corrigido para normalizar whitespace antes de procurar os filtros.
7. O commit da correção foi 12242e143eefc3d950d4a556740f19465c190087.
8. Mensagem do commit: test(issue-26): normalize status helper gate inspection.
9. O CI #91 passou.

### 3.13 Validator corrigido para o SHA exato

1. O validator foi atualizado para buscar diretamente db/tests/032_youtube_integration_status.sql.
2. O arquivo foi buscado do SHA 12242e143eefc3d950d4a556740f19465c190087.
3. O teste foi executado contra growth_os_test.
4. O validator não reaplicou migrations.
5. O deployment de validação foi 26bdb67e-2753-4b19-a3ec-e24ba0080ca3.
6. A validação confirmou migration 014 presente, growth.youtube_integration_status() presente, TEST-032 PASS, MIGRATIONS REAPPLIED: NO e produção intocada.
7. O resultado foi considerado válido para o candidato daquele SHA.

### 3.14 Checkpoint criado para evitar nova perda de contexto

1. Para registrar o estado vivo do PR, foi criado PROJECT_CURRENT_STATE.md no branch do PR #29.
2. O checkpoint explicou que o SHA vivo precisa ser buscado no GitHub antes de qualquer ação.
3. Foi registrado que qualquer novo commit altera o SHA candidato.
4. A criação/ajuste do checkpoint gerou novos heads.
5. O SHA vivo final tornou-se 05bc516df3479b0ab338efe0ad991877d80812dd.
6. O CI do novo SHA foi run #93, SUCCESS.
7. O validator foi ligado novamente ao SHA exato.
8. O deployment da validação final foi cd01b102-f9db-4636-bb51-0d6d0f9fe951.
9. A prova retornada registrou:
   - PROOF-1 PASS target_db=growth_os_test (production untouched);
   - PROOF-2 CANDIDATE SHA EXACT: 05bc516df3479b0ab338efe0ad991877d80812dd;
   - PROOF-3 MIGRATION 014 PRESENT: growth.youtube_integration_status();
   - PROOF-4 FETCHED db/tests/032_youtube_integration_status.sql FROM EXACT SHA (2027 bytes);
   - TEST-032 PASS;
   - PROOF-DB TARGET DATABASE: growth_os_test;
   - MIGRATIONS REAPPLIED: NO;
   - OVERALL: VALIDATION COMPLETE - PR #29 CANDIDATE 05BC516 VALIDATED.
10. Estado após essa etapa: PR #29 aberto, draft e mergeable; CI #93 SUCCESS; banco de teste validado; produção intocada; Claude pendente; merge/deploy final não executado.

---

## 4. Mapa completo dos ambientes Railway

### 4.1 Ambiente canônico: successful-embrace

- Papel: fonte da verdade do produto.
- Project ID: 76277bf9-640b-4964-b406-76b71feff7fb.
- Environment ID: fdf989ff-78b5-4268-9465-2739acc40d2f.
- Serviço: growth-os.
- Service ID: 2d5f783b-b260-4ab7-885f-894a67884cba.
- Postgres ID: 81141a4f-00a4-450d-9ef7-0557e7167d0b.
- Domínio: https://growth-os-production-d120.up.railway.app.
- Build: npm run build.
- Start: npm run start -w @growth-os/api.
- Healthcheck: /health/ready.
- Último deploy canônico verificado: 7fa19ad4-a200-4a96-821b-091e5a94acd3, SUCCESS.
- Conteúdo operacional: Postgres canônico, migrator, testes de integração, validação do Postgres e validators do Issue #26.
- Decisão: continuar aqui.

### 4.2 Ambiente secundário: grateful-courage

- Papel: desvio temporário.
- Project ID: c8ea04f7-481c-4b7e-bc0f-d018c20bedb7.
- Serviço: @growth-os/api.
- Service ID: a049360f-9be3-49a9-b65b-725c0be6d69e.
- Postgres ID: 4e1270cd-794d-4846-861f-8de1d059ddec.
- Domínio: https://growth-osapi-production-0df6.up.railway.app.
- Estado: API abriu, mas o Postgres era novo/vazio.
- Erro: schema growth does not exist.
- Decisão: não usar como fonte da verdade; tratar como temporário até a limpeza final.

### 4.3 Ambiente intermediário: spirited-love

- Papel: apareceu durante a primeira tentativa de criar o novo API.
- Problema: referência privada para Postgres de outro projeto.
- Erro: getaddrinfo ENOTFOUND postgres.railway.internal.
- Decisão: não é ambiente canônico.

### 4.4 Serviços temporários de validação do PR #29

- pr29-014-apply: aplicou migration 014 somente no banco de teste.
- issue-26-post012-smoke-v2: forneceu as referências do banco de teste.
- migrator: não foi usado para migration 014 porque estava apontando para growth_os_797f0a3, banco incorreto.
- Deploy de aplicação da migration: 04f665e9-baf5-4531-ac04-3cda080fac55.
- Deploy validator do SHA 12242e: 26bdb67e-2753-4b19-a3ec-e24ba0080ca3.
- Deploy validator final do SHA 05bc516: cd01b102-f9db-4636-bb51-0d6d0f9fe951.

---

## 5. GitHub, branches, commits, CI e PRs

### 5.1 PR #28

- Título: feat(issue-26): add YouTube connector foundation.
- Estado: MERGED.
- Head aprovado: 9bf5e78ea883093a0e52b547193ef891e869c5ba.
- Merge commit: d68bcf0430d181e456e30523c46a590142560704.
- Base anterior: e24f9daf6cbcd869b120c3c98dd6928e8aa7d362.
- CI: #88 / run id 33905183596, SUCCESS.
- Issue: #26, OPEN.

### 5.2 PR #29

- Título: feat(issue-26): add YouTube connection and sync UX.
- Branch: feat/issue-26-youtube-integration-ux.
- Estado: OPEN, draft, mergeable.
- SHA inicial: dcf8c0dfe992be7fff33c07efcbee7ac6aa58e7b.
- SHA atual: 05bc516df3479b0ab338efe0ad991877d80812dd.
- CI inicial: #90, SUCCESS.
- CI atual: #93, SUCCESS.
- Arquivos principais: rotas YouTube, API, interface YouTube, migration 014 e teste 032.
- Validação final: SUCCESS no deploy cd01b102-f9db-4636-bb51-0d6d0f9fe951.
- Claude adversarial: pendente.
- Merge: não executado.
- Deploy final: não executado.

### 5.3 Commits de correção registrados

- 12242e143eefc3d950d4a556740f19465c190087
  - Mensagem: test(issue-26): normalize status helper gate inspection.
  - Motivo: corrigir falso negativo do teste 032 causado por comparação literal de whitespace.
- 05bc516df3479b0ab338efe0ad991877d80812dd
  - Motivo: head atual do PR #29 após o checkpoint operacional e atualização da memória do estado vivo.

---

## 6. Identity, login e primeiro usuário

1. Não existe login/senha padrão do Growth OS.
2. A senha do Railway não é senha da aplicação.
3. O Client Secret do Google não é senha da aplicação.
4. O Postgres canônico possui Identity v1.
5. Existe a função DB growth.identity_signup(text,text,smallint).
6. Existem helpers para sessão, workspace e convites.
7. O app expõe HTTP para signin, session, seleção de workspace, signout e signout-all.
8. Na revisão registrada não foi encontrada rota HTTP /v1/auth/signup em apps/api/src/app.ts.
9. O primeiro acesso canônico precisa usar uma rota de signup prevista no design ou provisionamento inicial controlado usando a API/helper de Identity.
10. Não inserir usuário ou senha manualmente no Postgres secundário.
11. Não inserir senha sem respeitar hash, auditoria e RLS.
12. Toda mudança material em Identity deve passar por alteração versionada, CI, validação, revisão adversarial do Claude, deploy controlado e evidência.

---

## 7. Guardrails de arquitetura preservados

1. PostgreSQL é o source of truth.
2. Isolamento por tenant deve ser preservado.
3. RLS e FORCE devem continuar ativos.
4. growth.provider_credentials isola credenciais.
5. app_runtime não deve receber SELECT direto indevido em credenciais.
6. Helpers YouTube são SECURITY DEFINER com owner, search_path e revokes revisados.
7. derived_analytics é separado e fail-closed/kill-switched.
8. OAuth exige managed account pré-existente com authority_status=contractually_granted.
9. Não fazer backfill inseguro antes do boundary semântico de 24/08/2026 para views.
10. YouTube Analytics day é calendário Pacific.
11. DST e limites de source_range devem preservar a semântica real.
12. Google I/O ocorre fora de uma transação DB longa.
13. Persistência do report ocorre depois em transação tenant.
14. Retries usam requestNonce/collection_run_id e chave de idempotência.
15. Revisões intencionais do provedor usam novo nonce.
16. Nenhum dado sintético pode virar sinal ou oportunidade em produção.
17. Insuficiência de evidência deve produzir empty/no-op verdadeiro, não oportunidade inventada.
18. O sistema deve continuar a cadeia provider data -> normalized observations -> signals -> insight/evidence -> ranked opportunity -> Opportunity Radar.

---

## 8. Erros, desvios, evidências e correções

| Ocorrência | Evidência/efeito | Correção |
|---|---|---|
| Usar GOOGLE_CLIENT_ID/SECRET | Os nomes não eram os consumidos pelo conector | Usar YOUTUBE_OAUTH_CLIENT_ID/SECRET |
| Criar @growth-os/web separado com npm run dev | Topologia de produção inadequada | Usar same-origin; API serve o build web |
| Omitir DATABASE_URL | Zod falhou no startup | Configurar referência correta |
| Usar postgres.railway.internal entre projetos | ENOTFOUND | API e banco no mesmo projeto ou alternativa explícita |
| Ativar Public Access | Criaria custo/egress público | Recusado; Postgres permaneceu privado |
| Criar API junto de Postgres novo | API abriu, mas faltava schema growth | Não usar como fonte da verdade |
| Interpretar login como apenas falta de usuário | Log mostrou schema inexistente | Corrigir diagnóstico: banco inteiro era inadequado |
| Usar validator preso a SHA antigo | PR #29 não era validado | Buscar sempre o SHA vivo exato |
| Procurar tabela growth.schema_migrations | Tabela não existe no projeto | Inspecionar diretamente pg_proc/função esperada |
| Usar serviço migrator errado | Apontava para growth_os_797f0a3 | Aplicar somente no banco de teste correto |
| Reaplicar migration na validação | Poderia contaminar prova/idempotência | Confirmar MIGRATIONS REAPPLIED: NO |
| Comparar whitespace literal no teste 032 | Falso negativo em pg_get_functiondef | Normalizar whitespace antes da asserção |
| Atualizar checkpoint do PR | Novo commit mudou o SHA candidato | Buscar o head vivo novamente e repetir validação |
| Assumir PR #28 aberto/draft | Informação antiga divergente | Consultar GitHub e registrar MERGED |
| Confundir URL secundária com canônica | Poderia levar a deploy/login/banco errados | Usar successful-embrace/growth-os como fonte da verdade |

---

## 9. Decisões explícitas do usuário

1. Continuar no novo chat sem perder as decisões anteriores.
2. Executar diretamente o que puder ser executado por integração, evitando usar o usuário como ponte desnecessária.
3. Não ativar Google Cloud Free Trial/Start free.
4. Não cadastrar cartão com risco de cobrança.
5. Não ativar Public Access do Postgres.
6. Não aceitar custo de egress público para resolver a conexão.
7. Não rotacionar o OAuth Client Secret naquele momento, apesar do alerta de exposição.
8. Prosseguir até o deploy e continuar com gates de evidência.
9. Registrar no documento tudo que foi realizado, e não apenas itens considerados relevantes.
10. Manter no GitHub uma memória operacional contínua para que a execução não dependa do histórico de um chat.

---

## 10. Pendências e ordem segura de retomada

1. Confirmar no Google Auth Platform a origem canônica e o redirect canônico do cliente Growth OS Web.
2. Confirmar o estado vivo do PR #29 no GitHub antes de qualquer nova ação.
3. Não usar grateful-courage como banco do produto.
4. Validar o serviço canônico em /health/ready, /, /v1/system e ausência de erro de configuração YouTube.
5. Concluir a revisão adversarial formal do Claude no SHA exato do PR #29.
6. Somente depois dos gates, decidir merge do PR #29.
7. Resolver signup/provisionamento inicial no banco canônico por fluxo de Identity seguro.
8. Autenticar e selecionar/criar workspace canônico.
9. Garantir um managed_account com authority_status=contractually_granted.
10. Executar OAuth YouTube real.
11. Confirmar callback, state, criptografia da credencial e persistência da conexão.
12. Executar primeiro sync real.
13. Provar metric_observations com provenance, semantic version, source range e idempotência.
14. Implementar/validar observação -> sinal factual -> insight/evidence -> oportunidade -> Radar.
15. Manter fail-closed quando a evidência for insuficiente.
16. Executar o Production Truth Gate completo na URL canônica.
17. Capturar e registrar todas as evidências de cada gate.
18. Remover serviços temporários/duplicados depois de não serem mais necessários.
19. Remover origens e redirects OAuth secundários depois da limpeza.
20. Atualizar este arquivo após cada ação material.

---

## 11. Protocolo obrigatório para futuras atualizações

A partir deste arquivo, cada execução deve seguir esta sequência:

1. Antes de agir, consultar o GitHub e identificar o branch e SHA vivos.
2. Registrar a intenção da ação.
3. Registrar o comando, alteração, ferramenta ou configuração aplicada.
4. Registrar o resultado exato, incluindo falha.
5. Se falhar, registrar mensagem de erro e diagnóstico.
6. Registrar a correção executada.
7. Registrar IDs de deployment, workflow, teste, migration ou recurso.
8. Registrar o banco/ambiente exato afetado.
9. Declarar explicitamente se produção foi alterada ou permaneceu intocada.
10. Atualizar o estado do PR, branch e SHA.
11. Atualizar a evidência de CI/validator/Claude.
12. Registrar decisões do usuário.
13. Registrar pendências criadas.
14. Nunca apagar uma tentativa falha: marcar como falha, correção ou supersedida.
15. Nunca registrar segredo em texto.
16. Se uma alteração gerar novo commit, invalidar as provas específicas do SHA anterior e repetir os gates necessários.
17. Não considerar um relatório local como memória oficial enquanto a atualização não estiver no GitHub.
18. Fazer commit desta memória em branch/PR próprio, sem alterar silenciosamente o SHA do PR de feature.
19. Depois que este PR documental for mergeado, atualizar o arquivo na main após cada etapa material do projeto.

### Modelo de entrada para novas ações

Data/hora:  
Objetivo:  
Estado anterior:  
Ação executada:  
Arquivos/configurações/comandos:  
Ambiente afetado:  
Resultado:  
Evidência/ID/URL/SHA:  
Falha ou desvio:  
Correção:  
Produção alterada?:  
Decisão do usuário:  
Próximo passo:  

---

## 12. Referências

- Repositório: https://github.com/dbdanielbaracho/GROWTH-OS
- Issue #26: https://github.com/dbdanielbaracho/GROWTH-OS/issues/26
- PR #28: https://github.com/dbdanielbaracho/GROWTH-OS/pull/28
- PR #29: https://github.com/dbdanielbaracho/GROWTH-OS/pull/29
- Serviço canônico: https://growth-os-production-d120.up.railway.app
- API secundário, não canônico: https://growth-osapi-production-0df6.up.railway.app
- Google Auth Clients: https://console.cloud.google.com/auth/clients

Documentos canônicos já identificados no repositório:

- docs/FULL_PRODUCT_ROADMAP.md
- docs/canonical/README.md
- db/IDENTITY_V1_DESIGN.md
- README.md

Documento de checkpoint criado no branch do PR #29:

- PROJECT_CURRENT_STATE.md
- Ele é específico do PR #29 e não substitui esta memória operacional geral.

---

## 13. Ponto exato para retomada

Continuar no GROW OS usando o repositório dbdanielbaracho/GROWTH-OS e consultar primeiro este arquivo. O ambiente canônico é Railway successful-embrace, serviço growth-os, domínio https://growth-os-production-d120.up.railway.app, com Postgres canônico no mesmo projeto. O PR #28 foi aprovado pelo Claude e mergeado no commit d68bcf0430d181e456e30523c46a590142560704. O PR #29 está aberto/draft/mergeable no SHA 05bc516df3479b0ab338efe0ad991877d80812dd, CI #93 SUCCESS e validator final SUCCESS no banco growth_os_test, com produção intocada. A revisão adversarial formal do Claude e o merge do PR #29 ainda estão pendentes. grateful-courage é um desvio com Postgres vazio e não deve virar fonte da verdade.

A próxima execução deve começar confirmando o SHA vivo, o estado da revisão do PR #29 e o gate correspondente. Nenhuma validação do SHA anterior deve ser tratada como válida automaticamente depois de novo commit.


---

## 14. Retomada registrada: revisão independente do PR #29

**Data:** 05 de setembro de 2026  
**Objetivo:** continuar o projeto a partir da memória oficial e revisar o candidato exato antes do gate Claude/merge.

1. A memória oficial foi consultada na branch main antes de agir.
2. O PR #29 foi consultado diretamente no GitHub.
3. O SHA vivo confirmado foi 05bc516df3479b0ab338efe0ad991877d80812dd.
4. O PR continua OPEN, draft e sem merge.
5. O PR continua com base main no commit d68bcf0430d181e456e30523c46a590142560704.
6. O PR declara como escopo:
   - migration 014 com growth.youtube_integration_status();
   - gate SQL 032;
   - endpoint autenticado de status;
   - callback OAuth retornando à aplicação;
   - painel web Connect -> consentimento Google -> Sync;
   - retry com o mesmo caller nonce;
   - derived analytics fail-closed.
7. A lista de arquivos do PR foi revisada no SHA exato.
8. Foram revisados, no mínimo, os caminhos de:
   - rotas API YouTube;
   - connector OAuth/sync;
   - migration 014;
   - teste SQL 032;
   - API web;
   - painel YouTube;
   - shell same-origin;
   - checkpoint operacional.
9. A revisão verificou que o endpoint de status usa o helper SQL e não concede SELECT direto do app_runtime em managed_accounts ou platform_connections.
10. A revisão verificou que a migration mantém SECURITY DEFINER, owner growth_migrator, EXECUTE para app_runtime e revoga PUBLIC.
11. A revisão verificou que o teste 032 inspeciona tenant, authority, provider, privilégio e ausência de material secreto, normalizando whitespace.
12. A revisão verificou que o fluxo de callback não retorna credenciais ao navegador e redireciona para o shell da aplicação.
13. A revisão verificou que o retry de sync preserva o mesmo requestNonce depois de erro ambíguo.
14. A revisão verificou que a produção não foi alterada por esta etapa.
15. Não foi identificado novo bloqueador técnico na revisão estática do SHA exato.
16. O GitHub Actions check run foi confirmado:
   - workflow: CI;
   - job: validate;
   - run id: 33945965750;
   - job id: 101251988844;
   - head SHA: 05bc516df3479b0ab338efe0ad991877d80812dd;
   - conclusão: success.
17. As etapas verdes confirmadas foram:
   - Checkout;
   - Setup Node;
   - Install dependencies;
   - Test Integrity Gate;
   - Typecheck;
   - Build;
   - Production same-origin web shell gate;
   - Test.
18. O endpoint agregado de commit status não tinha statuses tradicionais publicados, mas o check run do GitHub Actions estava concluído com SUCCESS; os dois fatos foram preservados separadamente.
19. A validação Railway anterior permanece vinculada ao SHA exato e confirmou:
   - target_db=growth_os_test;
   - migration 014 presente;
   - TEST-032 PASS;
   - MIGRATIONS REAPPLIED: NO;
   - production untouched.
20. Não há integração Claude disponível nesta sessão para executar a revisão adversarial formal.
21. Portanto, o PR #29 não foi aprovado para merge nesta etapa.
22. O merge e o deploy de produção continuam pendentes.
23. Próxima ação obrigatória: enviar o SHA exato 05bc516df3479b0ab338efe0ad991877d80812dd ao Claude para revisão adversarial; qualquer novo commit invalida as provas específicas do SHA atual e exige repetição dos gates.

**Resultado desta execução:** revisão independente concluída; nenhum novo bloqueador encontrado; gate Claude pendente; produção intocada.


---

## 15. Diagnóstico registrado: o que falta para finalizar o projeto

**Data:** 05 de setembro de 2026  
**Fontes verificadas:** Issue #26, FULL_PRODUCT_ROADMAP.md, PR #29 e estado Railway/GitHub registrado neste documento.

### 15.1 Fechamento do PR #29

Ainda falta:

1. Revisão adversarial formal do Claude no SHA exato 05bc516df3479b0ab338efe0ad991877d80812dd.
2. Se houver achados do Claude, implementar as correções e repetir CI/validação no novo SHA.
3. Sair de draft somente depois dos gates exigidos.
4. Fazer merge do PR #29.
5. Fazer deploy controlado do merge na Railway canônica.
6. Repetir o Production Truth Gate no SHA efetivamente implantado.

O CI #93 e a validação isolada da migration 014 já estão verdes, mas não substituem a revisão Claude nem a prova de produção.

### 15.2 Conclusão do Issue #26

O Issue #26 só estará concluído quando a cadeia abaixo for comprovada com dados reais:

provider data -> normalized observations -> factual signal -> insight/evidence -> ranked opportunity -> Opportunity Radar

Ainda falta:

1. Confirmar no Google Auth Platform a origem e o callback canônicos do cliente Growth OS Web.
2. Resolver o primeiro acesso por signup/provisionamento seguro no banco canônico.
3. Criar ou selecionar workspace real.
4. Garantir managed_account com authority_status=contractually_granted.
5. Executar autorização YouTube real.
6. Confirmar callback, state, expiração, proteção contra replay, criptografia e persistência da credencial.
7. Executar o primeiro sync real.
8. Confirmar metric_observations reais com provenance, semantic version, source range, freshness e idempotência.
9. Provar retry/crash safety, rate limit, erro do provedor e dado incompleto/atrasado.
10. Gerar pelo menos um sinal determinístico e baseado em evidência, sem transformar correlação em causalidade.
11. Criar insight com estado epistemológico explícito: confirmed account, account hypothesis, general practice ou insufficient signal.
12. Criar oportunidade ranqueada somente se a evidência permitir.
13. Confirmar a apresentação no API/web.
14. Se os dados não forem suficientes, provar o empty/no-op verdadeiro em vez de inventar resultado.
15. Executar o Production Truth Gate completo: URL pública -> SHA implantado -> usuário autenticado -> workspace -> provedor real -> observações -> sinal/evidência -> Radar.
16. Registrar todas as provas no GitHub.
17. Remover o ambiente secundário grateful-courage e URLs OAuth secundárias quando não forem mais necessários.

### 15.3 Finalização do produto Growth OS inteiro

O PR #29 e o Issue #26 representam apenas o primeiro vertical slice de inteligência com YouTube. O produto inteiro ainda exige as fases do roadmap:

1. Controle do programa: contratos de arquitetura/API/eventos, política de segredos/dados, release, rollback, backup, disaster recovery e rastreabilidade requisito-teste-freeze.
2. Identity, tenancy e acesso: signup, signin, signout, sessão, workspaces, convites, RBAC, troca de workspace, onboarding, recuperação de conta, controles de segurança e auditoria.
3. Application shell/design system: navegação, telas de autenticação/onboarding, administração de equipe, estados de loading/empty/error/recovery, acessibilidade e cobertura de navegador.
4. Conectores: além do YouTube, Instagram/Meta, TikTok e X conforme acesso, quotas, regras, revisão, histórico, webhooks/polling e limites reais dos provedores.
5. Content Operations: Content Intelligence, Content Authoring, AI Content Studio, Creative Production, biblioteca de assets, lineage, revisão, aprovação, versionamento, calendário e campanhas.
6. Publishing/orchestration: agendamento, publicação idempotente, validação por provedor, filas, retries, dead-letter, cancelamento, reconciliação, falhas parciais, status e notificações.
7. Data/analytics: ingestão de métricas, normalização, provenance, atribuição, experimentos, dashboards, relatórios, exports, OGI, freshness e anomalias.
8. Intelligence Platform: Growth Brain, Opportunity Radar completo, Global Trend Migration, Competitor Intelligence, Viral DNA, recomendações explicáveis, feedback/evaluation datasets, abstração de modelos, custos e segurança.
9. Experiments/multiplication: hipóteses, variantes, originalidade, MULTIPLY, lineage, adaptação entre canais, medição, promoção de vencedores e arquivamento de perdedores.
10. Copilot/Autopilot/operations: Copilot baseado em evidências, execução com aprovação, políticas de Autopilot, limites, emergency stop, command center, alertas, incidentes, runbooks, workers e custos.
11. Comercial/enterprise: planos, assinaturas, billing, entitlements, usage metering, limites, agências multi-cliente, administração enterprise, compliance, consentimento, retenção, exclusão, suporte e conformidade com políticas dos provedores.
12. Hardening/launch: testes end-to-end e cross-browser, carga, resiliência, segurança, observabilidade, SLOs, alertas, backup/restore drill, revisão de privacidade/segurança, pilotos com contas reais e freeze final.

### 15.4 Conclusão de status

O deploy SUCCESS da Railway não significa que o produto inteiro está pronto. Neste momento:

- fundamento do conector YouTube: implementado e validado;
- PR #29: tecnicamente validado no candidato, mas ainda sem Claude/merge/deploy final;
- Issue #26: em andamento;
- primeiro Production Truth Gate real: não concluído;
- produto completo: não concluído;
- fases posteriores do roadmap: não executadas ou apenas parciais.

Este diagnóstico não autoriza merge ou deploy. Ele serve para impedir que um slice validado seja confundido com a finalização do Growth OS.


---

## 16. Correção registrada: identidade do benchmark “Doxa”

**Data:** 05 de setembro de 2026

1. Foi solicitado o link do concorrente Doxa citado anteriormente como benchmark do Growth OS.
2. A verificação pública não confirmou um site oficial de uma plataforma de crescimento orgânico chamada Doxa.
3. O domínio https://doxa.com/ encontrado na pesquisa é de uma empresa de seguros e não deve ser tratado como concorrente do Growth OS.
4. Foi encontrado o perfil relacionado https://www.instagram.com/doxascale/, associado à mensagem “future of organic growth”, mas o acesso público ao perfil redirecionou para login e não permitiu confirmar toda a plataforma.
5. Até confirmação adicional por fonte primária, Doxa/DoxaScale deve ser classificada como benchmark não verificado, e não como concorrente oficialmente confirmado.
6. A lista de concorrentes confirmados deve continuar separando:
   - social media management: Sprout Social, Hootsuite, Metricool, Later e Buffer;
   - social listening/inteligência: Brandwatch, Meltwater, Sprinklr e Emplifi;
   - growth/market intelligence: Semrush, Rival IQ, Exploding Topics e TrendIntel;
   - referências verticais/adjacentes: Kalodata e Cruva.
7. Esta correção não altera código, banco ou produção; altera apenas a precisão do registro de concorrentes.


---

## 17. Correção definitiva: Doxa não pertence ao Growth OS

**Data:** 05 de setembro de 2026

1. O usuário corrigiu que Doxa não tem relação com o projeto Growth OS.
2. A referência anterior a Doxa como concorrente, benchmark ou plataforma-alvo foi incorreta.
3. Doxa e DoxaScale devem ser removidas da lista de concorrentes, benchmarks, referências e comparativos do Growth OS.
4. O domínio doxa.com não deve ser usado para analisar o projeto.
5. O perfil doxa/doxascale também não deve ser tratado como referência do Growth OS.
6. Nenhum novo concorrente deve ser atribuído ao projeto sem confirmação explícita ou fonte primária adequada.
7. A busca no repositório canônico dbdanielbaracho/GROWTH-OS não encontrou referências atuais a Doxa no código, issues ou arquivos pesquisados.
8. Esta correção substitui qualquer registro anterior que tenha classificado Doxa/DoxaScale como concorrente ou benchmark do Growth OS.
9. O registro de concorrentes do Growth OS fica pendente de revisão correta; não há substituição automática por outro nome nesta etapa.
10. Esta alteração é documental e não altera código, banco ou produção.


---

## 18. Correção final: concorrente correto identificado como Doxa Viral

**Data:** 05 de setembro de 2026

1. O usuário forneceu o endereço correto da plataforma concorrente:
   https://www.doxaviral.com/
2. O concorrente/referência correta é Doxa Viral.
3. O domínio doxa.com continua descartado por ser uma empresa não relacionada ao projeto.
4. DoxaScale também não deve ser usado como identificação do concorrente.
5. A classificação anterior que removeu Doxa por completo foi corrigida: a referência válida é Doxa Viral.
6. A análise competitiva do Growth OS deve considerar Doxa Viral como referência/concorrente, usando o site correto.
7. Esta atualização não altera código, banco ou produção; corrige somente a identidade do concorrente no registro operacional.


---

## 19. Matriz de concorrentes criada

**Data:** 05 de setembro de 2026

1. Foi criada a matriz versionada docs/COMPETITOR_MATRIX.md.
2. A matriz separa Growth OS de Creator Commerce OS.
3. Doxa Viral foi registrado como concorrente direto/benchmark principal do Growth OS conforme link fornecido pelo usuário.
4. Sprout Social, Hootsuite, Metricool, Later, Buffer, Brandwatch, Meltwater, Sprinklr, Emplifi, Semrush, Rival IQ, Exploding Topics e TrendIntel foram classificados como concorrentes adjacentes ou referências de categorias diferentes.
5. Kalodata, FastMoss, Cruva e Euka foram registrados como concorrentes principais do Creator Commerce OS, que é um produto independente.
6. Reacher, Colaba, EchoTik, Shoplus, TikWatch e PiPiADS foram registrados como benchmarks adjacentes/secundários do Creator Commerce OS.
7. Nenhum código, banco ou produção foi alterado.


---

## 20. Matriz competitiva criada

**Data:** 05 de setembro de 2026

1. Foi criada docs/COMPETITIVE_GAP_MATRIX.md.
2. A matriz compara o Growth OS com Doxa Viral e concorrentes adjacentes por capacidade.
3. Foi adotada escala de ☆ a ★★★★★, com definição explícita para evitar confundir intenção com produto comprovado.
4. As notas do Growth OS foram baseadas no estado real do GitHub/Railway.
5. As notas dos concorrentes foram marcadas como benchmark preliminar, sujeitas a auditoria funcional completa.
6. A matriz também mantém separada a lista de concorrentes do Creator Commerce OS.
7. Nenhum código, banco ou produção foi alterado.


## 23. Implementação do baseline visual editorial

**Data:** 05 de setembro de 2026

1. O usuário decidiu continuar o desenvolvimento do Growth OS usando a direção visual editorial inspirada nos princípios do Doxa Viral, sem copiar marca, textos ou interface.
2. Foi criada a branch `feat/growth-os-editorial-ui-v0-1` a partir do SHA técnico `05bc516df3479b0ab338efe0ad991877d80812dd`.
3. Foi aberto o PR #39: `feat: apply editorial visual baseline to Growth OS shell`.
4. A alteração aplica ao shell web um baseline de alto contraste, fundo grafite/preto, tipografia editorial, acento dourado de oportunidade, hierarquia reforçada, superfícies orientadas a evidência e estados verdadeiros.
5. A alteração está concentrada no estilo visual; não altera API, banco, lógica de provedor, dados de produção ou deploy.
6. O PR #39 permanece draft e requer CI, revisão responsiva/acessibilidade, comparação competitiva, revisão independente e Claude antes de merge/freeze.
7. O SHA inicial do PR #39 é `a923f7981169c3c2bd8baf15a8d52bb74acf91ea`.
8. A direção visual anterior do assistente não foi reutilizada como baseline; o baseline adotado é o conceito editorial aprovado pelo usuário nesta conversa.
9. Próximo passo: confirmar CI do SHA exato, inspecionar o build real em desktop/mobile e registrar achados/correções sem alterar produção.


## 24. Validação do baseline visual e estado do SHA final

**Data:** 05 de setembro de 2026

1. O CI run #117 terminou SUCCESS para o SHA de código visual `a923f7981169c3c2bd8baf15a8d52bb74acf91ea`.
2. Depois do run #117, foi adicionada a memória operacional ao branch e um marcador neutro de validação exata no stylesheet, produzindo o SHA atual `c44f3e4395c030c0ce684297f64e59d91c10981b`.
3. O GitHub não publicou novo workflow para o SHA `c44f3e4395c030c0ce684297f64e59d91c10981b` durante esta execução; portanto, o run #117 não é tratado como prova do SHA atual.
4. A prova válida registrada é: código visual do baseline passou no run #117; o SHA final do branch ainda requer CI específico antes de qualquer merge.
5. PR #39 continua aberto e draft. Nenhum merge ou deploy foi executado.
6. Produção permaneceu intocada.
7. Próximo gate: obter CI do SHA atual, fazer inspeção visual real em desktop/mobile, registrar achados de acessibilidade/responsividade e enviar o SHA final para revisão adversarial do Claude.


## 25. Evolução executada: Radar editorial orientado por sinais

**Data:** 05 de setembro de 2026

### 25.1 Objetivo

Continuar a implementação do baseline visual escolhido pelo usuário, convertendo o shell do Opportunity Radar em uma experiência de produto mais editorial e orientada por sinais, sem inventar dados e sem alterar produção.

### 25.2 Alterações realizadas

1. O arquivo `apps/web/src/main.tsx` foi atualizado no branch `feat/growth-os-editorial-ui-v0-1`.
2. A seção inicial do Radar foi substituída por uma composição editorial com:
   - rótulo `Signal feed · this week`;
   - promessa centrada em detectar movimento inicial;
   - explicação explícita de que oportunidades dependem de observações armazenadas;
   - link de navegação para o feed de oportunidades;
   - aviso `Evidence first · no synthetic signals`;
   - leitura do primeiro sinal real disponível no workspace;
   - fallback factual `Waiting for a real signal` quando não houver oportunidade;
   - contagem real de confiança e evidências quando existir oportunidade.
3. O feed recebeu o identificador `radar-feed` para permitir navegação direta a partir do hero.
4. O arquivo `apps/web/src/styles.css` recebeu o bloco `Editorial signal stage v0.1`.
5. O bloco visual adiciona:
   - composição orbital decorativa;
   - leitura textual do sinal primário;
   - CTA textual com affordance de navegação;
   - contraste e hierarquia editorial;
   - adaptação para largura intermediária;
   - composição empilhada em telas estreitas.
6. Nenhuma chamada de API, regra de tenant, persistência, migration, credencial, provider, banco ou configuração de produção foi alterada.

### 25.3 Evidência dos commits

- Commit da composição editorial em `main.tsx`: `0710bebc8f98b5da28dabe83a51ef34124e81527`.
- Commit do CSS responsivo do signal stage: `50de62a6cc72316c54542c2b453019ef8edb900f`.
- SHA atual do branch antes desta atualização documental: `50de62a6cc72316c54542c2b453019ef8edb900f`.
- Ainda não existe CI publicado para esse SHA exato nesta execução; nenhuma prova anterior de outro SHA será reutilizada como se fosse prova do atual.
- PR #39 continua OPEN e DRAFT.
- Nenhum merge foi executado.
- Nenhum deploy foi executado.
- Produção permaneceu intocada.

### 25.4 Critérios ainda obrigatórios

1. CI para o SHA exato após o commit documental ou após o próximo head estável.
2. Inspeção visual real em desktop e mobile.
3. Verificação de foco, contraste, navegação por teclado, estados loading/empty/error e comportamento sem dados.
4. Verificação de que o painel YouTube e demais superfícies do shell não quebram a coerência visual.
5. Revisão competitiva baseada em critérios documentados, sem tratar intenção como capacidade comprovada.
6. Revisão adversarial formal do Claude.
7. Somente depois dos gates: decisão de sair de draft, merge e eventual deploy controlado.

**Resultado desta execução:** evolução visual aplicada ao produto e registrada na memória oficial; PR #39 ainda não está aprovado para merge; produção intocada.


## 26. Correção preventiva de compilação após a evolução visual

**Data:** 05 de setembro de 2026

1. Depois da mudança do hero, a métrica antiga `evidenceTotal` deixou de ser renderizada.
2. A variável e a importação `useMemo` que existia apenas para essa métrica foram removidas de `apps/web/src/main.tsx`.
3. A correção evita variável/importação sem uso no TypeScript e não altera a lógica de carregamento, seleção, tenant, evidência ou API.
4. Commit da correção: `e4ee5ae4f881142e863c01ec323724f03012acf5`.
5. O head do PR #39 passou a ser `e4ee5ae4f881142e863c01ec323724f03012acf5` antes desta atualização documental.
6. O CI do SHA exato ainda precisa ser confirmado; nenhuma execução de SHA anterior é considerada prova deste head.
7. PR #39 permanece OPEN e DRAFT; não houve merge, deploy ou alteração de produção.

**Resultado:** correção preventiva aplicada e registrada; próximo gate continua sendo CI/inspeção visual/revisão adversarial no SHA exato.


## 27. Coerência visual do painel de integração YouTube

**Data:** 05 de setembro de 2026

1. A revisão da superfície visual identificou que `apps/web/src/youtube-integration.css` ainda usava o tema claro legado, enquanto o shell do Radar já usava o baseline editorial grafite/preto.
2. O arquivo recebeu o bloco `Editorial integration surface v0.1`.
3. O painel foi alinhado ao shell com:
   - fundo escuro e bordas grafite;
   - tipografia e texto compatíveis com o contraste editorial;
   - estados de sucesso, erro, vazio e sync com cores semânticas preservadas;
   - botão primário dourado coerente com a ação de oportunidade;
   - bordas menos arredondadas e superfícies mais editoriais;
   - comportamento mobile existente preservado.
4. A lógica de OAuth, sincronização, estados de provedor, autorização, dados, API e segurança não foi alterada.
5. Commit: `32859fabf0d8814f87c83fc84e9bc9d535bba6d5`.
6. O head do PR #39 passou a ser `32859fabf0d8814f87c83fc84e9bc9d535bba6d5` antes desta atualização documental.
7. Não há CI publicado para o SHA exato nesta execução; nenhuma prova anterior foi reutilizada.
8. PR #39 continua OPEN e DRAFT.
9. Nenhum merge ou deploy foi executado.
10. Produção permaneceu intocada.

**Resultado:** integração visual coerente com o shell; ainda pendentes CI do SHA exato, inspeção real, revisão de acessibilidade e revisão adversarial do Claude.


## 28. Acessibilidade: foco de teclado no baseline editorial

**Data:** 05 de setembro de 2026

1. Foi adicionado um baseline global de `:focus-visible` em `apps/web/src/styles.css`.
2. Links, botões, inputs, selects e textareas agora recebem contorno visível em dourado editorial com espaçamento suficiente contra a superfície escura.
3. O CTA textual do hero recebe espaçamento de foco específico para não confundir o sublinhado de navegação com o estado de foco.
4. A mudança não altera dados, API, autenticação, regras de tenant ou produção.
5. Commit: `334092e85f6076700c2288a968f1abaa9b830f3e`.
6. O head do PR #39 passou a ser `334092e85f6076700c2288a968f1abaa9b830f3e` antes desta atualização documental.
7. CI do SHA exato, inspeção em navegador e revisão adversarial do Claude continuam pendentes.
8. PR #39 continua OPEN e DRAFT; nenhum merge ou deploy foi executado; produção intocada.

**Resultado:** requisito básico de navegação por teclado registrado e aplicado; gates externos continuam obrigatórios.


## 29. Gate de consistência do head visual atual

**Data:** 05 de setembro de 2026

1. Foram buscados novamente no GitHub os arquivos finais do branch `feat/growth-os-editorial-ui-v0-1`.
2. `apps/web/src/main.tsx` confirmou:
   - hero com `Signal feed · this week`;
   - âncora `radar-feed`;
   - fallback `Waiting for a real signal`;
   - ausência de `evidenceTotal`;
   - ausência de `useMemo` após a remoção da métrica obsoleta.
3. `apps/web/src/styles.css` confirmou o bloco `Keyboard focus baseline v0.1`.
4. `apps/web/src/youtube-integration.css` confirmou o bloco `Editorial integration surface v0.1`.
5. SHAs de blob verificados:
   - `main.tsx`: `c33fb7b5302c9eda16c7ef7f1a0040b7a947d25a`;
   - `styles.css`: `b03cfdbaa0664c83a67152f13c2aab427914c38f`;
   - `youtube-integration.css`: `4ce0f901309008dc28f8c6cb5de444cef9d8d0c6`.
6. O head do PR #39 confirmado antes desta atualização documental foi `57d0d31ff0d3004be2fa156ba1cf122f5d4b023a`.
7. O PR #39 continua OPEN, DRAFT e não mergeado.
8. Não há review, thread ou comentário registrado no PR #39 nesta verificação.
9. Não há workflow run publicado para o SHA exato `57d0d31ff0d3004be2fa156ba1cf122f5d4b023a`.
10. O CI #117 do SHA anterior não é reutilizado como prova do head atual.
11. Nenhum deploy foi executado e a produção permaneceu intocada.
12. A revisão adversarial formal do Claude continua sendo um bloqueio externo obrigatório; sem ela, não há autorização para sair de draft, fazer merge ou fazer deploy.

**Resultado:** consistência estrutural e documental verificada; gates externos permanecem corretamente abertos.


## 30. Production Truth Gate parcial: superfície pública canônica

**Data:** 05 de setembro de 2026

1. O ambiente consultado foi exclusivamente o canônico: Railway `successful-embrace`, serviço `growth-os`, domínio `https://growth-os-production-d120.up.railway.app`.
2. `GET /health/ready` retornou HTTP 200 com:
   `{"status":"ready","database":"ok"}`.
3. `GET /` retornou HTTP 200 e entregou o shell HTML do Growth OS.
4. `GET /v1/system` retornou HTTP 200 com:
   `{"name":"Growth OS","version":"0.1.0","environment":"production"}`.
5. Esses checks confirmam disponibilidade pública, serving do shell, identificação do serviço e conectividade do banco no healthcheck.
6. Esses checks não comprovam autenticação, workspace, OAuth YouTube, sync real, observação, sinal, insight, oportunidade ou Radar com dados reais.
7. Não foi feito deploy, alteração de variável, migration ou mudança no banco nesta etapa.
8. Produção permaneceu somente em leitura.
9. O próximo gate é provar signup/signin/sessão/workspace no banco canônico e, depois, autorização e sync real do YouTube.

**Resultado:** superfície pública canônica saudável; Production Truth Gate completo ainda pendente.


## 31. Production Truth Gate parcial: proteção dos endpoints autenticados

**Data:** 05 de setembro de 2026

1. Sem sessão autenticada, `GET /v1/auth/session` retornou HTTP 401 `{"status":"unauthorized"}`.
2. Sem sessão autenticada, `GET /v1/opportunities` retornou HTTP 401 `{"status":"unauthorized"}`.
3. Sem sessão autenticada, `GET /v1/integrations/youtube/status` retornou HTTP 401 `{"status":"unauthorized"}`.
4. Isso confirma que os endpoints de sessão protegida, Opportunity Radar e status do YouTube não expõem dados sem autenticação.
5. Esses checks são apenas negativos/unauthenticated; não comprovam que um usuário válido consiga entrar, selecionar workspace ou acessar dados autorizados.
6. Não houve tentativa de signup, criação de usuário, migration, alteração de banco, alteração de variável ou deploy.
7. O próximo passo operacional depende de provisionamento/autorização segura de uma conta de teste no banco canônico; nenhuma conta ou credencial foi inventada.

**Resultado:** proteção sem sessão confirmada; autenticação positiva e jornada completa ainda pendentes.


## 32. Implementação do Growth Intelligence Engine determinístico

**Data:** 05 de setembro de 2026

### 32.1 Banco e contrato

1. Foi criada a migration forward-only `db/migrations/015_youtube_growth_intelligence.sql`.
2. Foi criada a tabela `growth.factual_signals`.
3. A tabela registra:
   - workspace e conta social;
   - tipo de sinal;
   - métrica;
   - estado;
   - observações de origem;
   - valor atual;
   - baseline;
   - delta;
   - tamanho da amostra;
   - confiança;
   - versão da lógica;
   - janela de origem;
   - expiração.
4. `growth.insights` recebeu `source_signal_id`.
5. `growth.opportunities` recebeu `source_signal_id`.
6. As relações garantem que insight e oportunidade possam ser rastreados até o sinal factual.
7. A função `growth.recompute_youtube_growth_intelligence(uuid)` foi criada como:
   - `SECURITY DEFINER`;
   - proprietária de `growth_migrator`;
   - sem EXECUTE para `PUBLIC`;
   - executável por `app_runtime`;
   - validada por contexto de tenant.
8. `growth.factual_signals` usa RLS e FORCE RLS.
9. `app_runtime` não recebe INSERT direto em `factual_signals`, `insights` ou `opportunities`.

### 32.2 Regra determinística

1. O engine considera somente observações YouTube da métrica `views`.
2. Exige conta YouTube conectada.
3. Exige `authority_status=contractually_granted`.
4. Exige `authorization_class=authorized_account`.
5. Exige `completeness_status=complete`.
6. Exige `freshness_status=fresh`.
7. Exige no mínimo três observações.
8. Calcula a média das observações anteriores e compara com a observação mais recente.
9. Só cria sinal quando o valor mais recente está pelo menos 25% acima da média anterior.
10. Se a amostra for insuficiente ou o delta não atingir o limiar, retorna `insufficient_signal` e não cria oportunidade.
11. A confiança é determinística e inclui o método e `causal_claim=false`.
12. O score da oportunidade é determinístico, limitado entre 0 e 100, e não é apresentado como causalidade ou previsão garantida.

### 32.3 Evidência e idempotência

1. O sinal guarda os IDs das observações usadas.
2. O insight recebe evidências `metric_observation:<id>` da classe `owned`.
3. A oportunidade recebe as mesmas referências de evidência.
4. A chave natural usa workspace, conta, tipo de sinal, métrica, fim da janela e versão da lógica.
5. Reprocessar o mesmo período atualiza o mesmo sinal, insight e oportunidade.
6. Foi criado o teste `apps/api/integration-tests/growth-intelligence.integration.mts`.
7. O teste cria três observações determinísticas, executa o helper duas vezes pelo caminho de runtime e comprova:
   - oportunidade criada;
   - IDs estáveis entre execuções;
   - uma única linha de sinal;
   - uma única linha de insight;
   - uma única linha de oportunidade.
8. Foi criado o gate SQL `db/tests/033_youtube_growth_intelligence.sql`.

### 32.4 Integração com o sync e interface

1. `apps/api/src/youtube-connector.ts` chama o engine depois de persistir as observações do sync.
2. O retorno do sync agora informa:
   - `intelligenceStatus`;
   - `signalId`;
   - `insightId`;
   - `opportunityId`;
   - quantidade de observações usadas;
   - delta determinístico.
3. `apps/web/src/api.ts` tipa o novo contrato.
4. `apps/web/src/youtube-integration.tsx` informa se o Opportunity Radar foi atualizado ou se ainda não há amostra suficiente.
5. Após sync concluído, a interface dispara `growth-os:radar-refresh`.
6. `apps/web/src/main.tsx` escuta o evento e recarrega o Radar sem exigir refresh manual da página.
7. O fallback de ausência de evidência permanece explícito.

### 32.5 Evidências dos commits

- Migration 015: `de338973bd111f52188a1351fa3e8c0d03fd85a8`.
- Gate SQL 033: `6f0a7035c25a3b662db3dcbd7ca970093d39e8e8`.
- Engine no sync: `b19101b3baa93b9019bba47dc0507e416869b555`.
- Contrato web do sync: `3ab68f5262644d71e1cc60eaf17830187e22daae`.
- Refresh do Radar e feedback do sync: `16fe22d11e17944f0c78ac4a2a11159ee4390b19`, `62339414651a989b0e19b7f2d7b94c96ca623760`.
- CSS do resultado do engine: `84c8c950f40cc68bb0f6f89747c7a6b9a47ced8b`.
- Documento técnico: `ca32cb0d4ff00a44fbfa61ae45bcd94a59a2cc08`.
- Teste de integração corrigido: `46e7ac651747938d4fe494aaf786b703c9cce9c0`.
- Head do branch antes desta atualização documental: `46e7ac651747938d4fe494aaf786b703c9cce9c0`.

### 32.6 Estado e limites

1. Nenhuma migration 015 foi aplicada na produção.
2. Nenhum provider real foi chamado nesta execução.
3. Nenhuma oportunidade sintética foi criada.
4. Nenhum deploy foi executado.
5. Produção permaneceu intocada.
6. CI e validação Railway do SHA exato ainda são necessários.
7. O Production Truth Gate real continua dependendo de conta autorizada, OAuth YouTube e sync real.
8. Claude ainda deve revisar adversarialmente este bloco antes de merge/freeze/deploy.

**Resultado:** a cadeia implementável `observação -> sinal factual -> insight/evidence -> oportunidade -> Radar` foi codificada para YouTube, com no-op e idempotência; a prova física exata ainda está pendente.


## 33. Correção do teste de integração e validação isolada interrompida

**Data:** 05 de setembro de 2026

### 33.1 Correção aplicada

1. A primeira versão do teste de integração do Growth Intelligence Engine fazia a leitura final das contagens usando `app_runtime`.
2. Isso estava incorreto por desenho de segurança: `app_runtime` pode executar a função SECURITY DEFINER, mas não recebe SELECT direto em `growth.factual_signals`.
3. O teste foi corrigido para:
   - executar a recomputação duas vezes pelo caminho `app_runtime`;
   - confirmar a persistência final usando uma conexão `MIGRATOR_DATABASE_URL`;
   - manter a verificação de idempotência e limpeza dos fixtures.
4. Commit da correção: `7a3283d94e17fb926944579cafaa89691c71e271`.
5. O head atual da PR #39 é exatamente `7a3283d94e17fb926944579cafaa89691c71e271`.
6. O CI retornado pelo GitHub para esse SHA é uma lista vazia; portanto, não há workflow publicado para o head exato e nenhum CI de SHA anterior é reutilizado como prova.

### 33.2 Validação Railway tentada

1. Foi solicitado um validator isolado para o candidato `6a0bc99f31966359b6d1aab6ed0cdb46c0cc3abc`, que era o head imediatamente anterior à correção do teste.
2. O validator executou em Railway no serviço `pr33-sha-6a0bc99-validator-ephemeral`, deployment `660977eb-cbb6-4d4e-a506-cf0b08b02ed1`.
3. O próprio resultado declarou `status=fail`, `target_database=growth_os_test`, `migration_015_applied=false`, `gate_033_result=PENDING` e `production_safe=false`.
4. A falha aconteceu antes da validação SQL: o container não possui o binário `psql` (`/bin/sh: 1: psql: not found`).
5. Essa execução não prova falha da migration 015 nem da lógica do engine; prova apenas que o validator escolhido não tinha a ferramenta de cliente necessária.
6. A tentativa anterior com o Railway Agent para um validator do mesmo escopo terminou em timeout HTTP 504. Depois do timeout, não apareceu novo deploy da aplicação canônica nem mudança na produção.
7. O serviço canônico `growth-os` continua no deployment SUCCESS `23629579-551e-456b-85d1-29b29a53a050`, commit `17ee387477763921c0c4cbab326557142d4b26b3`.
8. O serviço `pr33-sha-6a0bc99-validator-ephemeral` também permanece sem prova válida do código atual, pois validou SHA anterior e falhou no preflight.

### 33.3 Estado de segurança e próximo gate

1. Nenhuma migration 015 foi aplicada na produção.
2. Nenhum dado, variável, credencial ou deployment do serviço canônico foi alterado.
3. A validação correta precisa executar no banco `growth_os_test`, confirmar `current_database()='growth_os_test'`, aplicar o candidato atual `7a3283d94e17fb926944579cafaa89691c71e271`, rodar o gate SQL 033 e o teste de integração, e registrar o resultado completo.
4. O próximo passo é corrigir o executor do validator para usar um cliente PostgreSQL disponível, ou usar um caminho equivalente que não dependa de `psql`, sem tocar em `growth-os`/produção.
5. Claude continua obrigatório para revisão adversarial do SHA final; ainda não há aprovação externa registrada.
6. Não é permitido sair de draft, fazer merge ou fazer deploy antes de CI do SHA atual, validação isolada aprovada, revisão do Claude e Production Truth Gate final.

**Resultado:** a falha foi localizada no ambiente do validator, o teste do produto foi corrigido e a produção continua protegida; a prova física do SHA atual segue pendente.


## 34. Tentativas adicionais de tornar a validação observável

**Data:** 05 de setembro de 2026

1. O head atual da PR #39 foi reconfirmado como `8c6be7c9bdf956b81e2c6a9b64d160c6c121b05c`.
2. A PR #39 continua OPEN, DRAFT e não mergeada; o base SHA continua `17ee387477763921c0c4cbab326557142d4b26b3).
3. O GitHub continua sem workflow publicado para o SHA atual; a lista de runs associada ao SHA é vazia.

### 34.1 Executor Bun

1. O serviço anterior `pr33-sha-6a0bc99-validator-ephemeral` falhou no preflight porque o container não tinha `psql`.
2. O serviço foi atualizado para um script Bun com cliente PostgreSQL, mas seus redeploys continuaram reutilizando snapshot antigo; nenhum resultado do SHA atual foi aceito.
3. Foi criado `pr39-growth-intelligence-validator` com o SHA atual e referências ao banco de teste.
4. A configuração foi confirmada pelo Railway, mas o runtime one-shot não expôs stdout nos logs.
5. A tentativa de transformá-lo em HTTP produziu HTTP 502 `connection refused`; o serviço reiniciou e não forneceu resultado de validação.
6. Um diagnóstico independente do Railway confirmou que esse tipo de wrapper Bun não oferece stdout observável de forma confiável.

### 34.2 Executor PostgreSQL

1. Foi criado `pr39-growth-intelligence-psql-validator` com a imagem `postgres:16-alpine`.
2. O container iniciou o próprio Postgres local por causa do entrypoint da imagem e não executou o comando `psql` contra o banco de validação; portanto, também não é prova.
3. O script SQL completo preparado continha preflight `growth_os_test`, migration 015, gate 033, fixtures autorizados, execução como `app_runtime`, idempotência, contagens e limpeza.
4. Nenhum dado de produção foi usado ou alterado por essa tentativa.

### 34.3 Executor Node isolado

1. Foi criado `pr39-growth-intelligence-node-validator` com a imagem `node:20-alpine`.
2. As variáveis foram referenciadas do serviço de integração existente, mantendo os bancos de teste separados.
3. Deployment: `acd69e2c-2329-4e49-9a24-5277874f7feb`.
4. O start command foi confirmado contendo:
   - download do repositório no SHA `8c6be7c9bdf956b81e2c6a9b64d160c6c121b05c`;
   - instalação das dependências da API;
   - execução de `npx tsx integration-tests/growth-intelligence.integration.mts`.
5. O deployment terminou SUCCESS, mas os logs capturados contêm apenas `Starting Container`; não há `PASS`, `FAIL`, `EXIT` ou resultado JSON do teste.
6. SUCCESS do container não é tratado como SUCCESS do teste. O resultado do teste permanece `UNKNOWN/PENDING`.
7. A execução anterior do serviço `node-integration-tests` mostrou apenas a suíte antiga de confirmação; ela não é reutilizada como prova do SHA atual.

### 34.4 Decisão e proteção

1. Não foi feito merge.
2. Não foi feito deploy do SHA da PR #39.
3. O serviço canônico `growth-os` continua no deployment de produção `23629579-551e-456b-85d1-29b29a53a050`, commit `17ee387477763921c0c4cbab326557142d4b26b3`.
4. A production database continua intocada.
5. A validação física do SHA atual segue pendente porque o Railway não forneceu uma saída observável do teste.
6. O próximo caminho seguro é executar o teste em um executor já conhecido por publicar logs de runtime, ou registrar o resultado em um canal persistente de teste e lê-lo sem expor segredos.
7. Depois da validação, ainda são obrigatórios: CI do SHA atual, revisão adversarial do Claude, confirmação de credenciais OAuth reais, Production Truth Gate completo e somente então merge/deploy controlado.

**Resultado:** todos os bloqueios e tentativas foram registrados; nenhum resultado não observado foi promovido a aprovação.
