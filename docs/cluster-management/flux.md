# Flux

### Replace ssh key

WIP: Must be a better way to do this

Run the bootstrap command
# Flux CD Management

GitOps management using Flux CD for continuous deployment.

## Current Setup

This cluster uses Flux CD v2 for GitOps-based application deployment. All applications are managed through Git commits and automatically deployed.

## Bootstrap Process

The cluster bootstrap process handles Flux installation automatically:

```bash
# Bootstrap complete cluster including Flux
task bootstrap:flux
```

This command:
1. Creates the flux-system namespace
2. Installs Flux controllers
3. Configures SOPS decryption with age key
4. Sets up Git repository source
5. Applies initial Kustomizations

## Manual Flux Operations

### Force Reconciliation
```bash
# Reconcile all sources and kustomizations
flux reconcile source git home-kubernetes
flux reconcile kustomization flux-system

# Force reconcile specific app
flux reconcile kustomization <app-name> -n flux-system
```

### Suspend/Resume Applications
```bash
# Suspend an application (stops reconciliation)
flux suspend hr <helm-release> -n <namespace>
flux suspend kustomization <app-name> -n flux-system

# Resume an application
flux resume hr <helm-release> -n <namespace>
flux resume kustomization <app-name> -n flux-system
```

### View Status
```bash
# Check all Flux resources
flux get all -A

# Check specific types
flux get sources git -A
flux get kustomizations -A
flux get helmreleases -A
```

## SOPS Integration

Secrets are encrypted using SOPS with age encryption:

```bash
# The age key is automatically configured during bootstrap
# Located at: age.key (encrypted with repository key)

# To manually recreate the secret:
cat age.key | kubectl -n flux-system create secret generic sops-age
    --from-file=age.agekey=/dev/stdin
```

## Repository Structure

- `kubernetes/flux/config/` - Flux system configuration
- `kubernetes/flux/vars/` - Cluster variables and secrets
- `kubernetes/apps/` - Application definitions organized by namespace

## Troubleshooting

### Check Flux Logs
```bash
# Controller logs
kubectl logs -n flux-system -l app=source-controller
kubectl logs -n flux-system -l app=kustomize-controller
kubectl logs -n flux-system -l app=helm-controller

# Or use flux command
flux logs -A
```

### Common Issues

#### Secret Decryption Fails
```bash
# Check SOPS age secret exists
kubectl -n flux-system get secret sops-age

# Recreate if missing
cat age.key | kubectl -n flux-system create secret generic sops-age
    --from-file=age.agekey=/dev/stdin
```

#### Git Authentication Issues
```bash
# Check git source status
flux get sources git -A

# Check repository access
kubectl -n flux-system get gitrepository home-kubernetes -o yaml
```

## Best Practices

1. **Always use Git workflow** - No direct kubectl apply
2. **Test changes in branches** before merging to main
3. **Use flux suspend/resume** for maintenance
4. **Monitor reconciliation status** regularly
5. **Keep secrets encrypted** with SOPS
