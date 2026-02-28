# Project Research Summary

**Project:** Persistent OpenCode on Kubernetes (Two Workspaces)
**Domain:** Flux GitOps Kubernetes — PVC-backed init-container workload with Envoy Gateway ingress
**Researched:** 2026-03-01
**Confidence:** HIGH — all findings verified against live cluster manifests; no training-data assumptions

## Executive Summary

This project deploys two identical-but-isolated OpenCode AI coding workspaces (`opencode-flux` and `opencode-ha`) onto an existing, opinionated Flux CD GitOps Kubernetes cluster. The cluster is not greenfield — it has a complete, working stack (bjw-s app-template, Rook Ceph, Envoy Gateway, External Secrets via Doppler, VolSync) — and every manifest must conform to existing cluster conventions exactly or break Flux reconciliation chains, SOPS decryption, and validation hooks. The dominant architectural pattern is: **Flux Kustomization → ExternalSecret + OCIRepository + HelmRelease + VolSync template**, and new deployments are most safely created by mirroring the `home-assistant-v2` and `openwebui` app patterns verbatim.

The key technical challenge is a multi-step pod initialization sequence: an `alpine/git` init container must idempotently clone a private GitHub repo to a PVC on first boot (skip if `.git` exists), then seed `auth.json` for GitHub Copilot OAuth, before the main `opencode` container starts. Every secret flows from Doppler → ExternalSecret → Kubernetes Secret (never from SOPS in app directories). One non-obvious TLS gotcha: the cluster's existing wildcard cert (`*.angryninja.cloud`) **does not cover** the planned third-level subdomains (`flux.opencode.angryninja.cloud`, `ha.opencode.angryninja.cloud`) — a dedicated `Certificate` resource for `*.opencode.angryninja.cloud` is required.

The primary operational risk is GitHub Copilot OAuth token expiry, which causes silent model unavailability with no Kubernetes-visible failure. Mitigation is a `seed-copilot-auth.sh` operator script (updates Doppler, triggers pod restart via Stakater Reloader annotation) — this must be built in Phase 1 and tested before declaring the deployment production-ready. With correct fsGroup settings, idempotent init container scripting, and a `BackendTrafficPolicy` for WebSocket timeout, the deployment is low-risk and maps cleanly onto existing cluster patterns.

---

## Key Findings

### Recommended Stack

The cluster stack is already decided; no technology selection is needed. Every new app must use `bjw-s app-template 4.4.0` (the cluster-standard OCIRepository chart), referencing it as an in-namespace OCIRepository at `oci://ghcr.io/bjw-s-labs/helm/app-template:4.4.0`. Secrets exclusively use the Doppler `ClusterSecretStore` named `doppler-secrets` via `external-secrets.io/v1` ExternalSecrets — there is no SOPS-provider SecretStore for app-level secrets. Storage uses Rook Ceph's `ceph-block` default StorageClass with `ReadWriteOnce` PVCs, provisioned via the `../../../../templates/volsync` reference in `app/kustomization.yaml`.

Ingress is Gateway API-only: `bjw-s route:` values block generates an HTTPRoute targeting `envoy-internal` Gateway (port `sectionName: https`). The `appProtocol: kubernetes.io/ws` annotation on the Service port is required for WebSocket streaming. A `BackendTrafficPolicy` with `requestTimeout: 0s` must be created in the `opencode` namespace — this is not inherited from the cluster-level policy and the Home Assistant app proves the pattern.

**Core technologies:**
- **bjw-s app-template `4.4.0`**: HelmRelease chart — every workload on this cluster uses it; provides `controllers`, `initContainers`, `persistence`, `route` in one manifest
- **Flux CD `v2.17.2`**: GitOps reconciliation — already installed; use `kustomize.toolkit.fluxcd.io/v1` and `helm.toolkit.fluxcd.io/v2` apiVersions
- **Envoy Gateway `1.7.0`** (`envoy-internal`): L7 HTTPS ingress — LAN-only, wildcard TLS at Gateway layer, `appProtocol: kubernetes.io/ws` required
- **External Secrets Operator + Doppler** (`ClusterSecretStore: doppler-secrets`): All app secrets — Doppler is the only provider; never use SOPS for app secrets
- **Rook Ceph `v1.18.9`** (`ceph-block`): PVC-backed persistence — `ReadWriteOnce`; one pod per PVC enforced
- **VolSync** (cluster-managed): PVC backup to Minio — referenced via `../../../../templates/volsync`; requires `APP` + `VOLSYNC_CAPACITY` in `ks.yaml` postBuild
- **cert-manager** + `letsencrypt-production` ClusterIssuer: TLS — wildcard `*.angryninja.cloud` does NOT cover third-level subdomains; need new `Certificate` for `*.opencode.angryninja.cloud`
- **Stakater Reloader** (`reloader.stakater.com/auto: "true"`): Pod auto-restart on secret change — enables zero-touch Copilot token refresh

### Expected Features

All features are fully specified in the PRD and PROJECT.md. The MVP is tightly scoped; no ambiguity about what is in vs. out of scope.

**Must have (table stakes):**
- PVC-backed workspace storage (`5Gi`, `ReadWriteOnce`, Rook Ceph) — pod restarts destroy in-memory state without this
- Init container: idempotent git clone (`alpine/git`, check `.git` not just directory) — workspace must start in the correct repo
- Init container: `auth.json` seeding from Secret — Copilot OAuth unavailable without pre-seeded auth
- HTTPS via Envoy Gateway HTTPRoute (`envoy-internal`, `sectionName: https`) — only valid ingress path on this cluster
- `*.opencode.angryninja.cloud` TLS certificate — third-level subdomain not covered by existing wildcard
- Server password protection (`OPENCODE_PASSWORD` env var) — web UI is network-accessible
- Correct `workingDir` per workspace (`/workspace`) — wrong dir = no AI project context
- Kubernetes Secrets via Doppler ExternalSecret — cluster pattern; no plaintext in git
- `seed-copilot-auth.sh` operator script — manual re-auth when Copilot token expires
- Resource limits/requests (`100m/256Mi` req, `500m/512Mi` limit) — protects cluster from runaway pod
- `opencode` namespace + Flux GitOps structure — prerequisites for everything

**Should have (differentiators, add in v1.x):**
- `reloader.stakater.com/auto: "true"` annotation — zero-touch Copilot token refresh after seed
- VolSync PVC backup — protects `auth.json` and session history against Ceph degradation
- External-DNS annotation on HTTPRoute — auto-creates DNS records for both subdomains

**Defer (v2+):**
- Automated Copilot token refresh (non-interactive re-auth in OpenCode — currently requires manual `/connect` on laptop)
- Optional `git pull` init step on subsequent boots (low priority; manual pull from terminal is acceptable)

**Anti-features (explicitly out of scope):**
- Multi-replica / HA deployment (`ReadWriteOnce` PVC only mounts one node)
- Automatic git pull/push from running pod (race conditions, PRD explicitly excluded)
- OAuth proxy / SSO in front of OpenCode (overkill for personal single-user tool)
- Custom OpenCode image / Dockerfile (adds build pipeline; use official `ghcr.io/anomalyco/opencode`)

### Architecture Approach

The deployment follows the cluster's two-level GitOps pattern: a `ks.yaml` Flux Kustomization in `flux-system` namespace points at an `app/` directory containing the actual resources (ExternalSecret, OCIRepository, HelmRelease, VolSync template reference). Two fully independent instances (`opencode-flux` and `opencode-ha`) live in a single `opencode` namespace with separate PVCs, Secrets, and reconciliation lifecycles — they share nothing. The pod initialization sequence has four ordered levels: (1) PVC bound → (2) Secrets synced → (3) Init container runs → (4) Main container starts. HTTPRoutes are generated by the bjw-s `route:` values block, not standalone files.

**Major components:**
1. **`namespace.yaml` + namespace `kustomization.yaml`** — creates `opencode` namespace with `prune: disabled` label; bootstraps the parent aggregator that references both workspace `ks.yaml` files
2. **`opencode-flux/ks.yaml` + `opencode-ha/ks.yaml`** — Flux Kustomizations in `flux-system`; each `dependsOn: [external-secrets-stores, rook-ceph-cluster]`; inject `APP` and `VOLSYNC_CAPACITY` via `postBuild.substitute`
3. **`app/externalsecret.yaml`** — pulls `GITHUB_PAT`, `OPENCODE_PASSWORD`, `COPILOT_AUTH_JSON` from Doppler into a namespaced Kubernetes Secret
4. **`app/ocirepository.yaml`** — references bjw-s app-template `4.4.0` chart from `ghcr.io`
5. **`app/helmrelease.yaml`** — full workload definition: `alpine/git` init container (idempotent clone + auth seed), `opencode web` main container, `route:` to `envoy-internal`, `persistence:` with `advancedMounts` binding PVC to both containers at correct paths
6. **VolSync template** (`../../../../templates/volsync`) — creates PVC + ReplicationSource for Minio backup; PVC name matches `${APP}` anchor in HelmRelease
7. **`BackendTrafficPolicy`** (per-workspace) — sets `requestTimeout: 0s`, `connectionIdleTimeout: 3600s` for WebSocket streaming; must be in `opencode` namespace targeting each HTTPRoute
8. **`Certificate`** (shared) — `*.opencode.angryninja.cloud` via `letsencrypt-production` ClusterIssuer; required before any HTTPS testing

### Critical Pitfalls

1. **Third-level subdomain not covered by wildcard cert** — `*.angryninja.cloud` is a single-level wildcard and does NOT cover `flux.opencode.angryninja.cloud`. Create a `Certificate` resource for `*.opencode.angryninja.cloud` (or list both SANs) referencing the existing `letsencrypt-production` ClusterIssuer, and reference it in the Gateway listener or HTTPRoute TLS config. Certificate must be `Ready: True` before HTTPS testing.

2. **fsGroup mismatch causes silent Copilot auth failure** — If init container (root) writes `auth.json` and main container (UID 1000) can't read it, OpenCode starts healthy but shows no Copilot models. Set `defaultPodOptions.securityContext.fsGroup: 1000` + `fsGroupChangePolicy: OnRootMismatch` and explicitly `chmod 600` + `chown 1000:1000` in the init script. Verify with `kubectl exec … ls -la ~/.local/share/opencode/`.

3. **Init container re-clones on every restart** — Check for `/workspace/.git` (not just `/workspace`) to detect a completed clone. A failed partial clone leaves a directory but no `.git`; the check must handle this: `if [ ! -d /workspace/.git ]; then rm -rf /workspace && git clone ...`. Verify by deleting pod on existing PVC — init container should exit in <2s.

4. **GitHub PAT leaks in pod logs** — `set -x` trace mode or git error messages print the full clone URL including the token. Use `set -e` only (no `-x`), write a `.netrc` file instead of embedding PAT in the URL, and verify with `kubectl logs … -c git-clone | grep ghp_` returns nothing.

5. **WebSocket connections dropped by Envoy Gateway default timeouts** — The cluster-level `BackendTrafficPolicy` is selector-based and does not automatically cover the `opencode` namespace. Create a namespace-scoped `BackendTrafficPolicy` with `requestTimeout: 0s` alongside the HelmRelease (not as an afterthought). Without it, AI streaming cuts off at 60s with no user-visible error.

6. **Flux ExternalSecret overwrites manually-seeded Copilot auth Secret** — If an ExternalSecret targets the same Secret name as the seed script, Flux overwrites the manually-set token on the next sync (~30 min). Choose one authoritative source: store `auth.json` content in Doppler and use ExternalSecret exclusively, OR mark the manually-managed Secret with `kustomize.toolkit.fluxcd.io/prune: disabled` and have no ExternalSecret for it.

7. **Doppler variables must exist before ExternalSecret reconciles** — Add `OPENCODE_FLUX_GITHUB_PAT`, `OPENCODE_FLUX_PASSWORD`, `OPENCODE_FLUX_COPILOT_AUTH_JSON` (and `_HA_` variants) to the Doppler `k3s-cluster/prd` project as a prerequisite step before any Flux reconciliation. Missing variables cause `SecretSyncError` → `CreateContainerConfigError` → pod never starts.

---

## Implications for Roadmap

Based on research, suggested phase structure (4 phases):

### Phase 1: Foundation — Namespace, Certificates, Secrets Infrastructure

**Rationale:** Everything depends on the namespace existing, the TLS certificate being issued, and Doppler secrets being populated. The cert-manager `Certificate` for `*.opencode.angryninja.cloud` has DNS-01 challenge propagation delay (~2 min) and must reach `Ready: True` before any HTTPS testing. Doppler variable population is a hard prerequisite for ExternalSecret reconciliation. Getting these right first prevents the most common class of cascade failures (wrong namespace, missing secrets, cert mismatch).

**Delivers:** `opencode` namespace with prune guard; `*.opencode.angryninja.cloud` Certificate (`Ready: True`); all 6 Doppler variables populated (`OPENCODE_FLUX_*` and `OPENCODE_HA_*`); `seed-copilot-auth.sh` operator script in `scripts/`; Flux Kustomization aggregator in `kubernetes/apps/opencode/kustomization.yaml`.

**Features addressed:** `opencode` namespace, all Kubernetes Secrets (via Doppler), `seed-copilot-auth.sh` script, TLS certificate coverage.

**Pitfalls avoided:** Pitfall 5 (wrong namespace), Pitfall 7 (Doppler variables missing), Pitfall 9 (HTTPRoute namespace restriction / cert mismatch), Pitfall 10 (ExternalSecret overwrite — decide authoritative secret source here).

---

### Phase 2: Flux Workspace Deployment (`opencode-flux`)

**Rationale:** Build and validate one workspace end-to-end before duplicating. The `opencode-flux` workspace (k8s-cluster repo) is the more interesting case operationally — it will be used to edit cluster manifests. Validate the complete init container → main container → PVC → HTTPRoute chain in isolation. The `BackendTrafficPolicy` must be created alongside the HelmRelease (not after), per the pitfall research.

**Delivers:** `opencode-flux/ks.yaml` + `app/` (ExternalSecret, OCIRepository, HelmRelease, VolSync template); `BackendTrafficPolicy` for WebSocket; `flux.opencode.angryninja.cloud` reachable via HTTPS; Copilot models visible in UI; `kubectl exec` confirms `auth.json` readable by UID 1000; init container exits in <2s on second pod start (idempotency verified).

**Stack used:** bjw-s app-template `4.4.0`, `alpine/git` init container, Doppler ExternalSecret (`external-secrets.io/v1`), Rook Ceph `ceph-block` PVC via VolSync template, Envoy Gateway `envoy-internal` HTTPRoute, `BackendTrafficPolicy` (`gateway.envoyproxy.io/v1alpha1`).

**Architecture implemented:** Patterns 1–6 from ARCHITECTURE.md; full `ks.yaml → app/` separation; `advancedMounts` for per-container PVC paths.

**Pitfalls avoided:** Pitfall 1 (fsGroup), Pitfall 2 (re-clone), Pitfall 3 (PAT in logs), Pitfall 4 (WebSocket timeout), Pitfall 8 (subPath directory), Pitfall 12 (app-template version).

---

### Phase 3: HA Workspace Deployment (`opencode-ha`)

**Rationale:** Once the `opencode-flux` pattern is validated, the `opencode-ha` workspace is a near-identical copy with a different repo URL, secret prefix, and subdomain. Doing this as a separate phase avoids debugging two deployments simultaneously.

**Delivers:** `opencode-ha/ks.yaml` + `app/` (parallel to Phase 2 structure); `BackendTrafficPolicy` for `opencode-ha`; `ha.opencode.angryninja.cloud` reachable via HTTPS; both workspaces independently operational.

**Stack used:** Identical to Phase 2; swap `opencode-flux` → `opencode-ha`, k8s-cluster repo URL → home-assistant-config repo URL.

**Pitfalls avoided:** Pitfall 6 (separate PVCs — no sharing between workspaces).

---

### Phase 4: Persistence Validation & Operational Hardening

**Rationale:** Table-stakes features (workspaces running) are done after Phase 3. Phase 4 validates the operational promises: Copilot auth survives restarts, PVC re-attaches after node failure, re-auth workflow is documented and tested, and v1.x enhancements (Reloader, external-dns) are applied.

**Delivers:** Verified idempotency (delete pod → recreate → Copilot models still present); node drain test (PVC re-attaches within 5 min); re-auth runbook documented; Stakater Reloader annotation added; external-dns annotations on HTTPRoutes; VolSync backup confirmed (`ReplicationSource` healthy).

**Features addressed:** `reloader.stakater.com/auto: "true"`, VolSync PVC backup, external-dns annotations, Copilot token expiry re-auth workflow.

**Pitfalls avoided:** Pitfall 6 (PVC VolumeAttachment stuck on node failure), Pitfall 11 (Copilot token expiry — re-auth runbook).

---

### Phase Ordering Rationale

- **Namespace + certs + secrets first:** DNS-01 cert issuance has propagation delay; starting this early means the cert is Ready by the time HTTPS testing begins in Phase 2. Doppler variable population is a hard blocker with no workaround.
- **One workspace before two:** Debugging the init container + fsGroup + PVC mount chain is easier with a single instance. Copying a validated pattern to create the second workspace takes <30 minutes.
- **`BackendTrafficPolicy` in Phase 2 (not Phase 4):** The pitfall research is unambiguous — WebSocket timeout is not an edge case, it's the dominant failure mode for AI streaming interfaces. Must be co-deployed with the HelmRelease.
- **Operational hardening last:** Reloader, VolSync confirmation, and external-dns are enhancements to a working system, not prerequisites for launch.

### Research Flags

Phases with well-documented patterns (skip `/gsd-research-phase`):
- **Phase 2 & 3:** All patterns directly derived from live cluster manifests (`home-assistant-v2`, `openwebui`, `mosquitto`). The HelmRelease skeleton in STACK.md is near-production-ready.
- **Phase 4 (VolSync):** The template is already in the cluster; the `ReplicationSource` pattern is confirmed working for `emhass`, `evcc`, `frigate`, `home-assistant`.

Phases that may benefit from targeted research during planning:
- **Phase 1 (`Certificate` for `*.opencode.angryninja.cloud`):** The Gateway TLS configuration for a non-wildcard-covered subdomain is the one area not directly validated in PITFALLS.md against a live example. Confirm whether to reference the cert from the Gateway listener or the HTTPRoute `tls` block — check `home-assistant` for a per-app cert example if one exists.
- **Phase 4 (Copilot re-auth):** Whether `auth.json` content can be stored as a Doppler variable (it's a JSON blob) needs validation. The ExternalSecret template engine supports this via `{{ .KEY }}` substitution, but confirm encoding requirements.

---

## Confidence Assessment

| Area | Confidence | Notes |
|------|------------|-------|
| Stack | HIGH | Every technology verified against live cluster manifests; no inference |
| Features | HIGH | PRD + PROJECT.md fully specified; competitor analysis complete; anti-features explicit |
| Architecture | HIGH | All 6 patterns derived from working apps in the same cluster; build order validated via `dependsOn` docs |
| Pitfalls | HIGH | 12 pitfalls grounded in cluster manifests + official Kubernetes/Flux/Envoy docs; recovery costs assessed |

**Overall confidence:** HIGH

### Gaps to Address

- **`Certificate` Gateway integration:** Exactly how the new `*.opencode.angryninja.cloud` cert is referenced in the HTTPRoute or Gateway listener needs a concrete example. The wildcard cert is referenced at the Gateway listener level; a per-namespace cert may work differently. Check if any existing cluster app creates its own cert (unlikely) or confirm the cert should be in the `network` namespace referenced by the Gateway's `certificateRefs`.

- **Copilot `auth.json` in Doppler:** The `auth.json` is a multi-line JSON blob. Doppler's ExternalSecret template engine handles this via `{{ .KEY }}`, but the encoding (raw JSON vs. base64) needs one round-trip test to confirm before Phase 1 is declared complete. If raw JSON fails, base64 decode in the init container is the fallback.

- **`envoy-internal` vs `envoy-external` Gateway decision:** FEATURES.md recommends `envoy-internal` (LAN-only, reduces attack surface). STACK.md recommends `envoy-external` (mobile/remote access). The PROJECT.md should resolve this; confirm with project owner before Phase 2 manifest authoring. The difference is one word (`internal` vs `external`) in `parentRefs.name`, but the security implication is significant.

---

## Sources

### Primary (HIGH confidence — live cluster manifests)
- `kubernetes/apps/home/home-assistant-v2/app/helmrelease.yaml` — authoritative init container + git clone + `advancedMounts` pattern
- `kubernetes/apps/ai/openwebui/app/helmrelease.yaml` — `globalMounts` + `route:` + `existingClaim` pattern; VolSync template reference
- `kubernetes/apps/home/home-assistant/app/helmrelease.yaml` — `route:` to `envoy-external`, `appProtocol: ws`, deploy-key `subPath` mount
- `kubernetes/apps/home/home-assistant/app/backendtrafficpolicy.yaml` — WebSocket timeout pattern (`requestTimeout: 0s`)
- `kubernetes/apps/network/envoy-gateway/app/envoy.yaml` — Gateway definitions, TLS wildcard cert reference, `allowedRoutes` scope
- `kubernetes/apps/network/certificates/app/production.yaml` — wildcard cert (`*.angryninja.cloud`) coverage boundary
- `kubernetes/apps/external-secrets/external-secrets/stores/clustersecretstore.yaml` — Doppler is the only `ClusterSecretStore`
- `kubernetes/templates/volsync/` — PVC + ReplicationSource creation via `${APP}` + `${VOLSYNC_CAPACITY}` substitution

### Primary (HIGH confidence — project specification)
- `/Users/jbaker/Development/opencode-remote/docs/PRD.md` — full requirements and architectural decisions
- `/Users/jbaker/git/k8s-cluster/.planning/PROJECT.md` — constraints, key decisions, acceptance criteria

### Secondary (MEDIUM confidence — official docs)
- https://fluxcd.io/flux/components/kustomize/kustomizations/#dependencies — `dependsOn` namespace-scoping behavior
- https://kubernetes.io/docs/concepts/workloads/pods/init-containers/ — init container ordering constraints

---
*Research completed: 2026-03-01*
*Ready for roadmap: yes*
