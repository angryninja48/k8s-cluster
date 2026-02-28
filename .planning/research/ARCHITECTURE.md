# Architecture Research

**Domain:** Persistent multi-workspace application deployment on Flux GitOps Kubernetes cluster
**Researched:** 2026-03-01
**Confidence:** HIGH — derived directly from existing cluster conventions and real app examples

---

## Standard Architecture

### System Overview

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Git Repository (Source of Truth)                │
│  kubernetes/apps/opencode/                                              │
│  ├── namespace.yaml         ← Namespace (deployed first, prune:off)    │
│  ├── kustomization.yaml     ← Namespace aggregator                     │
│  ├── opencode-flux/ks.yaml  ← Flux Kustomization for flux workspace    │
│  └── opencode-ha/ks.yaml    ← Flux Kustomization for HA workspace      │
└──────────────────────────┬──────────────────────────────────────────────┘
                           │ Flux polls (30m) / task reconcile
                           ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                    Flux CD (flux-system namespace)                      │
│                                                                         │
│  apps.yaml ──► namespace/kustomization.yaml ──► opencode-flux/ks.yaml  │
│                                             └──► opencode-ha/ks.yaml   │
│                                                                         │
│  Each ks.yaml:                                                          │
│    dependsOn: [external-secrets-stores, rook-ceph-cluster]             │
│    path: ./kubernetes/apps/opencode/<name>/app                         │
│    postBuild.substitute: APP, VOLSYNC_CAPACITY                         │
└──────────────────────────┬──────────────────────────────────────────────┘
                           │ Flux applies resources to cluster
                           ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                      opencode namespace (Kubernetes)                    │
│                                                                         │
│  ┌──────────────────────────┐  ┌──────────────────────────┐            │
│  │  opencode-flux workspace │  │  opencode-ha workspace   │            │
│  │  ─────────────────────── │  │  ─────────────────────── │            │
│  │  ExternalSecret          │  │  ExternalSecret          │            │
│  │    → opencode-flux-secret│  │    → opencode-ha-secret  │            │
│  │  PVC (5Gi, ceph-block)   │  │  PVC (5Gi, ceph-block)   │            │
│  │  HelmRelease (app-tmpl)  │  │  HelmRelease (app-tmpl)  │            │
│  │    initContainer:        │  │    initContainer:        │            │
│  │      git clone / seed    │  │      git clone / seed    │            │
│  │    container: opencode   │  │    container: opencode   │            │
│  └──────────────────────────┘  └──────────────────────────┘            │
│                                                                         │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                   Envoy Gateway (network ns)                     │  │
│  │  HTTPRoute: flux.opencode.angryninja.cloud → opencode-flux svc   │  │
│  │  HTTPRoute: ha.opencode.angryninja.cloud   → opencode-ha svc     │  │
│  │  TLS: wildcard cert from cert-manager (already provisioned)      │  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────────────┐
│                     Persistent Storage (Rook Ceph)                      │
│                                                                         │
│  PVC: opencode-flux   (5Gi, ReadWriteOnce, ceph-block)                 │
│    /workspace/        ← cloned k8s-cluster repo                        │
│    ~/.local/share/opencode/auth.json  ← GitHub Copilot OAuth           │
│                                                                         │
│  PVC: opencode-ha     (5Gi, ReadWriteOnce, ceph-block)                 │
│    /workspace/        ← cloned home-assistant-config repo              │
│    ~/.local/share/opencode/auth.json  ← GitHub Copilot OAuth           │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Component Responsibilities

| Component | Responsibility | Lives In |
|-----------|---------------|----------|
| `namespace.yaml` | Creates `opencode` namespace with `prune: disabled` label | `kubernetes/apps/opencode/` |
| `kustomization.yaml` (namespace) | Aggregates namespace.yaml + both ks.yaml files | `kubernetes/apps/opencode/` |
| `opencode-flux/ks.yaml` | Flux Kustomization meta-resource for flux workspace | `kubernetes/apps/opencode/opencode-flux/` |
| `opencode-ha/ks.yaml` | Flux Kustomization meta-resource for HA workspace | `kubernetes/apps/opencode/opencode-ha/` |
| `app/kustomization.yaml` | Kustomize resource aggregator listing all resources | `kubernetes/apps/opencode/<name>/app/` |
| `app/externalsecret.yaml` | Syncs secrets from Doppler via ClusterSecretStore | `kubernetes/apps/opencode/<name>/app/` |
| `app/ocirepository.yaml` | References bjw-s app-template chart from ghcr.io | `kubernetes/apps/opencode/<name>/app/` |
| `app/helmrelease.yaml` | Deployment definition: init container + main container + route + PVC | `kubernetes/apps/opencode/<name>/app/` |
| Init container (`alpine/git`) | Idempotent git clone on first boot; skips if `.git` already present | Inside HelmRelease values |
| Main container (`opencode`) | Runs `opencode web --hostname 0.0.0.0 --port 4096` | Inside HelmRelease values |
| PVC (`opencode-flux` / `opencode-ha`) | Persists workspace dir + auth.json across pod restarts | Created via VolSync template OR inline claim |
| ExternalSecret → K8s Secret | Bridges Doppler secrets into namespace-scoped Kubernetes Secret | `opencode` namespace |
| `route:` in HelmRelease values | bjw-s app-template generates HTTPRoute to Envoy Gateway | Rendered by helm-controller |

---

## Recommended Project Structure

```
kubernetes/apps/opencode/
├── namespace.yaml                  # Namespace definition (prune: disabled)
├── kustomization.yaml              # Lists: namespace.yaml, opencode-flux/ks.yaml, opencode-ha/ks.yaml
├── opencode-flux/
│   ├── ks.yaml                     # Flux Kustomization (targetNamespace: opencode)
│   └── app/
│       ├── kustomization.yaml      # Lists: externalsecret.yaml, ocirepository.yaml, helmrelease.yaml
│       ├── externalsecret.yaml     # Syncs GITHUB_PAT, SERVER_PASSWORD, COPILOT_AUTH_JSON
│       ├── ocirepository.yaml      # app-template OCI chart reference
│       └── helmrelease.yaml        # Full workload definition (init + app + route + persistence)
└── opencode-ha/
    ├── ks.yaml                     # Flux Kustomization (targetNamespace: opencode)
    └── app/
        ├── kustomization.yaml
        ├── externalsecret.yaml
        ├── ocirepository.yaml
        └── helmrelease.yaml
```

### Structure Rationale

- **Separate `opencode-flux/` and `opencode-ha/` directories:** Two independent apps with separate PVCs, secrets, repos, and Flux reconciliation lifecycles. Mirrors how `home-assistant` and `home-assistant-v2` coexist in the `home` namespace.
- **`ks.yaml` at app root (not inside `app/`):** Convention: `ks.yaml` is the Flux Kustomization pointer; `app/` is what it points to. See every existing app.
- **`ocirepository.yaml` inside `app/`:** bjw-s app-template is referenced per-app as an OCIRepository (not the global HelmRepository). See `home-assistant-v2` and `openwebui` for confirmation.
- **No standalone `pvc.yaml`:** Use VolSync `claim.yaml` template if backups are needed. Without VolSync, define PVC inline in helmrelease `persistence:` using `existingClaim` pointing to a PVC created via the template — OR skip VolSync and use a raw PVC in `app/` (see `mosquitto/app/data-pvc.yaml` pattern). For initial deploy, a simple inline PVC in the helmrelease `persistence.config` with `accessModes: [ReadWriteOnce]` and `size: 5Gi` is simplest.

---

## Architectural Patterns

### Pattern 1: Namespace Creation with Prune Guard

**What:** Namespace defined in `namespace.yaml` at the namespace directory root, with label `kustomize.toolkit.fluxcd.io/prune: disabled`. Listed first in the namespace `kustomization.yaml` before any app `ks.yaml` files.

**When to use:** Always. Every namespace follows this pattern.

**Why it matters:** The `prune: disabled` label prevents Flux from ever deleting the namespace itself during reconciliation, even if apps within it are removed. Protects all workloads.

**Example:**
```yaml
# kubernetes/apps/opencode/namespace.yaml
---
apiVersion: v1
kind: Namespace
metadata:
  name: opencode
  labels:
    kustomize.toolkit.fluxcd.io/prune: disabled
```

```yaml
# kubernetes/apps/opencode/kustomization.yaml
---
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ./namespace.yaml          # ← namespace first
  - ./opencode-flux/ks.yaml
  - ./opencode-ha/ks.yaml
```

---

### Pattern 2: ks.yaml → app/ Separation

**What:** The Flux Kustomization (`ks.yaml`) is a meta-resource in `flux-system` namespace that points Flux at the `app/` directory. The actual Kubernetes resources (HelmRelease, ExternalSecret, etc.) live inside `app/`. These are entirely separate concerns.

**When to use:** Always. Every app uses this two-level structure.

**Key properties in ks.yaml:**
- `metadata.namespace: flux-system` — Flux Kustomizations always live here
- `spec.targetNamespace: opencode` — where resources are deployed
- `spec.dependsOn` — blocking dependencies (see build order below)
- `spec.postBuild.substitute` — injects `APP` and `VOLSYNC_CAPACITY` into app resources

**Example:**
```yaml
# kubernetes/apps/opencode/opencode-flux/ks.yaml
---
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: &app opencode-flux
  namespace: flux-system
spec:
  targetNamespace: opencode
  commonMetadata:
    labels:
      app.kubernetes.io/name: *app
  dependsOn:
    - name: external-secrets-stores
    - name: rook-ceph-cluster
  path: ./kubernetes/apps/opencode/opencode-flux/app
  prune: true
  sourceRef:
    kind: GitRepository
    name: home-kubernetes
  healthChecks:
    - apiVersion: helm.toolkit.fluxcd.io/v2
      kind: HelmRelease
      name: opencode-flux
      namespace: opencode
  interval: 30m
  retryInterval: 1m
  timeout: 10m
  postBuild:
    substitute:
      APP: *app
      VOLSYNC_CAPACITY: 5Gi
```

---

### Pattern 3: Init Container for Idempotent Repo Bootstrap

**What:** An `initContainer` using `alpine/git` runs before the main OpenCode container. It checks whether the PVC already contains a `.git` directory. If yes, optionally pulls; if no, clones. This is the canonical pattern for the cluster — see `home-assistant-v2` for the exact idiom.

**When to use:** Any app that needs a git repository pre-populated on a PVC before the main process starts.

**Critical details:**
- The init container mounts the **same PVC** as the main container (via `advancedMounts` in bjw-s app-template)
- The SSH deploy key is mounted from a Secret via `advancedMounts` with `subPath: GIT_DEPLOY_KEY` and `defaultMode: 0400`
- The init container uses `runAsUser: 0` (root) to handle SSH key permissions; main container uses non-root
- The init container also seeds `~/.local/share/opencode/auth.json` from the Secret if the file doesn't exist yet (avoid re-auth on every restart)

**Example skeleton:**
```yaml
initContainers:
  init-workspace:
    image:
      repository: alpine/git
      tag: latest
    command:
      - sh
      - -c
      - |
        set -e
        cp /secrets/github-pat /tmp/ssh-key
        chmod 600 /tmp/ssh-key
        export HOME=/tmp
        export GIT_SSH_COMMAND="ssh -i /tmp/ssh-key -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no"

        if [ -d /workspace/.git ]; then
          echo "Repo already cloned, skipping."
        else
          echo "Cloning repo..."
          git clone git@github.com:owner/repo.git /workspace
        fi

        # Seed auth.json if not present (Copilot OAuth)
        AUTH_DIR="/workspace/.local/share/opencode"
        mkdir -p "$AUTH_DIR"
        if [ ! -f "$AUTH_DIR/auth.json" ]; then
          cp /secrets/auth-json "$AUTH_DIR/auth.json"
          chmod 600 "$AUTH_DIR/auth.json"
        fi
    securityContext:
      runAsUser: 0
      runAsGroup: 0
      allowPrivilegeEscalation: false
```

---

### Pattern 4: ExternalSecret → Kubernetes Secret → Pod envFrom

**What:** All secrets are sourced from Doppler via the `doppler-secrets` ClusterSecretStore. An `ExternalSecret` resource in `opencode` namespace creates a namespaced Kubernetes Secret. The HelmRelease references that Secret via `secretRef` in `envFrom` or as a mounted volume.

**When to use:** Every secret in this cluster. Never commit plaintext secrets. The SOPS pattern is cluster-level (vars); app-level secrets use Doppler ExternalSecrets.

**Data flow:**
```
Doppler (external)
  → ClusterSecretStore "doppler-secrets" (external-secrets ns)
    → ExternalSecret (opencode ns)
      → Kubernetes Secret (opencode ns)
        → Pod envFrom / volumeMount
```

**For OpenCode, the secret needs:**
- `GITHUB_PAT` — SSH deploy key (PEM format) for git clone
- `SERVER_PASSWORD` — OpenCode web UI password
- `COPILOT_AUTH_JSON` — serialized `auth.json` content for GitHub Copilot OAuth token seeding

**Example:**
```yaml
# app/externalsecret.yaml
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: opencode-flux-secret
  namespace: opencode
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: doppler-secrets
  target:
    name: opencode-flux-secret
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        GIT_DEPLOY_KEY: "{{ .OPENCODE_FLUX_DEPLOY_KEY }}"
        SERVER_PASSWORD: "{{ .OPENCODE_SERVER_PASSWORD }}"
        COPILOT_AUTH_JSON: "{{ .OPENCODE_COPILOT_AUTH_JSON }}"
  data:
    - remoteRef:
        key: OPENCODE_FLUX_DEPLOY_KEY
      secretKey: OPENCODE_FLUX_DEPLOY_KEY
    - remoteRef:
        key: OPENCODE_SERVER_PASSWORD
      secretKey: OPENCODE_SERVER_PASSWORD
    - remoteRef:
        key: OPENCODE_COPILOT_AUTH_JSON
      secretKey: OPENCODE_COPILOT_AUTH_JSON
```

---

### Pattern 5: Envoy Gateway HTTPRoute via bjw-s app-template `route:` Values

**What:** The bjw-s app-template generates an `HTTPRoute` resource when `route:` is configured in HelmRelease values. This is the cluster-standard pattern — NOT a separate `httproute.yaml` file. The `route:` block references an Envoy Gateway by name and namespace, and specifies hostnames and backend service identifiers.

**When to use:** All apps exposed via HTTPS. Internal-only tools use `envoy-internal`; externally-accessible tools use `envoy-external`. OpenCode should use `envoy-internal` (personal tool, not public).

**How TLS works:** The Envoy Gateway `envoy-internal` listener already has a wildcard TLS certificate attached (`${SECRET_DOMAIN/./-}-production-tls`) from cert-manager. Individual apps do NOT need their own Certificate resources — the wildcard covers `*.angryninja.cloud`.

**Example (in helmrelease.yaml values):**
```yaml
service:
  app:
    controller: *app
    ports:
      http:
        port: 4096
        appProtocol: kubernetes.io/ws   # important for WebSocket support

route:
  app:
    enabled: true
    parentRefs:
      - name: envoy-internal
        namespace: network
        sectionName: https
    hostnames:
      - "flux.opencode.${SECRET_DOMAIN}"   # substituted at reconcile time
    rules:
      - backendRefs:
          - identifier: app
            port: 4096
```

**Note:** The `appProtocol: kubernetes.io/ws` annotation on the Service port is important — OpenCode uses WebSockets for the terminal/session interface.

---

### Pattern 6: PVC Persistence with VolSync Template

**What:** PVCs are defined via the VolSync template referenced in `app/kustomization.yaml`. The template uses `${APP}` and `${VOLSYNC_CAPACITY}` substituted by `postBuild.substitute` in `ks.yaml`. The HelmRelease references the resulting PVC by name via `existingClaim: *app`.

**When to use:** Any stateful app needing backup capability. For OpenCode, VolSync is strongly recommended since `auth.json` and workspace state must survive node failures.

**Template reference in `app/kustomization.yaml`:**
```yaml
resources:
  - ./externalsecret.yaml
  - ./ocirepository.yaml
  - ./helmrelease.yaml
  - ../../../../templates/volsync   # ← adds claim.yaml + ReplicationSource
```

**PVC reference in HelmRelease:**
```yaml
persistence:
  config:
    existingClaim: *app   # resolves to "opencode-flux"
    advancedMounts:
      opencode-flux:
        app:
          - path: /home/user   # main container home dir
        init-workspace:
          - path: /home/user   # init container must share same mount
```

---

## Data Flow

### GitOps Reconciliation Flow (Steady State)

```
Git push to main
    ↓
Flux GitRepository polls (30m or task reconcile)
    ↓
apps.yaml discovers kubernetes/apps/opencode/kustomization.yaml
    ↓
namespace kustomization.yaml aggregates:
  └── namespace.yaml → applied immediately (Namespace resource)
  └── opencode-flux/ks.yaml → Flux Kustomization created in flux-system
  └── opencode-ha/ks.yaml   → Flux Kustomization created in flux-system
    ↓
Each Flux Kustomization (after dependsOn satisfied):
    ↓
SOPS decrypt (if applicable) + postBuild.substitute APP/VOLSYNC_CAPACITY
    ↓
app/kustomization.yaml builds resources:
  ├── externalsecret.yaml → ExternalSecret applied
  ├── ocirepository.yaml  → OCIRepository applied
  ├── helmrelease.yaml    → HelmRelease applied
  └── ../../../../templates/volsync → PVC + ReplicationSource applied
    ↓
external-secrets-operator reconciles ExternalSecret:
  Doppler → ClusterSecretStore → Kubernetes Secret (opencode namespace)
    ↓
helm-controller reconciles HelmRelease:
  OCIRepository → chart fetched from ghcr.io/bjw-s-labs/helm/app-template
  chart rendered with values → Deployment + Service + HTTPRoute generated
    ↓
Kubernetes scheduler creates Pod:
  1. PVC bound (Rook Ceph assigns block volume)
  2. Secrets mounted (from ExternalSecret-created Secret)
  3. Init container runs:
     a. Checks PVC for existing .git → clone if absent
     b. Seeds auth.json from Secret if absent
  4. Main container starts: opencode web --hostname 0.0.0.0 --port 4096
    ↓
Envoy Gateway routes traffic:
  flux.opencode.angryninja.cloud → opencode-flux Service → Pod:4096
  ha.opencode.angryninja.cloud   → opencode-ha Service   → Pod:4096
```

### Secret Flow (Detail)

```
Doppler (external secret store)
  OPENCODE_FLUX_DEPLOY_KEY
  OPENCODE_HA_DEPLOY_KEY
  OPENCODE_SERVER_PASSWORD
  OPENCODE_COPILOT_AUTH_JSON
       ↓
ClusterSecretStore "doppler-secrets" (external-secrets namespace)
  watches Doppler API
       ↓
ExternalSecret "opencode-flux-secret" (opencode namespace)
ExternalSecret "opencode-ha-secret"   (opencode namespace)
  each creates a namespaced Kubernetes Secret
       ↓
HelmRelease init container mounts Secret as volume (subPath: GIT_DEPLOY_KEY)
HelmRelease main container references Secret via envFrom (SERVER_PASSWORD → env)
```

---

## Build Order (Dependency Chain)

Flux `dependsOn` enforces this order. Resources at each level cannot start until the prior level is healthy.

```
Level 0: Bootstrap (pre-existing, not part of this project)
  ├── flux-system:flux               — Flux CD itself
  ├── rook-ceph:rook-ceph-cluster    — Ceph storage
  └── external-secrets:external-secrets-stores  — Doppler ClusterSecretStore

Level 1: Namespace (no dependencies, no healthChecks needed)
  └── opencode Namespace
      (created by namespace/kustomization.yaml directly, before ks.yaml files)

Level 2: App Kustomizations (depend on Level 0)
  ├── opencode-flux Flux Kustomization
  │     dependsOn: external-secrets-stores, rook-ceph-cluster
  └── opencode-ha Flux Kustomization
        dependsOn: external-secrets-stores, rook-ceph-cluster

Level 3: Resources applied by each Flux Kustomization
  ├── ExternalSecret (reconciled by external-secrets-operator)
  │     → Kubernetes Secret created (must exist before Pod starts)
  ├── OCIRepository (chart source)
  ├── PVC / VolSync claim.yaml
  │     → Rook Ceph provisions block volume
  └── HelmRelease → Deployment
        dependsOn (helm level): rook-ceph-cluster (for PVC provisioner)

Level 4: Pod execution order (Kubernetes-enforced)
  1. PVC bound (storage provisioned)
  2. Secrets mounted (ExternalSecret must be Ready first)
  3. Init container: git clone + auth.json seed
  4. Main container: opencode web server starts

Level 5: Routing (after Deployment is healthy)
  └── Envoy Gateway HTTPRoute becomes active
        (created by helm-controller rendering HelmRelease values)
```

### What depends on what (explicit)

| Resource | Depends On | Why |
|----------|------------|-----|
| `ks.yaml` `dependsOn: external-secrets-stores` | `external-secrets-stores` Flux Kustomization | ExternalSecret CRD + ClusterSecretStore must exist before ExternalSecret can reconcile |
| `ks.yaml` `dependsOn: rook-ceph-cluster` | `rook-ceph-cluster` Flux Kustomization | ceph-block StorageClass must exist before PVC can be provisioned |
| HelmRelease `dependsOn: rook-ceph-cluster` | Same as above | Belt-and-suspenders: helm-controller won't install until Ceph ready |
| Pod init container | PVC bound + Secret created | Kubernetes init container semantics — waits for volumes to mount |
| Pod main container | Init container exit 0 | Kubernetes guarantees init containers complete before app container starts |
| HTTPRoute | Service exists | Envoy Gateway: route target must be resolvable |

---

## Integration Points

### External Services

| Service | Integration Pattern | Notes |
|---------|---------------------|-------|
| Envoy Gateway (`envoy-internal`) | `route:` in bjw-s app-template values → generates HTTPRoute | Already handles wildcard TLS; no Certificate needed per-app |
| Rook Ceph (`ceph-block` StorageClass) | PVC `storageClassName: ceph-block` (via VolSync template default) | ReadWriteOnce; one pod per PVC |
| Doppler (via external-secrets) | ExternalSecret → ClusterSecretStore `doppler-secrets` | Secrets must be added to Doppler project before ExternalSecret reconciles |
| GitHub (private repos) | SSH deploy key mounted to init container | Deploy key added to each repo as read-only key |
| GitHub Copilot OAuth | `auth.json` seeded from Secret on first boot; persisted on PVC | Re-auth only needed if token expires; survives pod restarts |

### Internal Boundaries

| Boundary | Communication | Notes |
|----------|---------------|-------|
| Init container ↔ Main container | Shared PVC mount (no network) | Init writes to PVC; main reads from same PVC |
| Init container ↔ Secret | Volume mount (`subPath`) | SSH key copied to `/tmp`, chmod 600 before use |
| Main container ↔ Envoy Gateway | HTTP/WebSocket on port 4096 | `appProtocol: kubernetes.io/ws` required on Service port |
| ExternalSecret ↔ HelmRelease | Secret name referenced in `secretRef` and `volumeMount` | Secret must be created before Pod starts (external-secrets-stores dependsOn enforces this) |
| opencode-flux ↔ opencode-ha | None (fully independent) | Two separate Deployments, Secrets, PVCs — no shared state |

---

## Anti-Patterns

### Anti-Pattern 1: Inline Secrets in HelmRelease or kustomization.yaml

**What people do:** Hard-code passwords or tokens in `helmrelease.yaml` values or environment variables.

**Why it's wrong:** Committed to Git in plaintext. Violates cluster-wide policy. Fails pre-commit `validate-consistency.sh` checks.

**Do this instead:** All secrets via ExternalSecret → Doppler. Reference by name in `secretRef` or as a volume mount. Keep Doppler as the single source of truth.

---

### Anti-Pattern 2: Creating a Standalone HTTPRoute YAML File

**What people do:** Create a separate `httproute.yaml` in `app/` with a hardcoded HTTPRoute resource.

**Why it's wrong:** The bjw-s app-template generates the HTTPRoute from the `route:` values block. Adding a standalone file creates a duplicate resource conflict. Every existing app in the cluster uses the `route:` values block pattern (see `home-assistant`, `home-assistant-v2`, `openwebui`).

**Do this instead:** Configure `route:` inside HelmRelease values. Let helm-controller generate the HTTPRoute.

---

### Anti-Pattern 3: Requesting a Certificate per App

**What people do:** Create a `Certificate` resource (cert-manager) for each app subdomain.

**Why it's wrong:** The cluster already has a wildcard certificate (`*.angryninja.cloud`) provisioned in `network` namespace, attached to both `envoy-external` and `envoy-internal` Gateway listeners. Per-app certificates are unnecessary and create DNS-01 challenge overhead.

**Do this instead:** Use the existing wildcard. Reference `sectionName: https` in the `parentRefs` of the route. The wildcard TLS is already terminated at the Gateway.

---

### Anti-Pattern 4: Sharing a PVC Between the Two Workspaces

**What people do:** Mount one PVC into both `opencode-flux` and `opencode-ha` deployments.

**Why it's wrong:** `ReadWriteOnce` PVCs can only be mounted by one node at a time (Rook Ceph block). Multiple pods on different nodes will fail to attach. Additionally, the two workspaces have different repos and different auth contexts — mixing them breaks isolation.

**Do this instead:** One PVC per workspace (`opencode-flux` and `opencode-ha`), each 5Gi, each bound to its own deployment.

---

### Anti-Pattern 5: Not Using `advancedMounts` for Shared PVC Between Init and App Containers

**What people do:** Use `globalMounts` for the PVC, which mounts it at the same path in all containers including init containers.

**Why it's wrong:** For OpenCode, the init container runs as root and may need a different mount path or behavior than the main container. `advancedMounts` allows per-container mount targeting. See `home-assistant-v2` — it uses `advancedMounts` to mount both the PVC and the SSH key secret to only the containers that need them.

**Do this instead:** Use `advancedMounts` keyed by container name, so each container gets explicit mounts.

---

## Concrete File Skeleton

The following is the minimal viable file set for one workspace (repeat for the other, changing `flux` to `ha` and the repo URL):

```
kubernetes/apps/opencode/
├── namespace.yaml
│   # Namespace: opencode, label prune:disabled
│
├── kustomization.yaml
│   # resources: [namespace.yaml, opencode-flux/ks.yaml, opencode-ha/ks.yaml]
│
├── opencode-flux/
│   ├── ks.yaml
│   │   # Flux Kustomization in flux-system
│   │   # targetNamespace: opencode
│   │   # dependsOn: [external-secrets-stores, rook-ceph-cluster]
│   │   # path: ./kubernetes/apps/opencode/opencode-flux/app
│   │   # postBuild.substitute: APP: opencode-flux, VOLSYNC_CAPACITY: 5Gi
│   │
│   └── app/
│       ├── kustomization.yaml
│       │   # resources: [externalsecret.yaml, ocirepository.yaml, helmrelease.yaml]
│       │   # + optionally: ../../../../templates/volsync
│       │
│       ├── externalsecret.yaml
│       │   # ExternalSecret: opencode-flux-secret
│       │   # secretStoreRef: doppler-secrets
│       │   # keys: GIT_DEPLOY_KEY, SERVER_PASSWORD, COPILOT_AUTH_JSON
│       │
│       ├── ocirepository.yaml
│       │   # OCIRepository: opencode-flux
│       │   # url: oci://ghcr.io/bjw-s-labs/helm/app-template
│       │   # tag: 4.4.0 (or current)
│       │
│       └── helmrelease.yaml
│           # HelmRelease: opencode-flux
│           # chartRef: OCIRepository/opencode-flux
│           # dependsOn: rook-ceph-cluster
│           # values:
│           #   controllers.opencode-flux:
│           #     initContainers.init-workspace: (git clone + auth seed)
│           #     containers.app: opencode web --hostname 0.0.0.0 --port 4096
│           #   service.app: port 4096, appProtocol kubernetes.io/ws
│           #   route.app: parentRefs envoy-internal, host flux.opencode.${SECRET_DOMAIN}
│           #   persistence.config: existingClaim opencode-flux, advancedMounts both containers
│           #   persistence.deploy-key: secret, subPath GIT_DEPLOY_KEY, init container only
│
└── opencode-ha/
    └── [same structure, repo = home-assistant-config]
```

---

## Scaling Considerations

| Scale | Architecture Adjustments |
|-------|--------------------------|
| 1 user (current) | Single Deployment, RWO PVC, internal Envoy Gateway — fine as designed |
| Multiple users | Would need ReadWriteMany PVCs (CephFS), session multiplexing, auth layer — out of scope |
| HA for OpenCode pod | Not needed — stateless restarts with PVC persistence are sufficient |

---

## Sources

- Existing cluster apps (HIGH confidence — directly observed):
  - `kubernetes/apps/home/home-assistant-v2/` — init container + git clone + deploy key pattern
  - `kubernetes/apps/home/home-assistant/` — route: + advancedMounts + ExternalSecret pattern
  - `kubernetes/apps/ai/openwebui/` — init container + ocirepository + route: pattern
  - `kubernetes/apps/home/mosquitto/` — standalone PVC + init container pattern
  - `kubernetes/apps/network/envoy-gateway/app/envoy.yaml` — Gateway + wildcard TLS structure
  - `kubernetes/apps/network/certificates/app/production.yaml` — wildcard cert definition
  - `kubernetes/apps/external-secrets/external-secrets/ks.yaml` — external-secrets-stores Kustomization (dependency target)
- `kubernetes/flux/vars/cluster-settings.yaml` — cluster-wide variable substitution
- `.planning/PROJECT.md` — project constraints and requirements
- `.planning/codebase/ARCHITECTURE.md` — cluster architecture patterns

---
*Architecture research for: Persistent OpenCode on Kubernetes (Flux GitOps)*
*Researched: 2026-03-01*
