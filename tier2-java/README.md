# Tier 2 - Loan Credit Analysis Service (Java Spring Boot)

## Responsabilidades

1. **Análise de Crédito Inicial**: Gera um score de crédito (tier2Score) no intervalo [0-70]
2. **Propagação de Contexto**: Mantém e propaga W3C TraceContext
3. **Roteamento**: Encaminha para Tier 3 (Análise de Risco Avançada)
4. **Logging de Negócio**: Registra atributos de negócio estruturados

## Endpoints

### POST /internal/credit/analyze
Realiza análise de crédito inicial.

**Headers:**
- `traceparent`: W3C Trace Context (obrigatório para correlação)
- `tracestate`: W3C Trace State (opcional)
- `x-application-id`: ID da aplicação (para logging)

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
  "environment": "demo",
  "createdAt": "2024-01-01T10:00:00Z",
  "updatedAt": "2024-01-01T10:00:00Z"
}
```

**Response (200):**
```json
{
  "applicationId": "uuid",
  "customerId": "CUST-12345",
  "tier2Score": 65,
  "tier3Score": 25,
  ...
}
```

### GET /internal/credit/health
Health check endpoint.

### GET /actuator/health
Spring Boot Actuator health endpoint (detalhado).

## Configuração

### Variáveis de Ambiente

| Variável | Descrição | Padrão |
|----------|-----------|---------|
| `SERVER_PORT` | Porta do servidor | 8080 |
| `TIER3_URL` | URL do serviço Tier 3 | http://tier3-service:8000 |
| `LOGGING_LEVEL_ROOT` | Nível de log | INFO |

### application.properties
Ver `src/main/resources/application.properties` para configurações.

## Regra de Negócio

### Geração de tier2Score
- Gera um número aleatório no intervalo **[0, 70]**
- Score representa análise de crédito inicial
- Não considera valor solicitado (análise rápida)

### Propagação
- Recebe `traceparent` e `tracestate` do Tier 1
- Propaga para Tier 3 via HTTP headers
- Adiciona atributos de negócio nos logs

## Build e Deployment

### Build Local
```bash
# Com Maven
mvn clean package

# Rodar localmente
java -jar target/loan-credit-analysis-1.0.0.jar

# Ou via Maven
mvn spring-boot:run
```

### Docker Build
```bash
docker build -t loan-credit-analysis:1.0 .

docker run -p 8080:8080 \
  -e TIER3_URL=http://tier3:8000 \
  loan-credit-analysis:1.0
```

### Kubernetes Deployment
Ver manifests em `/k8s/tier2/`

## Observabilidade

### Logs Estruturados (JSON)
Usando Logstash Logback Encoder para logs estruturados:
```json
{
  "timestamp": "2024-01-01T10:00:00.000Z",
  "level": "INFO",
  "service": "tier2-credit-analysis",
  "tier": "tier2",
  "message": "Credit analysis completed",
  "applicationId": "uuid",
  "customerId": "CUST-001",
  "tier2Score": 65,
  "costCenter": "CC-RETAIL-001",
  "team": "lending-team-alpha",
  "traceparent": "00-...",
  "latencyMs": 150
}
```

### Atributos de Negócio
Todos os logs incluem:
- `applicationId`
- `customerId`
- `requestedAmount`
- `channel`
- `region`
- `segment`
- `costCenter`
- `team`
- `environment`
- `tier2Score`

### Métricas (Spring Boot Actuator)
Endpoint `/actuator/metrics` expõe:
- JVM metrics
- HTTP request metrics
- Custom business metrics

## Dynatrace Instrumentation

Este serviço roda no Kubernetes com Dynatrace OneAgent instalado via Dynatrace Operator.

**Recursos Automáticos:**
- Captura de todas as transações HTTP (entrada/saída)
- Propagação automática de PurePath
- Coleta de métricas de performance (response time, throughput, errors)
- Indexação de logs estruturados JSON
- Code-level visibility (métodos, SQL statements)

**Para Visualizar no Dynatrace:**
1. **Services** → `loan-credit-analysis`
2. **Distributed Traces** → Filtrar por `applicationId` ou `costCenter`
3. **Service Flow** → Ver chamada Tier1 → Tier2 → Tier3
4. **Logs** → Filtrar por `tier:tier2` e business attributes

## Testes

```bash
# Teste local
curl -X POST http://localhost:8080/internal/credit/analyze \
  -H "Content-Type: application/json" \
  -H "traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01" \
  -d '{
    "applicationId": "test-uuid-001",
    "customerId": "CUST-001",
    "requestedAmount": 25000,
    "termMonths": 24,
    "product": "personal_loan",
    "channel": "mobile",
    "region": "BR-SP",
    "segment": "premium",
    "costCenter": "CC-RETAIL-001",
    "team": "lending-team-alpha",
    "environment": "demo",
    "createdAt": "2024-01-01T10:00:00Z",
    "updatedAt": "2024-01-01T10:00:00Z"
  }'

# Health check
curl http://localhost:8080/internal/credit/health
curl http://localhost:8080/actuator/health
```

## Dependências

- **Spring Boot 3.2**: Framework
- **Spring WebFlux**: Cliente HTTP reativo
- **Logstash Logback Encoder**: Logs JSON estruturados
- **Lombok**: Redução de boilerplate
- **Spring Boot Actuator**: Health checks e métricas

