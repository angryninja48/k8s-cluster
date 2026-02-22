# Technology Stack

**Analysis Date:** 2026-02-22

## Languages

**Primary:**
- YAML - Cluster configuration, Kubernetes manifests, Flux CD resources
- Bash - Automation scripts, validation, cluster operations

**Secondary:**
- Python 3.14.2 - Migration scripts and tooling
- Go - Talos Linux, Flux CD, kubectl (tool dependencies)

## Runtime

**Environment:**
- Kubernetes v1.35.0 - Container orchestration platform
- Talos Linux v1.12.1 - Immutable operating system for Kubernetes nodes
- Containerd - Container runtime (configured via Talos)

**Package Manager:**
- mise - Tool version management (Python, kubectl, flux, helm, etc.)
- uv - Python dependency management (fast pip alternative)
- Helm - Kubernetes package manager
- Kustomize - Kubernetes native configuration management
- No lockfile for application dependencies (infrastructure as code repository)

## Frameworks

**Core:**
- Flux CD v2.17.2 - GitOps continuous deployment operator
- Talos Linux v1.12.1 - Kubernetes distribution
- Cilium v1.18.6 - eBPF-based CNI (container networking)
- Rook Ceph v1.18.9 - Distributed storage orchestration

**Testing:**
- yamllint - YAML syntax validation
- kubeconform - Kubernetes manifest validation
- flux-local v8.1.0 - Local Flux validation and diff testing
- pre-commit hooks - Automated validation on git commits

**Build/Dev:**
- Task v3 - Task runner for cluster operations (`Taskfile.yaml`)
- Helmfile - Declarative Helm chart deployment
- talhelper - Talos configuration generation from `talconfig.yaml`
- SOPS - Secret encryption/decryption with age

## Key Dependencies

**Critical:**
- flux2 (via aqua) - GitOps operator for continuous deployment
- talosctl (via aqua) - Talos Linux management CLI
- kubectl (via aqua) - Kubernetes command-line tool
- helm (via aqua) - Kubernetes package manager
- sops (via aqua) - Secret encryption tool
- age (via aqua) - Encryption key management for SOPS

**Infrastructure:**
- kustomize (via aqua) - Kubernetes configuration customization
- helmfile (via aqua) - Helm release orchestration
- yq (via aqua) - YAML processor
- jq (via aqua) - JSON processor
- cloudflared (via aqua) - Cloudflare tunnel client
- talhelper (via aqua) - Talos configuration generator
- kubeconform (via aqua) - Kubernetes manifest schema validation

## Configuration

**Environment:**
- Configuration via `mise` environment variables in `.mise.toml`
- Key environment variables:
  - `KUBECONFIG` → `{{config_root}}/kubeconfig`
  - `SOPS_AGE_KEY_FILE` → `{{config_root}}/age.key`
  - `TALOSCONFIG` → `{{config_root}}/kubernetes/bootstrap/talos/clusterconfig/talosconfig`
- Cluster settings: `kubernetes/flux/vars/cluster-settings.yaml`
- Encrypted secrets: `kubernetes/flux/vars/cluster-secrets.sops.yaml`

**Build:**
- `.mise.toml` - Tool versions and environment setup
- `Taskfile.yaml` - Main task definitions
- `.taskfiles/` - Modular task definitions (bootstrap, talos, volsync, rook-ceph)
- `.sops.yaml` - SOPS encryption configuration with age keys
- `.pre-commit-config.yaml` - Git hooks for validation
- `age.key` - SOPS encryption key (gitignored, generated locally)

## Platform Requirements

**Development:**
- mise installed for tool management
- Python 3.14+ (managed by mise)
- Git for repository operations
- Access to `age.key` for secret decryption
- Network access to cluster nodes (10.20.0.0/24)

**Production:**
- 3+ physical nodes with Talos Linux installed
- Network: 10.20.0.0/24 (node network), 10.69.0.0/16 (pod network), 10.96.0.0/16 (service network)
- Storage: Local disks for Rook Ceph distributed storage
- Control plane VIP: 10.20.0.250
- Kubernetes API endpoint: https://10.20.0.250:6443

---

*Stack analysis: 2026-02-22*
