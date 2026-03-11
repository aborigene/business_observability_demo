# Demonstration Guide

This guide provides scenarios and talking points for demonstrating Dynatrace Business Observability and Cost Allocation capabilities.

## Demo Preparation

### Prerequisites
- Application fully deployed (see [SETUP.md](SETUP.md))
- Dynatrace UI accessible
- Terminal with kubectl access
- Browser with Dynatrace environment open

### Pre-Demo Checklist
```bash
# Verify all pods are running
kubectl get pods -n loan-app

# Get Tier 1 load balancer URL
export TIER1_URL=$(kubectl get svc tier1-service -n loan-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')

# Test application
curl -X POST http://$TIER1_URL/api/loan/submit \
  -H "Content-Type: application/json" \
  -d @examples/loan-request-approved.json
```

## Demo Flow

### Part 1: Application Architecture (5 minutes)

**Talking Points:**
- "This is a realistic multi-tier loan application processing system"
- "5 tiers in different languages: Node.js, Java, C, Python, .NET"
- "Mix of Kubernetes and EC2 deployments"
- "Demonstrates various Dynatrace monitoring approaches"

**Show:**
```
┌─────────────────────────────────────────────────────────────────────┐
│                      Loan Application Flow                          │
├─────────────────────────────────────────────────────────────────────┤
│ Tier 1 (Node.js/K8s)   → Authorization & Validation                │
│ Tier 2 (Java/K8s)      → Initial Credit Analysis (0-70 score)      │
│ Tier 3 (C/EC2)         → Advanced Risk Analysis (0-30 score)       │
│ Tier 4 (Python/K8s)    → Decision Engine + Business Events         │
│ Tier 5 (.NET/EC2)      → Final Calculation & Persistence           │
└─────────────────────────────────────────────────────────────────────┘
```

### Part 2: End-to-End Distributed Tracing (10 minutes)

**Demo Steps:**

1. **Submit Loan Request**
```bash
curl -X POST http://$TIER1_URL/api/loan/submit \
  -H "Content-Type: application/json" \
  -d '{
    "applicationId": "LOAN-2024-001",
    "customerId": "CUST-12345",
    "requestedAmount": 50000,
    "term": 60,
    "costCenter": "retail-banking",
    "team": "mortgage-team",
    "segment": "retail",
    "channel": "Mobile",
    "product": "HomeLoan",
    "region": "NorthAmerica",
    "officeId": "NYC-001",
    "agentId": "AGT-789"
  }'
```

2. **Navigate to Dynatrace → Distributed Traces**
   - Filter by service: `loan-submission`
   - Select the most recent trace

3. **Walk Through the Trace**

**Talking Points:**
- "Notice the complete visibility across 5 different technology stacks"
- "W3C Trace Context propagation ensures end-to-end correlation"
- "See timing breakdown: Tier 1 validation, Tier 2 scoring, etc."
- "Database calls automatically captured in Tier 5"

**Highlight:**
- **Service calls**: Each tier clearly visible
- **Response times**: Where time is spent
- **Database queries**: SQL statements from Tier 5
- **Custom attributes**: Business context (applicationId, costCenter, team)

4. **Show Service Flow**
   - Open **Service Flow** view
   - "This shows the complete architecture discovered automatically"

### Part 3: Hybrid Monitoring Approaches (8 minutes)

**Scenario:** "Each tier has different monitoring requirements"

#### 3.1 Full Stack Monitoring (Tier 1, 2, 5)

**Navigate to:** Services → loan-submission

**Show:**
- Code-level visibility
- Method hotspots
- Response time distribution
- Failure rate

**Talking Points:**
- "OneAgent automatically instruments Node.js, Java, and .NET"
- "No code changes required"
- "Code-level visibility for troubleshooting"

#### 3.2 Infrastructure-Only Monitoring (Tier 3)

**Navigate to:** Infrastructure → Hosts → Tier 3 EC2

**Show:**
- CPU, memory, disk, network metrics
- Process monitoring
- Log correlation

**Talking Points:**
- "Tier 3 is a legacy C application"
- "Infrastructure-only mode: minimal overhead"
- "Still collects logs with business context"
- "Demonstrates monitoring legacy systems without code changes"

#### 3.3 SaaS Service Monitoring (Tier 4)

**Navigate to:** Business Analytics → Business Events

**Talking Points:**
- "Tier 4 simulates a SaaS decision engine"
- "No OneAgent (external service)"
- "Uses Business Events API for visibility"
- "Captures business outcomes without agent"

### Part 4: Business Events Deep Dive (10 minutes)

**Navigate to:** Business Analytics → Business Events

#### 4.1 Show Business Events

**Filter:**
```
event.type == "loan.decision"
```

**Talking Points:**
- "Every loan decision generates a Business Event"
- "Contains complete business context"
- "Can analyze by decision type, amount, team, cost center"

**Show Event Details:**
```json
{
  "event.type": "loan.decision",
  "decision": "APPROVED",
  "finalScore": 85,
  "tier2Score": 65,
  "tier3Score": 20,
  "approvedAmount": 50000,
  "totalDue": 53250.00,
  "interestRate": 0.065,
  "applicationId": "LOAN-2024-001",
  "customerId": "CUST-12345",
  "costCenter": "retail-banking",
  "team": "mortgage-team",
  "segment": "retail",
  "region": "NorthAmerica",
  "dt.trace_id": "..."
}
```

#### 4.2 Create Business Analysis

**Create a Query:**
```dql
fetch bizevents
| filter event.type == "loan.decision"
| summarize 
    count = count(),
    avgScore = avg(finalScore),
    totalApproved = sum(approvedAmount)
  by decision
```

**Show:**
- Approval rate
- Average scores by decision
- Total approved amounts

**Talking Points:**
- "Business events are queryable in real-time"
- "Can create dashboards for business KPIs"
- "Correlates with technical metrics via trace ID"

#### 4.3 Advanced Query: Team Performance

```dql
fetch bizevents
| filter event.type == "loan.decision"
| summarize 
    applications = count(),
    approved = countIf(decision == "APPROVED"),
    totalAmount = sum(approvedAmount),
    avgScore = avg(finalScore)
  by team
| fieldsAdd approvalRate = approved / applications * 100
| sort approvalRate desc
```

**Talking Points:**
- "Measure team performance"
- "Identify high-performing vs struggling teams"
- "Data-driven coaching opportunities"

### Part 5: Cost Allocation (12 minutes)

See [COST_ALLOCATION.md](COST_ALLOCATION.md) for detailed setup.

**Navigate to:** Settings → Cost and traffic management → Cost allocation

**Show:**
1. **Configure Cost Tags**
   - Add tags: `costCenter`, `team`, `segment`
   - Map to business event attributes

2. **Cost Analysis View**
   ```dql
   fetch bizevents
   | filter event.type == "loan.decision"
   | summarize 
       transactions = count(),
       estimatedCost = count() * 0.01  // $0.01 per transaction
     by costCenter, team
   ```

3. **Create Cost Dashboard**

**Talking Points:**
- "Allocate cloud costs to business units"
- "Track which teams/products drive costs"
- "Chargeback model for internal billing"
- "Optimize by identifying cost centers with low approval rates"

### Part 6: Real-World Scenarios (10 minutes)

#### Scenario 1: Unauthorized Region Blocked

**Submit Request:**
```bash
curl -X POST http://$TIER1_URL/api/loan/submit \
  -H "Content-Type: application/json" \
  -d @examples/loan-request-unauthorized.json
```

**Response (HTTP 200):**
```json
{
  "status": "unauthorized",
  "message": "Loan application not authorized",
  "reason": "Region 'Sanctioned' is not authorized for loan applications",
  "applicationId": "uuid-generated",
  "details": {
    "customerId": "CUST-00000",
    "region": "Sanctioned",
    "channel": "Mobile",
    "requestedAmount": 100000
  }
}
```

**In Dynatrace:**
- Show successful request (200 status) in Tier 1 service
- No cascade to downstream services
- Log entry shows authorization declined with reason
- "Authorization happens at the edge - request is handled gracefully"

#### Scenario 2: High-Value Loan (Tier 3 Engaged)

**Submit Request:**
```bash
curl -X POST http://$TIER1_URL/api/loan/submit \
  -H "Content-Type: application/json" \
  -d '{
    "applicationId": "LOAN-2024-002",
    "customerId": "CUST-67890",
    "requestedAmount": 250000,
    ...
  }'
```

**In Dynatrace:**
- Show trace includes Tier 3 participation
- Tier 3 log: "Processing high-value loan: $250,000"
- "Advanced risk analysis only for loans >= $10,000"

#### Scenario 3: Partial Approval

**Submit Request:**
```bash
curl -X POST http://$TIER1_URL/api/loan/submit \
  -H "Content-Type: application/json" \
  -d @examples/loan-request-partial.json
```

**Response:**
```json
{
  "status": "success",
  "decision": "PARTIALLY_APPROVED",
  "finalScore": 55,
  "approvedAmount": 40000,
  "requestedAmount": 50000,
  "totalDue": 42700.00
}
```

**In Business Events:**
- Show partial approval event
- "Score between rejection (40) and approval (60) thresholds"
- "Approved amount formula: requestedAmount - (100 - finalScore)"

### Part 7: Troubleshooting Demo (8 minutes)

**Simulate an Issue:**

1. **Cause Database Connection Issue**
```bash
# Scale Tier 5 to 0 (simulate downtime)
kubectl scale deployment tier5-loan-finalizer --replicas=0 -n loan-app

# Submit request
curl -X POST http://$TIER1_URL/api/loan/submit \
  -H "Content-Type: application/json" \
  -d @examples/loan-request-approved.json
```

2. **In Dynatrace:**
   - Navigate to Problems
   - Show problem card: "Increased failure rate for loan-finalizer"
   - Open problem details
   - Root cause: Connection refused to Tier 5

3. **Resolve:**
```bash
# Scale back up
kubectl scale deployment tier5-loan-finalizer --replicas=2 -n loan-app

# Verify recovery
kubectl get pods -n loan-app
```

**Talking Points:**
- "Problems detected automatically"
- "Root cause analysis: exact failing service"
- "Impact analysis: affected users, business transactions"

## Demo Q&A Preparation

### Expected Questions

**Q: Does this require code changes?**
A: Minimal. OneAgent is automatic. Only Business Events API requires explicit calls.

**Q: What's the overhead?**
A: < 3% CPU, < 100MB memory per OneAgent pod. Infrastructure-only mode even lighter.

**Q: Can we use this with legacy applications?**
A: Yes. Tier 3 demonstrates infrastructure-only monitoring for legacy C code.

**Q: How do we get Business Events from external SaaS services?**
A: Use the Business Events API (REST endpoint). Tier 4 demonstrates this pattern.

**Q: What about cost?**
A: Business Events may incur Davis Data Units (DDUs). Review pricing with Dynatrace.

**Q: Can we query Business Events in real-time?**
A: Yes. Use DQL for real-time queries and dashboards.

## Load Testing (Bonus)

For more dramatic demos:

```bash
# Install k6
brew install k6

# Run load test
k6 run - <<EOF
import http from 'k6/http';
import { sleep } from 'k6';

export let options = {
  stages: [
    { duration: '2m', target: 100 },
    { duration: '5m', target: 100 },
    { duration: '2m', target: 0 },
  ],
};

export default function () {
  const payload = JSON.stringify({
    applicationId: 'LOAN-' + Math.floor(Math.random() * 10000),
    customerId: 'CUST-' + Math.floor(Math.random() * 1000),
    requestedAmount: Math.floor(Math.random() * 200000) + 10000,
    term: 60,
    costCenter: ['retail-banking', 'commercial-banking', 'wealth-management'][Math.floor(Math.random() * 3)],
    team: ['mortgage-team', 'personal-loan-team', 'auto-loan-team'][Math.floor(Math.random() * 3)],
    segment: 'retail',
    channel: 'Mobile',
    product: 'HomeLoan',
    region: 'NorthAmerica',
    officeId: 'NYC-001',
    agentId: 'AGT-' + Math.floor(Math.random() * 1000),
  });

  http.post('http://${TIER1_URL}/api/loan/submit', payload, {
    headers: { 'Content-Type': 'application/json' },
  });

  sleep(1);
}
EOF
```

Watch in Dynatrace:
- Service load increase
- Response time under load
- Auto-scaling in action (HPA)
- Business event volume

## Summary

This demo showcases:
✅ Multi-language distributed tracing
✅ Hybrid deployment patterns (K8s + EC2)
✅ Multiple monitoring modes (full-stack, infra-only, API)
✅ Business Events for business observability
✅ Cost allocation by business units
✅ Real-world authorization and scoring logic
✅ Database monitoring
✅ Auto-discovery and code-level insights
