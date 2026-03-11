# Tier 5 - Loan Finalizer Service (.NET 8)

## Responsabilidades

1. **Cálculo de Valor Aprovado**: Baseado no status de decisão e score final
2. **Cálculo de Juros**: Aplica taxa base + prêmio de risco baseado no score
3. **Persistência**: Salva todas as informações no PostgreSQL
4. **API de Consulta**: Endpoints para recuperar aplicações por filtros

## Arquitetura

- **Framework**: ASP.NET Core 8.0 (Minimal API)
- **Database**: PostgreSQL com Entity Framework Core
- **Deployment**: EC2 com Dynatrace OneAgent (Full Stack)
- **Monitoring**: Código instrumentado automaticamente pelo OneAgent

## Endpoints

### POST /internal/loan/finalize
Finaliza o empréstimo com cálculos e persistência.

**Headers:**
- `traceparent`: W3C Trace Context
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
  "environment": "demo",
  "tier2Score": 65,
  "tier3Score": 25,
  "finalScore": 90,
  "decisionStatus": "APPROVED",
  "decisionReason": "Final score 90 meets approval threshold",
  "createdAt": "2024-01-01T10:00:00Z",
  "updatedAt": "2024-01-01T10:00:00Z"
}
```

**Response (200):**
```json
{
  "success": true,
  "applicationId": "uuid",
  "decisionStatus": "APPROVED",
  "approvedAmount": 50000,
  "totalDue": 56400,
  "decisionReason": "Final score 90 meets approval threshold",
  "processingTimeMs": 125.5
}
```

### GET /internal/loan/{applicationId}
Recupera uma aplicação específica.

### GET /internal/loan
Lista aplicações com filtros opcionais.

**Query Parameters:**
- `costCenter`: Filtrar por centro de custo
- `team`: Filtrar por time
- `decisionStatus`: Filtrar por status (APPROVED, REJECTED, PARTIALLY_APPROVED)

**Example:**
```bash
GET /internal/loan?costCenter=CC-RETAIL-001&decisionStatus=APPROVED
```

### GET /health
Health check endpoint.

## Regras de Negócio

### 1. Cálculo de Approved Amount

#### APPROVED
```
approvedAmount = requestedAmount
```

#### REJECTED
```
approvedAmount = 0
```

#### PARTIALLY_APPROVED
```
reduction = 100 - finalScore
approvedAmount = requestedAmount - reduction
approvedAmount = max(0, approvedAmount)
```

**Exemplos:**
- finalScore = 90 → reduction = 10 → approvedAmount = requestedAmount - 10
- finalScore = 50 → reduction = 50 → approvedAmount = requestedAmount - 50
- finalScore = 20 → reduction = 80 → approvedAmount = max(0, requestedAmount - 80)

### 2. Cálculo de Total Due (Juros)

#### Quando approvedAmount = 0
```
totalDue = 0
```

#### Quando approvedAmount > 0
```
baseRate = 0.02 (configurável via appsettings ou env var)
riskPremium = (100 - finalScore) / 1000
interestRate = baseRate + riskPremium
totalDue = approvedAmount * (1 + interestRate * termMonths)
```

**Exemplos:**

**Score Alto (90):**
```
riskPremium = (100 - 90) / 1000 = 0.010 (1%)
interestRate = 0.02 + 0.010 = 0.030 (3% ao mês)
totalDue = 50000 * (1 + 0.030 * 36) = 50000 * 2.08 = R$ 104.000
```

**Score Médio (50):**
```
riskPremium = (100 - 50) / 1000 = 0.050 (5%)
interestRate = 0.02 + 0.050 = 0.070 (7% ao mês)
totalDue = 50000 * (1 + 0.070 * 36) = 50000 * 3.52 = R$ 176.000
```

**Score Baixo (20):**
```
riskPremium = (100 - 20) / 1000 = 0.080 (8%)
interestRate = 0.02 + 0.080 = 0.100 (10% ao mês)
totalDue = 50000 * (1 + 0.100 * 36) = 50000 * 4.6 = R$ 230.000
```

## Database Schema

### Tabela: loan_applications

| Column | Type | Description |
|--------|------|-------------|
| id | SERIAL PRIMARY KEY | Auto-increment ID |
| application_id | VARCHAR(100) UNIQUE NOT NULL | UUID da aplicação |
| customer_id | VARCHAR(100) NOT NULL | ID do cliente |
| requested_amount | DOUBLE PRECISION NOT NULL | Valor solicitado |
| term_months | INTEGER NOT NULL | Prazo em meses |
| product | VARCHAR(100) NOT NULL | Tipo de produto |
| channel | VARCHAR(50) NOT NULL | Canal |
| region | VARCHAR(50) NOT NULL | Região |
| segment | VARCHAR(50) NOT NULL | Segmento |
| cost_center | VARCHAR(100) NOT NULL | Centro de custo |
| team | VARCHAR(100) NOT NULL | Time responsável |
| environment | VARCHAR(50) NOT NULL | Ambiente |
| created_at | TIMESTAMP NOT NULL | Data de criação |
| updated_at | TIMESTAMP NOT NULL | Data de atualização |
| tier2_score | INTEGER | Score Tier 2 (0-70) |
| tier3_score | INTEGER | Score Tier 3 (0-30) |
| final_score | INTEGER | Score final |
| decision_status | VARCHAR(50) | Status da decisão |
| approved_amount | DOUBLE PRECISION | Valor aprovado |
| total_due | DOUBLE PRECISION | Valor total devido |
| decision_reason | VARCHAR(500) | Motivo da decisão |

**Indexes:**
- `application_id` (UNIQUE)
- `customer_id`
- `cost_center`
- `team`
- `decision_status`
- `created_at`

## Configuração

### Variáveis de Ambiente

| Variável | Descrição | Padrão |
|----------|-----------|---------|
| `ASPNETCORE_URLS` | URLs do servidor | http://+:5000 |
| `ASPNETCORE_ENVIRONMENT` | Ambiente .NET | Production |
| `DATABASE_URL` | Connection string PostgreSQL | - |
| `Loan__BaseRate` | Taxa base mensal | 0.02 |

### Connection String (PostgreSQL)
```
Host=<RDS_ENDPOINT>;Port=5432;Database=loandb;Username=loanuser;Password=<PASSWORD>
```

### appsettings.json
```json
{
  "ConnectionStrings": {
    "DefaultConnection": "Host=localhost;Port=5432;Database=loandb;..."
  },
  "Loan": {
    "BaseRate": 0.02
  }
}
```

## Build e Deployment

### Local Development
```bash
# Restaurar pacotes
dotnet restore

# Rodar migrações
dotnet ef database update

# Rodar aplicação
dotnet run

# Ou com watch (hot reload)
dotnet watch run
```

### Docker Build
```bash
docker build -t loan-finalizer:1.0 .

docker run -p 5000:5000 \
  -e DATABASE_URL="Host=postgres;Port=5432;Database=loandb;..." \
  -e Loan__BaseRate=0.02 \
  loan-finalizer:1.0
```

### EC2 Deployment (Recomendado)
Ver `ec2-userdata.sh` - usado pelo Terraform.

O script user-data:
1. Instala .NET 8 SDK e Runtime
2. Instala Dynatrace OneAgent em modo Full Stack
3. Prepara ambiente e systemd service
4. Cria script de deployment (`deploy-app.sh`)

**Após criação da EC2:**
```bash
# SSH na EC2
ssh ec2-user@<EC2-IP>

# Deploy da aplicação
cd /opt/loan-finalizer
sudo ./deploy-app.sh
```

### Database Migrations
```bash
# Adicionar nova migração
dotnet ef migrations add InitialCreate

# Aplicar migrações
dotnet ef database update

# Ou programaticamente no Program.cs (já implementado):
db.Database.Migrate();
```

## Observabilidade

### Dynatrace OneAgent (Full Stack)
Este tier usa OneAgent em **modo Full Stack** (padrão):
- ✅ **Code-level instrumentation**: Métodos, classes, SQL statements
- ✅ **Distributed tracing**: Propagação automática de PurePath
- ✅ **Database monitoring**: Queries, performance, slow statements
- ✅ **Logs**: Coleta automática de logs estruturados
- ✅ **Métricas de negócio**: Captura de atributos customizados

### Logs Estruturados (JSON)
Logs incluem atributos de negócio:
```json
{
  "timestamp": "2024-01-01T10:00:00Z",
  "level": "Information",
  "message": "Loan finalized and persisted",
  "applicationId": "uuid",
  "customerId": "CUST-001",
  "decisionStatus": "APPROVED",
  "approvedAmount": 50000,
  "totalDue": 56400,
  "costCenter": "CC-RETAIL-001",
  "team": "lending-team-alpha",
  "latencyMs": 125.5,
  "traceparent": "00-..."
}
```

### Visualização no Dynatrace

#### 1. Service Monitoring
- **Services** → `loan-finalizer`
- Ver todas as chamadas de entrada (from Tier 4)
- Ver todas as chamadas de saída (to PostgreSQL)

#### 2. Database Monitoring
- **Databases** → PostgreSQL instance
- Ver queries executadas
- Identificar slow queries
- Ver database connections pool

#### 3. Distributed Traces
- Trace completo end-to-end:
  - Tier 1 (Node.js) → Tier 2 (Java) → Tier 3 (C logs) → [Business Event] → **Tier 5 (.NET)** → PostgreSQL
- Filtrar por `applicationId` ou business attributes

#### 4. Code-Level Visibility
- Ver métodos executados:
  - `LoanCalculationService.CalculateLoanAmounts`
  - `LoanCalculationService.CalculatePartialApproval`
  - `LoanCalculationService.CalculateTotalDue`
  - Entity Framework queries
- Ver parâmetros e valores de retorno

#### 5. Business Analytics
- Criar métricas customizadas:
  - Taxa de aprovação por costCenter
  - Valor médio aprovado por team
  - Taxa de juros média por segment
  - Volume de empréstimos por região

## Testes

### Teste de Aprovação Total
```bash
curl -X POST http://localhost:5000/internal/loan/finalize \
  -H "Content-Type: application/json" \
  -H "traceparent: 00-abc123-def456-01" \
  -d '{
    "applicationId": "test-001",
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
    "finalScore": 90,
    "decisionStatus": "APPROVED",
    "createdAt": "2024-01-01T10:00:00Z",
    "updatedAt": "2024-01-01T10:00:00Z"
  }'

# Expected:
# approvedAmount = 50000
# totalDue ≈ 104000 (com 3% ao mês de juros)
```

### Teste de Aprovação Parcial
```bash
curl -X POST http://localhost:5000/internal/loan/finalize \
  -H "Content-Type: application/json" \
  -d '{
    "applicationId": "test-002",
    "customerId": "CUST-002",
    "requestedAmount": 20000,
    "termMonths": 24,
    "product": "personal_loan",
    "channel": "app",
    "region": "BR-RJ",
    "segment": "standard",
    "costCenter": "CC-RETAIL-002",
    "team": "lending-team-beta",
    "environment": "demo",
    "tier2Score": 45,
    "tier3Score": 5,
    "finalScore": 50,
    "decisionStatus": "PARTIALLY_APPROVED",
    "createdAt": "2024-01-01T10:00:00Z",
    "updatedAt": "2024-01-01T10:00:00Z"
  }'

# Expected:
# approvedAmount = 20000 - (100 - 50) = 19950
# totalDue calculado com 7% ao mês de juros
```

### Teste de Rejeição
```bash
curl -X POST http://localhost:5000/internal/loan/finalize \
  -H "Content-Type: application/json" \
  -d '{
    "applicationId": "test-003",
    "customerId": "CUST-003",
    "requestedAmount": 10000,
    "termMonths": 12,
    "product": "personal_loan",
    "channel": "web",
    "region": "BR-MG",
    "segment": "basic",
    "costCenter": "CC-RETAIL-001",
    "team": "lending-team-alpha",
    "environment": "demo",
    "tier2Score": 20,
    "tier3Score": 5,
    "finalScore": 25,
    "decisionStatus": "REJECTED",
    "createdAt": "2024-01-01T10:00:00Z",
    "updatedAt": "2024-01-01T10:00:00Z"
  }'

# Expected:
# approvedAmount = 0
# totalDue = 0
```

### Consultar Aplicação
```bash
# Por ID
curl http://localhost:5000/internal/loan/test-001

# Listar por cost center
curl http://localhost:5000/internal/loan?costCenter=CC-RETAIL-001

# Listar por status
curl http://localhost:5000/internal/loan?decisionStatus=APPROVED
```

## Troubleshooting

### Aplicação não conecta no banco
```bash
# Verificar connection string
cat /opt/loan-finalizer/app.env | grep DATABASE_URL

# Testar conexão manual
psql "Host=<RDS>;Port=5432;Database=loandb;Username=loanuser"

# Ver logs do aplicativo
journalctl -u loan-finalizer -f

# Ver erros do Entity Framework
journalctl -u loan-finalizer | grep "Microsoft.EntityFrameworkCore"
```

### OneAgent não está instrumentando
```bash
# Verificar OneAgent status
systemctl status oneagent

# Verificar processo do aplicativo
ps aux | grep dotnet

# Verificar se OneAgent está attached
cat /proc/<PID>/maps | grep dynatrace

# Logs do OneAgent
tail -f /var/log/dynatrace/oneagent/oneagent.log
```

### Migrações não aplicadas
```bash
cd /opt/loan-finalizer

# Rodar migrations manualmente
dotnet ef database update --project LoanFinalizer.csproj

# Ou via código (já está no Program.cs)
# db.Database.Migrate();
```

## Demonstração de Valor

Este tier demonstra:
1. **Full-Stack Monitoring**: Código, banco de dados, infraestrutura
2. **Code-Level Visibility**: Métodos C# instrumentados automaticamente
3. **Database Monitoring**: Performance de queries PostgreSQL
4. **Business Attributes**: Correlação de dados de negócio com performance
5. **Cost Allocation**: Análise por costCenter/team com dados reais de DB

