# Cost Allocation Guide

This guide explains how to use Dynatrace Business Events for cost allocation and chargeback across business units.

## Overview

Cost allocation enables you to:
- Track cloud infrastructure costs by business unit (team, cost center, product)
- Implement chargeback or showback models
- Identify cost optimization opportunities
- Align cloud spend with business value

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│             Business Event Attributes                     │
├──────────────────────────────────────────────────────────┤
│ costCenter         → "retail-banking"                     │
│ team               → "mortgage-team"                      │
│ segment            → "retail"                             │
│ region             → "NorthAmerica"                       │
│ product            → "HomeLoan"                           │
│ channel            → "Mobile"                             │
│ officeId           → "NYC-001"                            │
├──────────────────────────────────────────────────────────┤
│         + Infrastructure Metrics (CPU, Memory)            │
├──────────────────────────────────────────────────────────┤
│                  Cost Allocation Model                    │
└──────────────────────────────────────────────────────────┘
```

## Cost Allocation Model

### Transaction-Based Costs

Each loan application incurs costs across multiple resources:

| Resource | Cost per Transaction | Notes |
|----------|----------------------|-------|
| Tier 1 (K8s pod) | $0.001 | API Gateway + Validation |
| Tier 2 (K8s pod) | $0.002 | Credit Analysis (Java) |
| Tier 3 (EC2 instance) | $0.003 | Risk Engine (high-value only) |
| Tier 4 (K8s pod) | $0.001 | Decision Engine |
| Tier 5 (EC2 instance) | $0.002 | Finalization + DB write |
| RDS PostgreSQL | $0.001 | Database operation |
| **Total** | **$0.010** | Per standard flow |

For high-value loans (≥$10,000) with Tier 3:
**Total: $0.013**

### Infrastructure Allocation

Monthly infrastructure costs are allocated proportionally:

| Component | Monthly Cost | Allocation Method |
|-----------|--------------|-------------------|
| EKS Control Plane | $72 | Fixed |
| EKS Node Group (2x t3.medium) | ~$120 | By pod count/CPU |
| Tier 3 EC2 (t3.small) | ~$30 | By transaction count |
| Tier 5 EC2 (t3.small) | ~$30 | By transaction count |
| RDS (db.t3.micro) | ~$25 | By transaction count |
| Data Transfer | Variable | By region/volume |
| **Total** | **~$277/month** | |

## Setup in Dynatrace

### Step 1: Create Cost Allocation Tags

Navigate to: **Settings → Cost and traffic management → Cost allocation**

1. **Create Tag: costCenter**
   - Tag name: `costCenter`
   - Source: Business Events
   - Attribute: `costCenter`
   - Apply to: All services

2. **Create Tag: team**
   - Tag name: `team`
   - Source: Business Events
   - Attribute: `team`
   - Apply to: All services

3. **Create Tag: segment**
   - Tag name: `segment`
   - Source: Business Events
   - Attribute: `segment`
   - Apply to: All services

4. **Create Tag: product**
   - Tag name: `product`
   - Source: Business Events
   - Attribute: `product`
   - Apply to: All services

### Step 2: Configure Service-Level Tags

For each service (Tier 1-5), add custom tags:

```yaml
# Example for Tier 1 deployment
metadata:
  labels:
    dt.owner: "retail-banking"
    dt.cost_center: "retail"
spec:
  template:
    metadata:
      annotations:
        owner: "retail-banking"
        cost-center: "retail"
```

### Step 3: Enable Cloud Cost Management

If using AWS Cost and Usage Reports:

1. **AWS Setup:**
   ```bash
   # Enable Cost and Usage Reports
   aws cur put-report-definition \
     --report-definition file://cost-report-definition.json
   
   # Grant Dynatrace access to CUR S3 bucket
   # See Dynatrace documentation for IAM role setup
   ```

2. **Dynatrace Setup:**
   - Navigate to: **Cloud and virtualization → AWS**
   - Enable "Monitor AWS costs"
   - Configure CUR bucket

## Cost Analysis Queries

### Query 1: Transaction Count by Cost Center

```dql
fetch bizevents
| filter event.type == "loan.decision"
| summarize 
    transactions = count(),
    estimatedCost = count() * 0.010  // $0.01 per transaction
  by costCenter
| sort estimatedCost desc
```

**Use Case:** Monthly chargeback invoice

### Query 2: Cost by Team with Approval Rate

```dql
fetch bizevents
| filter event.type == "loan.decision"
| summarize 
    applications = count(),
    approved = countIf(decision == "APPROVED"),
    avgAmount = avg(approvedAmount),
    totalRevenue = sum(approvedAmount * 0.01),  // 1% origination fee
    infra_cost = count() * 0.010
  by team
| fieldsAdd 
    approvalRate = approved / applications * 100,
    roi = (totalRevenue - infra_cost) / infra_cost * 100
| sort roi desc
```

**Use Case:** Team performance with cost efficiency

### Query 3: High-Value Loan Analysis

```dql
fetch bizevents
| filter event.type == "loan.decision"
| filter requestedAmount >= 10000
| summarize 
    count = count(),
    cost_with_tier3 = count() * 0.013,  // Includes Tier 3
    avgScore = avg(finalScore)
  by costCenter, segment
```

**Use Case:** Understand Tier 3 utilization costs

### Query 4: Regional Cost Distribution

```dql
fetch bizevents
| filter event.type == "loan.decision"
| summarize 
    transactions = count(),
    estimatedCost = count() * 0.010,
    dataTransferCost = count() * 0.002  // Estimated data transfer
  by region
| fieldsAdd totalCost = estimatedCost + dataTransferCost
| sort totalCost desc
```

**Use Case:** Multi-region cost optimization

### Query 5: Channel Cost Efficiency

```dql
fetch bizevents
| filter event.type == "loan.decision"
| summarize 
    applications = count(),
    approved = countIf(decision == "APPROVED"),
    totalApproved = sum(approvedAmount),
    conversionRate = countIf(decision == "APPROVED") / count() * 100,
    costPerApplication = count() * 0.010 / count()
  by channel
| fieldsAdd costPerApproval = costPerApplication / (conversionRate / 100)
| sort costPerApproval asc
```

**Use Case:** Optimize marketing channel investments

## Creating Cost Dashboards

### Dashboard 1: Executive Cost Overview

**Tiles:**

1. **Total Monthly Cost**
   ```dql
   fetch bizevents
   | filter event.type == "loan.decision"
   | filter timestamp >= now() - 30d
   | summarize 
       transactions = count(),
       transactionCost = count() * 0.010,
       infraCost = 277  // Monthly fixed
   | fieldsAdd totalCost = transactionCost + infraCost
   ```

2. **Cost by Business Unit (Pie Chart)**
   ```dql
   fetch bizevents
   | filter event.type == "loan.decision"
   | filter timestamp >= now() - 30d
   | summarize cost = count() * 0.010
     by costCenter
   ```

3. **Daily Cost Trend (Line Chart)**
   ```dql
   fetch bizevents
   | filter event.type == "loan.decision"
   | filter timestamp >= now() - 30d
   | makeTimeseries 
       dailyCost = count() * 0.010,
       by: 1d
   ```

4. **Top Cost-Driving Teams (Table)**
   ```dql
   fetch bizevents
   | filter event.type == "loan.decision"
   | filter timestamp >= now() - 30d
   | summarize 
       transactions = count(),
       cost = count() * 0.010,
       approvalRate = countIf(decision == "APPROVED") / count() * 100
     by team
   | sort cost desc
   | limit 10
   ```

### Dashboard 2: Team Chargeback Report

Create a dashboard for each team:

```dql
fetch bizevents
| filter event.type == "loan.decision"
| filter team == "mortgage-team"
| filter timestamp >= now() - 30d
| summarize 
    totalApplications = count(),
    approved = countIf(decision == "APPROVED"),
    rejected = countIf(decision == "REJECTED"),
    partial = countIf(decision == "PARTIALLY_APPROVED"),
    totalApprovedAmount = sum(approvedAmount),
    avgProcessingTime = avg(processingTime),
    infrastructureCost = count() * 0.010
```

## Cost Optimization Strategies

### 1. Identify Low-Value Transactions

```dql
fetch bizevents
| filter event.type == "loan.decision"
| filter decision == "REJECTED"
| summarize 
    rejected = count(),
    wastedCost = count() * 0.010,
    avgScore = avg(finalScore)
  by costCenter
| sort wastedCost desc
```

**Action:** Implement pre-qualification to reduce rejected applications.

### 2. Optimize High-Value Loan Processing

```dql
fetch bizevents
| filter event.type == "loan.decision"
| filter requestedAmount >= 10000
| summarize 
    count = count(),
    tier3Cost = count() * 0.003,
    avgScore = avg(tier3Score)
  by segment
```

**Action:** Consider increasing threshold for Tier 3 engagement if scores aren't improving outcomes.

### 3. Capacity Planning

```dql
fetch bizevents
| filter event.type == "loan.decision"
| makeTimeseries 
    hourlyTransactions = count(),
    by: 1h
| fieldsAdd requiredCapacity = hourlyTransactions / 100  // 100 TPS per pod
```

**Action:** Right-size EKS node groups based on actual transaction patterns.

### 4. Regional Optimization

```dql
fetch bizevents
| filter event.type == "loan.decision"
| summarize 
    transactions = count(),
    cost = count() * 0.010
  by region
| fieldsAdd costPercentage = cost / sum(cost) * 100
```

**Action:** Deploy regional infrastructure where transaction volume justifies it.

## Chargeback Implementation

### Monthly Invoice Generation

Create a scheduled notebook that generates monthly invoices:

```python
import requests
import json
from datetime import datetime, timedelta

# Dynatrace API endpoint
DT_URL = "https://your-env.live.dynatrace.com"
DT_TOKEN = "your-api-token"

# Query for last month
last_month = datetime.now() - timedelta(days=30)

query = """
fetch bizevents
| filter event.type == "loan.decision"
| filter timestamp >= ${last_month}
| summarize 
    transactions = count(),
    transactionCost = count() * 0.010,
    allocatedInfra = 277 / 10  // Divide fixed costs by business units
  by costCenter, team
| fieldsAdd totalCost = transactionCost + allocatedInfra
"""

# Execute query
response = requests.post(
    f"{DT_URL}/api/v2/queries/execute",
    headers={"Authorization": f"Api-Token {DT_TOKEN}"},
    json={"query": query}
)

# Generate invoice CSV
invoices = response.json()["result"]["records"]
for invoice in invoices:
    print(f"{invoice['costCenter']},{invoice['team']},{invoice['totalCost']:.2f}")
```

### Showback Dashboard

For non-billing organizations, create a "showback" dashboard showing relative usage:

```dql
fetch bizevents
| filter event.type == "loan.decision"
| summarize 
    transactions = count(),
    shareOfTotal = count() / sum(count()) * 100
  by costCenter
| sort shareOfTotal desc
```

## Advanced: Predictive Cost Modeling

### Forecast Next Month's Costs

```dql
fetch bizevents
| filter event.type == "loan.decision"
| filter timestamp >= now() - 90d
| makeTimeseries 
    dailyTransactions = count(),
    by: 1d
| fieldsAdd 
    movingAvg = movingAverage(dailyTransactions, 7),
    projectedMonthly = movingAvg * 30,
    projectedCost = projectedMonthly * 0.010
```

### Scenario Planning

What if we increase approval threshold?

```dql
fetch bizevents
| filter event.type == "loan.decision"
| filter finalScore >= 55  // Current threshold: 60
| summarize 
    additionalApprovals = count(),
    additionalRevenue = sum(approvedAmount) * 0.01,
    additionalCost = count() * 0.010
| fieldsAdd netImpact = additionalRevenue - additionalCost
```

## Best Practices

1. **Tag Consistency**
   - Use standardized cost center codes
   - Validate tags at ingestion
   - Document tag taxonomy

2. **Regular Reviews**
   - Monthly cost review meetings
   - Quarterly optimization reviews
   - Annual budget planning with historical data

3. **Attribution Models**
   - Direct costs: Per-transaction infrastructure
   - Shared costs: EKS control plane allocated by usage
   - Fixed costs: Amortized across all transactions

4. **Automation**
   - Automated monthly reports
   - Alert on cost anomalies
   - Self-service dashboards for teams

5. **Integration**
   - Export to financial systems
   - Integrate with AWS Cost Explorer
   - Combine with application performance data

## Reporting Templates

### Monthly Cost Report Template

```
==============================================================
                 MONTHLY COST ALLOCATION REPORT
                      [Month Year]
==============================================================

SUMMARY
-------
Total Transactions:        [X,XXX]
Total Infrastructure Cost: $XXX.XX
Cost per Transaction:      $X.XXX
Peak Daily Transactions:   [X,XXX]

BY COST CENTER
--------------
Cost Center          | Transactions | Cost    | % of Total
---------------------|--------------|---------|------------
retail-banking       | XX,XXX       | $XXX.XX | XX%
commercial-banking   | XX,XXX       | $XXX.XX | XX%
wealth-management    | XX,XXX       | $XXX.XX | XX%

BY TEAM
-------
Team                 | Trans | Approved | Rate   | Cost
---------------------|-------|----------|--------|--------
mortgage-team        | X,XXX | X,XXX    | XX%    | $XX.XX
personal-loan-team   | X,XXX | X,XXX    | XX%    | $XX.XX
auto-loan-team       | X,XXX | X,XXX    | XX%    | $XX.XX

RECOMMENDATIONS
---------------
1. [Recommendation based on data]
2. [Recommendation based on data]
3. [Recommendation based on data]
==============================================================
```

## Next Steps

1. Review queries and customize for your organization
2. Set up automated dashboards
3. Schedule monthly cost allocation reports
4. Integrate with financial systems
5. Train teams on cost awareness
6. Optimize based on insights

For questions or assistance, consult Dynatrace documentation or contact support.
