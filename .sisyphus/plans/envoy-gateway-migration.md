# Envoy Gateway Migration - Full Cluster Migration

## TL;DR

> **Quick Summary**: Migrate all applications from nginx-ingress to Envoy Gateway HTTPRoutes, update external-dns AND k8s-gateway to watch HTTPRoute resources, then remove nginx-ingress completely. Phased execution with verification gates to ensure zero downtime.
>
> **Deliverables**:
> - external-dns updated to watch `gateway-httproute` source (external DNS via Cloudflare)
> - k8s-gateway updated to watch `HTTPRoute` resources (internal DNS resolution)
> - HTTPRoute resources for all 30 applications
> - Certificates moved from ingress-nginx to envoy-gateway namespace
> - HelmRelease ingress configs disabled
> - ingress-nginx completely removed
>
> **Estimated Effort**: Large
> **Parallel Execution**: YES - 3 waves (infrastructure → HTTPRoutes → cleanup)
> **Critical Path**: external-dns update → HTTPRoute creation → Ingress removal → nginx deletion

---

## Context

### Original Request
User was migrating from nginx-ingress to Envoy Gateway. evcc was the test app that failed due to DNS resolution issues. User wants the full migration completed with nginx-ingress removal.

### Interview Summary
**Key Discussions**:
- **DNS Root Cause**: external-dns has `--annotation-filter=external-dns.home.arpa/enabled in (true)` but Gateways lack this annotation
- **Scope**: All apps, not just evcc
- **nginx fate**: Remove completely after migration
- **external-dns approach**: Add `gateway-httproute` source (recommended)

**Research Findings**:
- 25 HelmReleases with ingress config, 2 standalone Ingress resources
- Envoy Gateways (envoy-internal, envoy-external) already configured with TLS
- Certificate `${SECRET_DOMAIN/./-}-production-tls` referenced by Gateways
- k8s-gateway is for split-horizon DNS, NOT Ingress translation

### Metis Review
**Identified Gaps** (addressed):
- **Rollback Strategy**: Phased approach - HTTPRoutes created BEFORE Ingresses disabled
- **Certificate Migration Timing**: Certificates stay in network namespace, update dependency path
- **WebSocket Apps**: home-assistant, frigate need no special handling (Envoy supports WebSocket by default)
- **Large Uploads**: photoprism, qbittorrent - Envoy default is unlimited, will work
- **flux-webhook**: Critical path - migrate carefully with verification
- **tesla-proxy**: External service needs HTTPRoute with correct backend

---

## Work Objectives

### Core Objective
Migrate all cluster applications from nginx-ingress to Envoy Gateway while maintaining continuous availability, then remove nginx-ingress.

### Concrete Deliverables
- `kubernetes/apps/network/external-dns/app/helmrelease.yaml` - updated with gateway-httproute source
- `kubernetes/apps/network/envoy-gateway/certificates/` - new directory with production.yaml
- `kubernetes/apps/network/envoy-gateway/ks.yaml` - updated with certificates kustomization
- HTTPRoute files for all 30 applications
- Updated HelmReleases with `ingress.app.enabled: false`
- `kubernetes/apps/network/kustomization.yaml` - ingress-nginx removed

### Definition of Done
- [ ] `kubectl get httproute -A` shows all apps with Accepted=True
- [ ] `kubectl get ingress -A` shows no resources (or only explicitly excluded)
- [ ] All app hostnames resolve and return expected HTTP status
- [ ] ingress-nginx namespace does not exist

### Must Have
- Phased execution with verification gates between phases
- Each HTTPRoute preserves exact hostname and path from Ingress
- External apps have `external-dns.home.arpa/enabled: "true"` annotation
- Zero downtime during migration

### Must NOT Have (Guardrails)
- DO NOT consolidate apps into shared HTTPRoutes - 1:1 mapping only
- DO NOT change Gateway listener configurations
- DO NOT upgrade envoy-gateway version during migration
- DO NOT modify k8s-gateway configuration
- DO NOT add new hostnames or paths not in original Ingress
- DO NOT delete ingress-nginx until ALL apps verified via HTTPRoute
- DO NOT make changes beyond exact scope (no "while we're here" improvements)

---

## Verification Strategy

> **UNIVERSAL RULE: ZERO HUMAN INTERVENTION**
>
> ALL tasks MUST be verifiable by running kubectl/curl commands.
> No "user manually tests" or "visually confirm" steps allowed.

### Test Decision
- **Infrastructure exists**: YES (kubectl available)
- **Automated tests**: NO (GitOps validation via Flux reconciliation)
- **Framework**: kubectl + curl for verification

### Agent-Executed QA Scenarios (MANDATORY — ALL tasks)

Every task includes verification commands the agent executes directly.

**Verification Tool by Deliverable Type:**

| Type | Tool | How Agent Verifies |
|------|------|-------------------|
| **Flux Kustomization** | Bash (kubectl) | `flux reconcile ks <name> && flux get ks <name>` |
| **HTTPRoute** | Bash (kubectl) | `kubectl get httproute -n <ns> <name> -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'` |
| **DNS Record** | Bash (dig) | `dig +short <hostname> @1.1.1.1` |
| **HTTP Access** | Bash (curl) | `curl -s -o /dev/null -w "%{http_code}" -k https://<hostname>/` |

---

## Execution Strategy

### Parallel Execution Waves

```
Wave 1: Infrastructure (Sequential within wave)
├── Task 1: Pre-flight validation
├── Task 2: Update external-dns (add gateway-httproute source)
├── Task 3: Move certificates to envoy-gateway
└── Task 4: Update envoy-gateway-config dependency

Wave 2: Create HTTPRoutes (Parallel - all at once)
├── Tasks 5-11: Internal apps - home namespace
├── Tasks 12-19: Internal apps - media namespace
├── Tasks 20-24: Internal apps - ai namespace
├── Tasks 25-28: Internal apps - observability namespace
├── Tasks 29-30: Internal apps - network/kube-system
├── Tasks 31-34: External apps (home-assistant, tesla-proxy, garmin-mcp, flux-webhook)
└── Task 35: Standalone HTTPRoutes (flux-webhook, tesla-proxy externalservice)

Wave 3: Verification Gate
└── Task 36: Verify ALL HTTPRoutes accepted and accessible

Wave 4: Disable Ingresses (Parallel)
├── Tasks 37-66: Set ingress.app.enabled=false in all HelmReleases
└── Task 67: Delete standalone Ingress resources

Wave 5: Cleanup
├── Task 68: Verify no Ingress resources remain
├── Task 69: Remove ingress-nginx from network kustomization
└── Task 70: Delete ingress-nginx directory

Wave 6: Final Verification
└── Task 71: Final cluster-wide verification
```

### Dependency Matrix

| Task | Depends On | Blocks |
|------|------------|--------|
| 1 (Pre-flight) | None | 2-4 |
| 2-4 (Infrastructure) | 1 | 5-35 |
| 5-35 (HTTPRoutes) | 2-4 | 36 |
| 36 (Verification) | 5-35 | 37-67 |
| 37-67 (Disable Ingress) | 36 | 68 |
| 68-70 (Cleanup) | 67 | 71 |
| 71 (Final) | 70 | None |

---

## TODOs

### Phase 1: Infrastructure Setup

- [x] 1. Pre-flight Validation (COMPLETED - 2026-02-04)

  **What to do**:
  - Verify envoy-internal and envoy-external Gateways are programmed
  - Verify TLS certificate secret exists
  - Verify external-dns is running
  - Check external-dns version supports gateway-httproute

  **NOTE**: Task 1a added - Envoy Gateway was not deployed! Fixed by adding envoy-gateway to network kustomization.

  **Must NOT do**:
  - Make any changes - read-only verification only

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Read-only verification commands
  - **Skills**: `[]`
    - No special skills needed for kubectl commands

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (must complete first)
  - **Blocks**: Tasks 2-4
  - **Blocked By**: None

  **References**:
  - `kubernetes/apps/network/envoy-gateway/config/envoy.yaml:46-104` - Gateway definitions
  - `kubernetes/apps/network/external-dns/app/helmrelease.yaml` - external-dns configuration

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Verify Gateways are programmed
    Tool: Bash (kubectl)
    Steps:
      1. kubectl get gateway -n network envoy-internal -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'
      2. Assert: Output equals "True"
      3. kubectl get gateway -n network envoy-external -o jsonpath='{.status.conditions[?(@.type=="Programmed")].status}'
      4. Assert: Output equals "True"
    Expected Result: Both Gateways show Programmed=True

  Scenario: Verify TLS certificate exists
    Tool: Bash (kubectl)
    Steps:
      1. kubectl get secret -n network -o name | grep production-tls
      2. Assert: Output contains "production-tls"
    Expected Result: Certificate secret exists in network namespace

  Scenario: Verify external-dns is running
    Tool: Bash (kubectl)
    Steps:
      1. kubectl get pods -n network -l app.kubernetes.io/name=external-dns -o jsonpath='{.items[0].status.phase}'
      2. Assert: Output equals "Running"
    Expected Result: external-dns pod is running
  ```

  **Commit**: NO

---

- [ ] 2. Update external-dns to watch gateway-httproute source

  **What to do**:
  - Add `gateway-httproute` to the `sources` list in external-dns HelmRelease
  - Sources should be: `["ingress", "gateway-httproute"]`

  **Must NOT do**:
  - Remove the `ingress` source yet (needed during transition)
  - Change annotation filter
  - Modify any other external-dns settings

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single file edit
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Sequential (Wave 1)
  - **Blocks**: Tasks 5-35
  - **Blocked By**: Task 1

  **References**:
  - `kubernetes/apps/network/external-dns/app/helmrelease.yaml:17-19` - Current sources config (only "ingress")

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: external-dns HelmRelease updated
    Tool: Bash (kubectl)
    Steps:
      1. task reconcile
      2. kubectl get helmrelease -n network external-dns -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}'
      3. Assert: Output equals "True"
    Expected Result: HelmRelease reconciles successfully

  Scenario: external-dns logs show gateway-httproute source
    Tool: Bash (kubectl)
    Steps:
      1. Sleep 30s (allow reconciliation)
      2. kubectl logs -n network -l app.kubernetes.io/name=external-dns --tail=50 | grep -i "gateway"
      3. Assert: Output shows gateway source loaded (or no errors)
    Expected Result: external-dns running with new source
  ```

  **Commit**: YES
  - Message: `feat(network): add gateway-httproute source to external-dns`
  - Files: `kubernetes/apps/network/external-dns/app/helmrelease.yaml`

---

- [x] 2a. Update k8s-gateway to watch HTTPRoute resources (COMPLETED - 2026-02-04)

  **What to do**:
  - Add `HTTPRoute` to the `watchedResources` list in k8s-gateway HelmRelease
  - watchedResources should be: `["Ingress", "Service", "HTTPRoute"]`

  **Why this is critical**:
  - k8s-gateway provides split-horizon DNS for internal cluster resolution
  - Without HTTPRoute in watchedResources, internal DNS queries for HTTPRoute hostnames will fail
  - external-dns handles EXTERNAL DNS (Cloudflare), k8s-gateway handles INTERNAL DNS
  - Currently only watches `["Ingress", "Service"]` - misses HTTPRoute completely

  **Must NOT do**:
  - Remove Ingress or Service from watchedResources (needed during transition)
  - Change domain, ttl, or other settings

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single line edit
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES (with Task 2)
  - **Parallel Group**: Wave 1
  - **Blocks**: Tasks 5-35 (HTTPRoute creation)
  - **Blocked By**: Task 1

  **References**:
  - `kubernetes/apps/network/k8s-gateway/app/helmrelease.yaml:34` - Current watchedResources
  - https://github.com/ori-edge/k8s_gateway - Docs confirm HTTPRoute support

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: k8s-gateway HelmRelease updated
    Tool: Bash (kubectl)
    Steps:
      1. kubectl get helmrelease -n network k8s-gateway -o jsonpath='{.spec.values.watchedResources}'
      2. Assert: Output contains "HTTPRoute"
    Expected Result: HTTPRoute in watchedResources list

  Scenario: k8s-gateway pod restarted with new config
    Tool: Bash (kubectl)
    Steps:
      1. kubectl get pods -n network -l app.kubernetes.io/name=k8s-gateway -o jsonpath='{.items[0].status.phase}'
      2. Assert: Output equals "Running"
    Expected Result: k8s-gateway pod running with new configuration
  ```

  **Commit**: YES (can group with Task 2)
  - Message: `feat(network): add HTTPRoute to k8s-gateway watchedResources`
  - Files: `kubernetes/apps/network/k8s-gateway/app/helmrelease.yaml`

---

- [x] 3. Create certificates kustomization under envoy-gateway (COMPLETED - 2026-02-04)

  **What to do**:
  - Create `kubernetes/apps/network/envoy-gateway/certificates/` directory
  - Copy `kubernetes/apps/network/ingress-nginx/certificates/production.yaml` to new location
  - Create `kubernetes/apps/network/envoy-gateway/certificates/kustomization.yaml`

  **Must NOT do**:
  - Delete original certificates from ingress-nginx (yet)
  - Modify certificate content

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: File copy and create
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 1 (with Task 4)
  - **Blocks**: Task 4
  - **Blocked By**: Task 1

  **References**:
  - `kubernetes/apps/network/ingress-nginx/certificates/production.yaml` - Source certificate
  - `kubernetes/apps/network/ingress-nginx/certificates/kustomization.yaml` - Source kustomization pattern

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: Certificate files exist in new location
    Tool: Bash (ls)
    Steps:
      1. ls kubernetes/apps/network/envoy-gateway/certificates/
      2. Assert: Output contains "production.yaml" and "kustomization.yaml"
    Expected Result: Both files exist
  ```

  **Commit**: YES (group with Task 4)
  - Message: `feat(network): add certificates to envoy-gateway`
  - Files: `kubernetes/apps/network/envoy-gateway/certificates/`

---

- [ ] 4. Update envoy-gateway ks.yaml with certificates kustomization

  **What to do**:
  - Add new Kustomization for `envoy-gateway-certificates` in `kubernetes/apps/network/envoy-gateway/ks.yaml`
  - It should depend on `cert-manager-issuers` (same as ingress-nginx-certificates)
  - Update `envoy-gateway-config` to depend on `envoy-gateway-certificates` instead of `ingress-nginx-certificates`

  **Must NOT do**:
  - Remove ingress-nginx-certificates dependency cluster-wide yet
  - Change other envoy-gateway kustomizations

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Single file edit
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO (depends on Task 3)
  - **Parallel Group**: Wave 1
  - **Blocks**: Tasks 5-35
  - **Blocked By**: Tasks 1, 3

  **References**:
  - `kubernetes/apps/network/envoy-gateway/ks.yaml:44-68` - Current ks.yaml structure
  - `kubernetes/apps/network/ingress-nginx/ks.yaml:1-23` - ingress-nginx-certificates pattern to follow

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: envoy-gateway-certificates kustomization reconciles
    Tool: Bash (kubectl)
    Steps:
      1. task reconcile
      2. flux get ks envoy-gateway-certificates
      3. Assert: Status shows "Ready" and "Applied"
    Expected Result: Certificates kustomization applied

  Scenario: envoy-gateway-config depends on new certificates
    Tool: Bash (kubectl)
    Steps:
      1. flux get ks envoy-gateway-config
      2. Assert: Shows "Ready" status
    Expected Result: Config kustomization still works with new dependency
  ```

  **Commit**: YES (group with Task 3)
  - Message: `feat(network): add certificates to envoy-gateway`
  - Files: `kubernetes/apps/network/envoy-gateway/ks.yaml`

---

### Phase 2: Create HTTPRoutes

**Pattern for ALL HTTPRoute tasks:**

Each HTTPRoute follows this structure:
```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/gateway.networking.k8s.io/httproute_v1.json
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: <app-name>
  annotations:
    # For EXTERNAL apps only:
    external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}
    external-dns.home.arpa/enabled: "true"
spec:
  parentRefs:
    - name: envoy-internal  # or envoy-external
      namespace: network
      sectionName: https
  hostnames:
    - "<hostname>.${SECRET_DOMAIN}"
  rules:
    - backendRefs:
        - name: <service-name>
          port: <port>
```

---

- [ ] 5. Create HTTPRoute for evcc

  **What to do**:
  - Create `kubernetes/apps/home/evcc/app/httproute.yaml`
  - Add `httproute.yaml` to `kubernetes/apps/home/evcc/app/kustomization.yaml`
  - Gateway: envoy-internal, hostname: evcc.${SECRET_DOMAIN}, service: evcc port 7070

  **Must NOT do**:
  - Disable ingress yet (that's Phase 4)
  - Change any other evcc configuration

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Create one file, edit kustomization
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: YES
  - **Parallel Group**: Wave 2 (all HTTPRoutes)
  - **Blocks**: Task 36
  - **Blocked By**: Tasks 2, 4

  **References**:
  - `kubernetes/apps/home/evcc/app/helmrelease.yaml:50-64` - Current ingress config (className: internal, host pattern)
  - `kubernetes/apps/network/envoy-gateway/config/envoy.yaml:106-127` - HTTPRoute https-redirect example pattern

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: HTTPRoute created and accepted
    Tool: Bash (kubectl)
    Steps:
      1. task reconcile
      2. kubectl get httproute -n home evcc -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'
      3. Assert: Output equals "True"
    Expected Result: HTTPRoute accepted by Gateway

  Scenario: evcc accessible via HTTPRoute
    Tool: Bash (curl)
    Steps:
      1. Get Gateway IP: kubectl get gateway -n network envoy-internal -o jsonpath='{.status.addresses[0].value}'
      2. curl -s -o /dev/null -w "%{http_code}" -k --resolve "evcc.${SECRET_DOMAIN}:443:<gateway-ip>" "https://evcc.${SECRET_DOMAIN}/"
      3. Assert: Status code is 200 or 302
    Expected Result: App accessible through Envoy Gateway
  ```

  **Commit**: YES (group with other home namespace HTTPRoutes)
  - Message: `feat(home): add HTTPRoutes for envoy-gateway migration`
  - Files: `kubernetes/apps/home/evcc/app/httproute.yaml`, `kubernetes/apps/home/evcc/app/kustomization.yaml`

---

- [ ] 6. Create HTTPRoute for teslamate

  **What to do**:
  - Create `kubernetes/apps/home/teslamate/app/httproute.yaml`
  - Add to kustomization.yaml
  - Gateway: envoy-internal, hostname: teslamate.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/home/teslamate/app/helmrelease.yaml:55-68` - Current ingress config

  **Acceptance Criteria**: Same pattern as Task 5

  **Commit**: YES (group with Task 5)

---

- [ ] 7. Create HTTPRoute for emhass

  **What to do**:
  - Create `kubernetes/apps/home/emhass/app/httproute.yaml`
  - Add to kustomization.yaml
  - Gateway: envoy-internal, hostname: emhass.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/home/emhass/app/helmrelease.yaml:62-76` - Current ingress config

  **Acceptance Criteria**: Same pattern as Task 5

  **Commit**: YES (group with Task 5)

---

- [ ] 8. Create HTTPRoute for zigbee2mqtt

  **What to do**:
  - Create `kubernetes/apps/home/zigbee2mqtt/app/httproute.yaml`
  - Add to kustomization.yaml
  - Gateway: envoy-internal, hostname: zigbee2mqtt.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/home/zigbee2mqtt/app/helmrelease.yaml:90-104` - Current ingress config

  **Acceptance Criteria**: Same pattern as Task 5

  **Commit**: YES (group with Task 5)

---

- [ ] 9. Create HTTPRoute for frigate

  **What to do**:
  - Create `kubernetes/apps/home/frigate/app/httproute.yaml`
  - Add to kustomization.yaml
  - Gateway: envoy-internal, hostname: frigate.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/home/frigate/app/helmrelease.yaml:83-97` - Current ingress config

  **Acceptance Criteria**: Same pattern as Task 5

  **Commit**: YES (group with Task 5)

---

- [ ] 10. Create HTTPRoutes for home-assistant (internal code-server + external main)

  **What to do**:
  - Create `kubernetes/apps/home/home-assistant/app/httproute.yaml` with TWO HTTPRoutes:
    1. `home-assistant` - EXTERNAL, hostname: hass.${SECRET_DOMAIN}, service: home-assistant port 8123
    2. `home-assistant-code` - internal, hostname: hass-code.${SECRET_DOMAIN}, service: home-assistant-code port 8081
  - Add to kustomization.yaml
  - EXTERNAL route needs: `external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}` and `external-dns.home.arpa/enabled: "true"`

  **References**:
  - `kubernetes/apps/home/home-assistant/app/helmrelease.yaml:94-121` - Current ingress config (two ingresses)

  **Acceptance Criteria**: Same pattern as Task 5 (verify both routes)

  **Commit**: YES (group with Task 5)

---

- [ ] 11. Create HTTPRoutes for tesla-proxy (internal + external)

  **What to do**:
  - Create `kubernetes/apps/home/tesla-proxy/app/httproute.yaml` with TWO HTTPRoutes:
    1. `tesla-proxy` - EXTERNAL, hostname: tesla-proxy.${SECRET_DOMAIN}, service: tesla-proxy port 4430
    2. `tesla-proxy-internal` - internal, based on HelmRelease internal ingress
  - Add to kustomization.yaml
  - EXTERNAL route needs external-dns annotations

  **Note**: This app also has an ExternalService Ingress that needs to be handled - see Task 35

  **References**:
  - `kubernetes/apps/home/tesla-proxy/app/helmrelease.yaml:101-130` - Current ingress configs
  - `kubernetes/apps/home/tesla-proxy/app/externalservice.yaml:30-65` - Standalone external Ingress

  **Acceptance Criteria**: Same pattern as Task 5

  **Commit**: YES (group with Task 5)

---

- [ ] 12. Create HTTPRoute for radarr

  **What to do**:
  - Create `kubernetes/apps/media/radarr/app/httproute.yaml`
  - Add to kustomization.yaml
  - Gateway: envoy-internal, hostname: radarr.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/media/radarr/app/helmrelease.yaml:80-94` - Current ingress config

  **Acceptance Criteria**: Same pattern as Task 5

  **Commit**: YES (group with other media namespace HTTPRoutes)
  - Message: `feat(media): add HTTPRoutes for envoy-gateway migration`

---

- [ ] 13. Create HTTPRoute for sonarr

  **What to do**:
  - Create `kubernetes/apps/media/sonarr/app/httproute.yaml`
  - Gateway: envoy-internal, hostname: sonarr.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/media/sonarr/app/helmrelease.yaml:89-103` - Current ingress config

  **Commit**: YES (group with Task 12)

---

- [ ] 14. Create HTTPRoute for lidarr

  **What to do**:
  - Create `kubernetes/apps/media/lidarr/app/httproute.yaml`
  - Gateway: envoy-internal, hostname: lidarr.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/media/lidarr/app/helmrelease.yaml:80-94` - Current ingress config

  **Commit**: YES (group with Task 12)

---

- [ ] 15. Create HTTPRoute for prowlarr

  **What to do**:
  - Create `kubernetes/apps/media/prowlarr/app/httproute.yaml`
  - Gateway: envoy-internal, hostname: prowlarr.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/media/prowlarr/app/helmrelease.yaml:74-88` - Current ingress config

  **Commit**: YES (group with Task 12)

---

- [ ] 16. Create HTTPRoute for overseerr

  **What to do**:
  - Create `kubernetes/apps/media/overseerr/app/httproute.yaml`
  - Gateway: envoy-internal, hostname: overseerr.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/media/overseerr/app/helmrelease.yaml:73-87` - Current ingress config

  **Commit**: YES (group with Task 12)

---

- [ ] 17. Create HTTPRoute for plex

  **What to do**:
  - Create `kubernetes/apps/media/plex/app/httproute.yaml`
  - Gateway: envoy-internal, hostname: plex.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/media/plex/app/helmrelease.yaml:104-118` - Current ingress config

  **Commit**: YES (group with Task 12)

---

- [ ] 18. Create HTTPRoute for photoprism

  **What to do**:
  - Create `kubernetes/apps/media/photoprism/app/httproute.yaml`
  - Gateway: envoy-internal, hostname: photoprism.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/media/photoprism/app/helmrelease.yaml:57-71` - Current ingress config

  **Commit**: YES (group with Task 12)

---

- [ ] 19. Create HTTPRoute for bazarr

  **What to do**:
  - Create `kubernetes/apps/media/bazarr/app/httproute.yaml`
  - Gateway: envoy-internal, hostname: bazarr.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/media/bazarr/app/helmrelease.yaml:75-89` - Current ingress config

  **Commit**: YES (group with Task 12)

---

- [ ] 20. Create HTTPRoute for qbittorrent

  **What to do**:
  - Create `kubernetes/apps/media/qbittorrent/app/httproute.yaml`
  - Gateway: envoy-internal, hostname: qbittorrent.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/media/qbittorrent/app/helmrelease.yaml:130-144` - Current ingress config

  **Commit**: YES (group with Task 12)

---

- [ ] 21. Create HTTPRoute for litellm

  **What to do**:
  - Create `kubernetes/apps/ai/litellm/app/httproute.yaml`
  - Gateway: envoy-internal, hostname: litellm.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/ai/litellm/app/helmrelease.yaml:90-104` - Current ingress config

  **Commit**: YES (group with other ai namespace HTTPRoutes)
  - Message: `feat(ai): add HTTPRoutes for envoy-gateway migration`

---

- [ ] 22. Create HTTPRoute for openwebui

  **What to do**:
  - Create `kubernetes/apps/ai/openwebui/app/httproute.yaml`
  - Gateway: envoy-internal, hostname: openwebui.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/ai/openwebui/app/helmrelease.yaml:85-99` - Current ingress config

  **Commit**: YES (group with Task 21)

---

- [ ] 23. Create HTTPRoute for ollama

  **What to do**:
  - Create `kubernetes/apps/ai/ollama/app/httproute.yaml`
  - Gateway: envoy-internal, hostname: ollama.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/ai/ollama/app/helmrelease.yaml:50-64` - Current ingress config

  **Commit**: YES (group with Task 21)

---

- [ ] 24. Create HTTPRoute for mcpo

  **What to do**:
  - Create `kubernetes/apps/ai/mcpo/app/httproute.yaml`
  - Gateway: envoy-internal, hostname: mcpo.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/ai/mcpo/app/helmrelease.yaml:94-108` - Current ingress config

  **Commit**: YES (group with Task 21)

---

- [ ] 25. Create HTTPRoute for garmin-mcp (EXTERNAL)

  **What to do**:
  - Create `kubernetes/apps/ai/garmin-mcp/app/httproute.yaml`
  - Gateway: envoy-EXTERNAL, hostname: garmin-mcp.${SECRET_DOMAIN}
  - Include external-dns annotations

  **References**:
  - `kubernetes/apps/ai/garmin-mcp/app/helmrelease.yaml:82-99` - Current ingress config (className: external)

  **Commit**: YES (group with Task 21)

---

- [ ] 26. Create HTTPRoute for grafana

  **What to do**:
  - Create `kubernetes/apps/observability/grafana/app/httproute.yaml`
  - Gateway: envoy-internal, hostname: grafana.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/observability/grafana/app/helmrelease.yaml:335-338` - Current ingress config

  **Commit**: YES (group with other observability namespace HTTPRoutes)
  - Message: `feat(observability): add HTTPRoutes for envoy-gateway migration`

---

- [ ] 27. Create HTTPRoutes for kube-prometheus-stack (alertmanager + prometheus)

  **What to do**:
  - Create `kubernetes/apps/observability/kube-prometheus-stack/app/httproute.yaml` with TWO HTTPRoutes:
    1. `alertmanager` - internal, hostname: alert-manager.${SECRET_DOMAIN}
    2. `prometheus` - internal, hostname: prometheus.${SECRET_DOMAIN}
  - Add to kustomization.yaml

  **References**:
  - `kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml:85-93` - alertmanager ingress
  - `kubernetes/apps/observability/kube-prometheus-stack/app/helmrelease.yaml:119-124` - prometheus ingress

  **Commit**: YES (group with Task 26)

---

- [ ] 28. Create HTTPRoute for kubernetes-dashboard

  **What to do**:
  - Create `kubernetes/apps/observability/kubernetes-dashboard/app/httproute.yaml`
  - Gateway: envoy-internal, hostname: kubernetes-dashboard.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/observability/kubernetes-dashboard/app/helmrelease.yaml:35-49` - Current ingress config

  **Commit**: YES (group with Task 26)

---

- [ ] 29. Create HTTPRoute for blackbox-exporter

  **What to do**:
  - Create `kubernetes/apps/observability/blackbox-exporter/app/httproute.yaml`
  - Gateway: envoy-internal, hostname: blackbox-exporter.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/observability/blackbox-exporter/app/helmrelease.yaml:25-39` - Current ingress config

  **Commit**: YES (group with Task 26)

---

- [ ] 30. Create HTTPRoute for unifi

  **What to do**:
  - Create `kubernetes/apps/network/unifi/app/httproute.yaml`
  - Gateway: envoy-internal, hostname: unifi.${SECRET_DOMAIN}

  **References**:
  - `kubernetes/apps/network/unifi/app/helmrelease.yaml:86-100` - Current ingress config

  **Commit**: YES
  - Message: `feat(network): add HTTPRoute for unifi`

---

- [ ] 31. Create HTTPRoute for hubble-ui (Cilium)

  **What to do**:
  - Create `kubernetes/apps/kube-system/cilium/app/httproute.yaml`
  - Gateway: envoy-internal, hostname: hubble.${SECRET_DOMAIN}
  - Add to kustomization.yaml

  **References**:
  - `kubernetes/apps/kube-system/cilium/app/helmrelease.yaml:51-57` - Current hubble ingress config

  **Commit**: YES
  - Message: `feat(kube-system): add HTTPRoute for hubble-ui`

---

- [ ] 32. Create HTTPRoute for flux-webhook (EXTERNAL - standalone)

  **What to do**:
  - Create `kubernetes/apps/flux-system/flux/github/webhooks/httproute.yaml`
  - Gateway: envoy-EXTERNAL, hostname: flux-webhook.${SECRET_DOMAIN}
  - Path: /hook/ (Prefix match)
  - Include external-dns annotations
  - Add to webhooks kustomization.yaml

  **Note**: This is a CRITICAL path - flux webhooks must work for GitOps

  **References**:
  - `kubernetes/apps/flux-system/flux/github/webhooks/ingress.yaml` - Current standalone Ingress

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: flux-webhook HTTPRoute accepted
    Tool: Bash (kubectl)
    Steps:
      1. kubectl get httproute -n flux-system flux-webhook -o jsonpath='{.status.parents[0].conditions[?(@.type=="Accepted")].status}'
      2. Assert: Output equals "True"
    Expected Result: HTTPRoute accepted

  Scenario: flux-webhook accessible via HTTPRoute
    Tool: Bash (curl)
    Steps:
      1. Get Gateway IP: kubectl get gateway -n network envoy-external -o jsonpath='{.status.addresses[0].value}'
      2. curl -s -o /dev/null -w "%{http_code}" -k --resolve "flux-webhook.${SECRET_DOMAIN}:443:<gateway-ip>" "https://flux-webhook.${SECRET_DOMAIN}/hook/"
      3. Assert: Status code is 200, 404, or 405 (endpoint exists)
    Expected Result: Webhook endpoint reachable
  ```

  **Commit**: YES
  - Message: `feat(flux-system): add HTTPRoute for flux-webhook`

---

### Phase 3: Verification Gate

- [ ] 33. Verify ALL HTTPRoutes are accepted and apps accessible

  **What to do**:
  - Run comprehensive verification of ALL HTTPRoutes
  - Check each app is accessible via its HTTPRoute
  - Verify external-dns created records for external apps
  - This is a GATE - do not proceed to Phase 4 until all pass

  **Must NOT do**:
  - Make any changes
  - Proceed if any verification fails

  **Recommended Agent Profile**:
  - **Category**: `quick`
    - Reason: Read-only verification commands
  - **Skills**: `[]`

  **Parallelization**:
  - **Can Run In Parallel**: NO
  - **Parallel Group**: Wave 3 (verification gate)
  - **Blocks**: Tasks 34-63
  - **Blocked By**: Tasks 5-32

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: All HTTPRoutes show Accepted=True
    Tool: Bash (kubectl)
    Steps:
      1. kubectl get httproute -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: {.status.parents[0].conditions[?(@.type=="Accepted")].status}{"\n"}{end}'
      2. Assert: ALL entries show "True"
    Expected Result: Every HTTPRoute is accepted

  Scenario: External DNS records created
    Tool: Bash (dig)
    Steps:
      1. dig +short hass.${SECRET_DOMAIN} @1.1.1.1
      2. Assert: Returns an IP address
      3. dig +short flux-webhook.${SECRET_DOMAIN} @1.1.1.1
      4. Assert: Returns an IP address
    Expected Result: DNS records exist for external apps

  Scenario: Sample apps accessible via Gateway
    Tool: Bash (curl)
    Steps:
      1. Get internal Gateway IP
      2. Test evcc: curl -s -o /dev/null -w "%{http_code}" -k --resolve ...
      3. Test grafana: curl -s -o /dev/null -w "%{http_code}" -k --resolve ...
      4. Get external Gateway IP
      5. Test hass: curl -s -o /dev/null -w "%{http_code}" -k --resolve ...
      6. Assert: All return 200 or 302
    Expected Result: Apps accessible through Envoy
  ```

  **Commit**: NO

---

### Phase 4: Disable Ingresses in HelmReleases

**Pattern for ALL ingress disable tasks:**

For each HelmRelease, change:
```yaml
    ingress:
      app:
        enabled: true
```
to:
```yaml
    ingress:
      app:
        enabled: false
```

---

- [ ] 34. Disable ingress in evcc HelmRelease

  **What to do**:
  - Set `ingress.app.enabled: false` in `kubernetes/apps/home/evcc/app/helmrelease.yaml`

  **References**:
  - `kubernetes/apps/home/evcc/app/helmrelease.yaml:50-64` - Current ingress config

  **Commit**: YES (group with other home namespace apps)
  - Message: `refactor(home): disable nginx ingress in favor of HTTPRoutes`

---

- [ ] 35-48. Disable ingress in remaining HelmReleases

  **Apps to update** (follow same pattern as Task 34):
  - teslamate, emhass, zigbee2mqtt, frigate, home-assistant (2 ingresses), tesla-proxy (2 ingresses)
  - radarr, sonarr, lidarr, prowlarr, overseerr, plex, photoprism, bazarr, qbittorrent
  - litellm, openwebui, ollama, mcpo, garmin-mcp
  - grafana, kubernetes-dashboard, blackbox-exporter
  - unifi
  - kube-prometheus-stack (alertmanager + prometheus ingresses)
  - cilium (hubble.ui.ingress.enabled: false)

  **Commit**: YES (group by namespace)
  - `refactor(home): disable nginx ingress in favor of HTTPRoutes`
  - `refactor(media): disable nginx ingress in favor of HTTPRoutes`
  - `refactor(ai): disable nginx ingress in favor of HTTPRoutes`
  - `refactor(observability): disable nginx ingress in favor of HTTPRoutes`
  - `refactor(network): disable nginx ingress in unifi`
  - `refactor(kube-system): disable nginx ingress in cilium`

---

- [ ] 49. Delete standalone Ingress resources

  **What to do**:
  - Delete `kubernetes/apps/flux-system/flux/github/webhooks/ingress.yaml`
  - Remove from webhooks kustomization.yaml
  - Delete the Ingress section from `kubernetes/apps/home/tesla-proxy/app/externalservice.yaml` (keep Service + Endpoints)
  - Update tesla-proxy kustomization.yaml if needed

  **References**:
  - `kubernetes/apps/flux-system/flux/github/webhooks/ingress.yaml` - Delete this file
  - `kubernetes/apps/home/tesla-proxy/app/externalservice.yaml:30-65` - Remove Ingress section

  **Commit**: YES
  - Message: `refactor: remove standalone nginx Ingress resources`

---

### Phase 5: Cleanup

- [ ] 50. Verify no Ingress resources remain

  **What to do**:
  - Run `kubectl get ingress -A` and verify empty
  - If any remain, investigate and resolve

  **Acceptance Criteria**:

  ```
  Scenario: No Ingress resources in cluster
    Tool: Bash (kubectl)
    Steps:
      1. kubectl get ingress -A
      2. Assert: "No resources found" or empty output
    Expected Result: All Ingress resources deleted
  ```

  **Commit**: NO

---

- [ ] 51. Remove ingress-nginx from network kustomization

  **What to do**:
  - Edit `kubernetes/apps/network/kustomization.yaml`
  - Remove `- ./ingress-nginx/ks.yaml` line
  - Add `- ./envoy-gateway/ks.yaml` if not already present

  **References**:
  - `kubernetes/apps/network/kustomization.yaml:9` - Line to remove

  **Commit**: YES (group with Task 52)
  - Message: `refactor(network): remove ingress-nginx, complete envoy-gateway migration`

---

- [ ] 52. Delete ingress-nginx directory

  **What to do**:
  - Delete entire `kubernetes/apps/network/ingress-nginx/` directory
  - This removes all ingress-nginx resources from the cluster

  **Must NOT do**:
  - Delete before Task 51 (would cause Flux errors)

  **Commit**: YES (group with Task 51)

---

### Phase 6: Final Verification

- [ ] 53. Final cluster-wide verification

  **What to do**:
  - Verify ingress-nginx namespace doesn't exist
  - Verify all apps still accessible via HTTPRoutes
  - Verify external DNS resolution works
  - Verify Flux reconciliation healthy

  **Acceptance Criteria**:

  **Agent-Executed QA Scenarios:**

  ```
  Scenario: ingress-nginx namespace deleted
    Tool: Bash (kubectl)
    Steps:
      1. kubectl get namespace ingress-nginx
      2. Assert: "NotFound" error
    Expected Result: Namespace no longer exists

  Scenario: All apps accessible via HTTPRoutes
    Tool: Bash (curl)
    Steps:
      1. For each app hostname, curl via Gateway IP
      2. Assert: All return expected status codes
    Expected Result: All apps working through Envoy

  Scenario: Flux healthy after migration
    Tool: Bash (flux)
    Steps:
      1. flux get ks -A | grep -v "True"
      2. Assert: Empty output (all Ready)
    Expected Result: All kustomizations reconciled
  ```

  **Commit**: NO (verification only)

---

## Commit Strategy

| Phase | Message | Files |
|-------|---------|-------|
| 1 | `feat(network): add gateway-httproute source to external-dns` | external-dns/app/helmrelease.yaml |
| 1 | `feat(network): add certificates to envoy-gateway` | envoy-gateway/certificates/, envoy-gateway/ks.yaml |
| 2 | `feat(home): add HTTPRoutes for envoy-gateway migration` | home/*/app/httproute.yaml, kustomization.yaml |
| 2 | `feat(media): add HTTPRoutes for envoy-gateway migration` | media/*/app/httproute.yaml, kustomization.yaml |
| 2 | `feat(ai): add HTTPRoutes for envoy-gateway migration` | ai/*/app/httproute.yaml, kustomization.yaml |
| 2 | `feat(observability): add HTTPRoutes for envoy-gateway migration` | observability/*/app/httproute.yaml |
| 2 | `feat(network): add HTTPRoute for unifi` | network/unifi/app/httproute.yaml |
| 2 | `feat(kube-system): add HTTPRoute for hubble-ui` | kube-system/cilium/app/httproute.yaml |
| 2 | `feat(flux-system): add HTTPRoute for flux-webhook` | flux-system/flux/github/webhooks/httproute.yaml |
| 4 | `refactor(home): disable nginx ingress in favor of HTTPRoutes` | home/*/app/helmrelease.yaml |
| 4 | `refactor(media): disable nginx ingress in favor of HTTPRoutes` | media/*/app/helmrelease.yaml |
| 4 | `refactor(ai): disable nginx ingress in favor of HTTPRoutes` | ai/*/app/helmrelease.yaml |
| 4 | `refactor(observability): disable nginx ingress in favor of HTTPRoutes` | observability/*/app/helmrelease.yaml |
| 4 | `refactor: remove standalone nginx Ingress resources` | webhooks/ingress.yaml, externalservice.yaml |
| 5 | `refactor(network): remove ingress-nginx, complete envoy-gateway migration` | network/kustomization.yaml, ingress-nginx/ |

---

## Success Criteria

### Verification Commands
```bash
# All HTTPRoutes accepted
kubectl get httproute -A -o jsonpath='{range .items[*]}{.metadata.namespace}/{.metadata.name}: {.status.parents[0].conditions[?(@.type=="Accepted")].status}{"\n"}{end}'
# Expected: All show "True"

# No Ingress resources
kubectl get ingress -A
# Expected: "No resources found"

# ingress-nginx gone
kubectl get namespace ingress-nginx
# Expected: Error "not found"

# Flux healthy
flux get ks -A --status-selector ready=false
# Expected: Empty output

# Sample app accessible
curl -s -o /dev/null -w "%{http_code}" https://evcc.${SECRET_DOMAIN}/
# Expected: 200 or 302
```

### Final Checklist
- [ ] All HTTPRoutes accepted by Gateways
- [ ] All apps accessible via new routes
- [ ] External DNS records created for external apps
- [ ] No Ingress resources remain in cluster
- [ ] ingress-nginx namespace deleted
- [ ] Flux reconciliation healthy
- [ ] No "Must NOT Have" violations
