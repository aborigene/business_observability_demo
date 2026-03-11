# Dynatrace Operator Installation Guide

## Prerequisites
1. Kubernetes cluster (EKS) running
2. kubectl configured with cluster access
3. Helm 3.x installed
4. Dynatrace tokens ready (API token with required permissions)

## Required Dynatrace Token Permissions

### API Token
The API token requires these scopes:
- `DataExport`
- `ReadConfig`
- `WriteConfig`
- `InstallerDownload`
- `entities.read`
- `settings.read`
- `settings.write`

### PaaS Token (Data Ingest Token)
Required for OneAgent deployment.

## Installation Steps

### 1. Add Dynatrace Helm Repository
```bash
helm repo add dynatrace https://raw.githubusercontent.com/Dynatrace/dynatrace-operator/main/config/helm/repos/stable
helm repo update
```

### 2. Install Dynatrace Operator
```bash
helm install dynatrace-operator dynatrace/dynatrace-operator \
  --namespace dynatrace \
  --create-namespace \
  --set installCRD=true
```

### 3. Update Secret with Your Tokens
Edit `01-secret.yaml` and replace placeholders:
- `REPLACE_WITH_YOUR_DT_API_TOKEN` - Your Dynatrace API token
- `REPLACE_WITH_YOUR_DT_PAAS_TOKEN` - Your Dynatrace PaaS token

### 4. Update DynaKube with Your Environment
Edit `02-dynakube.yaml` and replace:
- `YOUR_ENVIRONMENT_ID` - Your Dynatrace environment ID

### 5. Apply Manifests
```bash
# Apply namespace (already created by Helm)
kubectl apply -f 00-namespace.yaml

# Apply secret
kubectl apply -f 01-secret.yaml

# Apply DynaKube CR
kubectl apply -f 02-dynakube.yaml
```

### 6. Verify Installation
```bash
# Check operator pod
kubectl get pods -n dynatrace

# Check DynaKube status
kubectl get dynakube -n dynatrace

# Check OneAgent pods
kubectl get pods -n dynatrace -l app.kubernetes.io/component=operator

# View DynaKube details
kubectl describe dynakube dynakube -n dynatrace
```

## Verification

OneAgent should be deployed as a DaemonSet on all nodes:
```bash
kubectl get daemonset -n dynatrace
```

Check logs if issues occur:
```bash
# Operator logs
kubectl logs -n dynatrace deployment/dynatrace-operator

# OneAgent logs
kubectl logs -n dynatrace -l app.kubernetes.io/name=oneagent
```

## Troubleshooting

### Pods not starting
- Check token validity
- Verify API URL is correct
- Ensure network connectivity to Dynatrace

### OneAgent not injecting
- Check namespace labels
- Verify DynaKube status: `kubectl get dynakube -n dynatrace -o yaml`
- Review operator logs

### Manual namespace injection
To enable OneAgent injection in application namespaces:
```bash
kubectl label namespace loan-app oneagent=true
```

## Next Steps
After successful installation:
1. Deploy application tiers (tier1, tier2, tier4)
2. Verify monitoring in Dynatrace UI
3. Check distributed traces across services
