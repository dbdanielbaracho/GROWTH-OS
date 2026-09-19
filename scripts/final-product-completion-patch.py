from pathlib import Path


def replace_once(path: str, old: str, new: str) -> None:
    file = Path(path)
    text = file.read_text()
    if old not in text:
        raise SystemExit(f"anchor not found in {path}: {old[:100]!r}")
    file.write_text(text.replace(old, new, 1))


# API composition: import, validate, and expose evidence-grounded Copilot.
replace_once(
    "apps/api/src/app.ts",
    'import { listMetricAnalyticsSummary, listMetricQualityAnomalies } from "./analytics.js";\n',
    'import { listMetricAnalyticsSummary, listMetricQualityAnomalies } from "./analytics.js";\nimport { queryCopilot } from "./copilot.js";\n'
)
replace_once(
    "apps/api/src/app.ts",
    'const AnalyticsQuerySchema = z.object({\n  from: z.string().trim().optional(),\n  to: z.string().trim().optional()\n});\n',
    'const AnalyticsQuerySchema = z.object({\n  from: z.string().trim().optional(),\n  to: z.string().trim().optional()\n});\n\nconst CopilotQuerySchema = z.object({\n  message: z.string().trim().min(1).max(1000)\n});\n'
)
replace_once(
    "apps/api/src/app.ts",
    '  app.get("/v1/recommendations", async (request, reply) => {\n',
    '''  app.post("/v1/copilot/query", async (request, reply) => {\n    const principal = await requestPrincipal(request, reply);\n    if (!principal) return;\n\n    const parsed = CopilotQuerySchema.safeParse(request.body);\n    if (!parsed.success) return reply.code(400).send({ status: "invalid_request" });\n\n    try {\n      const copilot = await withTenantTransaction(principal, (client) =>\n        queryCopilot(client, principal, parsed.data.message)\n      );\n      return { status: "ok", reply: copilot };\n    } catch (error) {\n      app.log.error(error);\n      const mapped = databaseStatus(error);\n      return reply.code(mapped.code).send({ status: mapped.status });\n    }\n  });\n\n  app.get("/v1/recommendations", async (request, reply) => {\n'''
)

# Web API client: typed Copilot contract. Appending keeps the private request helper centralized.
api_path = Path("apps/web/src/api.ts")
api_text = api_path.read_text()
if "export type CopilotReply" not in api_text:
    api_text += '''\n\nexport type CopilotCitation = {\n  kind: "opportunity" | "insight" | "evidence" | "metric" | "recommendation" | "experiment" | "automation";\n  ref: string;\n  label: string;\n};\n\nexport type CopilotReply = {\n  mode: "evidence_grounded";\n  intent: "summary" | "metrics" | "evidence" | "actions" | "experiments" | "operations";\n  answer: string;\n  citations: CopilotCitation[];\n  workspace_pulse: {\n    opportunities: number;\n    insights: number;\n    metric_rows: number;\n    quality_alerts: number;\n    experiments: number;\n    automation_needs_attention: number;\n    automation_kill_switch: boolean;\n  };\n  suggested_prompts: string[];\n  limitations: string[];\n};\n\nexport async function queryCopilot(message: string): Promise<CopilotReply> {\n  const response = await requestJson<{ status: "ok"; reply: CopilotReply }>("/v1/copilot/query", {\n    method: "POST",\n    body: { message }\n  });\n  return response.reply;\n}\n'''
    api_path.write_text(api_text)

# Analytics UI must load the anomaly rows that it already renders.
replace_once(
    "apps/web/src/analytics-panel.tsx",
    '''      const metrics = await fetchMetricAnalyticsSummary();\n      if (generation !== authGeneration.current) return;\n      setRows(metrics);\n      setMessage(null);\n''',
    '''      const [metrics, qualityAlerts] = await Promise.all([\n        fetchMetricAnalyticsSummary(),\n        fetchMetricQualityAnomalies()\n      ]);\n      if (generation !== authGeneration.current) return;\n      setRows(metrics);\n      setAnomalies(qualityAlerts);\n      setMessage(null);\n'''
)
replace_once(
    "apps/web/src/analytics-panel.tsx",
    '''        setAuthenticated(false);\n        setRows([]);\n''',
    '''        setAuthenticated(false);\n        setRows([]);\n        setAnomalies([]);\n'''
)

# Mount the Copilot as a product-level panel.
replace_once(
    "apps/web/index.html",
    '    <div id="analytics-panel-root"></div>\n',
    '    <div id="analytics-panel-root"></div>\n    <div id="copilot-panel-root"></div>\n'
)
replace_once(
    "apps/web/index.html",
    '    <script type="module" src="/src/analytics-panel.tsx"></script>\n',
    '    <script type="module" src="/src/analytics-panel.tsx"></script>\n    <script type="module" src="/src/copilot-panel.tsx"></script>\n'
)

# Record the current user instruction and this implementation pass in the central execution memory.
memory = Path("docs/PROJECT_EXECUTION_MEMORY.md")
entry = '''\n\n## Continuação — fechamento de todas as pendências internas — 2026-09-19\n\n**Pedido exato do usuário:** "verificar todos as pendencias e resolver tudo ir até o final e resolver. temos que completar tudo"\n\n**Ponto de partida verificado:** `main` em `cf4bd898c32588ff4518fa742e5bf4a6d90e499c` após merge documental do PR #202; runtime de aplicação aceito continua `6289685a572a2dbfa0840d20311d2e3674c1605e` até um novo runtime-affecting merge/deploy. Railway canônico permanecia SUCCESS no app, migrator e publication worker. A única issue aberta era #26.\n\n**Auditoria desta continuação:**\n- confirmou que Analytics já possuía export JSON/freshness/completeness backend, mas a UI importava `fetchMetricQualityAnomalies` sem executá-la; alerta de qualidade podia ficar invisível;\n- confirmou que Experiments já possui UI/API para criar plano, variantes e registrar winner/loser/inconclusive com `evidence_ref`;\n- confirmou que Autopilot possui aprovação separada de execução e execução auditável do PR #199;\n- confirmou que o requisito de Copilot conversacional existia apenas no roadmap e não no código;\n- abriu a branch `feat/final-product-completion` para fechar lacunas internas em conjunto, sem TinyFish.\n\n**Implementação em andamento:**\n- serviço `apps/api/src/copilot.ts`: Copilot determinístico, evidence-grounded e fail-closed, limitado ao workspace e sem executar publicação;\n- testes unitários para classificação de intent, ausência de evidência e preservação das barreiras de aprovação;\n- painel web de Copilot com workspace pulse, referências de evidência e limites explícitos;\n- rota autenticada `/v1/copilot/query`;\n- correção do Analytics para carregar e exibir alertas de qualidade realmente retornados pelo backend.\n\n**Limites externos que continuam fora de qualquer atalho de código:** OAuth humano Google/YouTube para a prova real pós-PR #200 e autorização explícita do usuário para qualquer publicação pública concreta. Esses gates não podem ser declarados concluídos sem a prova real.\n'''
text = memory.read_text()
if "## Continuação — fechamento de todas as pendências internas — 2026-09-19" not in text:
    memory.write_text(text + entry)
