# Coding Conventions

**Analysis Date:** 2026-02-22

## Naming Patterns

**Files:**
- YAML files always use `.yaml` extension (never `.yml`)
- Resource files use lowercase: `helmrelease.yaml`, `kustomization.yaml`, `externalsecret.yaml`, `pvc.yaml`
- Flux Kustomization files always named `ks.yaml`
- Shell scripts use lowercase with hyphens: `validate-consistency.sh`, `fix-schemas.sh`

**Directories:**
- Use `kebab-case` for all directories: `home-assistant`, `kube-prometheus-stack`, `ingress-nginx`
- Namespace directories are lowercase: `media`, `observability`, `kube-system`, `cert-manager`
- App structure follows pattern: `<namespace>/<app-name>/ks.yaml` and `<namespace>/<app-name>/app/`

**Resources:**
- Resource names match directory names: directory `home-assistant` → HelmRelease name `home-assistant`
- Use YAML anchors for app names: `name: &app plex` then reference with `*app`
- Namespace names are lowercase single words or hyphenated: `flux-system`, `media`, `kube-system`

**Variables:**
- Global variables use SCREAMING_SNAKE_CASE: `${TIMEZONE}`, `${SECRET_DOMAIN}`, `${SVC_PLEX_ADDR}`
- Local YAML anchors use lowercase: `&app`, `&host`, `&port`, `&probes`, `&resources`

## Code Style

**Formatting:**
- Tool: None configured (no Prettier or similar)
- Indentation: 2 spaces (never tabs)
- Line length: Prefer ≤80 characters (exceptions for URLs, paths, and multi-line strings)
- Trailing whitespace: Not allowed (enforced by pre-commit hook)
- File ending: Single newline required (enforced by pre-commit hook)

**Linting:**
- Tool: yamllint (referenced but not enforced in pre-commit)
- YAML syntax validation via pre-commit hook: `check-yaml --unsafe`
- Custom consistency validation: `scripts/validate-consistency.sh`
- Schema validation: Every file must declare appropriate YAML schema

**YAML Anchors:**
- Use anchors to avoid repetition: `&app`, `&host`, `&port`, `&probes`, `&resources`
- Common pattern: `name: &app appname` then `app.kubernetes.io/name: *app`
- Probe patterns use anchors: `liveness: &probes` then `readiness: *probes`
- Resource limits use anchors: `limits: &resources` then `requests: <<: *resources`

## Import Organization

**Not applicable** - This is a YAML-based Kubernetes configuration repository. No import statements exist.

**Resource Organization:**
- Flux Kustomization (`ks.yaml`) references app directory: `path: ./kubernetes/apps/<namespace>/<app-name>/app`
- App Kustomization lists resources in order:
  1. Core resources (helmrelease.yaml, pvc.yaml)
  2. Supporting resources (externalsecret.yaml, ocirepository.yaml)
  3. Shared templates (volsync)

## Error Handling

**Patterns:**
- Flux retries on failure: `retryInterval: 1m` (required in all Flux Kustomizations)
- HelmRelease remediation strategy: `strategy: rollback` with `retries: 3`
- Health checks for critical apps using `healthChecks` in Flux Kustomization
- Cleanup on failed upgrades: `cleanupOnFail: true` in HelmRelease

**Example from `kubernetes/apps/media/plex/app/helmrelease.yaml`:**
```yaml
install:
  remediation:
    retries: 3
upgrade:
  cleanupOnFail: true
  remediation:
    strategy: rollback
    retries: 3
```

## Logging

**Framework:** None (Kubernetes/Flux native logging)

**Patterns:**
- Validation scripts log with emojis for visibility:
  - `echo "🔍 Running checks..."`
  - `echo "✅ SUCCESS: message"`
  - `echo "❌ ERROR: message" >&2`
  - `echo "ℹ️  INFO: message"`
- Shell scripts use `set -euo pipefail` for strict error handling
- Errors written to stderr using `>&2` redirection

## Comments

**When to Comment:**
- Schema declarations (required on every YAML file): `# yaml-language-server: $schema=...`
- Optional configuration sections with explanatory comments
- Rare TODO comments for setup instructions (found 1 instance in Plex helmrelease)
- Inline comments for complex or non-obvious configuration choices

**Guidelines:**
- Keep comments minimal and meaningful
- Use comments to explain "why" not "what"
- Optional/conditional sections get inline comments like `# Optional: for substitution`
- Reference external documentation when applicable

**Example from templates:**
```yaml
labels:                                    # Optional: for substitution
  substitution.flux.home.arpa/enabled: "true"
dependsOn:                                 # Optional: based on requirements
  - name: DEPENDENCY_NAME
```

## Function Design

**Not applicable** - This is a declarative YAML-based repository. No functions exist.

**Resource Design:**
- Each app follows consistent directory structure:
  ```
  <namespace>/<app-name>/
  ├── ks.yaml (Flux Kustomization)
  └── app/
      ├── kustomization.yaml
      ├── helmrelease.yaml
      └── [optional: externalsecret.yaml, pvc.yaml, ocirepository.yaml]
  ```

## Module Design

**Not applicable** - YAML resources, not modules.

**Resource Aggregation:**
- Namespace-level `kustomization.yaml` lists all apps: `- ./app-name/ks.yaml`
- App-level `kustomization.yaml` lists all resources: `- ./helmrelease.yaml`, `- ./pvc.yaml`
- Resources listed in logical order: prerequisites first, core resources, then supporting resources
- Alphabetical ordering within same priority level

## Shell Script Conventions

**File Location:**
- All scripts in `scripts/` directory
- Named descriptively: `validate-consistency.sh`, `fix-schemas.sh`, `fix-properties.sh`

**Script Structure:**
```bash
#!/bin/bash
# Description comment

set -euo pipefail  # Strict error handling

# Constants in CAPS
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ERRORS=0

# Helper functions
log_error() {
    echo "❌ ERROR: $1" >&2
    ERRORS=$((ERRORS + 1))
}

# Main logic with descriptive echo statements
echo "🔍 Running checks..."

# Exit with appropriate code
exit $ERRORS
```

**Patterns:**
- Use functions for reusable logic: `log_error()`, `log_success()`, `add_common_metadata()`
- Count errors and exit with count: `exit $ERRORS`
- Use descriptive emoji-prefixed messages for user feedback
- Find commands piped through processing: `find ... | while read file; do`

## Task Definitions

**Framework:** Task (Taskfile.yaml)

**Naming:**
- Tasks use colon-separated namespaces: `validate:all`, `validate:consistency`, `bootstrap:talos`
- Descriptive names indicating action: `reconcile`, `validate:yaml`, `fix:schemas`, `maintain:consistency`

**Structure from `Taskfile.yaml`:**
```yaml
task-name:
  desc: Human-readable description
  cmd: command to execute
  preconditions:
    - test -f {{.KUBECONFIG}}
    - which tool-name
```

## Validation Automation

**Pre-commit Hooks (`/.pre-commit-config.yaml`):**
- `trailing-whitespace` - Remove trailing spaces
- `end-of-file-fixer` - Ensure single newline at EOF
- `check-yaml --unsafe` - Validate YAML syntax
- `check-added-large-files` - Prevent large file commits
- `check-merge-conflict` - Detect merge markers
- Custom: `scripts/validate-consistency.sh` - Repository consistency validation

**Consistency Requirements (enforced by `scripts/validate-consistency.sh`):**
1. All Flux Kustomizations must have schema: `https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/kustomization-kustomize-v1.json`
2. All app kustomizations must have schema: `https://json.schemastore.org/kustomization`
3. All Flux Kustomizations must have: `targetNamespace`, `retryInterval`, `commonMetadata`
4. No commented applications in kustomization.yaml files
5. HelmRelease schemas must be current (no deprecated `bjw-s-labs` or `helm-v2beta2`)

## YAML Schema Standards

**Required Header Format:**
```yaml
---
# yaml-language-server: $schema=<schema-url>
```

**Schema URLs by File Type:**
- Flux Kustomization (`ks.yaml`): `https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/kustomization-kustomize-v1.json`
- App-template HelmRelease: `https://raw.githubusercontent.com/bjw-s/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json`
- System HelmRelease: `https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/helmrelease-helm-v2.json`
- Kustomization: `https://json.schemastore.org/kustomization`
- ExternalSecret: `https://kubernetes-schemas.pages.dev/external-secrets.io/externalsecret_v1beta1.json`

## Variable Substitution

**Global Variables:**
- Defined in `kubernetes/flux/vars/cluster-settings.yaml` and `kubernetes/flux/vars/cluster-secrets.sops.yaml`
- Referenced in manifests as `${VAR_NAME}`
- Common variables: `${TIMEZONE}`, `${SECRET_DOMAIN}`, `${SECRET_LAN_CIDR}`

**Service-Specific Variables:**
- Per-service variables like `${SVC_PLEX_ADDR}`, `${SVC_UNIFI_ADDR}`
- Substitution enabled via label: `substitution.flux.home.arpa/enabled: "true"`

**App-Specific Substitution:**
- Defined in Flux Kustomization `postBuild.substitute` section:
```yaml
postBuild:
  substitute:
    APP: *app
    VOLSYNC_CAPACITY: 20Gi
```

## Configuration Patterns

**Probe Configuration:**
```yaml
probes:
  liveness: &probes
    enabled: true
    custom: true
    spec:
      httpGet:
        path: /health
        port: &port 8080
      initialDelaySeconds: 0
      periodSeconds: 10
      timeoutSeconds: 1
      failureThreshold: 3
  readiness: *probes
  startup:
    enabled: false
```

**Resource Configuration:**
```yaml
resources:
  requests:
    cpu: 100m
    memory: 512Mi
  limits:
    memory: 1Gi
```

**Security Context:**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 568
  runAsGroup: 568
  fsGroup: 568
  fsGroupChangePolicy: OnRootMismatch
  supplementalGroups: [44, 10000]
  seccompProfile: { type: RuntimeDefault }
```

**Container Security:**
```yaml
securityContext:
  allowPrivilegeEscalation: false
  readOnlyRootFilesystem: true
  capabilities: { drop: ["ALL"] }
```

---

*Convention analysis: 2026-02-22*
