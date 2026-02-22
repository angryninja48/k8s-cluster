# Codebase Structure

**Analysis Date:** 2026-02-22

## Directory Layout

```
k8s-cluster/
├── kubernetes/           # Main cluster configuration (GitOps source)
│   ├── apps/            # Application deployments by namespace
│   ├── bootstrap/       # Cluster initialization (Talos, Helmfile, Flux)
│   ├── components/      # Shared Kustomize components
│   ├── flux/            # Flux CD configuration (repos, vars, apps)
│   └── templates/       # Reusable templates (VolSync)
├── .taskfiles/          # Task automation definitions
│   ├── bootstrap/       # Bootstrap task implementations
│   ├── talos/           # Talos operations tasks
│   ├── volsync/         # Backup and sync tasks
│   ├── rook-ceph/       # Storage tasks
│   └── kubernetes/      # Kubernetes operations
├── scripts/             # Validation and maintenance scripts
├── docs/                # Project documentation
│   ├── cluster-management/
│   ├── deployment/
│   ├── development/
│   ├── operations/
│   └── templates/
├── jobs/                # Job definitions (likely CI/CD)
├── .sisyphus/           # GSD workflow state tracking
├── .planning/           # Codebase analysis documents
├── .github/             # GitHub workflows
├── .private/            # Private configuration archives
├── Taskfile.yaml        # Root task definitions
├── kubeconfig           # Kubernetes cluster access (generated)
├── age.key              # SOPS encryption key (generated, gitignored)
└── .sops.yaml           # SOPS encryption configuration
```

## Directory Purposes

**kubernetes/:**
- Purpose: Single source of truth for cluster configuration
- Contains: All Kubernetes manifests managed via GitOps
- Key files: Structure mirrors Flux CD reconciliation hierarchy
- Git strategy: Committed to version control, Flux watches this directory

**kubernetes/apps/:**
- Purpose: Application workload deployments organized by namespace
- Contains: Per-namespace directories, each containing per-application subdirectories
- Key files: `<namespace>/kustomization.yaml` (namespace aggregator), `<app-name>/ks.yaml` (Flux Kustomization), `<app-name>/app/` (resources)
- Namespaces: ai, cert-manager, database, default, external-secrets, flux-system, home, kube-system, media, network, observability, openebs-system, rook-ceph, security, selfhosted, tools, volsync-system

**kubernetes/apps/<namespace>/<app-name>/:**
- Purpose: Complete application definition
- Contains: ks.yaml (Flux Kustomization meta-resource) + app/ directory (actual resources)
- Key pattern: Consistent structure across all applications
- Example: `kubernetes/apps/home/home-assistant/ks.yaml` + `kubernetes/apps/home/home-assistant/app/`

**kubernetes/apps/<namespace>/<app-name>/app/:**
- Purpose: Application resource definitions
- Contains: kustomization.yaml, helmrelease.yaml, externalsecret.yaml, ocirepository.yaml, configmap.yaml, pvc.yaml
- Key pattern: kustomization.yaml lists all resources to apply
- Reference: Can include templates via relative paths (e.g., `../../../../templates/volsync`)

**kubernetes/bootstrap/:**
- Purpose: Cluster initialization configuration
- Contains: talos/ (OS config), helmfile.yaml (essential charts), flux/ (GitOps bootstrap)
- Key files: `talos/talconfig.yaml`, `helmfile.yaml`, `flux/github-deploy-key.sops.yaml`
- Usage: Applied once during cluster setup via `task bootstrap:*` commands

**kubernetes/bootstrap/talos/:**
- Purpose: Talos Linux node configuration
- Contains: talconfig.yaml (cluster topology), talenv.yaml (version overrides), patches/ (config overrides), clusterconfig/ (generated machine configs)
- Key files: `talconfig.yaml`, `patches/global/`, `patches/controller/`
- Generated: clusterconfig/ directory created by `task talos:generate-config`

**kubernetes/bootstrap/talos/patches/:**
- Purpose: Talos configuration customization
- Contains: global/ (all nodes), controller/ (control plane), worker/ (worker nodes)
- Key files: `global/machine-kubelet.yaml`, `global/machine-network.yaml`, `controller/cluster.yaml`
- Pattern: YAML fragments merged into generated machine configs

**kubernetes/flux/:**
- Purpose: Flux CD GitOps operator configuration
- Contains: apps.yaml (root app cascade), config/ (cluster GitRepository), repositories/ (Helm/OCI sources), vars/ (cluster-wide variables)
- Key files: `apps.yaml`, `config/cluster.yaml`, `vars/cluster-settings.yaml`, `vars/cluster-secrets.sops.yaml`
- Reconciliation: Applied by cluster Kustomization defined in `config/cluster.yaml`

**kubernetes/flux/repositories/:**
- Purpose: Centralized Helm and OCI repository definitions
- Contains: helm/ (HelmRepository resources), oci/ (OCIRepository resources)
- Key files: `helm/bjw-s.yaml`, `helm/prometheus-community.yaml`, `oci/multus-cni.yaml`
- Usage: Referenced by HelmReleases across all namespaces

**kubernetes/flux/vars/:**
- Purpose: Cluster-wide configuration and secrets
- Contains: cluster-settings.yaml (ConfigMap with plaintext vars), cluster-secrets.sops.yaml (SOPS-encrypted secrets)
- Key files: `cluster-settings.yaml`, `cluster-secrets.sops.yaml`, `kustomization.yaml`
- Substitution: Injected into all Flux Kustomizations via postBuild.substituteFrom

**kubernetes/components/:**
- Purpose: Reusable Kustomize components
- Contains: common/ (shared configurations)
- Usage: Referenced by applications via Kustomize components feature

**kubernetes/templates/:**
- Purpose: Reusable manifest templates
- Contains: volsync/ (backup and replication templates)
- Key files: `volsync/kustomization.yaml`, `volsync/claim.yaml`, `volsync/minio.yaml`
- Usage: Included via relative path in app kustomization.yaml (e.g., `- ../../../../templates/volsync`)

**.taskfiles/:**
- Purpose: Task implementation definitions for automation
- Contains: bootstrap/, talos/, volsync/, rook-ceph/, kubernetes/
- Key files: `bootstrap/Taskfile.yaml`, `talos/Taskfile.yaml`, `volsync/Taskfile.yaml`
- Inclusion: Referenced in root Taskfile.yaml via includes section

**scripts/:**
- Purpose: Automation and validation scripts
- Contains: Bash scripts for repository consistency, schema validation, formatting
- Key files: `validate-consistency.sh`, `fix-schemas.sh`, `fix-helmrelease-schemas.sh`, `fix-properties.sh`, `fix-timeout-format.sh`
- Usage: Called by Task commands (e.g., `task validate:consistency`)

**docs/:**
- Purpose: Project documentation and guides
- Contains: cluster-management/, deployment/, development/, operations/, templates/
- Key files: `README.md`, `PRD.md` (product requirements)
- Usage: Human-readable documentation for operators

**.sisyphus/:**
- Purpose: GSD (Get Stuff Done) workflow state tracking
- Contains: evidence/, plans/, drafts/, notepads/
- Generated: Created by GSD workflow commands
- Committed: Yes, tracks workflow progress across sessions

**.planning/:**
- Purpose: Codebase analysis and mapping documents
- Contains: codebase/ (architecture, structure, conventions, testing docs)
- Key files: ARCHITECTURE.md, STRUCTURE.md (this file)
- Usage: Reference documents for AI-assisted development

**.github/:**
- Purpose: GitHub-specific configuration
- Contains: workflows/ (CI/CD automation)
- Usage: GitHub Actions workflows for automated validation

**.private/:**
- Purpose: Historical configuration backups
- Contains: Timestamped directories with previous configurations
- Committed: Yes (filtered configurations only)
- Usage: Configuration history and rollback reference

**Root configuration files:**
- `Taskfile.yaml`: Root task runner definitions, includes sub-taskfiles
- `kubeconfig`: Kubernetes cluster access credentials (generated by bootstrap)
- `age.key`: SOPS age encryption key (generated, never committed)
- `.sops.yaml`: SOPS encryption configuration (age public key)
- `.mise.toml`: Tool version management (Python, kubectl, flux, helm, etc.)
- `.pre-commit-config.yaml`: Git hooks for validation
- `.gitignore`: Excludes secrets, generated files, local configs

## Key File Locations

**Entry Points:**
- `kubernetes/flux/config/cluster.yaml`: Root GitRepository and Kustomization
- `kubernetes/flux/apps.yaml`: Application cascade entry point
- `kubernetes/bootstrap/talos/talconfig.yaml`: Talos cluster definition
- `kubernetes/bootstrap/helmfile.yaml`: Essential system charts
- `Taskfile.yaml`: Automation entry point

**Configuration:**
- `kubernetes/flux/vars/cluster-settings.yaml`: Cluster-wide ConfigMap variables
- `kubernetes/flux/vars/cluster-secrets.sops.yaml`: SOPS-encrypted secrets
- `kubernetes/bootstrap/talos/talenv.yaml`: Talos/Kubernetes version overrides
- `.sops.yaml`: Encryption configuration
- `.mise.toml`: Tool versions

**Core Logic:**
- `kubernetes/apps/<namespace>/<app-name>/app/helmrelease.yaml`: Application deployment definitions
- `kubernetes/apps/<namespace>/<app-name>/ks.yaml`: Flux Kustomization metadata
- `kubernetes/bootstrap/talos/patches/`: Talos configuration customization
- `.taskfiles/<category>/Taskfile.yaml`: Operational task definitions

**Testing:**
- `scripts/validate-consistency.sh`: Repository validation suite
- `.pre-commit-config.yaml`: Git pre-commit hooks
- No dedicated test/ directory (infrastructure-as-code project)

## Naming Conventions

**Files:**
- Flux Kustomizations: `ks.yaml` (distinguishes from Kustomize kustomization.yaml)
- App Kustomizations: `kustomization.yaml` (standard Kustomize)
- HelmReleases: `helmrelease.yaml`
- External Secrets: `externalsecret.yaml`
- OCI Repositories: `ocirepository.yaml`
- Namespaces: `namespace.yaml`
- SOPS-encrypted: `*.sops.yaml` (e.g., `cluster-secrets.sops.yaml`, `talsecret.sops.yaml`)
- Generated configs: No special suffix, stored in clusterconfig/ or root

**Directories:**
- Lowercase with hyphens: `kube-system`, `rook-ceph`, `home-assistant`
- Namespace directories: Match Kubernetes namespace name exactly
- App directories: Match application name (typically matches HelmRelease metadata.name)
- System directories: Prefix with `.` for hidden (`.taskfiles`, `.sisyphus`, `.planning`)

**Variables:**
- Cluster settings: `UPPERCASE_WITH_UNDERSCORES` (e.g., `TIMEZONE`, `SVC_K8S_GATEWAY_ADDR`)
- Task variables: `UPPERCASE_WITH_UNDERSCORES` (e.g., `KUBERNETES_DIR`, `TALOSCONFIG`)
- postBuild substitutions: `${VAR_NAME}` in manifests

**Namespaces:**
- Functional grouping: `home` (home automation), `media` (entertainment), `network` (networking), `observability` (monitoring)
- System namespaces: `kube-system`, `flux-system`, `cert-manager`, `external-secrets`
- Storage namespaces: `rook-ceph`, `openebs-system`, `volsync-system`

## Where to Add New Code

**New Application:**
- Primary code: `kubernetes/apps/<namespace>/<app-name>/app/`
  1. Create `kubernetes/apps/<namespace>/<app-name>/ks.yaml` (Flux Kustomization)
  2. Create `kubernetes/apps/<namespace>/<app-name>/app/kustomization.yaml` (resource list)
  3. Create `kubernetes/apps/<namespace>/<app-name>/app/helmrelease.yaml` (or other resources)
  4. Add `- ./<app-name>/ks.yaml` to `kubernetes/apps/<namespace>/kustomization.yaml`
- Tests: Run `task validate:all` before commit
- Example: `kubernetes/apps/home/home-assistant/` shows full pattern

**New Namespace:**
- Implementation: `kubernetes/apps/<namespace>/`
  1. Create `kubernetes/apps/<namespace>/namespace.yaml`
  2. Create `kubernetes/apps/<namespace>/kustomization.yaml` (lists namespace.yaml and app ks.yaml files)
  3. Add apps as `<namespace>/<app-name>/` subdirectories
- Pattern: See `kubernetes/apps/home/` or `kubernetes/apps/media/`

**New Helm Repository:**
- Helm repos: `kubernetes/flux/repositories/helm/<repo-name>.yaml`
- OCI repos: `kubernetes/flux/repositories/oci/<repo-name>.yaml`
- Update: Add to `kubernetes/flux/repositories/<type>/kustomization.yaml` resources list
- Example: `kubernetes/flux/repositories/helm/bjw-s.yaml`

**New Talos Patch:**
- Global (all nodes): `kubernetes/bootstrap/talos/patches/global/<patch-name>.yaml`
- Controller only: `kubernetes/bootstrap/talos/patches/controller/<patch-name>.yaml`
- Worker only: `kubernetes/bootstrap/talos/patches/worker/<patch-name>.yaml`
- Node-specific: `kubernetes/bootstrap/talos/patches/<node-hostname>/<patch-name>.yaml`
- Apply: Run `task talos:generate-config` then `task talos:apply-node IP=<node-ip>`

**New Task Automation:**
- Category-specific: `.taskfiles/<category>/Taskfile.yaml`
- Root-level: Add to `Taskfile.yaml` tasks section
- Include: Add to `Taskfile.yaml` includes section if creating new category
- Example: `.taskfiles/volsync/Taskfile.yaml` for backup operations

**New Validation Script:**
- Location: `scripts/<script-name>.sh`
- Integration: Add task to `Taskfile.yaml` referencing script
- Pre-commit: Add to `.pre-commit-config.yaml` if should run on commit

**New Template:**
- Shared templates: `kubernetes/templates/<template-name>/`
- Kustomization: Create `kubernetes/templates/<template-name>/kustomization.yaml`
- Usage: Apps reference via `../../../../templates/<template-name>` in kustomization.yaml
- Example: `kubernetes/templates/volsync/` for backup templates

**New Documentation:**
- Operations guides: `docs/operations/<guide-name>.md`
- Development guides: `docs/development/<guide-name>.md`
- Deployment guides: `docs/deployment/<guide-name>.md`
- Templates: `docs/templates/<template-name>.md`

## Special Directories

**kubernetes/bootstrap/talos/clusterconfig/:**
- Purpose: Generated Talos machine configurations
- Generated: Yes (by `task talos:generate-config`)
- Committed: Yes (for reference and idempotency)
- Contains: Per-node YAML configs, talosconfig, secrets

**kubernetes/flux/repositories/:**
- Purpose: Centralized repository definitions
- Generated: No (manually defined)
- Committed: Yes
- Organization: Subdirectories by type (helm/, oci/)

**kubernetes/templates/:**
- Purpose: Reusable Kustomize templates
- Generated: No (manually defined)
- Committed: Yes
- Usage: Referenced via relative paths in app kustomization.yaml

**Root directory generated files:**
- `kubeconfig`: Kubernetes access credentials (generated by `task bootstrap:talos`)
- `age.key`: SOPS encryption key (generated by `task init`)
- Committed: No (gitignored, must be backed up securely)

**.sisyphus/:**
- Purpose: GSD workflow state
- Generated: Yes (by GSD commands)
- Committed: Yes (tracks workflow across sessions)
- Contains: evidence/, plans/, drafts/, notepads/

**.planning/codebase/:**
- Purpose: AI-generated codebase analysis
- Generated: Yes (by `/gsd-map-codebase` command)
- Committed: Yes (provides context for future sessions)
- Contains: ARCHITECTURE.md, STRUCTURE.md, CONVENTIONS.md, TESTING.md, STACK.md, INTEGRATIONS.md, CONCERNS.md

**.private/:**
- Purpose: Historical configuration backups
- Generated: Yes (by configuration updates)
- Committed: Yes (timestamped directories)
- Contains: Previous versions of templates and taskfiles

**.venv/:**
- Purpose: Python virtual environment
- Generated: Yes (by `mise run deps`)
- Committed: No (gitignored)
- Contains: Python dependencies for validation scripts

**docs/:**
- Purpose: Human-readable documentation
- Generated: Partially (some by GSD, some manual)
- Committed: Yes
- Organization: By topic (cluster-management/, deployment/, development/, operations/)

---

*Structure analysis: 2026-02-22*
