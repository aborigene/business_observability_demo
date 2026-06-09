# Dynatrace Business Observability Demo

A complete, production-ready demonstration application showcasing **Dynatrace Business Observability** and **Cost Allocation** capabilities through a realistic multi-tier loan application processing system.

## 🎯 Demo Highlights

- ✅ **5-Tier Application** in different languages (Node.js, Java, C, Python, .NET)
- ✅ **Distributed Tracing** with W3C Trace Context propagation
- ✅ **Business Events API** for business-level observability  
- ✅ **Kubernetes-First Infrastructure** (all tiers on EKS Fargate)
- ✅ **Multiple Monitoring Modes** (full-stack, infrastructure-only, API-based)
- ✅ **Cost Allocation** by business units (team, cost center, segment)
- ✅ **Database Monitoring** with Entity Framework Core
- ✅ **Legacy App Monitoring** (C application containerized without code changes)

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
│   │ Kubernetes + OneAgent     │  Generates tier3Score (0-30)       │
│   └───────────┬───────────────┘  Only for amounts >= $10,000      │
│               ↓                                                     │
│   ┌───────────────────────────┐                                   │
│   │ Tier 4: Python FastAPI    │  Final Decision Engine             │
│   │ Kubernetes (No Agent)     │  Sends Business Events to DT       │
│   └───────────┬───────────────┘  Simulates SaaS service           │
│               ↓                                                     │
│   ┌───────────────────────────┐                                   │
│   │ Tier 5: .NET 8 API        │  Loan Calculation & Persistence    │
│   │ Kubernetes + OneAgent     │  Entity Framework Core             │
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
| **Tier 3** | C (Raw HTTP) | EKS (Kubernetes) | OneAgent Full-Stack | Advanced Risk Analysis (0-30) |
| **Tier 4** | Python FastAPI | EKS (Kubernetes) | Business Events API | Decision Engine + Business Events |
| **Tier 5** | .NET 8 Minimal API | EKS (Kubernetes) | OneAgent Full-Stack | Loan Calculation & DB Persistence |

### Infrastructure

- **VPC**: Create new (10.0.0.0/16) or use existing VPC with validation
- **EKS**: Create new Kubernetes 1.28 cluster or use an existing cluster (EKS Fargate, `linux/amd64`)
- **RDS**: PostgreSQL 15 (db.t3.micro) for loan storage
- **CodeBuild**: Builds and pushes all Docker images to ECR (native `linux/amd64`, no local cross-compilation needed)
- **Terraform**: Complete IaC for reproducible deployments

## 🚀 Quick Start

### Prerequisites
- AWS CLI configured
- Terraform >= 1.5.0
- kubectl >= 1.28  
- Helm 3.x
- Docker or Podman (for local builds; CodeBuild handles CI builds)
- Dynatrace environment with API & PaaS tokens

### 1. Deploy Infrastructure

```bash
cd infra/terraform
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values (see options below)
terraform init
terraform apply
```

#### VPC Options

**Option A: Create a new VPC (default)**
```hcl
use_existing_vpc = false
```

**Option B: Use an existing VPC**
```bash
# First validate your VPC meets requirements
./scripts/validate-vpc.sh vpc-xxxxxxxxxxxxx us-east-1
```
```hcl
use_existing_vpc            = true
existing_vpc_id             = "vpc-xxxxxxxxxxxxx"
existing_public_subnet_ids  = ["subnet-aaa", "subnet-bbb"]
existing_private_subnet_ids = ["subnet-ccc", "subnet-ddd"]
```

#### EKS Options

**Option A: Create a new EKS cluster (default)**
```hcl
use_existing_eks    = false
eks_cluster_version = "1.28"
```

**Option B: Use an existing EKS cluster**

Use this if your AWS environment restricts EKS cluster creation (e.g. via an org-level SCP). Point Terraform at a cluster that already exists:
```hcl
use_existing_eks          = true
existing_eks_cluster_name = "your-cluster-name"
```
Terraform will skip creating IAM roles, node groups, and the control plane, and will deploy workloads into the existing cluster instead.

### 2. Configure kubectl
```bash
aws eks update-kubeconfig --name <cluster-name> --region us-east-1
```

### 3. Build and Push Docker Images

Images are built with **AWS CodeBuild** on native `linux/amd64` — no local cross-compilation needed, even on ARM Macs.

**Trigger a build via CodeBuild (recommended):**
```bash
# After terraform apply, use the output command:
aws codebuild start-build \
  --project-name <codebuild_project_name> \
  --region us-east-1

# Watch logs
aws logs tail /aws/codebuild/<project-name> --follow
```

**Or build locally** (requires Docker or Podman):
```bash
./scripts/build-images.sh   # builds all 5 images
./scripts/push-to-ecr.sh    # pushes to ECR
```

> **ARM Mac note**: Local builds cross-compile to `linux/amd64` via `--platform` flag. This works but is slow for .NET images under QEMU emulation. Use CodeBuild for faster builds.

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

### 3. Monitoring Modes
- **Full-Stack** (Tiers 1, 2, 3, 5): Code-level visibility, database monitoring
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
├── buildspec.yml                      # AWS CodeBuild build specification
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
│   ├── Dockerfile                     # Multi-stage Alpine build
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
│   ├── Dockerfile                     # Multi-stage Alpine build with NuGet cache
│   └── README.md
│
├── infra/                             # Infrastructure as Code
│   └── terraform/
│       ├── main.tf                    # Root module
│       ├── variables.tf
│       ├── outputs.tf
│       ├── codebuild.tf               # CodeBuild project for Docker image builds
│       ├── terraform.tfvars.example
│       └── modules/
│           ├── vpc/                   # VPC with NAT gateways
│           ├── eks/                   # EKS cluster & node groups
│           └── rds/                   # PostgreSQL RDS
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
│   ├── tier3/
│   │   ├── 01-configmap.yaml
│   │   ├── 02-deployment.yaml
│   │   └── 03-hpa.yaml
│   ├── tier4/
│   │   ├── 01-configmap.yaml
│   │   ├── 02-secret.yaml
│   │   ├── 03-deployment.yaml
│   │   └── 04-hpa.yaml
│   └── tier5/
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
    ├── build-images.sh                # Build Docker images (local)
    ├── push-to-ecr.sh                 # Push to AWS ECR
    ├── deploy-k8s.sh                  # Deploy to Kubernetes
    ├── deploy-all.sh                  # End-to-end deployment
    ├── validate-vpc.sh                # Validate existing VPC
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
| `TIER2_URL` | Tier 2 service URL | `http://tier2-service.loan-app.svc.cluster.local:8080` |
| `UNAUTHORIZED_REGIONS` | Blocked regions (comma-separated) | `Sanctioned,Restricted` |
| `UNAUTHORIZED_CHANNELS` | Blocked channels (comma-separated) | `External,Public` |

### Tier 2 (Credit Analysis)
| Variable | Description | Example |
|----------|-------------|---------|
| `TIER3_URL` | Tier 3 service URL | `http://tier3-service.loan-app.svc.cluster.local:8000` |
| `SERVER_PORT` | Server port | `8080` |

### Tier 3 (Risk Analysis)
| Variable | Description | Example |
|----------|-------------|---------|
| `TIER4_HOST` | Tier 4 service host | `tier4-service.loan-app.svc.cluster.local` |
| `TIER4_PORT` | Tier 4 service port | `8001` |

### Tier 4 (Decision Engine)
| Variable | Description | Example |
|----------|-------------|---------|
| `TIER5_URL` | Tier 5 service URL | `http://tier5-service.loan-app.svc.cluster.local:5000` |
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
kubectl exec -it -n loan-app <tier3-pod> -- curl localhost:8000/health

# Tier 4
kubectl exec -it -n loan-app <tier4-pod> -- curl localhost:8001/health

# Tier 5
kubectl exec -it -n loan-app <tier5-pod> -- curl localhost:5000/internal/health
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

- All secrets stored in Kubernetes Secrets
- Database credentials not hardcoded
- OneAgent tokens stored securely
- All pods run in private subnets via EKS Fargate
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
