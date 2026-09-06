# Instagram Connector Lifecycle v0.1

**Status:** implementação candidata, aguardando CI e revisão adversarial.  
**Branch:** \`feat/growth-os-instagram-lifecycle-v1\`  
**Data:** 06 de setembro de 2026

## Objetivo

Completar o ciclo seguro da fundação Instagram aprovada na PR #41:

- renovar token long-lived sem expor credencial ao \`app_runtime\`;
- reconectar uma conta revogada/desconectada sem criar duplicidade;
- revogar localmente a conexão, removendo a credencial cifrada;
- manter publicação e insights em \`kill_switch=true\` até validação própria.

## Contrato implementado

### Refresh

O adaptador chama o endpoint oficial da Meta:

\`GET https://graph.instagram.com/refresh_access_token?grant_type=ig_refresh_token&access_token=...\`

A resposta precisa conter \`access_token\` e \`expires_in\`. O novo token é cifrado novamente com AES-256-GCM e o mesmo AAD vinculado a \`workspaceId + connectionId\`. O segredo nunca é retornado pela API nem armazenado em \`localStorage\`.

Endpoint:

\`POST /v1/integrations/instagram/:connectionId/refresh\`

### Reconexão

\`POST /v1/integrations/instagram/reconnect\` reutiliza a conexão mais recente nos estados \`revoked\`, \`disconnected\`, \`reauth_required\` ou \`failed\`. A callback aceita a mesma conta social quando ela pertence à mesma conexão e atualiza a projeção existente; uma conta já vinculada a outro workspace/conexão continua sendo rejeitada.

### Revogação local

\`POST /v1/integrations/instagram/:connectionId/revoke\`:

1. valida o tenant e a autoridade no banco;
2. remove a linha de \`provider_credentials\`;
3. marca \`platform_connections.state='revoked'\`;
4. limpa escopos e expiração;
5. preserva a linha histórica de \`social_accounts\`, permitindo reconexão sem apagar a linhagem de dados.

## Limites explícitos

- A revogação local remove o segredo do Growth OS; não é apresentada como prova de revogação remota na Meta.
- A migration 018 ainda precisa ser aplicada e validada no banco de produção.
- Credenciais Meta reais ainda não estão configuradas no Railway.
- Nenhuma publicação, insight ou sincronização Instagram foi habilitada por este bloco.

## Segurança e gates

A migration \`018_instagram_token_lifecycle.sql\` substitui apenas os helpers existentes de início/completação para suportar reconexão e adiciona \`instagram_revoke_connection(uuid)\`. Todos permanecem:

- \`SECURITY DEFINER\`;
- propriedade de \`growth_migrator\`;
- executáveis por \`app_runtime\`;
- não executáveis por \`PUBLIC\`;
- sem acesso direto de \`app_runtime\` a \`provider_credentials\` ou \`platform_connections\`.

O gate SQL \`036_instagram_token_lifecycle.sql\` verifica esses limites. O teste unitário verifica o endpoint de refresh e confirma que o client secret não é incluído na URL.

## Evidência de fornecedor

A documentação oficial da Meta descreve o refresh de um long-lived access token pelo endpoint \`refresh_access_token\`, com validade renovada de 60 dias quando as condições do provedor são atendidas:

- https://developers.facebook.com/documentation/instagram-platform/reference/refresh_access_token
- https://developers.facebook.com/documentation/instagram-platform/reference/access_token

A implementação não presume que um token expirado possa ser recuperado: falha de refresh continua exigindo reconexão.

## Critério de aceite deste bloco

Só será considerado validado após:

1. CI do SHA exato com migration 018, gates 033–036, typecheck, build e testes;
2. revisão adversarial do Claude no mesmo SHA;
3. merge/deploy somente depois de \`APPROVE\`;
4. aplicação comprovada da migration 018 em produção;
5. atualização da memória e do roadmap com todos os resultados, inclusive falhas.
