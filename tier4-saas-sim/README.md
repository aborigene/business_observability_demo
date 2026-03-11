# Tier 4 - Loan Decision Service (SaaS Simulator)

## Responsabilidades

1. **Cálculo de Score Final**: `finalScore = tier2Score + tier3Score`
2. **Decisão de Empréstimo**: Baseada em thresholds configuráveis
   - `APPROVED`: finalScore >= APPROVAL_THRESHOLD
   - `REJECTED`: finalScore <= REJECTION_THRESHOLD
   - `PARTIALLY_APPROVED`: entre os thresholds
3. **Business Events**: Publica evento de decisão no Dynatrace via API
4. **Roteamento**: Encaminha para Tier 5 (Cálculo Final e Persistência)

## Conceito: SaaS Externo (Sem OneAgent)

Este tier simula um **serviço SaaS externo** que:
- ❌ **NÃO** tem Dynatrace OneAgent instalado
- ❌ **NÃO** participa de distributed tracing automático
- ✅ **Publica** eventos de negócio via API do Dynatrace
- ✅ **Correlaciona** eventos com traces via `dt.trace_id`
- ✅ Representa um serviço de terceiros ou decisão de crédito externa

### Por Que Sem OneAgent?
Demonstra cenários onde:
- Serviço gerenciado por terceiros (não há controle sobre infraestrutura)
- SaaS vendor que não permite instalação de agentes
- Decisão de negócio externa (bureau de crédito, scoring engine)
- Necessidade de observabilidade via eventos de negócio apenas

## Endpoints

### POST /internal/decision/evaluate
Avalia a decisão final de empréstimo.

**Headers:**
- `traceparent`: W3C Trace Context (usado para correlação de Business Event)
- `tracestate`: W3C Trace State (opcional)
- `x-application-id`: ID da aplicação

**Request Body:**
```json
{
  "applicationId": "uuid",
  "customerId": "CUST-12345",
  "requestedAmount": 50000,
  "termMonths": 36,
  "product": "personal_loan",
  "channel": "mobile",
  "region": "BR-SP",
  "segment": "premium",
  "costCenter": "CC-RETAIL-001",
  "team": "lending-team-alpha",
  "tier2Score": 65,
  "tier3Score": 25,
  ...
}
```

**Regras de Decisão:**
```
finalScore = tier2Score + tier3Score

Se finalScore >= 60 (APPROVAL_THRESHOLD):
  → decisionStatus = APPROVED

Se finalScore <= 40 (REJECTION_THRESHOLD):
  → decisionStatus = REJECTED

Se 40 < finalScore < 60:
  → decisionStatus = PARTIALLY_APPROVED
```

**Response (200):**
```json
{
  "applicationId": "uuid",
  "tier2Score": 65,
  "tier3Score": 25,
  "finalScore": 90,
  "decisionStatus": "APPROVED",
  "decisionReason": "Final score 90 meets approval threshold of 60",
  ...
}
```

### GET /health
Health check endpoint.

## Business Events (Dynatrace)

### O Que São Business Events?
Business Events permitem que **qualquer aplicação** (mesmo sem OneAgent) envie eventos de negócio para o Dynatrace via API. Estes eventos:
- São indexados e pesquisáveis
- Podem ser correlacionados com traces via `dt.trace_id`
- Habilitam análises de negócio e cost allocation
- Aparecem na UI de Business Analytics

### Evento Publicado
Tipo: `com.loan.decision.made`

**Atributos do Evento:**
```json
{
  "event.type": "com.loan.decision.made",
  "event.provider": "loan-decision-service",
  "timestamp": "2024-01-01T10:00:00Z",
  
  "loan.applicationId": "uuid",
  "loan.customerId": "CUST-001",
  "loan.requestedAmount": 50000,
  "loan.approvedAmount": 0,
  "loan.termMonths": 36,
  
  "loan.tier2Score": 65,
  "loan.tier3Score": 25,
  "loan.finalScore": 90,
  
  "loan.decisionStatus": "APPROVED",
  "loan.decisionReason": "Final score 90 meets approval threshold",
  
  "loan.product": "personal_loan",
  "loan.segment": "premium",
  "loan.channel": "mobile",
  "loan.region": "BR-SP",
  "loan.costCenter": "CC-RETAIL-001",
  "loan.team": "lending-team-alpha",
  "loan.environment": "demo",
  
  "dt.trace_id": "4bf92f3577b34da6a3ce929d0e0e4736"
}
```

### API Endpoint
```
POST {DT_ENV_URL}/api/v2/bizevents/ingest
Authorization: Api-Token {DT_API_TOKEN}
Content-Type: application/json
```

### Permissões do Token
O `DT_API_TOKEN` precisa da permissão:
- ✅ **Ingest events** (`events.ingest`)

## Configuração

### Variáveis de Ambiente

| Variável | Descrição | Padrão |
|----------|-----------|---------|
| `PORT` | Porta do servidor | 8001 |
| `TIER5_URL` | URL do Tier 5 | http://tier5-service:5000 |
| `APPROVAL_THRESHOLD` | Score mínimo para aprovação | 60 |
| `REJECTION_THRESHOLD` | Score máximo para rejeição | 40 |
| `DT_ENV_URL` | URL do tenant Dynatrace | - |
| `DT_API_TOKEN` | Token com permissão de ingestão | - |
| `ENVIRONMENT` | Ambiente (dev/demo/prod) | demo |

### Configurar Dynatrace

1. **Obter URL do Tenant:**
   - Exemplo: `https://abc12345.live.dynatrace.com`

2. **Criar API Token:**
   - Settings → Access tokens → Generate new token
   - Nome: `bizevents-ingest-token`
   - Permissão: ✅ **Ingest events**
   - Copiar o token

3. **Configurar no Deployment:**
   ```bash
   export DT_ENV_URL=https://abc12345.live.dynatrace.com
   export DT_API_TOKEN=dt0c01.XXXXXXXXXX
   ```

## Build e Deployment

### Local Development
```bash
# Instalar dependências
pip install -r requirements.txt

# Copiar e configurar environment
cp .env.example .env
nano .env  # Editar DT_ENV_URL e DT_API_TOKEN

# Rodar
python -m uvicorn app.main:app --reload --port 8001
```

### Docker Build
```bash
docker build -t loan-decision-service:1.0 .

docker run -p 8001:8001 \
  -e TIER5_URL=http://tier5:5000 \
  -e APPROVAL_THRESHOLD=60 \
  -e REJECTION_THRESHOLD=40 \
  -e DT_ENV_URL=https://xxx.live.dynatrace.com \
  -e DT_API_TOKEN=dt0c01.XXXXX \
  loan-decision-service:1.0
```

### Kubernetes Deployment
Ver manifests em `/k8s/tier4/`

**IMPORTANTE**: Use Kubernetes Secrets para `DT_API_TOKEN`:
```bash
kubectl create secret generic dt-credentials \
  --from-literal=api-token=dt0c01.XXXXXXXXXX
```

## Visualização no Dynatrace

### 1. Business Events
- **Business Analytics** → **Explore Business Events**
- Filtrar por `event.type = com.loan.decision.made`
- Visualizar atributos de negócio

### 2. Análises Customizadas
Criar dashboards e queries:

**Decisões por Status:**
```dql
bizevents
| filter event.type == "com.loan.decision.made"
| summarize count(), by: loan.decisionStatus
```

**Scores Médios por Região:**
```dql
bizevents
| filter event.type == "com.loan.decision.made"
| summarize avg(loan.finalScore), by: loan.region
```

**Volume por Cost Center:**
```dql
bizevents
| filter event.type == "com.loan.decision.made"
| summarize count(), sum(loan.requestedAmount), by: loan.costCenter
```

### 3. Correlação com Traces
Se `dt.trace_id` está presente:
- Business Event aparece correlacionado com o PurePath
- Clicar no evento mostra o trace completo end-to-end
- Ver fluxo: Tier1 → Tier2 → Tier3 → [Business Event] → Tier5

### 4. Cost Allocation
Usar atributos de negócio para alocação de custos:
- `loan.costCenter`: Centro de custo responsável
- `loan.team`: Time que processou
- `loan.region`: Região geográfica
- `loan.segment`: Segmento de cliente

## Testes

### Teste de Aprovação (Score >= 60)
```bash
curl -X POST http://localhost:8001/internal/decision/evaluate \
  -H "Content-Type: application/json" \
  -H "traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01" \
  -d '{
    "applicationId": "test-approval",
    "customerId": "CUST-001",
    "requestedAmount": 50000,
    "termMonths": 36,
    "product": "personal_loan",
    "channel": "mobile",
    "region": "BR-SP",
    "segment": "premium",
    "costCenter": "CC-RETAIL-001",
    "team": "lending-team-alpha",
    "environment": "demo",
    "tier2Score": 65,
    "tier3Score": 25,
    "createdAt": "2024-01-01T10:00:00Z",
    "updatedAt": "2024-01-01T10:00:00Z"
  }'

# Resultado esperado:
# finalScore = 90 (65 + 25)
# decisionStatus = APPROVED (90 >= 60)
```

### Teste de Rejeição (Score <= 40)
```bash
curl -X POST http://localhost:8001/internal/decision/evaluate \
  -H "Content-Type: application/json" \
  -d '{
    "applicationId": "test-rejection",
    "customerId": "CUST-002",
    "requestedAmount": 5000,
    "termMonths": 12,
    "product": "personal_loan",
    "channel": "app",
    "region": "BR-RJ",
    "segment": "standard",
    "costCenter": "CC-RETAIL-002",
    "team": "lending-team-beta",
    "environment": "demo",
    "tier2Score": 25,
    "tier3Score": 0,
    "createdAt": "2024-01-01T10:00:00Z",
    "updatedAt": "2024-01-01T10:00:00Z"
  }'

# Resultado esperado:
# finalScore = 25 (25 + 0)
# decisionStatus = REJECTED (25 <= 40)
```

### Teste de Aprovação Parcial (40 < Score < 60)
```bash
curl -X POST http://localhost:8001/internal/decision/evaluate \
  -H "Content-Type: application/json" \
  -d '{
    "applicationId": "test-partial",
    "customerId": "CUST-003",
    "requestedAmount": 20000,
    "termMonths": 24,
    "product": "personal_loan",
    "channel": "branch",
    "region": "BR-MG",
    "segment": "standard",
    "costCenter": "CC-RETAIL-001",
    "team": "lending-team-alpha",
    "environment": "demo",
    "tier2Score": 45,
    "tier3Score": 5,
    "createdAt": "2024-01-01T10:00:00Z",
    "updatedAt": "2024-01-01T10:00:00Z"
  }'

# Resultado esperado:
# finalScore = 50 (45 + 5)
# decisionStatus = PARTIALLY_APPROVED (40 < 50 < 60)
```

### Verificar Business Events no Dynatrace
1. Aguardar ~1-2 minutos para ingestão
2. **Business Analytics** → **Explore Business Events**
3. Filtrar: `event.type = com.loan.decision.made`
4. Buscar por `loan.applicationId = test-approval`

## Troubleshooting

### Business Events não aparecem
```bash
# Verificar configuração
echo $DT_ENV_URL
echo $DT_API_TOKEN  # Deve começar com dt0c01.

# Verificar logs do aplicativo
# Procurar por "✅ Business Event sent successfully"
# Ou "❌ Failed to send Business Event"

# Testar API manualmente
curl -X POST ${DT_ENV_URL}/api/v2/bizevents/ingest \
  -H "Authorization: Api-Token ${DT_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{
    "eventType": "bizevents",
    "events": [{
      "event.type": "test.event",
      "test.field": "test-value"
    }]
  }'

# Resposta esperada: 202 Accepted
```

### Permissões do Token
Verificar que o token tem a permissão:
- Settings → Access tokens → [Seu Token]
- ✅ **Ingest events** (`events.ingest`)

## Demonstração

### Ponto-Chave da Demo
Este tier demonstra como:
1. **Serviços externos/SaaS** podem enviar eventos de negócio para Dynatrace
2. **Correlação** de eventos com traces distribuídos (sem OneAgent)
3. **Business Analytics** e segmentação por dimensões de negócio
4. **Cost Allocation** via atributos customizados (costCenter, team)
5. **Decisões configuráveis** via thresholds (APPROVAL_THRESHOLD, REJECTION_THRESHOLD)

### Roteiro de Demo
1. Mostrar código do envio do Business Event
2. Fazer uma solicitação de empréstimo end-to-end
3. Ver o trace distribuído (Tier1 → Tier2 → Tier3 → **[gap]** → Tier5)
4. Ver o Business Event no Dynatrace correlacionado com o trace
5. Criar dashboard com métricas de decisão por costCenter/team
6. Demonstrar queries de Business Analytics

