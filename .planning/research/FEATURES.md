# Feature Research

**Domain:** Persistent Kubernetes workload — personal AI coding workspace
**Researched:** 2026-03-01
**Confidence:** HIGH (PRD fully specified; cluster patterns verified from live cluster source)

---

## Feature Landscape

### Table Stakes (Deployment Is Broken Without These)

Features that must be present or the deployment fails its core purpose.

| Feature | Why Expected | Complexity | Notes |
|---------|--------------|------------|-------|
| **PVC-backed workspace storage** | Code and session data must survive pod restarts; without this the deployment is stateless and useless | LOW | One PVC per workspace; `5Gi`, `ReadWriteOnce`, Rook Ceph default class. Mount `/workspace` (repo) and `~/.local/share/opencode` (session DB + auth) as subPaths on same PVC |
| **PVC-backed auth.json persistence** | GitHub Copilot OAuth token lives at `~/.local/share/opencode/auth.json`; if not persisted, Copilot becomes unavailable on every pod restart | LOW | Use `subPath: opencode-data` on the workspace PVC — same PVC, second mount point. Do NOT use a separate PVC |
| **Init container: idempotent git clone** | Workspace must start in the correct git repo; must not re-clone if repo already exists on PVC (would blow away local changes) | MEDIUM | `alpine/git` image; check `[ -d /workspace/<repo>/.git ]` before cloning; inject GitHub PAT via Secret env var. This pattern exists (commented out) in `home-assistant` helmrelease — reactivate and adapt |
| **Init container: auth.json seeding** | `auth.json` must be pre-loaded before OpenCode starts or Copilot won't authenticate; can't do this after main container is running | LOW | `busybox` image; copy from Secret volume mount only if file doesn't already exist on PVC. Idempotent: `[ -f /data/opencode-data/auth.json ] \|\| cp /secrets/auth.json /data/opencode-data/` |
| **GitHub PAT in Kubernetes Secret** | Private repos require auth; hardcoding PAT in manifests is a security violation and would be committed to git | LOW | Secret: `opencode-git-credentials`, key `GITHUB_PAT`. Use HTTPS clone URL: `https://<PAT>@github.com/...`. Follow cluster's Doppler/ExternalSecret pattern for secret creation |
| **HTTPS via Envoy Gateway HTTPRoute** | Cluster uses Envoy Gateway exclusively; no other ingress controller. `gateway.networking.k8s.io/v1` HTTPRoute is the only valid ingress mechanism | LOW | Parent ref: `envoy-internal` for personal-use subdomain (not externally exposed). Pattern confirmed in `openwebui` and `home-assistant` helmreleases. TLS terminated at Gateway listener (existing wildcard cert `${SECRET_DOMAIN/./-}-production-tls`) |
| **cert-manager TLS certificate** | HTTPS requires a valid cert; browser will reject self-signed | LOW | ClusterIssuer already exists cluster-wide. Use `Certificate` resource or rely on Gateway's existing wildcard TLS secret. Verify which is appropriate — the existing Gateway listener already has `certificateRefs` pointing to the wildcard secret, so individual `Certificate` resources may be unnecessary |
| **Server password protection** | Web UI is internet-accessible (or at minimum cluster-accessible); must require authentication | LOW | `OPENCODE_SERVER_PASSWORD` env var from Kubernetes Secret `opencode-server-auth`. Username defaults to `opencode`. No additional auth layer needed |
| **Correct `workingDir` per workspace** | OpenCode must start in the repo directory to have project context; wrong dir = no AI context | LOW | `workingDir: /workspace/<repo-name>` in main container spec. Depends on init container having cloned the repo first |
| **Resource limits and requests** | Without limits, a runaway pod could starve other cluster workloads | LOW | `requests: cpu 100m, memory 256Mi` / `limits: cpu 500m, memory 512Mi` per PRD. Consistent with other cluster apps |
| **Flux GitOps manifest structure** | Cluster is Flux-managed; resources not in the GitOps structure won't be reconciled | LOW | `kubernetes/apps/opencode/<workspace>/` with `ks.yaml` + `app/` structure. `ks.yaml` must declare `dependsOn: external-secrets-stores` |
| **`opencode` namespace** | Isolates workloads; follows cluster convention of one namespace per logical group | LOW | New namespace; add `namespace.yaml` + entry in cluster namespace kustomization |

### Differentiators (Valuable for This Personal Use Case)

Features that make the deployment genuinely better than the minimum viable version.

| Feature | Value Proposition | Complexity | Notes |
|---------|-------------------|------------|-------|
| **`seed-copilot-auth.sh` operator script** | One-command flow to re-seed `auth.json` when Copilot token expires — without this, recovery requires manual `kubectl` steps | LOW | Reads `~/.local/share/opencode/auth.json` from local machine; calls `kubectl create secret ... --from-file` with `--dry-run=client -o yaml \| kubectl apply`. Must be idempotent. Not a cluster resource — lives in `scripts/` of cluster repo |
| **Doppler ExternalSecret for all secrets** | Follows cluster-wide pattern; secrets are version-controlled (encrypted), recoverable, and auditable. Doppler already used by every other app | MEDIUM | Requires adding `OPENCODE_GITHUB_PAT`, `OPENCODE_SERVER_PASSWORD`, and `OPENCODE_COPILOT_AUTH_JSON` to Doppler. `auth.json` is a JSON blob — template it into Secret using Doppler's template engine. Complexity comes from `auth.json` being a file not a simple string |
| **`reloader.stakater.com/auto: "true"` annotation** | Secret changes (e.g. new Copilot token) automatically trigger pod restart and pick up new `auth.json` — no manual `kubectl rollout restart` needed | LOW | One annotation on the Deployment. Already used by `mosquitto` and `openwebui`. Depends on `stakater/reloader` being installed on cluster (verify) |
| **VolSync PVC backup** | Protects session history and code from node failure / Ceph degradation. Session loss is annoying; code loss is serious | MEDIUM | Cluster already has VolSync. Pattern exists in `emhass`, `evcc`, `frigate`, `home-assistant`. Add `VOLSYNC_CAPACITY: 5Gi` and `VOLSYNC_SCHEDULE` to ks.yaml postBuild substitutions. Not needed for v1 but easy to add |
| **Internal-only Gateway exposure** | `opencode.angryninja.cloud` subdomains behind `envoy-internal` Gateway (not `envoy-external`) reduces attack surface for a personal tool | LOW | Simply use `envoy-internal` as parentRef instead of `envoy-external`. Pattern confirmed in `openwebui` and `home-assistant` code-server sidecar. No extra complexity |
| **`external-dns` annotation on HTTPRoute** | Automatic DNS record creation for `flux.opencode.angryninja.cloud` and `ha.opencode.angryninja.cloud` — without it, DNS must be configured manually | LOW | Add `external-dns.home.arpa/enabled: "true"` annotation to HTTPRoute. Already used cluster-wide |

### Anti-Features (Deliberately Do NOT Build)

Features that seem useful but add complexity without matching value for this use case.

| Feature | Why Requested | Why Problematic | Alternative |
|---------|---------------|-----------------|-------------|
| **Automatic `git pull` / repo sync** | "Keep code up to date automatically" | Race condition with OpenCode writing files; would need conflict resolution; PRD explicitly out of scope | Manual `git pull` inside the workspace terminal when needed |
| **Automatic `git push` of OpenCode changes** | "Persist code changes to GitHub" | OpenCode may produce partial/broken commits; requires SSH key management or PAT write scope; PRD explicitly out of scope | Manual `git push` from workspace terminal |
| **Multi-replica / HA deployment** | "Survive node failure without downtime" | `ReadWriteOnce` PVC only mounts to one node — multiple replicas would fight over PVC; OpenCode has no multi-instance coordination | `replicas: 1` with fast pod restart. PVC re-attaches on new node. Acceptable for personal use |
| **Separate PVCs for code vs auth** | "Clean separation of concerns" | Two PVCs per workspace = 4 PVCs total; subPath mounts on a single PVC achieve the same separation with half the storage resources | Single PVC per workspace using `subPath` mounts |
| **OAuth proxy / SSO in front of OpenCode** | "Enterprise-grade authentication" | Extra component (oauth2-proxy, Authelia); overkill for personal single-user tool; OpenCode's built-in password is sufficient | `OPENCODE_SERVER_PASSWORD` env var — already built into OpenCode |
| **Horizontal Pod Autoscaler** | "Auto-scale under load" | Single user; OpenCode is not a compute-intensive web service needing auto-scaling; HPA requires metrics-server and adds complexity | Fixed `replicas: 1` with appropriate resource limits |
| **Dedicated NetworkPolicy** | "Zero-trust pod-to-pod security" | Personal cluster; not a multi-tenant environment; adds manifest complexity for no practical security gain | Namespace isolation via `opencode` namespace is sufficient |
| **Sidecar git-sync container** | "Always-on git synchronization" | Creates write contention with OpenCode; `k8s.gcr.io/git-sync` runs continuously; conflicts with the "no auto-sync" requirement | Init container for clone-on-boot only is the correct pattern |
| **Custom OpenCode image / Dockerfile** | "Pin specific version or add tools" | Adds image build pipeline, registry, and maintenance burden; `ghcr.io/anomalyco/opencode:latest` is the official image | Use official image; accept latest tag until stability is proven |
| **Secrets in `kustomization.yaml` secretGenerator** | "Simple secret creation" | Stores secret values in plaintext in git history; violates cluster security posture | Doppler ExternalSecret (cluster pattern) or manually created Secrets |

---

## Feature Dependencies

```
[HTTPS access]
    └──requires──> [HTTPRoute]
                       └──requires──> [ClusterIP Service]
                       └──requires──> [Envoy Gateway (existing)]
                       └──requires──> [TLS cert (existing wildcard or new Certificate)]

[OpenCode web UI]
    └──requires──> [Deployment]
                       └──requires──> [PVC mounted at /workspace and ~/.local/share/opencode]
                       └──requires──> [workingDir = /workspace/<repo>]
                       └──requires──> [OPENCODE_SERVER_PASSWORD Secret]
                       └──requires──> [Init: git clone]
                                          └──requires──> [GITHUB_PAT Secret]
                                          └──requires──> [PVC exists and is writable]
                       └──requires──> [Init: auth.json seed]
                                          └──requires──> [copilot-auth Secret]
                                          └──requires──> [PVC exists and is writable]

[GitHub Copilot models available]
    └──requires──> [auth.json present on PVC]
                       └──requires──> [Init: auth.json seed (first boot)]
                       └──requires──> [auth.json persisted on PVC (subsequent boots)]

[seed-copilot-auth.sh script]
    └──requires──> [local auth.json exists (run /connect on laptop first)]
    └──enhances──> [GitHub Copilot models available] (recovery when token expires)

[reloader auto-restart]
    └──enhances──> [GitHub Copilot models available] (picks up refreshed auth Secret)
    └──requires──> [stakater/reloader installed on cluster]

[VolSync backup]
    └──enhances──> [PVC-backed persistence] (adds durability against storage failure)
    └──requires──> [VolSync operator installed (already on cluster)]

[Flux reconciliation]
    └──requires──> [ks.yaml in correct GitOps path]
    └──requires──> [dependsOn: external-secrets-stores]
```

### Dependency Notes

- **Init containers require PVC before Deployment can start:** Kubernetes guarantees init containers run before the main container, but the PVC must be `Bound` before the pod schedules. If Rook Ceph is degraded, the pod will stay `Pending`. This is expected behavior.
- **Init: git clone must precede Init: auth.json seed** in ordering — both mount the same PVC and the ordering prevents race conditions. In practice, Kubernetes runs init containers sequentially in declaration order.
- **`workingDir` depends on git clone succeeding:** If the init container fails (bad PAT, network issue), the main container never starts. This is desirable — a broken workspace is better than a misleading one.
- **Reloader annotation conflicts with manual pod management:** If the operator is manually managing pods, unexpected restarts from Reloader could be surprising. Acceptable trade-off for the convenience.
- **VolSync conflicts with `ReadWriteOnce` during backup:** VolSync uses a snapshot approach that doesn't require detaching the PVC. Confirm `VolumeSnapshot` CRD is present on cluster before enabling.

---

## MVP Definition

### Launch With (v1)

Minimum to satisfy all acceptance criteria from PROJECT.md.

- [ ] **`opencode` namespace** — prerequisite for everything else
- [ ] **3 Kubernetes Secrets** — `opencode-git-credentials` (PAT), `opencode-server-auth` (password), `opencode-copilot-auth` (auth.json) — created via Doppler ExternalSecret or manually
- [ ] **`seed-copilot-auth.sh` script** — needed to bootstrap `auth.json` Secret before first deployment
- [ ] **Flux workspace Deployment** — with two init containers (git clone + auth seed), PVC mounts, password env, resource limits
- [ ] **Flux workspace PVC** — `5Gi`, `ReadWriteOnce`
- [ ] **Flux workspace Service + HTTPRoute** — `flux.opencode.angryninja.cloud`, internal Gateway, TLS
- [ ] **HA workspace Deployment** — identical structure, different repo URL and subdomain
- [ ] **HA workspace PVC** — `5Gi`, `ReadWriteOnce`
- [ ] **HA workspace Service + HTTPRoute** — `ha.opencode.angryninja.cloud`, internal Gateway, TLS
- [ ] **Flux ks.yaml** — both workspaces declared, `dependsOn: external-secrets-stores`

### Add After Validation (v1.x)

Add once both workspaces are confirmed working end-to-end.

- [ ] **`reloader.stakater.com/auto: "true"` annotation** — add after confirming Reloader is installed; enables zero-touch Copilot token refresh
- [ ] **VolSync PVC backup** — add `ReplicationSource` after validating session persistence; protects against storage failure
- [ ] **External-DNS annotations on HTTPRoutes** — add if DNS records aren't auto-created; requires confirming ExternalDNS watches internal Gateway

### Future Consideration (v2+)

Defer until the core workspace pattern has been used in practice for weeks.

- [ ] **Automated Copilot token refresh** — investigate whether OpenCode can re-authenticate non-interactively; currently requires manual `/connect` on laptop + re-run of seed script
- [ ] **Second init container for `git pull`** — if stale repos become a pain point, add an optional pull step that runs only if `git status` shows the repo is N commits behind

---

## Feature Prioritization Matrix

| Feature | User Value | Implementation Cost | Priority |
|---------|------------|---------------------|----------|
| PVC-backed workspace storage | HIGH | LOW | P1 |
| Init container: idempotent git clone | HIGH | MEDIUM | P1 |
| Init container: auth.json seeding | HIGH | LOW | P1 |
| HTTPS via Envoy Gateway HTTPRoute | HIGH | LOW | P1 |
| Server password protection | HIGH | LOW | P1 |
| Correct `workingDir` per workspace | HIGH | LOW | P1 |
| Kubernetes Secrets for all credentials | HIGH | LOW | P1 |
| Flux GitOps manifest structure | HIGH | LOW | P1 |
| `seed-copilot-auth.sh` operator script | HIGH | LOW | P1 |
| Resource limits/requests | MEDIUM | LOW | P1 |
| `opencode` namespace | LOW | LOW | P1 |
| Doppler ExternalSecret (vs manual secrets) | MEDIUM | MEDIUM | P2 |
| Reloader auto-restart on secret change | MEDIUM | LOW | P2 |
| External-DNS annotations | MEDIUM | LOW | P2 |
| Internal-only Gateway exposure | MEDIUM | LOW | P2 |
| VolSync PVC backup | MEDIUM | MEDIUM | P2 |
| Automated Copilot token refresh | HIGH | HIGH | P3 |
| Git pull on boot (optional) | LOW | LOW | P3 |

**Priority key:**
- P1: Must have for launch (deployment is broken/unusable without it)
- P2: Should have; add in v1.x once core is validated
- P3: Nice to have; defer until need is demonstrated in practice

---

## Competitor Feature Analysis

> This is a personal infrastructure deployment, not a consumer product. "Competitors" are alternative approaches to the same problem.

| Feature | Run OpenCode on Laptop (status quo) | code-server on Kubernetes (alternative) | This Deployment (OpenCode on K8s) |
|---------|-------------------------------------|----------------------------------------|-----------------------------------|
| Device independence | ❌ Laptop-dependent | ✅ Browser access | ✅ Browser access |
| GitHub Copilot support | ✅ Native | ⚠️ Via extension; less integrated | ✅ Native (`auth.json` persistence) |
| Session persistence | ❌ Lost on close | ✅ Via PVC | ✅ Via PVC |
| Git context per project | ✅ Native | ✅ If configured | ✅ Via init container |
| Cluster visibility | ❌ None | ❌ None | ✅ In-cluster — can access cluster APIs |
| AI-native UX | ✅ OpenCode native | ❌ General IDE | ✅ OpenCode native |
| Token/auth lifecycle | ✅ Automatic refresh | N/A | ⚠️ Manual re-seed when token expires |

---

## Sources

- `/Users/jbaker/Development/opencode-remote/docs/PRD.md` — Primary requirements; HIGH confidence
- `/Users/jbaker/git/k8s-cluster/.planning/PROJECT.md` — Constraints and key decisions; HIGH confidence
- `/Users/jbaker/git/k8s-cluster/kubernetes/apps/ai/openwebui/app/helmrelease.yaml` — bjw-s app-template pattern with `route:`, init containers, PVC persistence; HIGH confidence (live cluster)
- `/Users/jbaker/git/k8s-cluster/kubernetes/apps/home/mosquitto/app/helmrelease.yaml` — Init container seeding secrets to PVC; HIGH confidence (live cluster)
- `/Users/jbaker/git/k8s-cluster/kubernetes/apps/home/home-assistant/app/helmrelease.yaml` — Commented-out git-sync init container using `alpine/git`; direct template for git clone pattern; HIGH confidence (live cluster)
- `/Users/jbaker/git/k8s-cluster/kubernetes/apps/home/tesla-proxy/app/httproute.yaml` — HTTPRoute `gateway.networking.k8s.io/v1` pattern with `envoy-external`; HIGH confidence (live cluster)
- `/Users/jbaker/git/k8s-cluster/kubernetes/apps/network/envoy-gateway/app/envoy.yaml` — Gateway definitions (`envoy-internal`, `envoy-external`), TLS config, existing wildcard cert reference; HIGH confidence (live cluster)
- `/Users/jbaker/git/k8s-cluster/kubernetes/apps/home/mosquitto/app/externalsecret.yaml` — Doppler ExternalSecret pattern; HIGH confidence (live cluster)

---
*Feature research for: Persistent OpenCode on Kubernetes*
*Researched: 2026-03-01*
