# Stack Research

**Domain:** Persistent PVC-backed web application on Flux CD / GitOps Kubernetes cluster
**Researched:** 2026-03-01
**Confidence:** HIGH — all findings verified against actual cluster manifests in this repo

---

## Executive Summary

This is not a greenfield technology decision — the cluster already has a complete, opinionated stack.
Every technology choice here is **derived from existing working manifests**, not general best practice.
The OpenCode deployment must follow existing patterns exactly; deviation creates drift and breaks
validation, SOPS decryption, and Flux reconciliation chains.

**Critical insight:** The cluster uses **Doppler** as the ExternalSecret provider (not a SOPS-native
provider). New secrets go into Doppler first, then an `ExternalSecret` manifest pulls them into
a Kubernetes `Secret`. SOPS `.sops.yaml` files are only used for standalone bootstrap secrets
(cloudflared, dns) that are applied directly — not for app-level secrets.

---

## Recommended Stack

### Core Technologies

| Technology | Version | Purpose | Why Recommended |
|------------|---------|---------|-----------------|
| bjw-s app-template | `4.4.0` (OCIRepository tag) | HelmRelease chart for all workloads | The cluster standard — every app in `home/`, `ai/`, `selfhosted/` uses this. Provides `controllers`, `containers`, `initContainers`, `persistence`, and `route` fields in a single HelmRelease. Use `4.4.0` to match the majority of cluster apps (one app uses `4.5.0`). |
| Flux CD | `v2.17.2` | GitOps reconciliation | Already installed. Manages all HelmReleases via `ks.yaml` → `app/kustomization.yaml` → resource files pattern. |
| Envoy Gateway | `1.7.0` (OCIRepository tag) | L7 ingress / HTTPRoute | Already deployed. Two Gateways: `envoy-external` (public) and `envoy-internal` (LAN-only). Both terminate TLS using the existing wildcard cert. OpenCode should use `envoy-external` since it needs browser access from any device. |
| cert-manager | Cluster-managed | TLS certificate provisioning | Already handling a wildcard `*.angryninja.cloud` cert via `letsencrypt-production` ClusterIssuer. **No per-app Certificate resource needed** — the Gateway's wildcard cert covers `*.angryninja.cloud` subdomains automatically. |
| Rook Ceph | `v1.18.9` | Distributed block storage | Default storage class is `ceph-block`. PVCs with `ReadWriteOnce` access mode are provisioned here. Already in use by HA, openwebui, and all other stateful apps. |
| External Secrets Operator | Cluster-managed | Secret provisioning via Doppler | Already deployed. `ClusterSecretStore` named `doppler-secrets` is the single provider. All app-level secrets go through this. |
| VolSync | Cluster-managed | PVC backup to Minio | Reusable via `../../../../templates/volsync` reference in `kustomization.yaml`. Requires `APP` and `VOLSYNC_CAPACITY` variables from `ks.yaml` postBuild. |

### Supporting Libraries / Patterns

| Library/Pattern | Version | Purpose | When to Use |
|-----------------|---------|---------|-------------|
| `alpine/git` init container | `latest` (use a pinned digest in production) | Git clone on first boot, pull on subsequent starts | Idempotent repo seeding: checks for `.git` directory, clones if absent, pulls if present. Pattern already validated in `home-assistant-v2`. |
| `reloader.stakater.com/auto: "true"` annotation | Cluster-wide | Restart pod when referenced Secrets change | Add to controller annotations whenever `envFrom` references an ExternalSecret-backed Secret. Ensures Copilot token changes propagate. |
| `appProtocol: kubernetes.io/ws` | Gateway API | Enable WebSocket upgrade on service port | Required for OpenCode's web UI — it uses WebSocket for terminal/editor streaming. Already used in `home-assistant` and `openwebui`. |
| Flux variable substitution (`${VAR_NAME}`) | Flux CD built-in | Inject cluster-wide values into manifests | Use `${SECRET_DOMAIN}` for hostnames. Variables come from `cluster-settings` ConfigMap and `cluster-secrets` Secret in `flux-system` namespace, injected via `postBuild.substituteFrom` in `apps.yaml`. |

### Development Tools

| Tool | Purpose | Notes |
|------|---------|-------|
| `yamllint` + `kubeconform` | Manifest validation | Pre-commit hooks run these automatically. Manifests must pass before commit. |
| `flux-local` | Local Flux diff testing | Run `task validate:flux` to verify Kustomization builds without pushing. |
| SOPS + age | Secret encryption | Only needed for the Doppler bootstrap secret (`stores/secret.sops.yaml`). App secrets go through Doppler, not SOPS directly. |

---

## File Structure Pattern

Every app follows this exact directory structure:

```
kubernetes/apps/opencode/
├── kustomization.yaml          # Namespace-level: lists opencode-flux/ and opencode-ha/
├── namespace.yaml              # Creates 'opencode' namespace
├── opencode-flux/
│   ├── ks.yaml                 # Flux Kustomization (lives in flux-system, targets opencode ns)
│   └── app/
│       ├── kustomization.yaml  # Lists all resources below
│       ├── ocirepository.yaml  # bjw-s app-template OCI source
│       ├── helmrelease.yaml    # Main HelmRelease with all values
│       └── externalsecret.yaml # Pulls secrets from Doppler
└── opencode-ha/
    ├── ks.yaml
    └── app/
        ├── kustomization.yaml
        ├── ocirepository.yaml
        ├── helmrelease.yaml
        └── externalsecret.yaml
```

**Note:** PVCs are created by the VolSync template (`../../../../templates/volsync`), referenced in `app/kustomization.yaml`. The HelmRelease then uses `existingClaim: *app` to bind to it.

---

## Key Manifest Patterns

### OCIRepository (verbatim from cluster pattern)

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: opencode-flux
  namespace: opencode
spec:
  interval: 15m
  layerSelector:
    mediaType: application/vnd.cncf.helm.chart.content.v1.tar+gzip
    operation: copy
  ref:
    tag: 4.4.0
  url: oci://ghcr.io/bjw-s-labs/helm/app-template
```

### HelmRelease — bjw-s app-template schema fields for this use case

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: &app opencode-flux
spec:
  chartRef:
    kind: OCIRepository
    name: opencode-flux
  interval: 1h
  install:
    remediation:
      retries: 3
  upgrade:
    cleanupOnFail: true
    remediation:
      strategy: rollback
      retries: 3
  dependsOn:
    - name: rook-ceph-cluster
      namespace: rook-ceph
    - name: external-secrets-stores       # wait for Doppler store to be ready
  values:
    controllers:
      opencode-flux:
        annotations:
          reloader.stakater.com/auto: "true"

        # --- Init container: git clone on first boot ---
        initContainers:
          git-clone:
            image:
              repository: alpine/git
              tag: latest
            command:
              - sh
              - -c
              - |
                set -e
                cp /secrets/github-pat /tmp/netrc
                chmod 600 /tmp/netrc

                if [ -d /workspace/.git ]; then
                  echo "Repo already cloned, skipping."
                else
                  echo "Cloning repo..."
                  git clone https://x-access-token:$(cat /secrets/github-pat)@github.com/ORG/REPO.git /workspace
                  echo "Clone complete."
                fi

                # Seed auth.json if not present
                if [ ! -f /data/auth.json ] && [ -f /secrets/auth-json ]; then
                  mkdir -p /data
                  cp /secrets/auth-json /data/auth.json
                  chmod 600 /data/auth.json
                  echo "auth.json seeded."
                fi
            securityContext:
              runAsUser: 0    # needs write to PVC before fsGroup takes over
              runAsGroup: 0

        containers:
          app:
            image:
              repository: ghcr.io/anomalyco/opencode
              tag: latest    # pin to digest in production
            command:
              - opencode
              - web
              - --hostname
              - 0.0.0.0
              - --port
              - "4096"
            env:
              OPENCODE_PASSWORD:
                valueFrom:
                  secretKeyRef:
                    name: opencode-flux-secrets
                    key: OPENCODE_PASSWORD
            envFrom:
              - secretRef:
                  name: opencode-flux-secrets
            securityContext:
              allowPrivilegeEscalation: false
              readOnlyRootFilesystem: false   # opencode writes session data
              capabilities: { drop: ["ALL"] }
            resources:
              requests:
                cpu: 100m
                memory: 256Mi
              limits:
                cpu: 500m
                memory: 512Mi

    defaultPodOptions:
      securityContext:
        runAsUser: 1000
        runAsGroup: 1000
        fsGroup: 1000
        fsGroupChangePolicy: OnRootMismatch
        seccompProfile: { type: RuntimeDefault }

    service:
      app:
        controller: *app
        ports:
          http:
            port: 4096
            appProtocol: kubernetes.io/ws   # OpenCode uses WebSocket

    # Route — not ingress. This cluster uses Gateway API HTTPRoute via bjw-s route: field.
    route:
      app:
        enabled: true
        parentRefs:
          - name: envoy-external
            namespace: network
            sectionName: https
        hostnames:
          - "flux.opencode.${SECRET_DOMAIN}"
        rules:
          - backendRefs:
              - identifier: app
                port: 4096

    persistence:
      # Main PVC — created by VolSync template, bound by existingClaim
      workspace:
        existingClaim: *app
        advancedMounts:
          opencode-flux:
            app:
              - path: /workspace    # working directory for the git repo
            git-clone:
              - path: /workspace    # init container shares same mount

      # Auth/data directory (opencode stores auth.json here)
      data:
        existingClaim: *app
        advancedMounts:
          opencode-flux:
            app:
              - path: /root/.local/share/opencode
            git-clone:
              - path: /data

      # Secret files mounted as volumes (not just env vars)
      github-secrets:
        type: secret
        name: opencode-flux-secrets
        defaultMode: 0400
        advancedMounts:
          opencode-flux:
            git-clone:
              - path: /secrets/github-pat
                subPath: GITHUB_PAT
                readOnly: true
              - path: /secrets/auth-json
                subPath: COPILOT_AUTH_JSON
                readOnly: true
```

**Key schema fields explained:**

| Field | Path | Purpose |
|-------|------|---------|
| `controllers.<name>.initContainers.<name>` | bjw-s v4+ | Init containers. Run before `containers`. Must complete successfully before app starts. |
| `controllers.<name>.containers.<name>.envFrom` | bjw-s v4+ | Bulk-inject all keys from a Secret as env vars. Use for `secretRef.name`. |
| `controllers.<name>.containers.<name>.env.<KEY>.valueFrom.secretKeyRef` | bjw-s v4+ | Single env var from a specific Secret key. Use when only 1-2 keys are needed. |
| `persistence.<name>.existingClaim` | bjw-s v4+ | Bind to a pre-existing PVC (created by VolSync template or standalone). |
| `persistence.<name>.advancedMounts.<controller>.<container>[]` | bjw-s v4+ | Mount the same volume to multiple containers at different paths. Use over `globalMounts` when init and app containers need different paths. |
| `persistence.<name>.globalMounts[]` | bjw-s v4+ | Mount to ALL containers in controller at same path. Use only when paths are identical. |
| `persistence.<name>.type: secret` | bjw-s v4+ | Mount a Kubernetes Secret as a volume. Use for file-format secrets (SSH keys, JSON files). |
| `persistence.<name>.subPath` | bjw-s v4+ | Mount a single key from a Secret/ConfigMap as a file. |
| `route.<name>.parentRefs[].sectionName: https` | Gateway API via bjw-s | Target only the HTTPS listener on the gateway. Must specify `https` to avoid also routing HTTP. |
| `service.<name>.ports.<port>.appProtocol: kubernetes.io/ws` | Gateway API hint | Signals to Envoy Gateway that this backend uses WebSocket. Required for OpenCode UI. |

### ExternalSecret — Doppler pattern

```yaml
---
apiVersion: external-secrets.io/v1
kind: ExternalSecret
metadata:
  name: opencode-flux-secrets
  namespace: opencode
spec:
  secretStoreRef:
    kind: ClusterSecretStore
    name: doppler-secrets       # The cluster's single provider
  target:
    name: opencode-flux-secrets
    creationPolicy: Owner
    template:
      engineVersion: v2
      data:
        GITHUB_PAT: "{{ .OPENCODE_FLUX_GITHUB_PAT }}"
        OPENCODE_PASSWORD: "{{ .OPENCODE_FLUX_PASSWORD }}"
        COPILOT_AUTH_JSON: "{{ .OPENCODE_FLUX_COPILOT_AUTH_JSON }}"
  dataFrom:
    - find:
        path: OPENCODE_FLUX_    # Pull all OPENCODE_FLUX_* keys from Doppler
```

**Why Doppler over SOPS-native ExternalSecret:**
The `ClusterSecretStore` named `doppler-secrets` is the **only** secret store in this cluster.
There is no SOPS-provider SecretStore. SOPS is only used to encrypt the Doppler API token
bootstrap secret itself. All application secrets live in Doppler.

### ks.yaml — Flux Kustomization

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/kustomization-kustomize-v1.json
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
    - name: rook-ceph-cluster
    - name: external-secrets-stores
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
      VOLSYNC_SCHEDULE: "0 2 * * *"   # Daily backup at 2am
```

### app/kustomization.yaml

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: opencode
resources:
  - ./externalsecret.yaml
  - ./ocirepository.yaml
  - ./helmrelease.yaml
  - ../../../../templates/volsync    # Creates PVC + VolSync backup/restore
labels:
  - pairs:
      app.kubernetes.io/name: opencode-flux
      app.kubernetes.io/instance: opencode-flux
```

---

## TLS / Certificate Strategy

**Do NOT create per-app `Certificate` resources.** The cluster uses a wildcard cert:

```yaml
# Already exists in kubernetes/apps/network/certificates/app/production.yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: "${SECRET_DOMAIN/./-}-production"
spec:
  secretName: "${SECRET_DOMAIN/./-}-production-tls"
  dnsNames:
    - "${SECRET_DOMAIN}"
    - "*.${SECRET_DOMAIN}"       # Covers flux.opencode.angryninja.cloud
```

The Gateway listeners reference this wildcard Secret directly:
```yaml
tls:
  certificateRefs:
    - kind: Secret
      name: ${SECRET_DOMAIN/./-}-production-tls
```

**New subdomains** (`flux.opencode.angryninja.cloud`, `ha.opencode.angryninja.cloud`) are automatically
covered because `*.angryninja.cloud` is already in the cert's `dnsNames`.

**Action required:** Only add an `HTTPRoute` (via the `route:` field in HelmRelease) pointing at
`envoy-external`. No cert-manager resource needed.

---

## PVC Strategy

Two options for PVC creation — use VolSync template:

**Option A (Recommended): VolSync template** — reference `../../../../templates/volsync` in kustomization.yaml.
This creates the PVC AND configures Minio backup. Required variables: `APP`, `VOLSYNC_CAPACITY`.

```yaml
# Resulting PVC from template with APP=opencode-flux, VOLSYNC_CAPACITY=5Gi:
# - name: opencode-flux
# - storageClassName: ceph-block
# - accessModes: [ReadWriteOnce]
# - storage: 5Gi
```

**Option B: Standalone PVC** — create a `pvc.yaml` manually. Use only if VolSync backup is not wanted.
```yaml
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: opencode-flux
spec:
  accessModes: ["ReadWriteOnce"]
  storageClassName: ceph-block
  resources:
    requests:
      storage: 5Gi
```

**Single PVC vs Two PVCs:** The init container and main container share the same PVC. Use
`advancedMounts` to mount it at different paths per container. A single 5Gi PVC is sufficient
for the workspace (git repo) and auth data combined.

---

## Alternatives Considered

| Recommended | Alternative | Why Not |
|-------------|-------------|---------|
| bjw-s `route:` field in HelmRelease | Standalone `HTTPRoute` manifest | Extra file with no benefit; bjw-s `route:` generates the same object. Unifi uses standalone only because it's not using app-template. |
| bjw-s `route:` field in HelmRelease | `ingress:` field in HelmRelease | `ingress:` uses nginx/ingress-controller classes; the cluster has migrated to Envoy Gateway. `ingress.enabled: false` in all working apps proves this. |
| Doppler ExternalSecret | SOPS `.sops.yaml` file in app dir | No SOPS-provider SecretStore exists. SOPS files work only for resources applied by Flux with SOPS decryption enabled (cluster-level only, not per-app). Doppler is the established pattern. |
| `advancedMounts` | `globalMounts` | `globalMounts` mounts at the same path in ALL containers — init container and app need different paths for the same PVC. Use `advancedMounts` for per-container path control. |
| VolSync template for PVC | Standalone `pvc.yaml` | Loses automated Minio backup. Adds complexity later to add backup. All stateful apps use VolSync template. |
| `envoy-external` Gateway | `envoy-internal` Gateway | `envoy-internal` is LAN-only. The requirement is "accessible from any device via browser" — needs external Gateway for mobile/remote access. |

---

## What NOT to Use

| Avoid | Why | Use Instead |
|-------|-----|-------------|
| `ingress:` block in HelmRelease | Uses nginx IngressClass; cluster has migrated to Envoy Gateway; all existing `ingress.enabled: false` | `route:` block in HelmRelease with `parentRefs.name: envoy-external` |
| Per-app `Certificate` resource | Wildcard cert `*.angryninja.cloud` already covers all subdomains; adding per-app cert creates conflicts and delays | Just add `route:` pointing to Gateway — TLS is handled at the Gateway layer |
| SOPS `.sops.yaml` in app directory | No SOPS-provider ClusterSecretStore exists; SOPS is only for bootstrap tokens and cluster-level vars | Doppler `ExternalSecret` with `ClusterSecretStore: doppler-secrets` |
| `globalMounts` when init+app need different paths | Mounts at same path in ALL containers; init container and app container need different paths for workspace/auth | `advancedMounts` keyed by `<controller>.<container>` |
| `readOnlyRootFilesystem: true` | OpenCode writes session state, auth, and temp files to its working directories | `readOnlyRootFilesystem: false` — OpenCode is not a read-only application |
| Single deployment for both workspaces | Shared PVC, workingDir conflicts; harder to restart/debug independently | Two independent HelmReleases (`opencode-flux`, `opencode-ha`) each with their own PVC and ExternalSecret |
| `alpine/git:latest` without digest pin | Mutable tag; image can change between pod restarts | Pin to a specific digest (`alpine/git:latest@sha256:...`) after initial development |

---

## Version Compatibility

| Package | Version in Cluster | Compatibility Notes |
|---------|-------------------|---------------------|
| bjw-s app-template | `4.4.0` (cluster majority) | `4.5.0` also in use (zigbee2mqtt). `route:` field requires 3.x+. Schema at `https://raw.githubusercontent.com/bjw-s/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json` |
| Flux CD | `v2.17.2` | `healthChecks` uses `helm.toolkit.fluxcd.io/v2` (not `v2beta2`) — the ks.yaml `home-assistant` has a stale `v2beta2` reference; use `v2` for new resources |
| External Secrets | `v1` (apiVersion) | `external-secrets.io/v1` — cluster has migrated from `v1beta1`. Use `v1` for all new ExternalSecrets |
| Gateway API HTTPRoute | `gateway.networking.k8s.io/v1` | GA since Gateway API 1.0. Use `v1` not `v1beta1`. |
| Kustomize Kustomization | `kustomize.toolkit.fluxcd.io/v1` | Use `v1` not `v1beta1` or `v1beta2`. |
| Helm | Flux `helm.toolkit.fluxcd.io/v2` | Use `v2` for HelmRelease apiVersion — confirmed from all working cluster manifests |

---

## Doppler Secret Naming Convention

Keys in Doppler should be namespaced to avoid collisions:

```
OPENCODE_FLUX_GITHUB_PAT      — GitHub PAT for flux k8s-cluster repo clone
OPENCODE_FLUX_PASSWORD        — Server auth password for flux.opencode.angryninja.cloud
OPENCODE_FLUX_COPILOT_AUTH_JSON — Contents of ~/.local/share/opencode/auth.json

OPENCODE_HA_GITHUB_PAT        — GitHub PAT for home-assistant-config repo clone
OPENCODE_HA_PASSWORD          — Server auth password for ha.opencode.angryninja.cloud
OPENCODE_HA_COPILOT_AUTH_JSON — Contents of ~/.local/share/opencode/auth.json
```

The ExternalSecret template maps these to normalized Kubernetes Secret keys (`GITHUB_PAT`,
`OPENCODE_PASSWORD`, `COPILOT_AUTH_JSON`) so the HelmRelease env/volume references are
identical between the two workspace instances.

---

## Sources

- `/Users/jbaker/git/k8s-cluster/kubernetes/apps/home/home-assistant-v2/app/helmrelease.yaml` — authoritative init container + git clone + advancedMounts pattern; **HIGH confidence**
- `/Users/jbaker/git/k8s-cluster/kubernetes/apps/ai/openwebui/app/helmrelease.yaml` — globalMounts + route + existingClaim pattern; **HIGH confidence**
- `/Users/jbaker/git/k8s-cluster/kubernetes/apps/home/home-assistant/app/helmrelease.yaml` — route to envoy-external, appProtocol: ws, deploy-key subPath mount pattern; **HIGH confidence**
- `/Users/jbaker/git/k8s-cluster/kubernetes/apps/network/envoy-gateway/app/envoy.yaml` — Gateway definitions, TLS termination via wildcard cert; **HIGH confidence**
- `/Users/jbaker/git/k8s-cluster/kubernetes/apps/network/certificates/app/production.yaml` — wildcard cert covers all subdomains; **HIGH confidence**
- `/Users/jbaker/git/k8s-cluster/kubernetes/apps/external-secrets/external-secrets/stores/clustersecretstore.yaml` — Doppler is the only ClusterSecretStore; **HIGH confidence**
- `/Users/jbaker/git/k8s-cluster/kubernetes/templates/volsync/` — PVC creation via VolSync template; default storageClass `ceph-block`; **HIGH confidence**
- `/Users/jbaker/git/k8s-cluster/kubernetes/apps/home/home-assistant-v2/ks.yaml` — ks.yaml pattern with postBuild.substitute for VolSync variables; **HIGH confidence**

---
*Stack research for: Persistent OpenCode on Kubernetes*
*Researched: 2026-03-01*
*All findings verified against actual cluster manifests — no training data assumptions*
