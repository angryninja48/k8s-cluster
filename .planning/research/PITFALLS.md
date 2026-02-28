# Pitfalls Research

**Domain:** Persistent Kubernetes workload — init-container secret seeding, PVC-backed sessions, Envoy Gateway ingress, Flux GitOps
**Researched:** 2026-03-01
**Confidence:** HIGH (grounded in actual cluster manifests + official docs)

---

## Critical Pitfalls

### Pitfall 1: Init Container Writes Files Init Container Can't Read Back (fsGroup Mismatch)

**What goes wrong:**
The `seed-auth` init container copies `auth.json` from a Secret volume to the PVC. The main OpenCode container then runs as a different UID and cannot read the file. Pod starts, but OpenCode sees no Copilot auth and silently falls back to "no provider available." No crash, no error in pod logs — just missing models.

**Why it happens:**
Init containers and the main container share the same `fsGroup` from `defaultPodOptions.securityContext`, but if that is omitted or the init container runs as root while the main container runs as non-root, ownership of newly created files is root:root (mode 0600 by default for Secrets). The main container user cannot read them.

**How to avoid:**
Set `defaultPodOptions.securityContext.fsGroup` and `fsGroupChangePolicy: OnRootMismatch` in the bjw-s app-template values. Explicitly `chmod 600` and `chown` in the init container script to the target UID/GID. Verify by running `kubectl exec -it <pod> -- ls -la ~/.local/share/opencode/` before declaring success.

```yaml
defaultPodOptions:
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    fsGroupChangePolicy: OnRootMismatch
```

**Warning signs:**
- OpenCode web UI loads but GitHub Copilot does not appear in `/models`
- `kubectl exec` into the pod and `cat ~/.local/share/opencode/auth.json` returns "Permission denied"
- Init container exits 0 (success) but main container logs show no Copilot provider

**Phase to address:** Phase 1 (Namespace & Secrets) — define security context before writing any init container logic

---

### Pitfall 2: Init Container Re-Clones Repo on Every Pod Restart (Idempotency Check Wrong)

**What goes wrong:**
The git-clone init container tests the wrong condition and re-clones the repo on every pod restart, destroying any uncommitted changes in the working directory. The check `if [ -d /workspace/<repo> ]` passes even when the directory is empty (e.g., after a failed clone left an empty dir). Or the check tests for the directory but not for `.git` presence.

**Why it happens:**
A common pattern is `if [ ! -d /workspace/repo ]; then git clone ...`. But if a previous clone failed mid-way and left a partial directory, the check passes and no re-clone occurs — leaving a broken repo. Alternatively, if the directory check is absent, every restart blows away the code.

**How to avoid:**
Check for a non-empty `.git` directory specifically:
```sh
if [ ! -d /workspace/repo/.git ]; then
  rm -rf /workspace/repo  # clean up any partial clone
  git clone https://${GITHUB_PAT}@github.com/org/repo.git /workspace/repo
fi
```
This handles: fresh PVC (clone), completed PVC (skip), and failed-partial-clone (re-clone).

**Warning signs:**
- Uncommitted changes disappear after a pod restart
- Init container takes 30–120s on every restart (network clone time visible in pod events)
- `kubectl describe pod` shows init container re-running longer than expected for a no-op

**Phase to address:** Phase 2 (Flux Workspace deployment) — init container script must be reviewed before merge

---

### Pitfall 3: GitHub PAT Embedded in Clone URL Appears in Pod Logs

**What goes wrong:**
The git clone command uses HTTPS with the PAT embedded: `git clone https://$GITHUB_PAT@github.com/...`. If the shell script has `set -x` (trace mode), or if the command fails and outputs usage/error text, the full URL including the token is printed to stdout and captured in pod logs — visible to anyone who can run `kubectl logs`.

**Why it happens:**
Init container scripts often use `set -e` for error-on-fail, and developers add `set -x` for debugging without removing it before merge. Git error messages also sometimes reflect the URL passed to them.

**How to avoid:**
- Use `set -e` without `-x` in the init container entrypoint script
- Use `git config credential.helper` or write a `.netrc` file instead of embedding in the URL:
  ```sh
  echo "machine github.com login x-access-token password ${GITHUB_PAT}" > ~/.netrc
  chmod 600 ~/.netrc
  git clone https://github.com/org/repo.git /workspace/repo
  rm ~/.netrc
  ```
- Mask the PAT: `git clone "https://x-access-token:${GITHUB_PAT}@github.com/..."` and explicitly test with `git -c http.extraHeader="Authorization: Bearer $GITHUB_PAT" clone ...`

**Warning signs:**
- `kubectl logs <pod> -c git-clone` output contains `https://ghp_` strings
- Cluster audit logs show PAT-bearing URLs in container command args

**Phase to address:** Phase 2 — review init container script before committing

---

### Pitfall 4: OpenCode WebSocket Connections Dropped by Envoy Gateway Default Timeouts

**What goes wrong:**
The OpenCode web UI uses WebSocket connections for real-time streaming of AI responses. Envoy Gateway's default `requestTimeout` is not infinite — and any connection idle for longer than the timeout is silently dropped. Users see the AI response cut off mid-stream, or the UI hangs indefinitely with no error.

**Why it happens:**
The cluster's global `BackendTrafficPolicy` already sets `requestTimeout: 0s` (unlimited) on the Envoy gateway-level policy, but this is a **selector-based** policy targeting `Gateway` resources — not automatically inherited by all `HTTPRoute` resources in new namespaces. A new namespace (`opencode`) may not be covered without explicitly confirming the policy applies.

The cluster already solved this for Home Assistant with a namespace-scoped `BackendTrafficPolicy` (see `kubernetes/apps/home/home-assistant/app/backendtrafficpolicy.yaml` — `requestTimeout: 0s`, `connectionIdleTimeout: 3600s`).

**How to avoid:**
Create a `BackendTrafficPolicy` in the `opencode` namespace targeting the OpenCode HTTPRoutes, mirroring the Home Assistant pattern:
```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: BackendTrafficPolicy
metadata:
  name: opencode-timeouts
  namespace: opencode
spec:
  targetRefs:
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: opencode-flux
  timeout:
    http:
      requestTimeout: 0s
      connectionIdleTimeout: 3600s
```

Also set `appProtocol: kubernetes.io/ws` on the Service port — already the established pattern for evcc, frigate, zigbee2mqtt, Home Assistant in this cluster.

**Warning signs:**
- AI responses cut off after exactly 15s or 60s (default gateway timeout values)
- Browser console shows WebSocket `1006: Abnormal Closure` errors
- `kubectl logs` on envoy pods shows `upstream request timeout`

**Phase to address:** Phase 2 (Flux Workspace) — add BackendTrafficPolicy alongside HTTPRoute, not as an afterthought

---

### Pitfall 5: Secret Not in Correct Namespace — ExternalSecret or Manual Secret Created in Wrong Namespace

**What goes wrong:**
The PRD specifies secrets in the `opencode` namespace. The cluster's secret pattern uses Doppler via ExternalSecrets (`ClusterSecretStore: doppler-secrets`). If the `ExternalSecret` is created before the `opencode` namespace exists (or in `flux-system`), the resulting Kubernetes Secret lands in the wrong namespace. The pod's `envFrom` or `volumeMount` referencing the secret fails with `secret not found`, causing `CreateContainerConfigError`.

**Why it happens:**
In Flux ks.yaml, `targetNamespace` must be set correctly AND the namespace Kustomization must be a `dependsOn` target. If the namespace ks.yaml uses `wait: false`, the ExternalSecret Kustomization may apply before the namespace exists.

**How to avoid:**
Structure the ks.yaml with explicit dependency ordering:
```yaml
# namespace ks.yaml
spec:
  wait: true
  path: ./kubernetes/apps/opencode/namespace
---
# secrets ks.yaml
spec:
  dependsOn:
    - name: opencode-namespace
    - name: external-secrets-stores
  path: ./kubernetes/apps/opencode/secrets
---
# workloads ks.yaml
spec:
  dependsOn:
    - name: opencode-secrets
    - name: rook-ceph-cluster  # PVC provisioner
  path: ./kubernetes/apps/opencode/flux-workspace
```

**Warning signs:**
- `kubectl get externalsecrets -n opencode` shows `SecretSyncError` or empty
- `kubectl describe pod` shows `CreateContainerConfigError: secret "opencode-git-credentials" not found`
- `kubectl get secret -n opencode` returns nothing despite ExternalSecrets existing

**Phase to address:** Phase 1 (Namespace & Secrets) — dependency ordering is the first thing to get right

---

### Pitfall 6: PVC Bound to Wrong Node — ReadWriteOnce Prevents Pod Rescheduling

**What goes wrong:**
Rook Ceph PVCs with `ReadWriteOnce` access mode can only be mounted by one node at a time. If the pod is rescheduled to a different node (e.g., after a node drain or failure), Kubernetes may not be able to mount the PVC on the new node if the previous node still has the volume attachment. The pod stays in `ContainerCreating` indefinitely.

**Why it happens:**
On a 3-node cluster with Rook Ceph, the `volumeattachment` object from the previous node may not be cleaned up promptly when a node goes down uncleanly (e.g., power loss). The new pod waits for the old attachment to be released, which requires `kubectl delete volumeattachment` manually or node recovery.

**How to avoid:**
- Use Rook Ceph's default storage class which provides block storage accessible from any node (replication factor ≥ 2) — this is already the cluster default
- Set `terminationGracePeriodSeconds: 30` (not 0) so the pod has time to release the volume before the node-level timeout
- Confirm the storage class is `ReadWriteOnce` backed by Ceph RBD (not local-path which is node-pinned)

**Warning signs:**
- Pod stuck in `ContainerCreating` after node failure or drain
- `kubectl describe pod` shows: `Multi-Attach error for volume ... Volume is already used by pod(s) on node`
- `kubectl get volumeattachment` shows a stale attachment to a now-dead node

**Phase to address:** Phase 4 (Persistence Validation) — deliberately drain a node and verify recovery

---

### Pitfall 7: Doppler Secret Variables Not Added to Doppler Project — ExternalSecret Silently Fails

**What goes wrong:**
The cluster uses Doppler (not SOPS) as the secrets backend for all app ExternalSecrets (`ClusterSecretStore: doppler-secrets`, project `k3s-cluster`, config `prd`). New secrets for the `opencode` app must be **added to the Doppler `k3s-cluster/prd` project** before the ExternalSecret can resolve them. If variables are missing, the ExternalSecret enters `SecretSyncError` with a message like `could not find key GITHUB_PAT_OPENCODE in Doppler`.

**Why it happens:**
The PRD describes "SOPS ExternalSecret" but the actual cluster pattern is Doppler-backed ExternalSecrets. Anyone following the PRD literally and creating SOPS-encrypted Secret manifests will find them ignored — the cluster's ExternalSecrets operator only syncs from Doppler.

**How to avoid:**
Add required variables to Doppler (`k3s-cluster/prd` config) **before** writing ExternalSecret manifests:
- `OPENCODE_GITHUB_PAT` — GitHub Personal Access Token
- `OPENCODE_SERVER_PASSWORD` — web UI password
- `OPENCODE_COPILOT_AUTH_JSON` — base64-encoded `auth.json` content

Then write ExternalSecrets referencing these Doppler keys via the existing `ClusterSecretStore: doppler-secrets`.

**Warning signs:**
- `kubectl get externalsecret -n opencode` shows `STATUS: SecretSyncError`
- `kubectl describe externalsecret <name> -n opencode` shows `could not find key` or `variable not found in config`
- Pod cannot start due to missing secret — `kubectl describe pod` shows `CreateContainerConfigError`

**Phase to address:** Phase 1 (Namespace & Secrets) — Doppler variable creation is a prerequisite, not a concurrent step

---

### Pitfall 8: subPath Volume Mount Breaks PVC Directory Sharing Between Init and Main Containers

**What goes wrong:**
The PRD design mounts the workspace PVC twice on the main container:
1. `/workspace` — for the git repo
2. `/root/.local/share/opencode` — for session data (`subPath: opencode-data`)

A `subPath` mount creates a bind-mount to a specific subdirectory. If the init container writes to `/data/opencode-data/auth.json` (the PVC root) expecting the main container to see it at `~/.local/share/opencode/auth.json`, this works. But if the paths are misaligned (e.g., init writes to `/workspace/.opencode/` while main reads from the subPath `opencode-data/`), the file is invisible to the main container.

Additionally: **`subPath` mounts do not automatically create parent directories**. If the PVC is fresh and `opencode-data/` subdirectory doesn't exist, the mount fails with `not a directory` on pod start.

**How to avoid:**
Have the init container explicitly `mkdir -p` the target subdirectory on the PVC before copying files:
```sh
mkdir -p /data/opencode-data
if [ ! -f /data/opencode-data/auth.json ]; then
  cp /secrets/auth.json /data/opencode-data/auth.json
  chmod 600 /data/opencode-data/auth.json
fi
```
Ensure the init container mounts the PVC at the same root path (`/data`) used by the `subPath` derivation.

**Warning signs:**
- Pod fails to start with `Error: failed to create containerd task: ... not a directory`
- `kubectl exec` into the pod shows `~/.local/share/opencode/` is empty despite init container success
- Init container exits 0 but `auth.json` is not found at the expected path

**Phase to address:** Phase 2 (Flux Workspace) — test volume layout with `kubectl exec` before integration testing

---

### Pitfall 9: HTTPRoute in New Namespace Rejected — Gateway AllowedRoutes Namespace Restriction

**What goes wrong:**
The Envoy Gateway `envoy-internal` and `envoy-external` Gateways use `allowedRoutes.namespaces.from: All` on the HTTPS listener — but only `from: Same` on the HTTP listener (port 80). An HTTPRoute in the `opencode` namespace pointing to the HTTP `sectionName: http` will be rejected with `RouteNotAllowed` because the Gateway only accepts HTTP routes from the `network` namespace itself.

Additionally, the Gateway uses a **wildcard certificate** (`*.angryninja.cloud`). A new subdomain like `flux.opencode.angryninja.cloud` is **not covered** by a wildcard — `*.angryninja.cloud` only covers one level of subdomain. `flux.opencode` is two levels deep from the apex.

**Why it happens:**
The existing cluster uses `*.angryninja.cloud` (single-level wildcard). The planned subdomains `flux.opencode.angryninja.cloud` and `ha.opencode.angryninja.cloud` are third-level and require a separate `Certificate` resource with explicit DNS SANs — or a wildcard like `*.opencode.angryninja.cloud`.

**How to avoid:**
- Route HTTPS only (use `sectionName: https`) — the Gateway already has `allowedRoutes.from: All` for HTTPS
- Create a dedicated cert-manager `Certificate` for `*.opencode.angryninja.cloud` (or list both SANs explicitly: `flux.opencode.angryninja.cloud`, `ha.opencode.angryninja.cloud`) referencing the existing `letsencrypt-production` ClusterIssuer
- Do NOT add `sectionName: http` in the HTTPRoute — the HTTPS-redirect `HTTPRoute` in `network` namespace handles HTTP→HTTPS for all routes already

**Warning signs:**
- `kubectl describe httproute -n opencode` shows `Accepted: False` with reason `NotAllowedByListeners`
- Certificate shows `CertificateNotReady` or HTTPS returns a TLS mismatch warning
- Browser shows "Your connection is not private" with cert mismatch (wrong cert domain)

**Phase to address:** Phase 2 (Flux Workspace) — certificate must be provisioned and Ready before HTTPRoute testing

---

### Pitfall 10: Flux Reconciliation Overwrites Manually-Created Secrets (Doppler vs. Manual Secret Collision)

**What goes wrong:**
The `seed-copilot-auth.sh` script creates the `opencode-copilot-auth` Kubernetes Secret imperatively (`kubectl create secret generic ...`). If a Flux-managed `ExternalSecret` targeting the same secret name also exists in the Kustomization, Flux's ExternalSecret operator will **overwrite** the manually-created secret on the next sync cycle (up to 30 minutes, or immediately on reconcile). The OAuth token is replaced with whatever is in Doppler (which may be stale or empty).

**Why it happens:**
ExternalSecrets with `creationPolicy: Owner` take ownership of the target Secret. Any external write to that Secret is overridden on the next sync. The PRD describes both a manual seed script and Doppler-backed secrets, creating a potential collision if both reference the same Kubernetes Secret name.

**How to avoid:**
Choose **one** authoritative source per Secret:
- **Option A (Recommended):** Store `auth.json` content in Doppler, use ExternalSecret exclusively. The seed script updates Doppler, not Kubernetes directly.
- **Option B:** Keep `opencode-copilot-auth` as a manually-managed Secret with **no ExternalSecret** targeting it. Annotate it with `kustomize.toolkit.fluxcd.io/prune: disabled` so Flux doesn't delete it on reconcile.

Do not have both a `kubectl create secret` script and an ExternalSecret referencing the same secret name.

**Warning signs:**
- Copilot auth works immediately after running seed script, then stops working ~30 minutes later
- `kubectl get secret opencode-copilot-auth -o yaml` shows `managedFields` with `fieldManager: external-secrets`
- `kubectl get externalsecret -n opencode` shows a sync for a secret that should be manually managed

**Phase to address:** Phase 1 (Namespace & Secrets) — decide the authoritative secret source before writing any manifests

---

### Pitfall 11: GitHub Copilot OAuth Token Expires Silently — No Alert

**What goes wrong:**
The GitHub Copilot OAuth token stored in `auth.json` has a finite lifetime. When it expires, OpenCode silently drops Copilot as an available provider. The application continues running, but AI models are unavailable with no log-level alert. From a browser, the user sees empty model lists or errors with no clear cause.

**Why it happens:**
Token expiry is an application-level event, not a Kubernetes-level event. There is no liveness probe that validates the Copilot token, and no external monitoring hook. The pod stays "healthy" from Kubernetes' perspective.

**How to avoid:**
- Document the re-auth workflow clearly: run `opencode /connect` locally, then re-run `seed-copilot-auth.sh`, then delete and recreate the pod
- Consider a simple Prometheus alerting rule on OpenCode HTTP endpoint returning 401 responses (if Copilot auth failure manifests as HTTP errors)
- Alternatively, check whether OpenCode exposes a `/health` or `/models` endpoint that can be polled and alerted on

**Warning signs:**
- OpenCode models list becomes empty (no Copilot providers)
- Pod shows running/healthy in `kubectl get pods` despite no working AI
- Last pod restart timestamp in `kubectl describe pod` is older than the known token lifetime

**Phase to address:** Phase 4 (Persistence Validation) — validate re-auth workflow and document recovery steps

---

### Pitfall 12: bjw-s app-template OCIRepository Version Mismatch

**What goes wrong:**
The cluster uses `oci://ghcr.io/bjw-s-labs/helm/app-template:4.4.0` (confirmed in all existing apps). If the new `opencode` OCIRepository references a different version (e.g., `3.x` or `latest`), the Helm values schema may differ — particularly for `controllers.*.initContainers` path and `persistence.*.advancedMounts` syntax. Flux will apply the HelmRelease with silently wrong values, resulting in init containers not running or volumes mounted in unexpected locations.

**Why it happens:**
The bjw-s app-template has breaking schema changes between major versions. Version 3.x uses different key names than 4.x for `initContainers` ordering and `persistence` `advancedMounts`. Copying a manifest from a blog post or older cluster example will likely use the wrong schema.

**How to avoid:**
Pin to `tag: 4.4.0` in the OCIRepository (matching all other cluster apps). Use the schema hint comment at the top of the HelmRelease:
```yaml
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json
```

**Warning signs:**
- `kubectl describe helmrelease opencode-flux -n opencode` shows `values: render error` or Helm lint failures
- Init containers defined in values don't appear in `kubectl describe pod`
- PVC is mounted but at a different path than specified

**Phase to address:** Phase 2 (Flux Workspace) — use schema comment validation during authoring

---

## Technical Debt Patterns

| Shortcut | Immediate Benefit | Long-term Cost | When Acceptable |
|----------|-------------------|----------------|-----------------|
| Store `auth.json` as SOPS secret in git | No Doppler dependency | Binary auth data requires base64 encoding, breaks existing SOPS pattern | Never — use Doppler like all other cluster secrets |
| Use `latest` image tag for OpenCode | Always newest features | Non-deterministic restarts; Flux drift detection fires on every new image | Never in production |
| Skip `BackendTrafficPolicy` for WebSocket | Fewer manifests | AI streaming cuts out silently at gateway timeout | Never — existing HA app proves the necessity |
| Single PVC for both workspaces | Simpler storage | ReadWriteOnce conflict if both pods schedule to different nodes | Never — isolation is the design intent |
| `readOnlyRootFilesystem: false` globally | Easier init scripts | Security regression; violates cluster-wide securityContext patterns | Acceptable only if OpenCode image requires writes to non-PVC paths |

---

## Integration Gotchas

| Integration | Common Mistake | Correct Approach |
|-------------|----------------|------------------|
| Doppler ExternalSecrets | Referencing variables with wrong casing or path prefix | Match exact Doppler variable names; use `find.path: OPENCODE_` to scope variables |
| Envoy Gateway HTTPRoute | Using `sectionName: http` for cross-namespace routes | Use only `sectionName: https`; HTTP→HTTPS redirect is handled globally in `network` namespace |
| cert-manager wildcard | Assuming `*.angryninja.cloud` covers `*.opencode.angryninja.cloud` | Create explicit `Certificate` for `*.opencode.angryninja.cloud` or list SANs individually |
| bjw-s `route` stanza | Using `ingress` stanza instead of `route` | All apps in this cluster use `route` (Gateway API), not `ingress` (Nginx). The HA app confirms `route.*.parentRefs` pattern |
| Rook Ceph PVC | Specifying explicit storageClassName | Omit `storageClassName` to use cluster default (Rook Ceph) — matches all existing app PVCs |
| Flux `dependsOn` namespace scope | `dependsOn` referencing a Kustomization in a different namespace | `dependsOn` entries in Flux v2 are **namespace-scoped to `flux-system`** — the Kustomization name, not the target namespace |

---

## Security Mistakes

| Mistake | Risk | Prevention |
|---------|------|------------|
| Committing auth.json to git (even SOPS-encrypted) | If age.key is compromised, all historic Copilot tokens are exposed | Store auth.json content in Doppler; never commit even encrypted |
| PAT in git clone URL in pod logs | Token visible to anyone with `kubectl logs` access | Use `.netrc` or `git credential.helper` pattern; no `-x` in init container scripts |
| No password on OpenCode web UI | AI coding environment with full file system access to private repos exposed publicly | `OPENCODE_SERVER_PASSWORD` must be set — this is enforced by the PRD but easy to omit during debugging |
| Using `repo` PAT scope when `repo:read` is sufficient | Excessive permissions; PAT can write to repos if compromised | Scope PAT to `contents:read` for private repos (or `repo` scope only if write needed for git operations) |
| Copilot auth.json stored world-readable on PVC | Any process in the pod can read OAuth tokens | Init container must `chmod 600 auth.json` and the file must be owned by the OpenCode process UID |

---

## "Looks Done But Isn't" Checklist

- [ ] **Init container idempotency:** Tests `.git` directory presence, not just repo directory presence — verify with `kubectl exec` on an existing PVC
- [ ] **WebSocket support:** `appProtocol: kubernetes.io/ws` set on Service port AND `BackendTrafficPolicy` with `requestTimeout: 0s` created in `opencode` namespace
- [ ] **Certificate coverage:** `*.opencode.angryninja.cloud` Certificate is `Ready: True` before testing HTTPS — not just `Issuing`
- [ ] **Doppler variables:** All three variables (`OPENCODE_GITHUB_PAT`, `OPENCODE_SERVER_PASSWORD`, `OPENCODE_COPILOT_AUTH_JSON`) exist in Doppler `k3s-cluster/prd` before ExternalSecret is applied
- [ ] **Route stanza not ingress stanza:** HelmRelease uses `route:` not `ingress:` for HTTPRoute creation
- [ ] **PVC not re-created on redeploy:** `persistentVolumeClaim` references `existingClaim` — Flux will not delete/recreate PVC on HelmRelease upgrade
- [ ] **Copilot auth survives restart:** Delete pod, wait for recreate, confirm Copilot models appear — this is the Phase 4 acceptance test
- [ ] **No `set -x` in init container:** Pod logs do not contain the GitHub PAT

---

## Recovery Strategies

| Pitfall | Recovery Cost | Recovery Steps |
|---------|---------------|----------------|
| auth.json permission denied | LOW | `kubectl exec` into pod, `chmod 600` the file or re-run seed script and delete pod |
| Repo re-cloned and changes lost | HIGH | Changes must be manually recovered from git history; no local backup exists |
| PAT leaked in pod logs | HIGH | Rotate PAT immediately via GitHub Settings; update Doppler variable; delete pod |
| WebSocket timeouts | LOW | Add `BackendTrafficPolicy` manifest, apply via Flux or `kubectl apply` |
| ExternalSecret overwrites manual secret | LOW | Remove ExternalSecret targeting that secret name; re-run seed script; confirm no collision |
| PVC stuck due to stale VolumeAttachment | MEDIUM | `kubectl delete volumeattachment <name>` (requires cluster-admin); pod will reschedule |
| Wrong app-template version | LOW | Update OCIRepository tag to `4.4.0`; Flux reconciles on next interval |
| Certificate not covering subdomain | LOW | Add or update `Certificate` with correct dnsNames; cert-manager re-issues automatically |

---

## Pitfall-to-Phase Mapping

| Pitfall | Prevention Phase | Verification |
|---------|------------------|--------------|
| fsGroup mismatch on auth.json | Phase 1 — define securityContext in HelmRelease template | `kubectl exec` → `ls -la ~/.local/share/opencode/` shows correct owner |
| Init container re-clone on restart | Phase 2 — review init script | Delete pod, verify init container exits in <2s (no clone), repo intact |
| PAT in pod logs | Phase 2 — init script review before merge | `kubectl logs <pod> -c git-clone` contains no `ghp_` strings |
| WebSocket timeout | Phase 2 — BackendTrafficPolicy alongside HTTPRoute | Hold AI session open for >60s; confirm no disconnect |
| Wrong namespace for secrets | Phase 1 — ks.yaml dependency ordering | `kubectl get externalsecret -n opencode` shows `STATUS: Synced` |
| PVC VolumeAttachment stuck | Phase 4 — persistence validation | Drain a node, verify pod reschedules and mounts PVC within 5 minutes |
| Doppler variables missing | Phase 1 — Doppler setup is a prerequisite | `kubectl get secret -n opencode` shows all three secrets populated |
| subPath directory not created | Phase 2 — init container creates subdirectory | `kubectl exec` → `ls /data/opencode-data/` exists before main container starts |
| HTTPRoute namespace restriction | Phase 2 — use `sectionName: https` only | `kubectl describe httproute -n opencode` shows `Accepted: True` |
| Flux overwrites manual secret | Phase 1 — no ExternalSecret collision | Verify only one owner of each Secret name; no ExternalSecret for copilot-auth |
| Token expiry (no alert) | Phase 4 — document re-auth runbook | Re-auth procedure tested end-to-end at least once |
| app-template schema mismatch | Phase 2 — pin OCIRepository to 4.4.0 | `flux get helmrelease -n opencode` shows `Ready: True`, no render errors |

---

## Sources

- Cluster manifests: `/Users/jbaker/git/k8s-cluster/kubernetes/apps/home/home-assistant/app/helmrelease.yaml` — confirmed WebSocket + BackendTrafficPolicy pattern
- Cluster manifests: `/Users/jbaker/git/k8s-cluster/kubernetes/apps/network/envoy-gateway/app/envoy.yaml` — confirmed Gateway `allowedRoutes` scope
- Cluster manifests: `/Users/jbaker/git/k8s-cluster/kubernetes/apps/external-secrets/external-secrets/stores/clustersecretstore.yaml` — confirmed Doppler (not SOPS) as secret store
- Cluster manifests: `/Users/jbaker/git/k8s-cluster/kubernetes/flux/vars/cluster-secrets.sops.yaml` — confirmed SOPS only for cluster-level bootstrap secrets, not app secrets
- Cluster manifests: `/Users/jbaker/git/k8s-cluster/kubernetes/apps/home/home-assistant/app/backendtrafficpolicy.yaml` — confirmed timeout pattern for long-running connections
- PRD: `/Users/jbaker/Development/opencode-remote/docs/PRD.md` — architectural decisions and risk assessment
- PROJECT.md: `/Users/jbaker/git/k8s-cluster/.planning/PROJECT.md` — requirements and constraints
- CONCERNS.md: `/Users/jbaker/git/k8s-cluster/.planning/codebase/CONCERNS.md` — known cluster fragilities
- Official docs: https://fluxcd.io/flux/components/kustomize/kustomizations/#dependencies — confirmed dependsOn scoping behavior
- Kubernetes docs: https://kubernetes.io/docs/concepts/workloads/pods/init-containers/ — init container constraints

---
*Pitfalls research for: persistent OpenCode on Kubernetes (init containers, Envoy Gateway, PVC-backed sessions, Flux GitOps)*
*Researched: 2026-03-01*
