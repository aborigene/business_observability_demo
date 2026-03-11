# Tier 1 - Loan Authorization Service (Node.js)

## Responsabilidades

1. **Validação de Entrada**: Valida todos os campos obrigatórios e tipos de dados
2. **Autorização**: Bloqueia solicitações de regiões e canais não autorizados
3. **Correlação**: Gera ou propaga W3C TraceContext para rastreamento distribuído
4. **Roteamento**: Encaminha solicitações válidas para o Tier 2 (Análise de Crédito)

## Endpoints

### POST /loan/applications
Cria uma nova solicitação de empréstimo.

**Request Body:**
```json
{
  "customerId": "CUST-12345",
  "requestedAmount": 50000,
  "termMonths": 36,
  "product": "personal_loan",
  "channel": "mobile",
  "region": "BR-SP",
  "segment": "premium",
  "costCenter": "CC-RETAIL-001",
  "team": "lending-team-alpha"
}
```

**Response (Success - 201):**
```json
{
  "applicationId": "uuid-generated",
  "status": "processing",
  "data": { ... },
  "processingTimeMs": 150
}
```

**Response (Validation Error - 400):**
```json
{
  "error": "Validation failed",
  "details": ["Missing required field: customerId"]
}
```

**Response (Authorization Declined - 200):**
```json
{
  "status": "unauthorized",
  "message": "Loan application not authorized",
  "reason": "Region 'Sanctioned' is not authorized for loan applications",
  "applicationId": "uuid-generated",
  "details": {
    "customerId": "CUST-12345",
    "region": "Sanctioned",
    "channel": "Mobile",
    "requestedAmount": 50000
  }
}
```

### GET /loan/applications/:id
Recupera detalhes de uma solicitação (placeholder).

### GET /health
Health check endpoint.

## Configuração

### Variáveis de Ambiente

| Variável | Descrição | Padrão |
|----------|-----------|---------|
| `PORT` | Porta do servidor | 3000 |
| `TIER2_URL` | URL do serviço Tier 2 | http://tier2-service:8080 |
| `UNAUTHORIZED_REGIONS` | Regiões bloqueadas (CSV) | "" |
| `UNAUTHORIZED_CHANNELS` | Canais bloqueados (CSV) | "" |
| `ENVIRONMENT` | Ambiente (dev/demo/prod) | demo |
| `LOG_LEVEL` | Nível de log | info |

## Regras de Autorização

### Regiões Não Autorizadas
Configurado via `UNAUTHORIZED_REGIONS`. Exemplo:
```bash
UNAUTHORIZED_REGIONS=Sanctioned,Restricted
```
Qualquer solicitação dessas regiões será rejeitada com status 200 e motivo na resposta.

### Canais Não Autorizados
Configurado via `UNAUTHORIZED_CHANNELS`. Exemplo:
```bash
UNAUTHORIZED_CHANNELS=External,Public
```
Qualquer solicitação desses canais será rejeitada com status 200 e motivo na resposta.

## Observabilidade

### Atributos de Negócio (Logs)
Todos os logs incluem atributos para Business Observability:
- `applicationId`: ID único da solicitação
- `customerId`: ID do cliente
- `requestedAmount`: Valor solicitado
- `product`: Tipo de produto
- `channel`: Canal de origem
- `region`: Região
- `segment`: Segmento do cliente
- `costCenter`: Centro de custo
- `team`: Time responsável
- `environment`: Ambiente
- `traceparent`: Tracing context W3C

### Propagação de Trace Context
O serviço propaga ou gera headers W3C TraceContext:
- `traceparent`: version-traceId-spanId-flags
- `tracestate`: vendor-specific trace state

## Build e Deployment

### Local Development
```bash
# Instalar dependências
npm install

# Copiar configuração
cp .env.example .env

# Editar .env conforme necessário
nano .env

# Rodar em modo desenvolvimento
npm run dev

# Rodar em produção
npm start
```

### Docker Build
```bash
docker build -t loan-authorization-service:1.0 .
docker run -p 3000:3000 \
  -e TIER2_URL=http://tier2:8080 \
  -e UNAUTHORIZED_REGIONS=BR-XX \
  loan-authorization-service:1.0
```

### Kubernetes Deployment
Ver manifests em `/k8s/tier1/`

## Testes

```bash
# Teste válido
curl -X POST http://localhost:3000/loan/applications \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "CUST-001",
    "requestedAmount": 25000,
    "termMonths": 24,
    "product": "personal_loan",
    "channel": "mobile",
    "region": "BR-SP",
    "segment": "premium",
    "costCenter": "CC-RETAIL-001",
    "team": "lending-team-alpha"
  }'

# Teste com região não autorizada
curl -X POST http://localhost:3000/loan/applications \
  -H "Content-Type: application/json" \
  -d '{
    "customerId": "CUST-002",
    "requestedAmount": 15000,
    "termMonths": 12,
    "product": "personal_loan",
    "channel": "mobile",
    "region": "BR-XX",
    "segment": "standard",
    "costCenter": "CC-RETAIL-002",
    "team": "lending-team-beta"
  }'
```

## Dynatrace Instrumentation

Este serviço roda no Kubernetes com Dynatrace OneAgent instalado via Dynatrace Operator.

O OneAgent automaticamente:
- Captura todas as transações HTTP
- Propaga trace context
- Coleta métricas de performance
- Indexa logs estruturados

Para visualizar no Dynatrace:
1. Services → loan-authorization-service
2. Distributed traces → filtrar por applicationId
3. Logs → filtrar por costCenter ou team
