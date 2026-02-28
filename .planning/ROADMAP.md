# Roadmap: Persistent OpenCode on Kubernetes

## Overview

Four phases deliver two always-on OpenCode workspaces accessible via browser from any device. Phase 1 lays the infrastructure that everything depends on (namespace, TLS cert, secrets). Phase 2 deploys and fully validates the Flux workspace end-to-end. Phase 3 mirrors that pattern for the HA workspace. Phase 4 confirms the core value proposition — that sessions and Copilot auth survive pod restarts — and adds operational hardening.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: Foundation** - Namespace, TLS certificate, and all secrets infrastructure in place
- [ ] **Phase 2: Flux Workspace** - `opencode-flux` fully deployed, reachable, and Copilot-enabled
- [ ] **Phase 3: HA Workspace** - `opencode-ha` fully deployed, reachable, and Copilot-enabled
- [ ] **Phase 4: Persistence Validation** - Pod-restart survival and operational hardening confirmed

## Phase Details

### Phase 1: Foundation
**Goal**: All prerequisites exist so workspace deployments cannot fail on missing infrastructure
**Depends on**: Nothing (first phase)
**Requirements**: INFRA-01, INFRA-02, INFRA-03, INFRA-04, SECR-01, SECR-02, SECR-03, SECR-04, SEC-01
**Success Criteria** (what must be TRUE):
  1. `opencode` namespace exists in the cluster and `kubectl get namespace opencode` returns `Active`
  2. `*.opencode.angryninja.cloud` Certificate shows `Ready: True` in cert-manager (verified with `kubectl get certificate -n network`)
  3. All 6 Doppler variables (`OPENCODE_FLUX_*` and `OPENCODE_HA_*`) are populated in the Doppler `k8s-cluster/prd` project
  4. `scripts/seed-copilot-auth.sh` exists, runs idempotently, and updates Doppler without errors
  5. `grep -r 'ghp_\|auth.json' kubernetes/apps/opencode/` returns no matches in committed manifests
**Plans**: TBD

Plans:
- [ ] 01-01: Create `opencode` namespace + Flux aggregator kustomization
- [ ] 01-02: Create `*.opencode.angryninja.cloud` Certificate resource
- [ ] 01-03: Populate Doppler variables + write `seed-copilot-auth.sh` script

### Phase 2: Flux Workspace
**Goal**: `flux.opencode.angryninja.cloud` serves the OpenCode UI with Copilot models available and WebSocket streaming uninterrupted
**Depends on**: Phase 1
**Requirements**: FLUX-01, FLUX-02, FLUX-03, FLUX-04, FLUX-05, FLUX-06, FLUX-07, FLUX-08, FLUX-09, SEC-02, SEC-03, SEC-04, SEC-05
**Success Criteria** (what must be TRUE):
  1. `https://flux.opencode.angryninja.cloud` loads the OpenCode web UI and prompts for a password when accessed without credentials
  2. GitHub Copilot models are listed and selectable in the Flux workspace UI
  3. The workspace working directory is `/Users/jbaker/git/k8s-cluster` (correct repo, not home dir)
  4. Deleting the `opencode-flux` pod and waiting for recreation: OpenCode sessions are still visible in the UI
  5. `kubectl logs opencode-flux-<pod> -c git-clone | grep 'ghp_'` returns no output (PAT not in logs)
  6. A second pod delete on a populated PVC: init container exits in under 2 seconds (no re-clone)
**Plans**: TBD

Plans:
- [ ] 02-01: Create `opencode-flux` ks.yaml + ExternalSecret + OCIRepository
- [ ] 02-02: Create HelmRelease with init container, PVC, HTTPRoute, resource limits
- [ ] 02-03: Create BackendTrafficPolicy for WebSocket timeout + validate end-to-end

### Phase 3: HA Workspace
**Goal**: `ha.opencode.angryninja.cloud` serves the OpenCode UI with the home-assistant-config repo loaded and Copilot available
**Depends on**: Phase 2
**Requirements**: HA-01, HA-02, HA-03, HA-04, HA-05, HA-06, HA-07, HA-08, HA-09
**Success Criteria** (what must be TRUE):
  1. `https://ha.opencode.angryninja.cloud` loads the OpenCode web UI and prompts for a password when accessed without credentials
  2. GitHub Copilot models are listed and selectable in the HA workspace UI
  3. The workspace working directory contains the home-assistant-config repo (not the k8s-cluster repo)
  4. Deleting the `opencode-ha` pod and waiting for recreation: OpenCode sessions are still visible in the UI
  5. Both workspaces are independently operational — restarting one pod does not affect the other
**Plans**: TBD

Plans:
- [ ] 03-01: Create `opencode-ha` ks.yaml + app/ directory (mirrored from Phase 2 pattern)
- [ ] 03-02: Validate HA workspace end-to-end (HTTPS, Copilot, correct repo, idempotency)

### Phase 4: Persistence Validation
**Goal**: The core value proposition is confirmed — sessions and Copilot auth survive indefinitely — and the system is hardened for daily use
**Depends on**: Phase 3
**Requirements**: (validation of previously mapped requirements; no new v1 requirements)
**Success Criteria** (what must be TRUE):
  1. After pod delete on both workspaces: Copilot auth is still valid and models are available (no re-auth needed)
  2. VolSync `ReplicationSource` for both workspace PVCs shows `lastSyncTime` updated (backup confirmed working)
  3. `seed-copilot-auth.sh` re-auth workflow is fully tested: running the script updates Doppler, pod restarts, Copilot still works
  4. Stakater Reloader annotation is present on both Deployments and a secret-change → pod restart cycle completes without manual intervention
**Plans**: TBD

Plans:
- [ ] 04-01: Validate persistence (pod-delete tests on both workspaces, VolSync backup confirmation)
- [ ] 04-02: Add Stakater Reloader annotation + test end-to-end re-auth workflow

## Progress

**Execution Order:**
Phases execute in numeric order: 1 → 2 → 3 → 4

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. Foundation | 0/3 | Not started | - |
| 2. Flux Workspace | 0/3 | Not started | - |
| 3. HA Workspace | 0/2 | Not started | - |
| 4. Persistence Validation | 0/2 | Not started | - |
