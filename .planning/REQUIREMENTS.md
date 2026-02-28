# Requirements: Persistent OpenCode on Kubernetes

**Defined:** 2026-03-01
**Core Value:** OpenCode sessions and GitHub Copilot auth survive indefinitely and are accessible from any device via browser — no laptop dependency.

## v1 Requirements

### Infrastructure Foundation

- [ ] **INFRA-01**: `opencode` namespace exists in the cluster with Flux prune guard
- [ ] **INFRA-02**: `*.opencode.angryninja.cloud` TLS Certificate is issued and `Ready: True` via cert-manager `letsencrypt-production` ClusterIssuer
- [ ] **INFRA-03**: Flux Kustomization aggregator (`kubernetes/apps/opencode/kustomization.yaml`) references both workspace `ks.yaml` files
- [ ] **INFRA-04**: All Doppler variables for both workspaces are populated before any ExternalSecret reconciles (`OPENCODE_FLUX_GITHUB_PAT`, `OPENCODE_FLUX_PASSWORD`, `OPENCODE_FLUX_COPILOT_AUTH_JSON`, `OPENCODE_HA_GITHUB_PAT`, `OPENCODE_HA_PASSWORD`, `OPENCODE_HA_COPILOT_AUTH_JSON`)

### Secrets Management

- [ ] **SECR-01**: GitHub PAT for each workspace is stored in a Kubernetes Secret via Doppler ExternalSecret (never plaintext in git)
- [ ] **SECR-02**: Server password for each workspace is stored in a Kubernetes Secret via Doppler ExternalSecret
- [ ] **SECR-03**: GitHub Copilot `auth.json` for each workspace is stored in a Kubernetes Secret via Doppler ExternalSecret
- [ ] **SECR-04**: A `seed-copilot-auth.sh` script exists in `scripts/` that reads `~/.local/share/opencode/auth.json` from the local machine and populates the Doppler variable (idempotent, safe to re-run)

### Flux Workspace

- [ ] **FLUX-01**: `https://flux.opencode.angryninja.cloud` loads the OpenCode web UI
- [ ] **FLUX-02**: Accessing the Flux workspace URL without authentication prompts for credentials (password-protected)
- [ ] **FLUX-03**: GitHub Copilot models are available in the Flux workspace UI
- [ ] **FLUX-04**: The Flux workspace working directory is the cloned k8s-cluster git repo
- [ ] **FLUX-05**: On first boot (empty PVC), the k8s-cluster repo is automatically cloned into the workspace PVC
- [ ] **FLUX-06**: On subsequent boots (non-empty PVC), the repo is NOT re-cloned (init container exits in <2s)
- [ ] **FLUX-07**: After pod delete and recreate, previous OpenCode sessions are visible in the UI
- [ ] **FLUX-08**: After pod delete and recreate, GitHub Copilot auth is still valid and models are available
- [ ] **FLUX-09**: AI streaming responses are not cut off mid-response (WebSocket timeout configured via `BackendTrafficPolicy`)

### HA Workspace

- [ ] **HA-01**: `https://ha.opencode.angryninja.cloud` loads the OpenCode web UI
- [ ] **HA-02**: Accessing the HA workspace URL without authentication prompts for credentials (password-protected)
- [ ] **HA-03**: GitHub Copilot models are available in the HA workspace UI
- [ ] **HA-04**: The HA workspace working directory is the cloned home-assistant-config git repo
- [ ] **HA-05**: On first boot (empty PVC), the home-assistant-config repo is automatically cloned into the workspace PVC
- [ ] **HA-06**: On subsequent boots (non-empty PVC), the repo is NOT re-cloned (init container exits in <2s)
- [ ] **HA-07**: After pod delete and recreate, previous OpenCode sessions are visible in the UI
- [ ] **HA-08**: After pod delete and recreate, GitHub Copilot auth is still valid and models are available
- [ ] **HA-09**: AI streaming responses are not cut off mid-response (WebSocket timeout configured via `BackendTrafficPolicy`)

### Security & GitOps

- [ ] **SEC-01**: No secrets (PAT, password, auth.json) appear in any committed git manifest
- [ ] **SEC-02**: All manifests follow the existing cluster GitOps pattern (`ks.yaml` + `app/` structure under `kubernetes/apps/opencode/`)
- [ ] **SEC-03**: GitHub PAT is not visible in pod logs (no `set -x` in init container, PAT not embedded in clone URL)
- [ ] **SEC-04**: Both workspace PVCs use `ReadWriteOnce` access mode with Rook Ceph `ceph-block` storage class, sized at `5Gi`
- [ ] **SEC-05**: Each pod has resource requests of `cpu: 100m, memory: 256Mi` and limits of `cpu: 500m, memory: 512Mi`

## v2 Requirements

### Operational Hardening

- **OPS-01**: Stakater Reloader annotation on Deployments enables zero-touch pod restart when Copilot auth Secret is updated
- **OPS-02**: VolSync `ReplicationSource` is configured for both workspace PVCs (backup to Minio)
- **OPS-03**: ExternalDNS annotations on HTTPRoutes auto-create DNS records for both subdomains
- **OPS-04**: Copilot token expiry re-auth runbook documented in `scripts/README.md`

### Automation

- **AUTO-01**: Optional `git pull` on subsequent boots to sync latest changes before session starts
- **AUTO-02**: Automated Copilot token refresh (non-interactive re-auth — not currently supported by OpenCode)

## Out of Scope

| Feature | Reason |
|---------|--------|
| Multi-replica / HA deployment | `ReadWriteOnce` PVCs only mount to one node; single replica is by design |
| Automatic `git push` from pods | Explicitly excluded in PRD; race conditions and unclear ownership |
| CI/CD pipeline integration | Not part of OpenCode's role in this architecture |
| Repo sync / pull automation | Manual `git pull` from terminal is acceptable for v1 |
| OAuth proxy / SSO in front of OpenCode | Overkill for personal single-user tool; server password is sufficient |
| Custom OpenCode image / Dockerfile | Adds build pipeline complexity; official `ghcr.io/anomalyco/opencode` is sufficient |
| Multi-user support | Personal use only |
| Mobile app | Browser access via any device satisfies the requirement |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| INFRA-01 | Phase 1 | Pending |
| INFRA-02 | Phase 1 | Pending |
| INFRA-03 | Phase 1 | Pending |
| INFRA-04 | Phase 1 | Pending |
| SECR-01 | Phase 1 | Pending |
| SECR-02 | Phase 1 | Pending |
| SECR-03 | Phase 1 | Pending |
| SECR-04 | Phase 1 | Pending |
| FLUX-01 | Phase 2 | Pending |
| FLUX-02 | Phase 2 | Pending |
| FLUX-03 | Phase 2 | Pending |
| FLUX-04 | Phase 2 | Pending |
| FLUX-05 | Phase 2 | Pending |
| FLUX-06 | Phase 2 | Pending |
| FLUX-07 | Phase 2 | Pending |
| FLUX-08 | Phase 2 | Pending |
| FLUX-09 | Phase 2 | Pending |
| HA-01 | Phase 3 | Pending |
| HA-02 | Phase 3 | Pending |
| HA-03 | Phase 3 | Pending |
| HA-04 | Phase 3 | Pending |
| HA-05 | Phase 3 | Pending |
| HA-06 | Phase 3 | Pending |
| HA-07 | Phase 3 | Pending |
| HA-08 | Phase 3 | Pending |
| HA-09 | Phase 3 | Pending |
| SEC-01 | Phase 1 | Pending |
| SEC-02 | Phase 2 | Pending |
| SEC-03 | Phase 2 | Pending |
| SEC-04 | Phase 2 | Pending |
| SEC-05 | Phase 2 | Pending |

**Coverage:**
- v1 requirements: 30 total
- Mapped to phases: 30
- Unmapped: 0 ✓

---
*Requirements defined: 2026-03-01*
*Last updated: 2026-03-01 after initial definition*
