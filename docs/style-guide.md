# Kubernetes Repository Style Guide

## 📋 Overview

This style guide ensures consistency across all YAML configurations in the k8s-cluster repository. Following these standards helps maintain readability, tooling support, and reduces errors.

## 🎯 Core Principles

1. **Consistency First** - All similar files should follow identical patterns
2. **Schema Validation** - Every YAML file must have appropriate schema declarations
3. **Self-Documenting** - Code structure should be immediately understandable
4. **Tool-Friendly** - Support IDE validation and autocomplete
5. **GitOps Ready** - Optimize for Flux CD reconciliation

## 📁 File Organization

### Directory Structure
```
kubernetes/apps/<namespace>/
├── kustomization.yaml          # Namespace-level resource aggregation
├── namespace.yaml              # Namespace definition
└── <app-name>/
    ├── ks.yaml                # Flux Kustomization for the app
    └── app/
        ├── kustomization.yaml  # App-level resource aggregation
        ├── helmrelease.yaml    # Helm chart configuration
        ├── externalsecret.yaml # Secret management (if needed)
        └── config/             # Application configs (if needed)
```

### File Naming Conventions
- **Directories**: `kebab-case` (e.g., `home-assistant`, `kube-prometheus-stack`)
- **Files**: `lowercase.yaml` (never `.yml`)
- **Resources**: Match directory name (e.g., `home-assistant` app → `home-assistant` HelmRelease)

## 📝 YAML Standards

### 1. Schema Declarations
Every YAML file MUST start with appropriate schema:

```yaml
---
# yaml-language-server: $schema=<appropriate-schema-url>
```

**Schema URLs by file type:**
- **Flux Kustomizations**: `https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/kustomization-kustomize-v1.json`
- **App Template HelmReleases**: `https://raw.githubusercontent.com/bjw-s/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json`
- **System HelmReleases**: `https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/helmrelease-helm-v2.json`
- **Kustomizations**: `https://json.schemastore.org/kustomization`

### 2. Document Structure
```yaml
---
# Schema declaration (required)
# yaml-language-server: $schema=<schema-url>

# Resource definition
apiVersion: <api-version>
kind: <kind>
metadata:
  name: <name>
  namespace: <namespace>  # if applicable
spec:
  # Spec content
```

### 3. Formatting Rules
- **Indentation**: 2 spaces (never tabs)
- **Line Length**: Prefer ≤80 characters (exceptions allowed for URLs/paths)
- **Trailing Spaces**: Not allowed
- **File Ending**: Single newline

## 🎛️ Flux Kustomization Standards

### Template Structure
```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/kustomization-kustomize-v1.json
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app <app-name>
  namespace: flux-system
  labels:                                    # Optional: for substitution
    substitution.flux.home.arpa/enabled: "true"
spec:
  targetNamespace: <namespace>               # Required
  commonMetadata:                            # Required
    labels:
      app.kubernetes.io/name: *app
  dependsOn:                                 # Optional: based on requirements
    - name: <dependency-name>
  path: ./kubernetes/apps/<namespace>/<app-name>/app
  prune: true                                # Default: true
  sourceRef:
    kind: GitRepository
    name: home-kubernetes
  wait: false                                # Default: false (true only if required)
  interval: 30m                              # Standard: 30m
  retryInterval: 1m                          # Required: 1m
  timeout: 5m                                # Standard: 5m (10m for complex apps)
  healthChecks:                              # Optional: for critical apps
    - apiVersion: helm.toolkit.fluxcd.io/v2beta2
      kind: HelmRelease
      name: <app-name>
      namespace: <namespace>
  postBuild:                                 # Optional: for substitution
    substitute:
      APP: *app
      VOLSYNC_CAPACITY: <size>               # If using VolSync
```

### Required Properties
All Flux Kustomizations MUST include:
- `targetNamespace`
- `commonMetadata.labels.app.kubernetes.io/name`
- `retryInterval: 1m`

### Property Order
1. `targetNamespace`
2. `commonMetadata`
3. `dependsOn` (if applicable)
4. `path`
5. `prune`
6. `sourceRef`
7. `wait`
8. `interval`
9. `retryInterval`
10. `timeout`
11. `healthChecks` (if applicable)
12. `postBuild` (if applicable)

## 🎨 HelmRelease Standards

### App Template Pattern (bjw-s)
```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <app-name>
spec:
  interval: 10m
  chart:
    spec:
      chart: app-template
      version: 3.5.1
      sourceRef:
        kind: HelmRepository
        name: bjw-s
        namespace: flux-system
  values:
    controllers:
      <app-name>:
        # Controller configuration
    # Additional app-template values
```

### System Chart Pattern
```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/helmrelease-helm-v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: <chart-name>
spec:
  interval: 10m
  chart:
    spec:
      chart: <chart-name>
      version: <version>
      sourceRef:
        kind: HelmRepository
        name: <repo-name>
        namespace: flux-system
  values:
    # Chart-specific values
```

## 📦 Kustomization Standards

### Namespace-Level Kustomization
```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  # Prerequisites first
  - ./namespace.yaml
  # Applications in alphabetical order
  - ./app-a/ks.yaml
  - ./app-b/ks.yaml
  - ./app-c/ks.yaml
```

### App-Level Kustomization
```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: <namespace>
resources:
  # Core resources first
  - ./helmrelease.yaml
  # Supporting resources
  - ./externalsecret.yaml    # if applicable
  - ./rbac.yaml             # if applicable
  # Config resources last
  - ./config/               # if applicable
```

## 🔧 Automation & Validation

### Pre-commit Hooks
Install and configure pre-commit hooks:
```bash
# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# Run manually
pre-commit run --all-files
```

### Task Commands
```bash
# Validate everything
task validate:all

# Run consistency checks
task validate:consistency

# Fix common issues
task maintain:consistency
```

### Validation Scripts
- `scripts/validate-consistency.sh` - Comprehensive consistency checking
- `scripts/fix-schemas.sh` - Automated schema fixes
- `scripts/fix-timeout-format.sh` - YAML formatting fixes

## ❌ Common Anti-Patterns

### DON'T
```yaml
# Missing schema
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization

# Malformed timeout
retryInterval: 1m  timeout: 5m

# Missing required properties
spec:
  path: ./some/path
  # Missing targetNamespace, commonMetadata, retryInterval

# Inconsistent naming
metadata:
  name: MyApp-Name_inconsistent

# Commented resources (remove instead)
resources:
  - ./app-a/ks.yaml
  # - ./disabled-app/ks.yaml  # DON'T: Remove entirely
```

### DO
```yaml
# Proper schema
---
# yaml-language-server: $schema=<appropriate-schema>
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization

# Proper formatting
retryInterval: 1m
timeout: 5m

# All required properties
spec:
  targetNamespace: namespace
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  retryInterval: 1m
  # ... other properties

# Consistent naming
metadata:
  name: &app my-app-name

# Clean resources
resources:
  - ./app-a/ks.yaml
  - ./app-b/ks.yaml
```

## 🚀 Quick Reference

### New Application Checklist
- [ ] Create directory: `kubernetes/apps/<namespace>/<app-name>/`
- [ ] Add Flux Kustomization: `ks.yaml` with all required properties
- [ ] Add app kustomization: `app/kustomization.yaml`
- [ ] Add HelmRelease: `app/helmrelease.yaml` with appropriate schema
- [ ] Update namespace kustomization to include new app
- [ ] Run validation: `task validate:consistency`
- [ ] Test deployment: `task validate:flux`

### Schema Quick Reference
| File Type | Schema URL |
|-----------|------------|
| Flux Kustomization | `https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/kustomization-kustomize-v1.json` |
| App Template HelmRelease | `https://raw.githubusercontent.com/bjw-s/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json` |
| System HelmRelease | `https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/helmrelease-helm-v2.json` |
| Kustomization | `https://json.schemastore.org/kustomization` |

---

**Maintained by:** Repository Consistency Team
**Last Updated:** $(date)
**Validation Status:** ✅ 100% Compliant
