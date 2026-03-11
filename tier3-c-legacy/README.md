# Tier 3 - Advanced Risk Analysis Engine (C Legacy)

## Responsabilidades

1. **Análise de Risco Avançada**: Gera tier3Score [0-30] **SOMENTE quando requestedAmount >= 10000**
2. **Log Estruturado**: Escreve logs JSON em `/var/log/loan-risk-engine/app.log`
3. **Correlação via Logs**: Inclui `traceparent` nos logs para correlação distribuída
4. **Roteamento**: Encaminha para Tier 4 (Decisor Final)

## Arquitetura de Observabilidade (CRÍTICO)

### OneAgent em Modo Infrastructure-Only
Este tier demonstra um caso de aplicação **legacy não instrumentável**:
- **Dynatrace OneAgent** instalado em modo **infra-only** (sem instrumentação de código)
- OneAgent coleta:
  - ✅ Métricas de infraestrutura (CPU, memória, disco, rede)
  - ✅ Processos em execução
  - ✅ **Logs do arquivo de aplicação** (`/var/log/loan-risk-engine/app.log`)
  - ❌ **NÃO** captura traces de código (sem APM)
  - ❌ **NÃO** injeta headers automaticamente

### Por Que Infrastructure-Only?
Simula cenários reais onde:
- Aplicação legacy em C/C++ sem SDK disponível
- Código fonte não modificável ou desconhecido
- Binário compilado sem possibilidade de recompilação
- Estratégia de migração gradual (infraestrutura primeiro, APM depois)

### Correlação via Logs
Como o OneAgent não instrumenta o código:
- O aplicativo **recebe** o header `traceparent` via HTTP
- O aplicativo **loga** o `traceparent` no arquivo JSON
- Dynatrace **indexa** os logs e **correlaciona** via `traceparent`
- Resultado: logs aparecem correlacionados com os traces dos outros tiers

## Endpoints

### POST /internal/risk/advanced
Realiza análise de risco avançada.

**Headers:**
- `traceparent`: W3C Trace Context (para logging de correlação)
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
  ...
}
```

**Regra de Negócio - tier3Score:**
- Se `requestedAmount >= 10000`: gera tier3Score aleatório [0-30]
- Se `requestedAmount < 10000`: tier3Score = 0 (não aplica análise avançada)

**Response (200):**
```json
{
  "applicationId": "uuid",
  "tier2Score": 65,
  "tier3Score": 25,
  ...
}
```

## Build e Deployment

### Build Local
```bash
# Compilar
make clean
make

# Instalar (requer sudo)
sudo make install

# Verificar
ls -l /opt/loan-risk-engine/loan-risk-server
```

### Instalação Manual em EC2
```bash
# Copiar arquivos para EC2
scp -r tier3-c-legacy/ ec2-user@<EC2-IP>:/tmp/

# SSH na EC2
ssh ec2-user@<EC2-IP>

# Executar instalação
cd /tmp/tier3-c-legacy
chmod +x install.sh
sudo ./install.sh
```

### Instalação via User-Data (Recomendado)
Ver `ec2-userdata.sh` - usado pelo Terraform na criação da EC2.

O script user-data:
1. Instala Dynatrace OneAgent em modo infra-only
2. Configura coleta de logs do arquivo `/var/log/loan-risk-engine/app.log`
3. Prepara ambiente para deployment da aplicação

## Configuração

### Variáveis de Ambiente

| Variável | Descrição | Padrão |
|----------|-----------|---------|
| `TIER4_HOST` | Hostname do Tier 4 | tier4-service |
| `TIER4_PORT` | Porta do Tier 4 | 8001 |

Configuradas no systemd service: `/etc/systemd/system/loan-risk-engine.service`

### Systemd Service
```bash
# Status
sudo systemctl status loan-risk-engine

# Logs do serviço
sudo journalctl -u loan-risk-engine -f

# Restart
sudo systemctl restart loan-risk-engine

# Stop/Start
sudo systemctl stop loan-risk-engine
sudo systemctl start loan-risk-engine
```

## Logs

### Formato de Log (JSON)
Arquivo: `/var/log/loan-risk-engine/app.log`

```json
{
  "timestamp": "2024-01-01T10:00:00Z",
  "level": "INFO",
  "service": "tier3-risk-analysis",
  "tier": "tier3",
  "message": "Generated advanced risk score for high-value loan",
  "applicationId": "uuid",
  "customerId": "CUST-001",
  "requestedAmount": 50000,
  "channel": "mobile",
  "region": "BR-SP",
  "costCenter": "CC-RETAIL-001",
  "team": "lending-team-alpha",
  "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
  "tier2Score": 65,
  "tier3Score": 25,
  "latencyMs": 45
}
```

### Visualizar Logs
```bash
# Tail logs da aplicação
tail -f /var/log/loan-risk-engine/app.log

# Filtrar por applicationId
grep "applicationId\":\"<ID>" /var/log/loan-risk-engine/app.log | jq

# Verificar tier3 scores gerados
grep tier3Score /var/log/loan-risk-engine/app.log | jq
```

## Dynatrace Configuration

### OneAgent Installation (Infrastructure-Only)
```bash
# Download e install via user-data
wget -O Dynatrace-OneAgent-Linux.sh \
  --header="Authorization: Api-Token ${DT_PAAS_TOKEN}" \
  "${DT_ENV_URL}/api/v1/deployment/installer/agent/unix/default/latest"

# Install em modo infra-only
sudo /bin/sh Dynatrace-OneAgent-Linux.sh \
  --set-infra-only=true \
  --set-host-property=Tier=tier3 \
  --set-host-property=Environment=demo
```

### Log Collection Configuration
Arquivo: `/var/lib/dynatrace/oneagent/agent/config/loganalytics/loan-risk-engine.json`

```json
{
  "logs": [
    {
      "source": {
        "path": "/var/log/loan-risk-engine/app.log"
      },
      "format": {
        "type": "json"
      },
      "attributes": [
        {
          "key": "service.name",
          "value": "tier3-risk-analysis"
        },
        {
          "key": "tier",
          "value": "tier3"
        }
      ]
    }
  ]
}
```

### Restart OneAgent
```bash
sudo systemctl restart oneagent
```

## Visualização no Dynatrace

### 1. Host Monitoring
- **Hosts** → Filtrar por tag `Tier=tier3`
- Ver métricas de infraestrutura (CPU, memória, disco, rede)
- Ver processo `loan-risk-server`

### 2. Logs
- **Logs** → Filtrar por `service.name="tier3-risk-analysis"`
- Buscar por `applicationId`, `customerId`, `costCenter`, `team`
- Ver correlação com traces via `traceparent`

### 3. Log Events Analysis
- Criar dashboard com:
  - Contagem de tier3Score gerados vs. não gerados
  - Distribuição de valores de tier3Score
  - Latência média por região/costCenter
  - Volume de solicitações por team

### 4. Custom Metrics (via Log Processing)
Criar métricas customizadas a partir dos logs:
- `loan.tier3.score.avg` - Score médio
- `loan.tier3.requests.by_region` - Requests por região
- `loan.tier3.high_value_loans.count` - Empréstimos >= 10k

## Testes

### Teste com Valor Alto (gera tier3Score)
```bash
curl -X POST http://<EC2-IP>:8000/internal/risk/advanced \
  -H "Content-Type: application/json" \
  -H "traceparent: 00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01" \
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
    "tier2Score": 65
  }'
```

### Teste com Valor Baixo (tier3Score = 0)
```bash
curl -X POST http://<EC2-IP>:8000/internal/risk/advanced \
  -H "Content-Type: application/json" \
  -H "traceparent: 00-abc123..." \
  -d '{
    "applicationId": "test-002",
    "customerId": "CUST-002",
    "requestedAmount": 5000,
    "termMonths": 12,
    "product": "personal_loan",
    "channel": "mobile",
    "region": "BR-RJ",
    "segment": "standard",
    "costCenter": "CC-RETAIL-002",
    "team": "lending-team-beta",
    "tier2Score": 55
  }'
```

### Verificar Logs
```bash
# Ver último log
tail -n 1 /var/log/loan-risk-engine/app.log | jq

# Verificar se tier3Score foi gerado corretamente
grep "test-001" /var/log/loan-risk-engine/app.log | jq '.tier3Score'
grep "test-002" /var/log/loan-risk-engine/app.log | jq '.tier3Score'
```

## Troubleshooting

### Aplicação não inicia
```bash
# Verificar se porta 8000 está disponível
sudo netstat -tlnp | grep 8000

# Verificar logs do systemd
sudo journalctl -u loan-risk-engine -n 50

# Verificar permissões do diretório de logs
ls -ld /var/log/loan-risk-engine
```

### Logs não aparecem no Dynatrace
```bash
# Verificar OneAgent status
sudo systemctl status oneagent

# Verificar configuração de log collection
cat /var/lib/dynatrace/oneagent/agent/config/loganalytics/loan-risk-engine.json

# Verificar se arquivo de log existe e tem conteúdo
ls -lh /var/log/loan-risk-engine/app.log
tail /var/log/loan-risk-engine/app.log

# Restart OneAgent
sudo systemctl restart oneagent
```

### OneAgent não está em modo infra-only
```bash
# Verificar configuração
cat /var/lib/dynatrace/oneagent/agent/config/ruxitagent.conf | grep infra

# Deve mostrar: infra-only=true
```

## Observações Importantes

1. **Modo Infra-Only**: O OneAgent NÃO instrumenta o código C
2. **Sem Auto-Tracing**: A aplicação não participa automaticamente de traces distribuídos
3. **Correlação Manual**: O `traceparent` é logado e correlacionado via Dynatrace Log Processing
4. **Threshold de R$ 10.000**: Tier3Score só é gerado para empréstimos >= R$ 10.000

## Demonstração de Valor

Este tier demonstra como Dynatrace pode:
- Monitorar aplicações legacy sem modificar código
- Coletar e indexar logs estruturados
- Correlacionar logs com traces distribuídos via headers
- Extrair insights de negócio (cost allocation) mesmo sem APM completo
- Migrar gradualmente de infra-only para full-stack monitoring
