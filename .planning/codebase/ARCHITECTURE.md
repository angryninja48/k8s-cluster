# Architecture

**Analysis Date:** 2026-02-22

## Pattern Overview

**Overall:** GitOps Multi-Layer Kubernetes Cluster Management with Declarative Infrastructure

**Key Characteristics:**
- Declarative infrastructure-as-code with Git as the single source of truth
- Multi-stage bootstrap sequence (OS → Core Services → GitOps → Applications)
- Hierarchical Flux CD Kustomization cascade with automatic reconciliation
- Encrypted secret management with SOPS and age
- Namespace-based workload isolation with consistent application patterns

## Layers

**Infrastructure Layer (Talos Linux):**
- Purpose: Immutable operating system providing Kubernetes foundation
- Location: `kubernetes/bootstrap/talos/`
- Contains: Node configurations, network patches, kubelet settings, machine configs
- Depends on: Physical/virtual hardware nodes
- Used by: Kubernetes control plane and worker nodes
- Key files: `talconfig.yaml`, `talenv.yaml`, `patches/global/`, `patches/controller/`
- Configuration generation: talhelper generates machine configs from templates

**Bootstrap Layer (Helmfile):**
- Purpose: Deploy essential system components before Flux takes over
- Location: `kubernetes/bootstrap/helmfile.yaml`
- Contains: Critical infrastructure charts (Cilium CNI, CoreDNS, Spegel, Flux, Prometheus CRDs)
- Depends on: Kubernetes API server availability
- Used by: All cluster workloads (provides networking and GitOps runtime)
- Execution: One-time deployment via `task bootstrap:apps`

**GitOps Control Layer (Flux CD):**
- Purpose: Continuous reconciliation of cluster state from Git
- Location: `kubernetes/flux/`
- Contains: Root Kustomizations, GitRepository sources, HelmRepositories, cluster variables
- Depends on: Bootstrap layer (Flux installed via Helmfile)
- Used by: Application layer deployments
- Key abstractions:
  - GitRepository (`config/cluster.yaml`): Watches GitHub repository main branch
  - Root Kustomization (`config/cluster.yaml`): Applies `kubernetes/flux/` directory
  - Apps Kustomization (`apps.yaml`): Recursively deploys all `ks.yaml` files in `kubernetes/apps/`

**Variable Substitution Layer:**
- Purpose: Inject cluster-wide configuration and secrets into manifests
- Location: `kubernetes/flux/vars/`
- Contains: ConfigMap (cluster-settings.yaml), Secret (cluster-secrets.sops.yaml)
- Depends on: SOPS age key deployed to flux-system namespace
- Used by: All Flux Kustomizations via postBuild.substituteFrom
- Pattern: Variables referenced as `${VAR_NAME}` in YAML manifests

**Repository Abstraction Layer:**
- Purpose: Centralized Helm and OCI repository definitions
- Location: `kubernetes/flux/repositories/`
- Contains: HelmRepository and OCIRepository resources for external charts
- Depends on: Flux source controller
- Used by: HelmReleases across all namespaces
- Structure: `helm/` (Helm repos), `oci/` (OCI registries)

**Application Layer:**
- Purpose: Deploy and manage workload applications via GitOps
- Location: `kubernetes/apps/<namespace>/<app-name>/`
- Contains: Flux Kustomizations (ks.yaml), HelmReleases, ExternalSecrets, ConfigMaps, PVCs
- Depends on: GitOps control layer, namespace-specific dependencies
- Used by: End users and other applications
- Namespaces: ai, cert-manager, database, default, external-secrets, flux-system, home, kube-system, media, network, observability, openebs-system, rook-ceph, security, selfhosted, tools, volsync-system

**Shared Components Layer:**
- Purpose: Reusable Kustomize components and templates
- Location: `kubernetes/components/`, `kubernetes/templates/`
- Contains: Common configurations, VolSync backup templates
- Depends on: Kustomize composition
- Used by: Applications via relative path references in kustomization.yaml

## Data Flow

**Bootstrap Flow (One-time):**

1. **Talos Configuration Generation:** talhelper reads `talconfig.yaml` + `talenv.yaml` → generates machine configs in `clusterconfig/`
2. **Node Configuration:** talosctl applies machine configs → nodes boot with Talos Linux
3. **Kubernetes Bootstrap:** talosctl bootstrap etcd → Kubernetes control plane initializes
4. **Core Services Deployment:** helmfile applies `bootstrap/helmfile.yaml` → Cilium, CoreDNS, Spegel, Flux deployed
5. **Flux Initialization:** kubectl applies sops-age secret, cluster-settings, cluster-secrets → Flux GitOps starts
6. **GitRepository Sync:** Flux watches GitHub repository → clones kubernetes/ directory
7. **Root Kustomization:** Flux applies `kubernetes/flux/` → repositories and vars deployed
8. **Apps Cascade:** `apps.yaml` Kustomization recursively discovers and deploys all `ks.yaml` files

**GitOps Reconciliation Flow (Continuous):**

1. **Git Commit:** Developer pushes changes to GitHub main branch
2. **Flux Poll:** GitRepository source polls every 30m (or immediate via `task reconcile`)
3. **Kustomization Build:** Flux builds Kustomize manifests from `path` specified in ks.yaml
4. **Secret Decryption:** SOPS provider decrypts `.sops.yaml` files using age key
5. **Variable Substitution:** postBuild injects values from cluster-settings and cluster-secrets
6. **Resource Application:** Flux applies resources to cluster via Kubernetes API
7. **Health Check:** Flux monitors HelmRelease/Deployment health defined in ks.yaml healthChecks
8. **Dependency Resolution:** dependsOn ensures proper ordering (e.g., database before application)

**Application Deployment Flow:**

1. **Namespace Kustomization:** Flux applies `kubernetes/apps/<namespace>/kustomization.yaml` → discovers app ks.yaml files
2. **App Flux Kustomization:** Flux processes `<app-name>/ks.yaml` → reads metadata, dependencies, targetNamespace
3. **App Resource Build:** Flux builds `<app-name>/app/kustomization.yaml` → aggregates helmrelease.yaml, externalsecret.yaml, etc.
4. **OCI/Helm Repository:** Flux fetches chart from OCIRepository or HelmRepository
5. **ExternalSecret Sync:** external-secrets-operator syncs secrets from SOPS to Kubernetes Secret
6. **HelmRelease Rendering:** Flux helm-controller renders chart with values → generates Deployment, Service, etc.
7. **Resource Creation:** Kubernetes applies resources → Pod scheduler assigns to nodes
8. **VolSync Backup:** If enabled, VolSync creates ReplicationSource for PVC backups to Minio

**State Management:**
- Cluster state stored in etcd (Kubernetes control plane)
- Desired state stored in Git repository (GitHub)
- Flux continuously reconciles actual state → desired state
- Secrets encrypted at rest in Git via SOPS
- Persistent data stored in Rook Ceph or OpenEBS volumes

## Key Abstractions

**Flux Kustomization (ks.yaml):**
- Purpose: Meta-resource that tells Flux where/how to deploy an application
- Examples: `kubernetes/apps/home/home-assistant/ks.yaml`, `kubernetes/apps/network/ingress-nginx/ks.yaml`
- Pattern: Lives at `<app-name>/ks.yaml`, points to `<app-name>/app/` directory
- Properties: targetNamespace, dependsOn, interval, retryInterval, timeout, postBuild substitutions

**Kustomize Kustomization (app/kustomization.yaml):**
- Purpose: Standard Kustomize resource aggregation
- Examples: `kubernetes/apps/home/home-assistant/app/kustomization.yaml`
- Pattern: Lists resources to apply (helmrelease.yaml, externalsecret.yaml, etc.)
- Composition: Can reference templates via relative paths (e.g., `../../../../templates/volsync`)

**HelmRelease:**
- Purpose: Declarative Helm chart deployment
- Examples: `kubernetes/apps/home/home-assistant/app/helmrelease.yaml`
- Pattern: References OCIRepository or HelmRepository via chartRef or chart
- Schema: Most apps use bjw-s app-template schema (`https://raw.githubusercontent.com/bjw-s/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json`)
- Values: Inline values override chart defaults (controllers, persistence, service, ingress)

**OCIRepository:**
- Purpose: Reference OCI-based Helm charts (e.g., ghcr.io)
- Examples: `kubernetes/apps/home/home-assistant/app/ocirepository.yaml`
- Pattern: Specifies chart URL, tag, and layer selector for Helm content
- Usage: HelmRelease chartRef.kind references OCIRepository by name

**HelmRepository:**
- Purpose: Reference traditional Helm chart repositories
- Examples: `kubernetes/flux/repositories/helm/bjw-s.yaml`
- Pattern: Centralized in `kubernetes/flux/repositories/helm/`
- Usage: HelmReleases reference by chart path (e.g., `bjw-s/app-template`)

**ExternalSecret:**
- Purpose: Sync secrets from SOPS-encrypted files to Kubernetes Secrets
- Examples: `kubernetes/apps/home/home-assistant/app/externalsecret.yaml`
- Pattern: References external-secrets ClusterSecretStore, creates Secret in app namespace
- Data flow: SOPS file → ClusterSecretStore → ExternalSecret → Kubernetes Secret → Pod envFrom

**VolSync Template:**
- Purpose: Reusable backup configuration for PVCs
- Location: `kubernetes/templates/volsync/`
- Pattern: Apps reference via `../../../../templates/volsync` in kustomization.yaml
- Variables: Requires `APP` and `VOLSYNC_CAPACITY` via postBuild.substitute
- Components: ReplicationSource (Restic to Minio), claim.yaml (PVC definition)

**Talos Patches:**
- Purpose: Override default Talos machine configuration
- Examples: `kubernetes/bootstrap/talos/patches/global/machine-kubelet.yaml`
- Pattern: YAML fragments merged into generated machine configs
- Scope: global/ (all nodes), controller/ (control plane only), worker/ (workers only)

## Entry Points

**Root GitOps Entry Point:**
- Location: `kubernetes/flux/config/cluster.yaml`
- Triggers: Flux source-controller polls GitRepository every 30m
- Responsibilities: Watches GitHub repo, applies `kubernetes/flux/` directory, decrypts SOPS, substitutes variables
- Cascade: Deploys repositories, vars, then triggers apps.yaml

**Apps Cascade Entry Point:**
- Location: `kubernetes/flux/apps.yaml`
- Triggers: Applied by cluster Kustomization
- Responsibilities: Recursively discovers all `ks.yaml` files in `kubernetes/apps/`, applies SOPS decryption and variable substitution to child Kustomizations
- Cascade: Applies namespace kustomization.yaml → app ks.yaml → app resources

**Talos Bootstrap Entry Point:**
- Location: `kubernetes/bootstrap/talos/talconfig.yaml`
- Triggers: `task talos:generate-config` command
- Responsibilities: Defines cluster topology, node IPs, network config, patches
- Output: Generates machine configs in `clusterconfig/` directory

**Helmfile Bootstrap Entry Point:**
- Location: `kubernetes/bootstrap/helmfile.yaml`
- Triggers: `task bootstrap:apps` command
- Responsibilities: Deploys essential system charts before Flux is ready
- Sequence: prometheus-operator-crds → cilium → coredns → spegel → flux

**Task Automation Entry Point:**
- Location: `Taskfile.yaml` (root), `.taskfiles/<category>/Taskfile.yaml`
- Triggers: `task <command>` invocations
- Responsibilities: Cluster operations (bootstrap, validation, reconciliation, backups)
- Categories: bootstrap, talos, volsync, rook-ceph, kubernetes

## Error Handling

**Strategy:** Multi-layered retry and remediation with eventual consistency

**Patterns:**
- **Flux Retry:** Kustomizations specify `retryInterval` (typically 1m) and `timeout` (5-10m) for transient failures
- **Helm Remediation:** HelmReleases define `install.remediation.retries` (3) and `upgrade.remediation.strategy: rollback`
- **Health Checks:** Flux Kustomizations include healthChecks for HelmReleases to block dependent resources
- **Dependency Ordering:** dependsOn in ks.yaml ensures prerequisites (e.g., databases, CNI) deploy first
- **SOPS Failure:** If age key missing, Flux marks Kustomization as "decryption failed" and retries on interval
- **Git Sync Failure:** If GitHub unreachable, Flux continues with last known good state
- **Manual Reconciliation:** `task reconcile` forces immediate sync from Git
- **Talos Recovery:** `task talos:reset` resets nodes to maintenance mode for disaster recovery
- **VolSync Unlock:** `task volsync:unlock` resolves locked Restic repositories after unclean shutdown

## Cross-Cutting Concerns

**Logging:**
- Promtail (observability namespace) scrapes pod logs → Loki
- Talos logs via `talosctl logs` command
- Flux logs via `flux logs -f --namespace flux-system`

**Validation:**
- Pre-commit hooks run `validate-consistency.sh` on every commit
- Schema validation via yaml-language-server comments
- Kustomize build validation via `task validate:kustomize`
- Flux dry-run via `task validate:flux`

**Authentication:**
- Flux → GitHub: Deploy key stored in `bootstrap/flux/github-deploy-key.sops.yaml`
- Talos → Control Plane: talosconfig generated in `bootstrap/talos/clusterconfig/talosconfig`
- kubectl → Kubernetes: kubeconfig generated in root directory
- External Services: ExternalSecrets manage credentials from SOPS files

---

*Architecture analysis: 2026-02-22*
