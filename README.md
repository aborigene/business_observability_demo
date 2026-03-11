# Dynatrace Business Observability Demo

A complete, production-ready demonstration application showcasing **Dynatrace Business Observability** and **Cost Allocation** capabilities through a realistic multi-tier loan application processing system.

## 🎯 Demo Highlights

- ✅ **5-Tier Application** in different languages (Node.js, Java, C, Python, .NET)
- ✅ **Distributed Tracing** with W3C Trace Context propagation
- ✅ **Business Events API** for business-level observability  
- ✅ **Hybrid Infrastructure** (Kubernetes + EC2)
- ✅ **Multiple Monitoring Modes** (full-stack, infrastructure-only, API-based)
- ✅ **Cost Allocation** by business units (team, cost center, segment)
- ✅ **Database Monitoring** with Entity Framework Core
- ✅ **Legacy App Monitoring** (C application without code changes)

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                      Loan Application Flow                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│   HTTP Request                                                      │
│       ↓                                                             │
│   ┌───────────────────────────┐                                   │
│   │ Tier 1: Node.js Express   │  Authorization & Validation        │
│   │ Kubernetes + OneAgent     │  Blocks unauthorized regions       │
│   └───────────┬───────────────┘                                   │
│               ↓                                                     │
│   ┌───────────────────────────┐                                   │
│   │ Tier 2: Java Spring Boot  │  Initial Credit Analysis           │
│   │ Kubernetes + OneAgent     │  Generates tier2Score (0-70)       │
│   └───────────┬───────────────┘                                   │
│               ↓                                                     │
│   ┌───────────────────────────┐                                   │
│   │ Tier 3: C Legacy App      │  Advanced Risk Analysis            │
│   │ EC2 + OneAgent (Infra)    │  Generates tier3Score (0-30)       │
│   └───────────┬───────────────┘  Only for amounts >= $10,000      │
│               ↓                                                     │
│   ┌───────────────────────────┐                                   │
│   │ Tier 4: Python FastAPI    │  Final Decision Engine             │
│   │ Kubernetes (No Agent)     │  Sends Business Events to DT       │
│   └───────────┬───────────────┘  Simulates SaaS service           │
│               ↓                                                     │
│   ┌───────────────────────────┐                                   │
│   │ Tier 5: .NET 8 API        │  Loan Calculation & Persistence    │
│   │ EC2 + OneAgent            │  Entity Framework Core             │
│   └───────────┬───────────────┘                                   │
│               ↓                                                     │
│   ┌───────────────────────────┐                                   │
│   │   PostgreSQL RDS          │  Loan Applications Database        │
│   └───────────────────────────┘                                   │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

## 📦 Components

### Application Tiers

| Tier | Technology | Infrastructure | Monitoring | Purpose |
|------|------------|----------------|------------|---------|
| **Tier 1** | Node.js Express | EKS (Kubernetes) | OneAgent Full-Stack | Authorization & Validation |
| **Tier 2** | Java Spring Boot 3.2 | EKS (Kubernetes) | OneAgent Full-Stack | Initial Credit Scoring (0-70) |
| **Tier 3** | C (Raw HTTP) | EC2 | OneAgent Infrastructure-Only | Advanced Risk Analysis (0-30) |
| **Tier 4** | Python FastAPI | EKS (Kubernetes) | Business Events API | Decision Engine + Business Events |
| **Tier 5** | .NET 8 Minimal API | EC2 | OneAgent Full-Stack | Loan Calculation & DB Persistence |

### Infrastructure

- **VPC**: Create new (10.0.0.0/16) or use existing VPC with validation
- **Deployment Modes**: Create new VPC or reuse existing (with automated validation)
- **EKS**: Kubernetes 1.28 cluster with managed node groups (t3.medium)
- **EC2**: 2 instances (t3.small) for Tier 3 and Tier 5
- **RDS**: PostgreSQL 15.4 (db.t3.micro) for loan storage
- **Terraform**: Complete IaC for reproducible deployments

## 🚀 Quick Start

### Prerequisites
- AWS CLI configured
- Terraform >= 1.5.0
- kubectl >= 1.28  
- Helm 3.x
- Docker
- Dynatrace environment with API & PaaS tokens

### 1. Deploy Infrastructure

#### Option A: Create New VPC (Default)
```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values (use_existing_vpc = false)
terraform init
terraform apply
```

#### Option B: Use Existing VPC
```bash
# First, validate your existing VPC
./scripts/validate-vpc.sh vpc-xxxxxxxxxxxxx us-east-1

# Update terraform.tfvars with validation output
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars:
#   use_existing_vpc = true
#   existing_vpc_id = "vpc-xxxxx"
#   existing_public_subnet_ids = [...]
#   existing_private_subnet_ids = [...]

terraform init
terraform apply
```

### 2. Configure kubectl
```bash
aws eks update-kubeconfig --name <cluster-name> --region us-east-1
```

### 3. Build and Push Images
```bash
./scripts/build-images.sh
./scripts/push-to-ecr.sh
```

### 4. Deploy Dynatrace Operator
```bash
# Install operator
helm repo add dynatrace https://raw.githubusercontent.com/Dynatrace/dynatrace-operator/main/config/helm/repos/stable
helm install dynatrace-operator dynatrace/dynatrace-operator \
  --namespace dynatrace --create-namespace --set installCRD=true

# Configure DynaKube
kubectl apply -f k8s/dynatrace-operator/
```

### 5. Deploy Applications
```bash
./scripts/deploy-k8s.sh
```

### 6. Test the Application
```bash
# Get load balancer URL
export TIER1_URL=$(kubectl get svc tier1-service -n loan-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Submit loan request
curl -X POST http://$TIER1_URL/api/loan/submit \
  -H "Content-Type: application/json" \
  -d @examples/loan-request-approved.json
```

## 📖 Documentation

Comprehensive guides available in the [docs/](docs/) folder:

- **[SETUP.md](docs/SETUP.md)**: Complete step-by-step setup instructions
- **[DEMO.md](docs/DEMO.md)**: Demo script with talking points and scenarios
- **[COST_ALLOCATION.md](docs/COST_ALLOCATION.md)**: Cost allocation setup and queries

## 🔍 Observability Features

### 1. Distributed Tracing
- W3C Trace Context propagation across all tiers
- End-to-end visibility: HTTP → Tier 1 → Tier 2 → Tier 3 → Tier 4 → Tier 5 → Database
- Service dependencies automatically discovered
- Code-level insights (method hotspots, SQL queries)

### 2. Business Events
Tier 4 sends business events to Dynatrace with complete context:
```json
{
  "event.type": "loan.decision",
  "decision": "APPROVED",
  "finalScore": 85,
  "approvedAmount": 50000,
  "costCenter": "retail-banking",
  "team": "mortgage-team",
  "dt.trace_id": "..."
}
```

### 3. Hybrid Monitoring
- **Full-Stack** (Tiers 1, 2, 5): Code-level visibility, database monitoring
- **Infrastructure-Only** (Tier 3): Legacy C app with log correlation
- **API-Based** (Tier 4): Business Events for SaaS service simulation

### 4. Cost Allocation  
Track costs by business dimensions:
- Cost Center: `retail-banking`, `commercial-banking`, `wealth-management`
- Team: `mortgage-team`, `personal-loan-team`, `auto-loan-team`
- Segment: `retail`, `commercial`, `premium`
- Region: `NorthAmerica`, `Europe`, `Asia`


## 💼 Business Logic

### Authorization Rules (Tier 1)
- Blocks requests from unauthorized regions (configurable via `UNAUTHORIZED_REGIONS`)
- Blocks requests from unauthorized channels (configurable via `UNAUTHORIZED_CHANNELS`)
- Validates all required fields before forwarding

### Scoring Logic
1. **Tier 2**: Generates `tier2Score` (random 0-70)
2. **Tier 3**: Generates `tier3Score` (random 0-30) **only if** `requestedAmount >= $10,000`
3. **Final Score**: `tier2Score + tier3Score`

### Decision Rules (Tier 4)
```
finalScore >= APPROVAL_THRESHOLD (60)     → APPROVED
finalScore <= REJECTION_THRESHOLD (40)    → REJECTED
Between thresholds                        → PARTIALLY_APPROVED
```

### Approved Amount Calculation (Tier 5)
```
APPROVED:             approvedAmount = requestedAmount
REJECTED:             approvedAmount = 0
PARTIALLY_APPROVED:   approvedAmount = max(0, requestedAmount - (100 - finalScore))
```

### Interest Calculation (Tier 5)
```
interestRate = baseRate + ((100 - finalScore) / 1000)
totalDue = approvedAmount * (1 + interestRate * termMonths)
```

**Example**: 
- `requestedAmount = $50,000`, `finalScore = 85`, `term = 60 months`, `baseRate = 0.05`
- `interestRate = 0.05 + ((100-85)/1000) = 0.05 + 0.015 = 0.065` (6.5%)
- `totalDue = 50000 * (1 + 0.065 * 60) = 50000 * 4.9 = $245,000`

## 📂 Repository Structure

```
business_observability_demo/
├── README.md                          # This file
├── .gitignore                         # Git ignore patterns
│
├── tier1-node/                        # Tier 1: Node.js Express
│   ├── src/
│   │   ├── index.js                   # Main application
│   │   └── utils/                     # Logging & tracing utilities
│   ├── package.json
│   ├── Dockerfile
│   └── README.md
│
├── tier2-java/                        # Tier 2: Java Spring Boot
│   ├── src/main/java/com/example/loan/
│   │   ├── LoanCreditAnalysisApplication.java
│   │   ├── controller/
│   │   ├── model/
│   │   └── service/
│   ├── pom.xml
│   ├── Dockerfile
│   └── README.md
│
├── tier3-c-legacy/                    # Tier 3: C Legacy App
│   ├── src/
│   │   └── server.c                   # HTTP server with JSON parsing
│   ├── Makefile
│   ├── loan-risk-engine.service       # systemd service
│   ├── install.sh
│   ├── ec2-userdata.sh
│   └── README.md
│
├── tier4-saas-sim/                    # Tier 4: Python FastAPI
│   ├── app/
│   │   ├── main.py                    # Business Events integration
│   │   └── __init__.py
│   ├── requirements.txt
│   ├── Dockerfile
│   └── README.md
│
├── tier5-dotnet/                      # Tier 5: .NET 8 Minimal API
│   ├── Program.cs
│   ├── Models/
│   │   └── LoanApplication.cs
│   ├── Data/
│   │   └── LoanDbContext.cs           # EF Core context
│   ├── Services/
│   │   └── LoanCalculationService.cs
│   ├── LoanFinalizer.csproj
│   ├── Dockerfile
│   ├── ec2-userdata.sh
│   └── README.md
│
├── infra/                             # Infrastructure as Code
│   └── terraform/
│       ├── main.tf                    # Root module
│       ├── variables.tf
│       ├── outputs.tf
│       ├── terraform.tfvars.example
│       ├── modules/
│       │   ├── vpc/                   # VPC with NAT gateways
│       │   ├── eks/                   # EKS cluster & node groups
│       │   ├── ec2/                   # EC2 instances for Tier 3 & 5
│       │   └── rds/                   # PostgreSQL RDS
│       └── userdata/
│           ├── tier3-userdata.sh      # Tier 3 EC2 setup
│           └── tier5-userdata.sh      # Tier 5 EC2 setup
│
├── k8s/                               # Kubernetes Manifests
│   ├── namespace/
│   │   └── loan-app-namespace.yaml
│   ├── dynatrace-operator/
│   │   ├── 00-namespace.yaml
│   │   ├── 01-secret.yaml
│   │   ├── 02-dynakube.yaml
│   │   └── README.md
│   ├── tier1/
│   │   ├── 01-configmap.yaml
│   │   ├── 02-secret.yaml
│   │   ├── 03-deployment.yaml
│   │   └── 04-hpa.yaml
│   ├── tier2/
│   │   ├── 01-configmap.yaml
│   │   ├── 02-deployment.yaml
│   │   └── 03-hpa.yaml
│   └── tier4/
│       ├── 01-configmap.yaml
│       ├── 02-secret.yaml
│       ├── 03-deployment.yaml
│       └── 04-hpa.yaml
│
├── docs/                              # Documentation
│   ├── SETUP.md                       # Complete setup guide
│   ├── DEMO.md                        # Demo script & scenarios
│   └── COST_ALLOCATION.md             # Cost allocation setup
│
├── examples/                          # Example requests
│   ├── loan-request-approved.json
│   ├── loan-request-rejected.json
│   ├── loan-request-partial.json
│   ├── loan-request-unauthorized.json
│   └── loan-request-highvalue.json
│
└── scripts/                           # Deployment automation
    ├── build-images.sh                # Build Docker images
    ├── push-to-ecr.sh                 # Push to AWS ECR
    ├── deploy-k8s.sh                  # Deploy to Kubernetes
    ├── deploy-all.sh                  # End-to-end deployment
    └── cleanup.sh                     # Cleanup all resources
```

## 🔧 Environment Variables

### Dynatrace Configuration
| Variable | Description | Example |
|----------|-------------|---------|
| `DT_ENV_URL` | Dynatrace environment URL | `https://abc12345.live.dynatrace.com` |
| `DT_API_TOKEN` | API token (bizevents.ingest) | `dt0c01.ABC...` |
| `DT_PAAS_TOKEN` | PaaS/Data Ingest token | `dt0c01.XYZ...` |

### Tier 1 (Authorization)
| Variable | Description | Example |
|----------|-------------|---------|
| `TIER2_URL` | Tier 2 service URL | `http://tier2-service:8080` |
| `UNAUTHORIZED_REGIONS` | Blocked regions (comma-separated) | `Sanctioned,Restricted` |
| `UNAUTHORIZED_CHANNELS` | Blocked channels (comma-separated) | `External,Public` |

### Tier 2 (Credit Analysis)
| Variable | Description | Example |
|----------|-------------|---------|
| `TIER3_URL` | Tier 3 EC2 URL | `http://10.0.1.100:8000` |
| `SERVER_PORT` | Server port | `8080` |

### Tier 3 (Risk Analysis)
| Variable | Description | Example |
|----------|-------------|---------|
| `TIER4_HOST` | Tier 4 service host | `tier4-service` |
| `TIER4_PORT` | Tier 4 service port | `8001` |

### Tier 4 (Decision Engine)
| Variable | Description | Example |
|----------|-------------|---------|
| `TIER5_URL` | Tier 5 EC2 URL | `http://10.0.1.200:5000` |
| `APPROVAL_THRESHOLD` | Score for approval | `60` |
| `REJECTION_THRESHOLD` | Score for rejection | `40` |

### Tier 5 (Finalization)
| Variable | Description | Example |
|----------|-------------|---------|
| `DATABASE_URL` | PostgreSQL connection string | `Host=rds-endpoint;Database=loandb;...` |
| `Loan__BaseRate` | Base monthly interest rate | `0.05` |

## 🎬 Demo Scenarios

### Scenario 1: Successful Approval
```bash
curl -X POST http://$TIER1_URL/api/loan/submit \
  -H "Content-Type: application/json" \
  -d @examples/loan-request-approved.json
```
**Expected**: `finalScore >= 60` → `APPROVED` with full amount

### Scenario 2: Rejection
```bash
curl -X POST http://$TIER1_URL/api/loan/submit \
  -H "Content-Type: application/json" \
  -d @examples/loan-request-rejected.json
```
**Expected**: `finalScore <= 40` → `REJECTED` with $0 approved

### Scenario 3: Partial Approval
```bash
curl -X POST http://$TIER1_URL/api/loan/submit \
  -H "Content-Type: application/json" \
  -d @examples/loan-request-partial.json
```
**Expected**: `40 < finalScore < 60` → `PARTIALLY_APPROVED` with reduced amount

### Scenario 4: Authorization Block
```bash
curl -X POST http://$TIER1_URL/api/loan/submit \
  -H "Content-Type: application/json" \
  -d @examples/loan-request-unauthorized.json
```
**Expected**: `region = "Sanctioned"` → Returns HTTP 200 with `status: "unauthorized"` and detailed reason. Request handled gracefully at Tier 1, no cascade to downstream services.

### Scenario 5: High-Value Loan (Tier 3 Engaged)
```bash
curl -X POST http://$TIER1_URL/api/loan/submit \
  -H "Content-Type: application/json" \
  -d @examples/loan-request-highvalue.json
```
**Expected**: `requestedAmount >= $10,000` → Tier 3 adds risk score

## 📊 Cost Analysis Queries

See [COST_ALLOCATION.md](docs/COST_ALLOCATION.md) for complete guide. Example DQL queries:

### Total Transactions by Cost Center
```dql
fetch bizevents
| filter event.type == "loan.decision"
| summarize count = count(), cost = count() * 0.010
  by costCenter
| sort cost desc
```

### Team Performance with ROI
```dql
fetch bizevents  
| filter event.type == "loan.decision"
| summarize 
    applications = count(),
    approved = countIf(decision == "APPROVED"),
    revenue = sum(approvedAmount * 0.01),
    cost = count() * 0.010
  by team
| fieldsAdd roi = (revenue - cost) / cost * 100
| sort roi desc
```

## 🧪 Testing

### Health Checks
```bash
# Tier 1
curl http://$TIER1_URL/health

# Tier 2  
kubectl exec -it -n loan-app <tier2-pod> -- curl localhost:8080/actuator/health

# Tier 3
ssh ec2-user@<tier3-ip> "curl localhost:8000/health"

# Tier 4
kubectl exec -it -n loan-app <tier4-pod> -- curl localhost:8001/health

# Tier 5
ssh ec2-user@<tier5-ip> "curl localhost:5000/internal/health"
```

### Database Verification
```bash
# Connect to RDS
psql -h <rds-endpoint> -U loanadmin -d loandb

# Check data
SELECT application_id, decision, final_score, approved_amount 
FROM loan_applications 
ORDER BY created_at DESC 
LIMIT 10;
```

## 🔒 Security Considerations

- All secrets stored in Kubernetes Secrets or AWS Secrets Manager
- Database credentials not hardcoded
- OneAgent tokens stored securely
- EC2 instances in private subnets (access via bastion or SSM)
- RDS not publicly accessible
- Security groups restrict access between tiers

## 📝 License

MIT License - See LICENSE file for details

## 🤝 Contributing

This is a demonstration application. Feel free to fork and adapt for your own demos.

## 📞 Support

For questions or issues:
1. Review [SETUP.md](docs/SETUP.md) for troubleshooting
2. Check Dynatrace documentation
3. Open an issue in the repository

## 🎓 Learning Resources

- [Dynatrace Business Events](https://www.dynatrace.com/support/help/platform-modules/business-analytics/ba-events-capturing)
- [Dynatrace Kubernetes Operator](https://www.dynatrace.com/support/help/setup-and-configuration/setup-on-k8s)
- [W3C Trace Context](https://www.w3.org/TR/trace-context/)
- [Cost Allocation in Dynatrace](https://www.dynatrace.com/support/help/platform-modules/infrastructure-monitoring/hosts/monitoring/host-monitoring)

---

**Built with ❤️ for demonstrating Dynatrace Business Observability capabilities**
