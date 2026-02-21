# NGINX to Envoy Gateway Migration - Product Requirements Document

**Document Version:** 1.0
**Last Updated:** February 21, 2026
**Status:** Approved
**Owner:** Platform Engineering

---

## Executive Summary

**TL;DR:** Migrate the entire Kubernetes cluster from NGINX Ingress Controller to Envoy Gateway with Gateway API within 1-3 days, maintaining parallel operation for easy rollback while ensuring all 29 applications remain accessible.

**Problem Statement:** The cluster currently relies on NGINX Ingress Controller, which lacks sufficient support on the Talos Linux platform. After limited testing with Envoy Gateway, the infrastructure is ready for full migration, but the process must be coordinated across 29 applications spanning 8 namespaces with critical NGINX-specific features (websockets, CORS, custom timeouts, backend TLS, SSL redirects) that must be preserved.

**Proposed Solution:** Execute a rapid but systematic migration using a parallel operation strategy where both NGINX and Envoy Gateway run simultaneously during cutover. Convert 4 standalone Ingress resources and 25 HelmRelease-based applications to Gateway API HTTPRoutes, manually mapping NGINX-specific annotations to Envoy Gateway policies and filters. Keep NGINX operational for 24-48 hours post-migration to enable git-based rollback if issues arise.

**Success Metrics:**
- All 29 applications accessible via their original domains within 3 days
- Zero critical service outages (non-critical disruptions acceptable)
- External-dns and cert-manager integrations validated and working
- NGINX Ingress Controller cleanly removed from cluster after validation period

---

## 1. Product Overview

### 1.1 Vision & Objectives

**Vision:** Establish a modern, GitOps-managed ingress platform using Gateway API and Envoy Gateway that provides production-ready routing, TLS termination, and traffic management with better Talos Linux compatibility and future extensibility.

**Primary Objectives:**
- **Objective 1:** Migrate all ingress routing (4 standalone Ingress + 25 HelmRelease apps) from NGINX to Envoy Gateway HTTPRoutes within 3 days
- **Objective 2:** Preserve all existing functionality including websockets, CORS, custom timeouts, backend protocol configurations, and TLS certificate management
- **Objective 3:** Maintain parallel operation (NGINX + Envoy) for 24-48 hours to enable rapid rollback via Git revert if critical issues emerge
- **Objective 4:** Validate external-dns and cert-manager integrations work correctly with Gateway API resources

### 1.2 Target Audience

**Primary Users:**
- **Platform Engineer (Self)** - Responsible for cluster operations, needs reliable ingress with rollback capability, familiar with Flux CD GitOps workflows, comfortable with downtime windows for home lab environment
- **Application Services** - 29 deployed services (home automation, media stack, AI workloads, observability tools) that require uninterrupted HTTP/HTTPS routing

**Secondary Users/Stakeholders:**
- **Home Network Users** - Family members and devices accessing services like Home Assistant, Plex, Frigate
- **Future Developers** - Anyone contributing to this cluster should find Gateway API patterns clearly documented and reusable

### 1.3 Scope

**In Scope (This Migration):**
- Convert 4 standalone Ingress resources to HTTPRoutes (observability/blackbox-exporter, rook-ceph/dashboard, flux-system/webhook, home/tesla-proxy)
- Convert 25 HelmRelease applications using bjw-s/app-template ingress to HTTPRoute definitions
- Map NGINX-specific annotations to Gateway API equivalents:
  - Websocket support (Home Assistant)
  - CORS configurations (Garmin MCP)
  - Custom proxy timeouts (Home Assistant)
  - Backend TLS protocol (UniFi, Tesla Proxy)
  - SSL redirect and rewrite rules (Tesla Proxy)
- Validate TLS certificate management with existing cert-manager setup
- Validate external-dns integration with HTTPRoute resources
- Deploy and configure two Gateway resources (envoy-external, envoy-internal) with separate LoadBalancer IPs
- Create reusable HTTPRoute templates for future applications
- Document migration patterns in repository README

**Out of Scope (Future Phases):**
- Performance optimization and load testing beyond basic functionality validation
- Advanced Envoy features (rate limiting beyond what exists, custom filters, WASM extensions)
- Migration of any runtime-only configurations not declared in Git repository
- Multi-cluster ingress or cross-cluster routing
- Advanced observability (Envoy access logs, distributed tracing) beyond basic metrics

**Non-Goals:**
- This is NOT a cluster-wide infrastructure redesign—only ingress layer is changing
- NOT migrating workloads themselves (pods, deployments, services remain unchanged)
- NOT implementing new features during migration (strict feature parity only)
- NOT optimizing application configurations beyond ingress requirements

---

## 2. User Stories & Requirements

### 2.1 Core User Stories

**Epic 1: Gateway API Infrastructure Deployment**

**User Story 1.1: Gateway API CRDs Installation**
- **Story:** As a platform engineer, I want Gateway API v1 CRDs installed before any Gateway resources, so that Flux can successfully apply Gateway and HTTPRoute manifests without errors
- **Acceptance Criteria:**
  - Given the cluster is running, when I apply gateway-api-crds via Flux, then `kubectl get crds | grep gateway` shows GatewayClass, Gateway, HTTPRoute CRDs installed
  - Given CRDs are installed, when I deploy envoy-gateway HelmRelease, then it deploys successfully without CRD conflicts
- **Priority:** Must-Have
- **Estimated Effort:** Small (1 hour—resources already exist in repo)

**User Story 1.2: Envoy Gateway Controller Deployment**
- **Story:** As a platform engineer, I want Envoy Gateway controller running in the network namespace with proper RBAC and configuration, so that it can reconcile Gateway and HTTPRoute resources
- **Acceptance Criteria:**
  - Given CRDs are installed, when envoy-gateway HelmRelease reconciles, then `kubectl get pods -n network` shows envoy-gateway-controller in Running state
  - Given controller is running, when I check logs, then no errors related to RBAC or configuration appear
  - Given GatewayClass "envoy" is created, when I `kubectl describe gatewayclass envoy`, then status shows Accepted: True
- **Priority:** Must-Have
- **Estimated Effort:** Small (1 hour—HelmRelease exists, may need values validation)

**User Story 1.3: Gateway Resources with LoadBalancer IPs**
- **Story:** As a platform engineer, I want two Gateway resources (envoy-external and envoy-internal) with static LoadBalancer IPs assigned via Cilium LBIPAM, so that services have stable external and internal endpoints
- **Acceptance Criteria:**
  - Given Gateways are deployed, when I `kubectl get gateway -n network`, then both envoy-external and envoy-internal show Status: Programmed=True with assigned IPs matching ${SVC_EXTERNAL_GW_ADDR} and ${SVC_INTERNAL_GW_ADDR}
  - Given Gateways are programmed, when I check envoy proxy pods, then 2 replicas are running per Gateway (4 total pods)
  - Given HTTP listeners exist on port 80, when I curl http://<gateway-ip>, then I receive 301 redirect to HTTPS (via existing https-redirect HTTPRoute)
  - Given HTTPS listeners exist on port 443 with TLS, when I curl https://<gateway-ip> (ignoring cert validation), then connection succeeds (even if 404 returned due to no matching route)
- **Priority:** Must-Have
- **Estimated Effort:** Small (1 hour—resources exist, validation needed)

**Epic 2: Certificate Management Validation**

**User Story 2.1: Existing TLS Certificates Work with Gateways**
- **Story:** As a platform engineer, I want to confirm that my existing wildcard certificate (${SECRET_DOMAIN/./-}-production-tls) works with Gateway TLS listeners, so that I don't need to recreate certificates
- **Acceptance Criteria:**
  - Given certificates exist in network namespace, when I inspect Gateway TLS configuration, then certificateRefs point to the correct secret name
  - Given Gateway references the secret, when I curl https://<gateway-ip> -v, then the served certificate matches the expected domain wildcard
  - Given existing cert-manager setup, when I check Certificate resources, then they show Ready=True without errors
- **Priority:** Must-Have
- **Estimated Effort:** Small (1 hour—check existing resources, verify references)

**User Story 2.2: cert-manager Integration with Gateway API**
- **Story:** As a platform engineer, I want to verify cert-manager can issue certificates for Gateway resources (not just Ingress), so that automatic certificate renewal continues working
- **Acceptance Criteria:**
  - Given cert-manager is installed (unknown version), when I check version, then it is v1.19+ (required for Gateway API annotation support)
  - IF cert-manager < v1.19, when I upgrade to v1.19+, then upgrade completes without errors
  - Given Gateway has `cert-manager.io/cluster-issuer` annotation, when I apply it, then cert-manager creates a Certificate resource
  - Given Certificate is created, when it becomes Ready, then the referenced Secret contains valid TLS data
- **Priority:** Should-Have (migration can proceed without this if manual certs used, but auto-renewal is critical long-term)
- **Estimated Effort:** Medium (2 hours—version check, potential upgrade, validation)

**Epic 3: External-DNS Integration**

**User Story 3.1: external-dns Watches HTTPRoute Resources**
- **Story:** As a platform engineer, I want external-dns to automatically create DNS records for HTTPRoute hostnames, so that I don't manually manage DNS entries
- **Acceptance Criteria:**
  - Given external-dns is running, when I check its configuration, then `sources` includes `gateway-httproute` (in addition to `ingress`)
  - Given HTTPRoute has hostname "test.${SECRET_DOMAIN}", when external-dns reconciles, then DNS record exists pointing to Gateway LoadBalancer IP
  - Given HTTPRoute uses external-dns annotations, when I inspect created DNS records, then they match the target specified in annotations (external.${SECRET_DOMAIN} or internal.${SECRET_DOMAIN})
- **Priority:** Must-Have
- **Estimated Effort:** Medium (2 hours—check config, update if needed, validate)

**Epic 4: NGINX Annotation Mapping**

**User Story 4.1: Websocket Support Migration (Home Assistant)**
- **Story:** As a home automation user, I want Home Assistant websocket connections to work through Envoy Gateway, so that real-time updates continue functioning
- **Acceptance Criteria:**
  - Given Home Assistant uses `nginx.ingress.kubernetes.io/websocket-services`, when I create HTTPRoute, then Envoy allows websocket upgrade by default (HTTP/1.1 Upgrade header passthrough)
  - Given Home Assistant uses custom proxy timeouts, when I map them to HTTPRoute timeout configuration or BackendTrafficPolicy, then websocket connections remain stable for hours without disconnection
  - Given Home Assistant is accessed via browser, when I open the UI, then websocket connection indicator shows green/connected
- **Priority:** Must-Have
- **Estimated Effort:** Medium (2 hours—research Envoy websocket behavior, configure timeouts, test)

**User Story 4.2: CORS Policy Migration (Garmin MCP)**
- **Story:** As an AI service user, I want Garmin MCP CORS to work correctly, so that browser-based API calls succeed
- **Acceptance Criteria:**
  - Given Garmin MCP uses `nginx.ingress.kubernetes.io/enable-cors` and `cors-allow-origin: "*"`, when I create SecurityPolicy with CORS configuration, then preflight OPTIONS requests return correct CORS headers
  - Given CORS policy is attached to HTTPRoute, when I make cross-origin API calls from browser, then requests succeed with credentials
  - Given CORS headers include specific methods/headers, when I inspect response headers, then Access-Control-Allow-Methods and Access-Control-Allow-Headers match NGINX configuration
- **Priority:** Must-Have
- **Estimated Effort:** Medium (2-3 hours—create SecurityPolicy, attach to HTTPRoute, test preflight)

**User Story 4.3: Backend TLS Protocol (UniFi, Tesla Proxy)**
- **Story:** As a network admin, I want UniFi and Tesla Proxy backends to be accessed via HTTPS (not HTTP), so that end-to-end encryption is maintained
- **Acceptance Criteria:**
  - Given UniFi uses `nginx.ingress.kubernetes.io/backend-protocol: HTTPS`, when I configure HTTPRoute, then Envoy establishes TLS connection to backend service (either via Service port naming convention `https` or upstream TLS configuration)
  - Given Tesla Proxy uses HTTPS backend, when I curl through Gateway, then backend connection uses TLS (verified via Envoy logs or tcpdump if needed)
  - Given backend has self-signed cert, when Envoy connects, then it either validates cert or is configured to skip validation (depending on security requirements)
- **Priority:** Must-Have
- **Estimated Effort:** Large (3-4 hours—research Envoy upstream TLS config, may need EnvoyPatchPolicy or Service annotation)

**User Story 4.4: URL Rewrite and SSL Redirect (Tesla Proxy)**
- **Story:** As a Tesla Proxy user, I want path rewrites and automatic HTTP→HTTPS redirect to work, so that routing behaves identically to NGINX
- **Acceptance Criteria:**
  - Given Tesla Proxy uses `nginx.ingress.kubernetes.io/rewrite-target: /`, when I create HTTPRoute with URLRewrite filter, then paths are rewritten correctly
  - Given force-ssl-redirect annotation, when I access http://tesla-proxy.${SECRET_DOMAIN}, then I get 301 redirect to https://
  - Given HTTPRoute is configured, when I test full end-to-end flow, then application loads without errors
- **Priority:** Must-Have
- **Estimated Effort:** Medium (2 hours—configure HTTPRoute filters, test)

**Epic 5: Application Migration Execution**

**User Story 5.1: Standalone Ingress to HTTPRoute Conversion**
- **Story:** As a platform engineer, I want to convert 4 standalone Ingress resources to HTTPRoute, so that they route through Envoy Gateway
- **Acceptance Criteria:**
  - Given blackbox-exporter, rook-ceph-dashboard, flux-webhook, tesla-proxy have Ingress resources, when I create equivalent HTTPRoute files, then each matches hostname, path, backend service, and TLS configuration
  - Given HTTPRoutes reference correct Gateway parentRef (envoy-internal or envoy-external), when applied, then HTTPRoute status shows Accepted=True and parentRef shows resolved
  - Given applications are accessed via original hostnames, when I test each one, then they load successfully
  - Given Ingress resources still exist, when both are active, then HTTPRoute takes precedence (no conflict)
- **Priority:** Must-Have
- **Estimated Effort:** Medium (3 hours—create 4 HTTPRoutes, validate each)

**User Story 5.2: HelmRelease Ingress Configuration Migration**
- **Story:** As a platform engineer, I want to convert 25 HelmRelease apps (using bjw-s app-template) from ingress to Gateway API configuration, so that they route through Envoy Gateway
- **Acceptance Criteria:**
  - Given apps have `ingress.app.enabled: true` and `className: internal/external`, when I update HelmRelease values to disable ingress OR create separate HTTPRoute resources, then apps deploy successfully
  - Given HelmRelease values include NGINX annotations, when I migrate to HTTPRoute + policies, then functional equivalence is achieved (websockets, CORS, timeouts, backend TLS)
  - Given 25 apps are migrated, when I check HTTPRoute status for all, then all show Accepted=True and parentRef resolved
  - Given apps are accessed via original hostnames, when I test a representative sample (5-10 apps), then they load successfully
- **Priority:** Must-Have
- **Estimated Effort:** Large (8-12 hours spread across 2-3 days—bulk editing, testing, debugging)

**User Story 5.3: Rollback Safety via Parallel Operation**
- **Story:** As a platform engineer, I want both NGINX and Envoy Gateway running simultaneously during migration, so that I can quickly revert via Git if critical issues arise
- **Acceptance Criteria:**
  - Given Envoy Gateway HTTPRoutes are deployed, when I check NGINX Ingress controller pods, then they remain running in network namespace
  - Given both systems are active, when I access services via external DNS (pointing to Envoy Gateway LoadBalancer), then traffic routes through Envoy
  - IF a critical issue occurs, when I revert Git commit removing Ingress resources and update DNS to point back to NGINX LoadBalancer, then traffic resumes through NGINX within 5 minutes
  - Given validation period completes (24-48 hours), when I remove NGINX Ingress HelmReleases and Ingress resources, then Envoy Gateway handles all traffic without issues
- **Priority:** Must-Have
- **Estimated Effort:** Small (built into migration process—no additional work beyond not deleting NGINX immediately)

**Epic 6: Validation and Cleanup**

**User Story 6.1: End-to-End Functional Testing**
- **Story:** As a platform engineer, I want to validate that all 29 applications are accessible and functional after migration, so that I can confidently proceed with cleanup
- **Acceptance Criteria:**
  - Given migration is complete, when I access each application via its original hostname, then it loads successfully (defined as: HTTP 200 response, application UI renders, no immediate errors in browser console)
  - Given critical applications (Home Assistant, Plex, Grafana, UniFi), when I test core functionality (login, media playback, dashboard load, device management), then all work correctly
  - Given monitoring is in place, when I check Envoy proxy metrics, then no abnormal error rates (5xx responses < 1%)
- **Priority:** Must-Have
- **Estimated Effort:** Medium (3-4 hours—systematic testing, issue triage)

**User Story 6.2: NGINX Ingress Controller Removal**
- **Story:** As a platform engineer, I want to cleanly remove NGINX Ingress Controller after successful validation, so that the cluster only runs Envoy Gateway
- **Acceptance Criteria:**
  - Given 24-48 hours have passed since migration without critical issues, when I delete NGINX Ingress internal/external HelmReleases, then they uninstall cleanly
  - Given HelmReleases are removed, when I delete remaining Ingress resources from Git, then Flux prunes them from cluster
  - Given NGINX is removed, when I check for leftover resources (`kubectl get all -n network -l app.kubernetes.io/name=ingress-nginx`), then none remain
  - Given only Envoy Gateway exists, when I access applications, then they continue working (no regression)
- **Priority:** Must-Have
- **Estimated Effort:** Small (1 hour—delete resources, verify cleanup)

### 2.2 Functional Requirements

**Feature 1: Gateway API Resource Management**

- **Description:** Deploy and manage Gateway API v1 resources (GatewayClass, Gateway, HTTPRoute) via Flux CD with proper dependencies
- **Requirements:**
  - FR-1.1: The system must install Gateway API CRDs before any Gateway resources are applied
  - FR-1.2: The system must deploy Envoy Gateway HelmRelease with dependency on CRDs
  - FR-1.3: The system must create two Gateway resources (envoy-external, envoy-internal) with distinct LoadBalancer IPs
  - FR-1.4: The system must create HTTPRoute resources in application namespaces that reference Gateways in network namespace via parentRefs
  - FR-1.5: The system should validate Gateway status shows Programmed=True before considering deployment successful
- **Acceptance Criteria:**
  - Flux Kustomizations for gateway-api resources have correct `dependsOn` ordering (CRDs → controller → gateways → routes)
  - `kubectl get gateway -n network` shows both Gateways with Status: Programmed and assigned IPs
  - `kubectl get httproute -A` shows all HTTPRoutes with Status: Accepted and parentRef resolved
  - Error handling: If Gateway is not Programmed, HTTPRoute status shows unresolved parentRef with descriptive error

**Feature 2: TLS Certificate Integration**

- **Description:** Configure Gateway HTTPS listeners to use existing TLS certificates and validate cert-manager integration for automatic renewal
- **Requirements:**
  - FR-2.1: The system must reference existing wildcard certificate secret in Gateway TLS listeners
  - FR-2.2: The system must support cert-manager v1.19+ annotations on Gateway resources for automatic certificate provisioning
  - FR-2.3: The system should validate that served certificates match expected domain before migration completes
  - FR-2.4: The system must ensure certificate secrets are in the same namespace as Gateway (network namespace)
- **Acceptance Criteria:**
  - Gateway HTTPS listeners reference `${SECRET_DOMAIN/./-}-production-tls` secret
  - TLS handshake succeeds when curling Gateway IP with SNI for configured hostnames
  - cert-manager creates Certificate resources automatically when Gateway has issuer annotation
  - Error handling: If secret not found, Gateway listener shows NotReady with "secret not found" error

**Feature 3: NGINX Annotation Equivalence**

- **Description:** Replicate all NGINX-specific annotation behaviors using Gateway API filters, policies, and Envoy configuration
- **Requirements:**
  - FR-3.1: The system must support websocket connections (replicate `nginx.ingress.kubernetes.io/websocket-services`)
  - FR-3.2: The system must support CORS policies (replicate `nginx.ingress.kubernetes.io/cors-*` annotations)
  - FR-3.3: The system must support custom proxy timeouts (replicate `nginx.ingress.kubernetes.io/proxy-*-timeout`)
  - FR-3.4: The system must support backend HTTPS connections (replicate `nginx.ingress.kubernetes.io/backend-protocol: HTTPS`)
  - FR-3.5: The system must support URL rewrites (replicate `nginx.ingress.kubernetes.io/rewrite-target`)
  - FR-3.6: The system must support HTTP→HTTPS redirects (replicate `nginx.ingress.kubernetes.io/force-ssl-redirect`)
- **Acceptance Criteria:**
  - Websockets: Home Assistant websocket indicator shows connected; long-lived connections (1+ hour) remain stable
  - CORS: Preflight OPTIONS requests return correct Access-Control-* headers; cross-origin API calls succeed
  - Timeouts: Long-running requests (Home Assistant) do not disconnect prematurely
  - Backend TLS: Envoy establishes TLS connections to services with backend-protocol HTTPS; tcpdump or logs confirm encrypted backend traffic
  - URL rewrites: Path rewrite HTTPRoute filters correctly transform request paths; application receives expected path
  - SSL redirects: HTTP requests to applications return 301 redirect to HTTPS; browser automatically upgrades to HTTPS
  - Error handling: If annotation has no Gateway API equivalent, migration plan documents workaround or limitation

**Feature 4: External-DNS Automation**

- **Description:** Configure external-dns to watch HTTPRoute resources and automatically create/update DNS records
- **Requirements:**
  - FR-4.1: The system must configure external-dns to include `gateway-httproute` in sources
  - FR-4.2: The system must create DNS A/CNAME records for HTTPRoute hostnames pointing to Gateway LoadBalancer IPs
  - FR-4.3: The system should respect external-dns annotations on HTTPRoute resources (target, enabled flag)
  - FR-4.4: The system must clean up DNS records when HTTPRoute resources are deleted
- **Acceptance Criteria:**
  - external-dns logs show "Processing HTTPRoute" messages
  - DNS queries for HTTPRoute hostnames resolve to correct Gateway LoadBalancer IP
  - Annotated HTTPRoutes create DNS records with specified target (external.${SECRET_DOMAIN} or internal.${SECRET_DOMAIN})
  - Error handling: If external-dns misconfigured, migration plan includes manual DNS record creation as fallback

**Feature 5: Parallel Operation and Rollback**

- **Description:** Maintain both NGINX and Envoy Gateway operational during migration period to enable rapid rollback
- **Requirements:**
  - FR-5.1: The system must keep NGINX Ingress controller HelmReleases active during migration
  - FR-5.2: The system must keep Ingress resources in Git repository during migration (commented or inactive)
  - FR-5.3: The system should support rollback via Git revert + DNS update to NGINX LoadBalancer IP
  - FR-5.4: The system must only remove NGINX components after 24-48 hour validation period
- **Acceptance Criteria:**
  - During migration, `kubectl get pods -n network` shows both NGINX and Envoy Gateway pods running
  - NGINX LoadBalancer service remains accessible with stable IP
  - If rollback needed, reverting Git commits and updating DNS to NGINX IP restores service within 5 minutes
  - Error handling: If NGINX accidentally removed early, procedure documents reinstallation from HelmRelease

### 2.3 Non-Functional Requirements

**Performance:**
- HTTPRoute lookup latency: < 10ms for Gateway to match hostname to route (Envoy native capability)
- TLS handshake time: < 100ms (no regression from NGINX)
- Request proxy latency: < 5ms overhead added by Envoy (comparable to NGINX)
- Gateway reconciliation time: < 30 seconds for HTTPRoute changes to be active (Flux + Envoy propagation)

**Security:**
- TLS termination: Minimum TLS 1.2 (configured in existing ClientTrafficPolicy)
- Certificate validation: Wildcard certificate must match all subdomains
- Backend TLS: Services requiring HTTPS backend must use encrypted upstream connections
- Secret isolation: TLS secrets remain in network namespace with RBAC preventing unauthorized access

**Scalability:**
- Concurrent connections: Support existing traffic patterns (home lab scale, not production SaaS)
- HTTPRoute count: Support 50+ HTTPRoute resources (current 29 apps + future growth)
- Envoy proxy replicas: 2 replicas per Gateway (4 total pods, existing configuration)
- Gateway listeners: Support unlimited hostnames via HTTPRoute hostname matching (no per-Gateway limit)

**Reliability:**
- Uptime target: 99% during migration period (allow for brief testing outages)
- Rollback capability: < 5 minutes to restore NGINX routing via Git revert
- Zero-data-loss: Migration only affects routing layer, no persistent data changes
- Fault tolerance: Envoy proxy replicas distributed across nodes (Kubernetes scheduling)

**Accessibility:**
- N/A—infrastructure migration does not affect user-facing UI accessibility

**Maintainability:**
- GitOps source of truth: All Gateway API resources in Git with Flux managing deployment
- Documentation: Migration patterns documented in repository CLAUDE.md and README.md
- Reusability: HTTPRoute templates created for common patterns (internal HTTPS, external HTTPS with auth)
- Validation: Pre-commit hooks validate HTTPRoute schema before Git push

---

## 3. Technical Specifications

### 3.1 Recommended Tech Stack

**Current Infrastructure (No Changes):**
- **Kubernetes Distribution:** Talos Linux 1.x
- **GitOps:** Flux CD v2 (kustomize-controller, helm-controller, source-controller)
- **Container Network:** Cilium CNI with eBPF dataplane
- **LoadBalancer:** Cilium LBIPAM for static IP assignment
- **Certificate Management:** cert-manager (version TBD, must verify/upgrade to v1.19+)
- **DNS Automation:** external-dns with Cloudflare provider
- **Monitoring:** Prometheus + Grafana (existing observability stack)

**New Components (Migration Additions):**
- **Gateway API:** v1.0+ CRDs (GatewayClass, Gateway, HTTPRoute)
  - Rationale: Industry-standard Kubernetes ingress evolution, better than custom CRDs
- **Envoy Gateway:** Latest stable release (v1.x, likely v1.7.0+ to avoid known bugs)
  - Rationale: Reference implementation for Gateway API with Envoy proxy, strong community support, Envoy proven at scale
- **Envoy Proxy:** Embedded in Envoy Gateway deployment
  - Rationale: High-performance L7 proxy with extensive observability, battle-tested in production environments

**Deployment Pattern:**
- **Helm Charts:** Envoy Gateway deployed via HelmRelease (Flux)
- **GitOps:** All configurations (Gateway, HTTPRoute, policies) in Git with Flux reconciliation
- **Namespaces:** Gateway resources in `network` namespace, HTTPRoutes in application namespaces

### 3.2 Data Models

**Entity: Gateway**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: envoy-external  # or envoy-internal
  namespace: network
  annotations:
    external-dns.alpha.kubernetes.io/target: external.${SECRET_DOMAIN}  # DNS target for external-dns
spec:
  gatewayClassName: envoy  # references GatewayClass
  infrastructure:
    annotations:
      external-dns.alpha.kubernetes.io/hostname: external.${SECRET_DOMAIN}
      lbipam.cilium.io/ips: ${SVC_EXTERNAL_GW_ADDR}  # static IP from Cilium LBIPAM
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: Same  # or All depending on routing needs
    - name: https
      protocol: HTTPS
      port: 443
      allowedRoutes:
        namespaces:
          from: All  # allow HTTPRoutes from any namespace
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: ${SECRET_DOMAIN/./-}-production-tls  # wildcard cert managed by cert-manager
```

**Validation Rules:**
- `gatewayClassName` must reference existing GatewayClass (envoy)
- `certificateRefs` secret must exist in same namespace (network)
- `lbipam.cilium.io/ips` must be valid IP from cluster IP pool
- Listener names must be unique within Gateway
- HTTPS listeners must have `tls` configuration

**Entity: HTTPRoute**
```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-name
  namespace: app-namespace  # application namespace, not network
  annotations:
    external-dns.alpha.kubernetes.io/target: internal.${SECRET_DOMAIN}  # or external
spec:
  parentRefs:
    - name: envoy-internal  # or envoy-external
      namespace: network  # Gateway is in network namespace
      sectionName: https  # references specific listener (http or https)
  hostnames:
    - "app.${SECRET_DOMAIN}"  # must match DNS wildcard covered by Gateway TLS cert
  rules:
    - matches:
        - path:
            type: PathPrefix  # or Exact
            value: /  # path to match
      backendRefs:
        - name: app-service  # Kubernetes Service in same namespace
          port: 8080  # Service port number
      filters:  # optional—used for rewrites, redirects, etc.
        - type: URLRewrite  # example filter for path rewrite
          urlRewrite:
            path:
              type: ReplacePrefixMatch
              replacePrefixMatch: /new-path
```

**Validation Rules:**
- `parentRefs[].name` must reference existing Gateway in specified namespace
- `hostnames` must be valid DNS names
- `backendRefs[].name` must reference Service in same namespace as HTTPRoute
- `backendRefs[].port` must match Service port
- If `sectionName` specified, must match Gateway listener name
- Filters must be valid Gateway API filter types (URLRewrite, RequestRedirect, RequestHeaderModifier, ResponseHeaderModifier, RequestMirror)

**Entity: SecurityPolicy (Envoy Gateway Specific)**
```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: app-cors-policy
  namespace: app-namespace
spec:
  targetRefs:
    - kind: HTTPRoute  # or Gateway
      name: app-httproute
  cors:
    allowOrigins:
      - "*"  # or specific origins
    allowMethods:
      - GET
      - POST
      - PUT
      - DELETE
      - OPTIONS
    allowHeaders:
      - DNT
      - User-Agent
      - X-Requested-With
      - If-Modified-Since
      - Cache-Control
      - Content-Type
      - Range
      - Authorization
    allowCredentials: true
    maxAge: 86400
```

**Validation Rules:**
- `targetRefs` must reference existing HTTPRoute or Gateway
- SecurityPolicy must be in same namespace as target resource
- CORS allowOrigins cannot mix "*" with specific origins
- SecurityPolicy attached to HTTPRoute overrides (does NOT merge) Gateway-level SecurityPolicy

**Entity: BackendTrafficPolicy (Envoy Gateway Specific)**
```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: BackendTrafficPolicy
metadata:
  name: app-timeout-policy
  namespace: app-namespace
spec:
  targetRefs:
    - kind: HTTPRoute
      name: app-httproute
  timeout:
    http:
      requestTimeout: 3600s  # custom timeout for long-lived connections
```

**Validation Rules:**
- `targetRefs` must reference existing HTTPRoute or Gateway
- Timeout values must be valid duration strings (e.g., "60s", "5m", "1h")
- BackendTrafficPolicy must be in same namespace as target

### 3.3 API Specifications

**N/A—This is an infrastructure migration, not an application with APIs.**

Kubernetes API is used for resource management:
- `kubectl apply` - create/update Gateway API resources
- `kubectl get gateway/httproute` - check status
- `kubectl describe` - view events and conditions

### 3.4 Third-Party Integrations

**Integration 1: cert-manager**
- **Purpose:** Automatic TLS certificate issuance and renewal for Gateway HTTPS listeners
- **API/SDK:** Kubernetes CRDs (Certificate, Issuer, ClusterIssuer)
- **Authentication:** N/A (in-cluster service account RBAC)
- **Data Flow:**
  1. Gateway created with `cert-manager.io/cluster-issuer` annotation
  2. cert-manager watches Gateway resources
  3. cert-manager creates Certificate resource for Gateway hostnames
  4. cert-manager performs ACME challenge (DNS-01 via Cloudflare)
  5. cert-manager stores issued certificate in Secret referenced by Gateway
- **Rate Limits:** Let's Encrypt rate limits (50 certs/domain/week, 300 pending authorizations)
- **Cost:** Free (Let's Encrypt, cert-manager OSS)
- **Version Requirement:** v1.19+ for Gateway API support

**Integration 2: external-dns**
- **Purpose:** Automatic DNS record creation for HTTPRoute hostnames
- **API/SDK:** Cloudflare API (via external-dns Cloudflare provider)
- **Authentication:** Cloudflare API token (stored in Kubernetes Secret)
- **Data Flow:**
  1. external-dns watches HTTPRoute resources
  2. Extracts hostnames from HTTPRoute spec
  3. Reads external-dns annotations for target (external/internal.${SECRET_DOMAIN})
  4. Creates/updates DNS A or CNAME records in Cloudflare
  5. Deletes records when HTTPRoute is removed
- **Rate Limits:** Cloudflare API rate limits (1200 requests/5 minutes)
- **Cost:** Free (Cloudflare Free tier, external-dns OSS)
- **Configuration Required:** Update external-dns deployment to include `gateway-httproute` in `--source` flag

**Integration 3: Cilium LBIPAM**
- **Purpose:** Static LoadBalancer IP assignment for Gateway Services
- **API/SDK:** Kubernetes Service annotations (lbipam.cilium.io/ips)
- **Authentication:** N/A (in-cluster Cilium agent)
- **Data Flow:**
  1. Gateway controller creates LoadBalancer Service for Gateway
  2. Service annotated with `lbipam.cilium.io/ips: <static-ip>`
  3. Cilium LBIPAM controller assigns requested IP to Service
  4. Service becomes accessible via assigned IP
- **Rate Limits:** N/A
- **Cost:** Free (Cilium OSS)

### 3.5 System Architecture

**High-Level Architecture:**

```
┌─────────────────────────────────────────────────────────────────┐
│                         External Clients                         │
│              (browsers, apps accessing services)                 │
└────────────────────────────┬────────────────────────────────────┘
                             │ DNS: *.${SECRET_DOMAIN}
                             │ (managed by external-dns)
                             ▼
                 ┌───────────────────────┐
                 │   Cloudflare DNS      │
                 └───────────┬───────────┘
                             │
            ┌────────────────┼────────────────┐
            ▼                                 ▼
  ┌──────────────────┐            ┌──────────────────┐
  │ envoy-external   │            │ envoy-internal   │
  │ Gateway          │            │ Gateway          │
  │ LoadBalancer IP  │            │ LoadBalancer IP  │
  │ (external.domain)│            │ (internal.domain)│
  └────────┬─────────┘            └────────┬─────────┘
           │                                │
           │  ┌─────────────────────────────┤
           │  │                             │
           ▼  ▼                             ▼
  ┌─────────────────────────────────────────────────┐
  │         Envoy Proxy Pods (network ns)           │
  │  - 2 replicas per Gateway (4 total)             │
  │  - Routes traffic based on HTTPRoute rules      │
  │  - Terminates TLS (cert from cert-manager)      │
  │  - Applies filters (CORS, timeouts, rewrites)   │
  └──────────────────┬──────────────────────────────┘
                     │ matches HTTPRoute hostname/path
                     │
        ┌────────────┼────────────┬─────────────┐
        ▼            ▼            ▼             ▼
   ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐
   │ Service │  │ Service │  │ Service │  │ Service │
   │ (home)  │  │ (media) │  │ (observ)│  │  (ai)   │
   └────┬────┘  └────┬────┘  └────┬────┘  └────┬────┘
        │            │            │            │
        ▼            ▼            ▼            ▼
   Application  Application  Application  Application
      Pods         Pods         Pods         Pods
```

**Key Components:**

- **Gateway API CRDs:** Define GatewayClass, Gateway, HTTPRoute resources (cluster-scoped config)
- **Envoy Gateway Controller:** Watches Gateway API resources, reconciles Envoy proxy configuration (network namespace)
- **Envoy Proxy Pods:** Data plane—handles actual traffic routing, TLS termination, load balancing (network namespace, 2 replicas per Gateway)
- **Gateway Resources:** Two Gateways (envoy-external, envoy-internal) with separate LoadBalancer IPs (network namespace)
- **HTTPRoute Resources:** Per-application routing rules in app namespaces, reference Gateways via parentRefs
- **SecurityPolicy/BackendTrafficPolicy:** Envoy Gateway extension policies for CORS, timeouts, etc. (app namespaces)
- **cert-manager:** Watches Gateways, issues TLS certificates, stores in Secrets (cert-manager namespace)
- **external-dns:** Watches HTTPRoutes, creates DNS records in Cloudflare (network namespace)

**Data Flow (HTTP Request):**
1. Client resolves `app.${SECRET_DOMAIN}` via DNS → gets Gateway LoadBalancer IP
2. Client sends HTTP request to Gateway IP:80
3. Envoy proxy receives request on HTTP listener
4. Global https-redirect HTTPRoute matches (sectionName: http), applies RequestRedirect filter
5. Client receives 301 redirect to `https://app.${SECRET_DOMAIN}`
6. Client sends HTTPS request to Gateway IP:443
7. Envoy terminates TLS using certificate from Secret (cert-manager issued)
8. Envoy matches HTTPRoute based on hostname (`app.${SECRET_DOMAIN}`)
9. Envoy applies filters (CORS, timeout, rewrite if configured)
10. Envoy forwards request to backend Service (via backendRef)
11. Application pod processes request, returns response
12. Envoy returns response to client (applies response filters if configured)

**Rollback Data Flow (If Migration Fails):**
1. Engineer reverts Git commits (removes HTTPRoute resources, restores Ingress resources)
2. Flux reconciles Git state, recreates Ingress resources
3. Engineer updates DNS records to point to NGINX LoadBalancer IP (manual Cloudflare update or external-dns annotation change)
4. Clients resolve DNS → get NGINX LoadBalancer IP
5. Traffic flows through NGINX Ingress Controller (existing stable routing)

---

## 4. User Experience & Design

### 4.1 Design Principles

- **Principle 1: Transparent Migration** - End users (application services, family members) should not notice the migration. All hostnames, paths, and behaviors remain identical.
- **Principle 2: GitOps Source of Truth** - All configuration changes committed to Git before applied to cluster. No manual kubectl apply outside GitOps workflow.
- **Principle 3: Fail-Safe Rollback** - Maintain parallel operation to enable rapid rollback. Never delete working configuration until replacement is validated.
- **Principle 4: Progressive Validation** - Test each annotation mapping and policy in isolation before bulk migration. Start with simple apps, progress to complex.

### 4.2 Key User Flows

**Flow 1: Platform Engineer Migrates Single Application**
1. Engineer identifies app with simple routing (e.g., blackbox-exporter: no special annotations, internal-only)
2. Engineer creates HTTPRoute YAML file in `kubernetes/apps/observability/blackbox-exporter/app/httproute.yaml`
3. Engineer adds HTTPRoute to `app/kustomization.yaml` resources list
4. Engineer commits to Git, pushes to repository
5. Flux reconciles Kustomization, applies HTTPRoute
6. Engineer checks HTTPRoute status: `kubectl describe httproute blackbox-exporter -n observability`
7. Engineer verifies parentRef resolved and status shows Accepted
8. Engineer tests access via `curl https://blackbox-exporter.${SECRET_DOMAIN}` → receives HTTP 200
9. Engineer marks app as migrated in tracking checklist

**Flow 2: Platform Engineer Migrates Application with NGINX Annotations (Home Assistant)**
1. Engineer reviews existing HelmRelease, identifies NGINX annotations (websocket, proxy timeouts)
2. Engineer researches Gateway API equivalents:
   - Websocket: Envoy supports by default, no special config needed
   - Proxy timeouts: Create BackendTrafficPolicy with custom timeouts
3. Engineer creates `home-assistant/app/httproute.yaml` with hostname, backend, parentRef
4. Engineer creates `home-assistant/app/backendtrafficpolicy.yaml` with 3600s timeout
5. Engineer adds both files to `app/kustomization.yaml` resources
6. Engineer commits, pushes to Git
7. Flux applies HTTPRoute and BackendTrafficPolicy
8. Engineer tests Home Assistant:
   - UI loads successfully
   - Websocket indicator shows green (connected)
   - Leaves browser tab open for 1+ hour to verify no disconnections
9. Engineer verifies no errors in Envoy proxy logs: `kubectl logs -n network -l gateway.envoyproxy.io/owning-gateway-name=envoy-external`
10. Engineer marks Home Assistant as migrated

**Flow 3: Platform Engineer Validates cert-manager Integration**
1. Engineer checks current cert-manager version: `kubectl get deployment -n cert-manager cert-manager -o yaml | grep image:`
2. IF version < v1.19, engineer upgrades cert-manager via HelmRelease in Git
3. Engineer creates test Gateway with cert-manager annotation:
   ```yaml
   metadata:
     annotations:
       cert-manager.io/cluster-issuer: "letsencrypt-staging"  # use staging first
   ```
4. Engineer applies test Gateway, watches for Certificate creation: `kubectl get certificate -n network -w`
5. Engineer checks Certificate status becomes Ready
6. Engineer inspects Secret contains valid TLS certificate: `kubectl get secret -n network <cert-name> -o yaml`
7. Engineer tests TLS handshake: `openssl s_client -connect <gateway-ip>:443 -servername test.${SECRET_DOMAIN}`
8. IF successful, engineer updates production Gateways with cert-manager annotation
9. Engineer verifies production certificates issued successfully

**Flow 4: Rollback After Critical Issue Discovered**
1. Engineer discovers critical issue (e.g., Home Assistant websockets disconnecting after 5 minutes)
2. Engineer makes rollback decision (cannot debug in production, need stable service ASAP)
3. Engineer reverts Git commits that added HTTPRoute resources: `git revert <commit-sha>`
4. Engineer pushes revert to Git
5. Flux reconciles, removes HTTPRoute resources, restores Ingress resources
6. Engineer updates DNS CNAME to point to NGINX LoadBalancer IP (Cloudflare dashboard or external-dns annotation)
7. Engineer verifies Home Assistant accessible via NGINX (within 5 minutes)
8. Engineer investigates websocket timeout issue in non-production environment
9. Engineer fixes issue (discovers BackendTrafficPolicy needed `idle_timeout` in addition to `request_timeout`)
10. Engineer re-migrates Home Assistant with corrected configuration

**Flow 5: Final NGINX Removal After Successful Validation**
1. Engineer confirms 48 hours have passed since migration with no critical issues
2. Engineer removes NGINX HelmRelease resources from Git:
   - Delete `kubernetes/apps/network/ingress-nginx/internal/helmrelease.yaml`
   - Delete `kubernetes/apps/network/ingress-nginx/external/helmrelease.yaml`
   - Delete `kubernetes/apps/network/ingress-nginx/ks.yaml`
3. Engineer removes all remaining Ingress resources from application directories
4. Engineer commits changes with clear message: "Remove NGINX Ingress Controller - migration complete"
5. Flux reconciles, uninstalls NGINX HelmReleases
6. Engineer verifies NGINX pods terminated: `kubectl get pods -n network | grep ingress-nginx` → no results
7. Engineer checks for leftover resources: `kubectl get all -n network -l app.kubernetes.io/name=ingress-nginx` → no results
8. Engineer validates all applications still accessible via Envoy Gateway
9. Engineer updates cluster documentation (README.md, CLAUDE.md) to reflect Gateway API as standard ingress method
10. Engineer closes migration project

### 4.3 UI/UX Requirements

**N/A—Infrastructure migration has no end-user UI.**

Platform engineer experience:
- **Readable YAML:** HTTPRoute resources use consistent formatting, clear comments
- **Clear Status Messages:** Gateway/HTTPRoute status conditions provide actionable error messages
- **Observable Behavior:** Envoy proxy logs accessible via kubectl for debugging
- **Documentation:** README.md and CLAUDE.md updated with Gateway API patterns, example HTTPRoutes for common use cases

### 4.4 Design Assets

**N/A—No design assets for infrastructure.**

Documentation assets:
- Architecture diagram (ASCII art in PRD, could be converted to Mermaid diagram)
- Example HTTPRoute templates (will be created in `kubernetes/templates/gateway-api/`)
- Migration checklist (included in this PRD, will be added to repository docs)

---

## 5. Implementation Plan

### 5.1 Development Phases

**Phase 1: Pre-Migration Validation (Day 1 Morning, 3-4 hours)**

**Objective:** Confirm existing Envoy Gateway installation is functional and identify any blockers

**Tasks:**
1. Validate Gateway API CRDs installed: `kubectl get crds | grep gateway.networking.k8s.io`
2. Verify Envoy Gateway controller running: `kubectl get pods -n network -l control-plane=envoy-gateway`
3. Check Gateway resources status: `kubectl get gateway -n network -o wide` (confirm Programmed=True, IPs assigned)
4. Test existing HTTPRoutes (rook-ceph, blackbox-exporter):
   - `curl https://rook.${SECRET_DOMAIN}` → dashboard loads
   - `curl https://blackbox-exporter.${SECRET_DOMAIN}` → exporter UI loads
5. Verify cert-manager version: `kubectl get deployment -n cert-manager cert-manager -o jsonpath='{.spec.template.spec.containers[0].image}'`
   - IF < v1.19, upgrade cert-manager HelmRelease in Git, wait for reconciliation
6. Check external-dns configuration: `kubectl get deployment -n network external-dns -o yaml | grep -A 10 args` (verify `--source=gateway-httproute` present)
   - IF missing, update external-dns HelmRelease values, commit to Git, wait for reconciliation
7. Document current state:
   - NGINX LoadBalancer IPs (external, internal)
   - Envoy Gateway LoadBalancer IPs (external, internal)
   - Applications currently using NGINX: 29 total (4 standalone Ingress + 25 HelmRelease)

**Deliverables:**
- Pre-migration validation checklist completed
- Any blockers identified and resolved (cert-manager upgrade, external-dns config)
- Baseline state documented for rollback reference

**Phase 2: Simple Application Migration (Day 1 Afternoon, 4-5 hours)**

**Objective:** Migrate 4 standalone Ingress resources + 5 simple HelmRelease apps (no complex annotations)

**Tasks:**
1. Create HTTPRoute for flux-webhook (external gateway, simple routing):
   - File: `kubernetes/apps/flux-system/flux/github/webhooks/httproute.yaml`
   - Config: parentRef=envoy-external, hostname=flux-webhook.${SECRET_DOMAIN}, backend=webhook-receiver:80
   - Commit to Git, wait for Flux reconciliation
   - Test: `curl https://flux-webhook.${SECRET_DOMAIN}/hook/` → webhook responds
2. Create HTTPRoute for rook-ceph-dashboard (internal gateway, already tested):
   - Verify existing `kubernetes/apps/rook-ceph/rook-ceph/cluster/httproute.yaml` is correct
   - Test access, confirm no changes needed
3. Create HTTPRoute for blackbox-exporter (internal gateway, already tested):
   - Verify existing `kubernetes/apps/observability/blackbox-exporter/app/httproute.yaml`
   - Test access, confirm no changes needed
4. Migrate 5 simple apps (no NGINX annotations):
   - Identify candidates: Grafana, Prometheus, Kubernetes Dashboard, and 2 media apps (Radarr, Sonarr)
   - For each app:
     - Create `app/httproute.yaml` with hostname, parentRef, backend
     - Add to `app/kustomization.yaml` resources
     - Commit to Git
     - Test application loads successfully
5. Update DNS if needed:
   - Verify external-dns creates correct DNS records
   - IF external-dns not working, manually update DNS to point to Envoy Gateway IPs

**Deliverables:**
- 9 applications migrated (4 standalone + 5 simple HelmRelease apps)
- All 9 applications tested and confirmed accessible
- HTTPRoute template pattern established for simple apps

**Phase 3: Complex Annotation Migration (Day 2 Morning, 4-5 hours)**

**Objective:** Migrate applications with NGINX-specific annotations (websockets, CORS, timeouts, backend TLS)

**Tasks:**
1. Home Assistant (websockets + proxy timeouts):
   - Create `kubernetes/apps/home/home-assistant/app/httproute.yaml`
   - Create `kubernetes/apps/home/home-assistant/app/backendtrafficpolicy.yaml`:
     ```yaml
     spec:
       timeout:
         http:
           requestTimeout: 3600s
           idleTimeout: 3600s  # for websockets
     ```
   - Commit to Git, test:
     - UI loads successfully
     - Websocket connection established
     - Leave browser tab open for 1 hour, verify no disconnections
2. Garmin MCP (CORS):
   - Create `kubernetes/apps/ai/garmin-mcp/app/httproute.yaml`
   - Create `kubernetes/apps/ai/garmin-mcp/app/securitypolicy.yaml`:
     ```yaml
     spec:
       cors:
         allowOrigins: ["*"]
         allowMethods: [GET, POST, PUT, DELETE, OPTIONS]
         allowHeaders: [DNT, User-Agent, X-Requested-With, If-Modified-Since, Cache-Control, Content-Type, Range, Authorization]
         allowCredentials: true
     ```
   - Test: Make cross-origin API call from browser console, verify CORS headers
3. UniFi + Tesla Proxy (backend HTTPS):
   - Research Envoy upstream TLS configuration
   - Options:
     - Use Service port name "https" (Kubernetes convention)
     - Create BackendTLSPolicy (if Envoy Gateway supports)
     - Use EnvoyPatchPolicy for advanced config (last resort)
   - Implement chosen approach for UniFi first (test dashboard access)
   - Apply same pattern to Tesla Proxy
4. Tesla Proxy (URL rewrite + SSL redirect):
   - Create HTTPRoute with filters:
     ```yaml
     filters:
       - type: URLRewrite
         urlRewrite:
           path:
             type: ReplaceFullPath
             replaceFullPath: /
     ```
   - Test path rewriting works correctly
   - Verify HTTP→HTTPS redirect (should use existing global https-redirect HTTPRoute)

**Deliverables:**
- 4 complex applications migrated with annotation equivalents
- BackendTrafficPolicy and SecurityPolicy examples created
- Backend TLS solution documented (for future apps)

**Phase 4: Bulk Migration (Day 2 Afternoon, 4-5 hours)**

**Objective:** Migrate remaining 16 applications (mostly media and home apps with standard patterns)

**Tasks:**
1. Batch create HTTPRoute resources for remaining apps:
   - Use template from simple apps (Phase 2)
   - Apps list: bazarr, prowlarr, qbittorrent, photoprism, lidarr, overseerr, plex, emhass, evcc, frigate, zigbee2mqtt, teslamate, openwebui, mcpo, litellm (15 total, not 16—recount)
   - For each app:
     - Create `app/httproute.yaml` with correct hostname, backend, parentRef (internal vs external)
     - Add to `app/kustomization.yaml` resources
2. Commit all HTTPRoutes in single commit (or logical groups by namespace)
3. Wait for Flux reconciliation (may take 5-10 minutes for bulk resources)
4. Systematic testing:
   - Create testing checklist spreadsheet/markdown
   - For each app:
     - Access via original hostname
     - Verify HTTP 200 response
     - Check UI loads (visual confirmation)
     - Mark as validated in checklist
5. Investigate and fix any failures:
   - Check HTTPRoute status for errors
   - Check Envoy proxy logs for routing issues
   - Verify Service name/port matches backend

**Deliverables:**
- All 29 applications migrated to HTTPRoute
- Testing checklist completed with pass/fail status for each app
- Any issues documented and resolved

**Phase 5: Validation and Cleanup (Day 3, 3-4 hours)**

**Objective:** Perform extended validation, document patterns, prepare for NGINX removal

**Tasks:**
1. Extended functional testing (2-3 hours):
   - Test critical workflows:
     - Home Assistant: Add automation, verify real-time updates
     - Plex: Start media playback, verify streaming works
     - Frigate: Check camera feeds load correctly
     - UniFi: Manage network devices, verify backend HTTPS works
   - Leave services running for several hours, monitor for issues
2. Monitor Envoy Gateway metrics:
   - Check Prometheus for Envoy error rates: `envoy_http_downstream_rq_xx{envoy_response_code_class="5"}`
   - Verify no abnormal 5xx error rates
   - Check Gateway status remains Programmed
3. Verify external-dns and cert-manager:
   - Confirm all DNS records created correctly (dig queries)
   - Check certificate expiry dates (should be ~90 days for Let's Encrypt)
4. Document migration patterns:
   - Update `kubernetes/README.md` with Gateway API usage examples
   - Update `CLAUDE.md` with HTTPRoute creation patterns
   - Create `kubernetes/templates/gateway-api/` directory with templates:
     - `httproute-internal-simple.yaml` - internal HTTPS, no filters
     - `httproute-external-simple.yaml` - external HTTPS, no filters
     - `httproute-with-cors.yaml` - HTTPRoute + SecurityPolicy for CORS
     - `httproute-with-timeout.yaml` - HTTPRoute + BackendTrafficPolicy for timeouts
5. Prepare NGINX removal (do NOT execute yet):
   - Create Git commit that removes:
     - `kubernetes/apps/network/ingress-nginx/` directory (HelmReleases)
     - All remaining `ingress.yaml` files
   - Do NOT push commit yet (wait for validation period)

**Deliverables:**
- Extended validation completed, no critical issues found
- Documentation updated with Gateway API patterns
- HTTPRoute templates created for future use
- NGINX removal commit prepared but not applied

**Phase 6: Post-Migration Monitoring (Days 4-5, Passive)**

**Objective:** Monitor cluster for 24-48 hours before removing NGINX

**Tasks:**
1. Passive monitoring:
   - Check Grafana dashboards daily for error rate spikes
   - Monitor cluster logs for Envoy Gateway errors
   - Verify no user complaints about service accessibility
2. IF critical issue discovered:
   - Execute rollback procedure (revert HTTPRoute commits, update DNS)
   - Investigate root cause in non-production environment
   - Re-migrate with fix
3. IF no issues after 48 hours:
   - Push NGINX removal commit to Git
   - Wait for Flux to uninstall NGINX HelmReleases
   - Verify NGINX pods terminated cleanly
   - Verify applications remain accessible (spot check 5-10 apps)

**Deliverables:**
- 48-hour validation period completed
- NGINX Ingress Controller removed from cluster
- Migration considered complete and successful

### 5.2 Task Dependencies

```
Phase 1 (Pre-Migration Validation)
  ↓
  ├─ cert-manager v1.19+ verified/upgraded
  ├─ external-dns configured for gateway-httproute
  └─ Existing Gateways validated (Programmed=True)
  ↓
Phase 2 (Simple Apps)
  ↓
  ├─ HTTPRoute template established
  └─ 9 apps migrated and validated
  ↓
Phase 3 (Complex Annotations)
  ↓
  ├─ Websocket pattern validated (Home Assistant)
  ├─ CORS pattern validated (Garmin MCP)
  ├─ Backend TLS solution implemented (UniFi, Tesla Proxy)
  └─ URL rewrite pattern validated (Tesla Proxy)
  ↓
Phase 4 (Bulk Migration)
  ↓
  └─ All 29 apps migrated to HTTPRoute
  ↓
Phase 5 (Validation & Cleanup)
  ↓
  ├─ Extended testing completed
  ├─ Documentation updated
  └─ NGINX removal commit prepared
  ↓
Phase 6 (Post-Migration Monitoring)
  ↓
  ├─ 48-hour validation period
  └─ NGINX removed (if no issues)
```

**Critical Path:**
Phase 1 (cert-manager + external-dns) → Phase 3 (annotation patterns) → Phase 4 (bulk migration) → Phase 6 (validation + cleanup)

**Parallel Work Opportunities:**
- While waiting for Flux reconciliation (Phase 2-4), engineer can document patterns (Phase 5)
- Template creation (Phase 5) can start after Phase 2 completes (HTTPRoute pattern established)

### 5.3 Resource Requirements

**Development Team:**
- **Platform Engineer (Self)**: 1 person - Full ownership of migration, GitOps changes, validation, troubleshooting
- **Time Commitment**: 3 days active work (8-12 hours/day) + 2 days passive monitoring

**Tools & Services:**
- **Existing (No Additional Cost):**
  - Kubernetes cluster (Talos Linux)
  - Flux CD (GitOps reconciliation)
  - cert-manager (certificate management)
  - external-dns (DNS automation)
  - Cilium (LoadBalancer IP management)
  - Prometheus + Grafana (monitoring)
  - Cloudflare (DNS hosting—Free tier)
- **New (Free/OSS):**
  - Gateway API CRDs (Kubernetes SIG, free)
  - Envoy Gateway (OSS, free)
  - Envoy Proxy (OSS, free, included in Envoy Gateway)

**Total Estimated Cost:** $0/month (all OSS software, existing infrastructure)

**Compute Resources:**
- Envoy Gateway controller: ~100m CPU, ~256Mi memory (already deployed)
- Envoy Proxy pods: 4 pods × (100m CPU, 256Mi memory) = 400m CPU, 1Gi memory (already deployed)
- No additional node capacity required (existing cluster can support)

---

## 6. Testing Strategy

### 6.1 Testing Types

**Unit Testing:**
- N/A—Infrastructure resources, no code to unit test
- YAML validation via pre-commit hooks (yamllint, schema validation)

**Integration Testing:**
- **Gateway ↔ HTTPRoute Integration:**
  - Validate HTTPRoute parentRef resolution (Gateway exists, listener matches sectionName)
  - Test HTTPRoute hostname matching (wildcards, exact matches)
  - Verify backend Service references resolve correctly
- **Gateway ↔ cert-manager Integration:**
  - Create test Gateway with cert-manager annotation
  - Verify Certificate resource auto-created
  - Confirm Secret populated with valid TLS certificate
- **HTTPRoute ↔ external-dns Integration:**
  - Create test HTTPRoute with external-dns annotations
  - Verify DNS record created in Cloudflare
  - Confirm DNS record points to correct Gateway LoadBalancer IP

**End-to-End Testing:**
- **Critical Application Workflows:**
  - Home Assistant: Login → navigate dashboard → verify websocket real-time updates
  - Plex: Browse library → start media playback → verify streaming (5+ minutes)
  - Frigate: View camera feed → verify video loads
  - Grafana: View dashboard → verify metrics load
  - UniFi: Access controller → manage device → verify backend HTTPS connection
- **Cross-Browser Testing:** N/A (infrastructure, not web app)
- **Mobile Responsiveness:** N/A (applications responsible for their own UI)

**Performance Testing:**
- **Baseline Comparison:**
  - Measure NGINX response time for 10 apps: `curl -w "@curl-format.txt" https://app.${SECRET_DOMAIN}`
  - Measure Envoy Gateway response time for same 10 apps
  - Verify no significant regression (< 10ms difference acceptable)
- **Load Testing (Optional):**
  - Use `ab` (Apache Bench) or `wrk` to generate load: 100 concurrent requests to representative app
  - Verify error rate < 1%, latency p99 < 500ms

**Chaos Testing (Optional, Post-Migration):**
- Kill Envoy proxy pod, verify Gateway auto-recovers (new pod scheduled)
- Simulate backend Service unavailable, verify Envoy returns 503 (not crashes)

### 6.2 Test Scenarios

**Scenario 1: HTTPRoute Matches Hostname Correctly**
- **Given:** HTTPRoute created with hostname "test.${SECRET_DOMAIN}"
- **When:** Client sends request with Host header "test.${SECRET_DOMAIN}"
- **Then:** Envoy routes request to correct backend Service (verified via response content or logs)

**Scenario 2: HTTPRoute Does NOT Match Wrong Hostname**
- **Given:** HTTPRoute created with hostname "test.${SECRET_DOMAIN}"
- **When:** Client sends request with Host header "wrong.${SECRET_DOMAIN}"
- **Then:** Envoy returns 404 Not Found (no matching route)

**Scenario 3: TLS Certificate Served Correctly**
- **Given:** Gateway references TLS certificate secret
- **When:** Client connects via HTTPS with SNI "test.${SECRET_DOMAIN}"
- **Then:** TLS handshake succeeds, certificate CN or SAN matches "*.${SECRET_DOMAIN}"

**Scenario 4: CORS Preflight Request Succeeds**
- **Given:** SecurityPolicy with CORS attached to HTTPRoute
- **When:** Browser sends OPTIONS request with Origin header
- **Then:** Response includes Access-Control-Allow-Origin, Access-Control-Allow-Methods, Access-Control-Allow-Headers

**Scenario 5: Websocket Connection Remains Stable**
- **Given:** Home Assistant HTTPRoute with BackendTrafficPolicy timeout=3600s
- **When:** Browser establishes websocket connection, remains idle for 1 hour
- **Then:** Websocket remains connected (no disconnection events in browser console)

**Scenario 6: Backend HTTPS Connection Established**
- **Given:** UniFi HTTPRoute configured for backend TLS
- **When:** Envoy connects to UniFi Service
- **Then:** Envoy establishes TLS connection to backend (verified via Envoy debug logs or tcpdump showing TLS handshake)

**Scenario 7: URL Rewrite Transforms Path**
- **Given:** HTTPRoute with URLRewrite filter (ReplacePrefixMatch /old → /new)
- **When:** Client sends request to /old/path
- **Then:** Backend receives request at /new/path (verified via backend logs)

**Scenario 8: HTTP Redirects to HTTPS**
- **Given:** Global https-redirect HTTPRoute attached to HTTP listener
- **When:** Client sends request to http://app.${SECRET_DOMAIN}
- **Then:** Client receives 301 redirect to https://app.${SECRET_DOMAIN}

**Scenario 9: external-dns Creates DNS Record**
- **Given:** HTTPRoute with hostname "test.${SECRET_DOMAIN}" and external-dns annotation
- **When:** external-dns reconciles HTTPRoute
- **Then:** DNS query for test.${SECRET_DOMAIN} returns Gateway LoadBalancer IP

**Scenario 10: Rollback Restores NGINX Routing**
- **Given:** HTTPRoute migration causes critical issue (e.g., 50% of apps return 503)
- **When:** Engineer reverts Git commit (removes HTTPRoutes, restores Ingress) and updates DNS to NGINX IP
- **Then:** All apps accessible via NGINX within 5 minutes (DNS propagation + Flux reconciliation)

---

## 7. Success Metrics & Analytics

### 7.1 Key Performance Indicators

**Adoption Metrics:**
- **HTTPRoute Resources Created:** 29 (target: 29/29 = 100% migration)
- **NGINX Ingress Removed:** Yes/No (target: Yes after 48h validation)
- **Rollback Events:** 0 (target: ideally 0, acceptable: 1-2 if quickly resolved)

**Engagement Metrics:**
- **Application Uptime:** > 99% during migration period (brief outages during testing acceptable)
- **DNS Resolution Success Rate:** 100% (all hostnames resolve to Gateway IPs)
- **TLS Certificate Validity:** 100% (all certs valid, no expiry warnings)

**Technical Metrics:**
- **Gateway Status:** Programmed=True for envoy-external and envoy-internal (target: 100% uptime)
- **HTTPRoute Status:** Accepted=True for all 29 HTTPRoutes (target: 100%)
- **Envoy Proxy Error Rate:** < 1% (5xx responses / total requests)
- **Response Time Regression:** < 10ms increase compared to NGINX baseline
- **cert-manager Certificate Issuance:** 100% success rate (if using cert-manager annotations)

### 7.2 Analytics Implementation

**Events to Track:**
- **Gateway Programmed Status Changes:** Alert if Gateway loses Programmed=True status
- **HTTPRoute Accepted Status Changes:** Alert if HTTPRoute rejected (parentRef not resolved, invalid hostname, etc.)
- **Envoy Proxy Pod Restarts:** Alert on unexpected restarts (may indicate OOMKill, crash loop)
- **5xx Error Rate Spike:** Alert if 5xx rate exceeds 5% over 5-minute window
- **TLS Certificate Expiry:** Alert 7 days before expiry (should auto-renew via cert-manager)
- **DNS Resolution Failures:** Monitor external-dns logs for errors creating DNS records

**Analytics Tools:**
- **Prometheus:** Metrics collection (Gateway status, Envoy proxy metrics, cert-manager metrics)
- **Grafana:** Visualization (create "Gateway API Migration" dashboard with key metrics)
- **Kubernetes Events:** `kubectl get events -n network --sort-by='.lastTimestamp'` - monitor for errors during reconciliation
- **Flux Notifications:** (Optional) Configure Flux to send alerts to Slack/Discord on Kustomization failures

**Metrics Queries (PromQL examples):**
```promql
# Envoy 5xx error rate
sum(rate(envoy_http_downstream_rq_xx{envoy_response_code_class="5"}[5m]))
  / sum(rate(envoy_http_downstream_rq_xx[5m]))

# Gateway status (1 = Programmed, 0 = Not Programmed)
gatewayapi_gateway_status{type="Programmed",status="True"}

# HTTPRoute status (1 = Accepted, 0 = Not Accepted)
gatewayapi_httproute_status{type="Accepted",status="True"}

# Envoy proxy pod restarts
sum(kube_pod_container_status_restarts_total{namespace="network",pod=~"envoy-.*"})
```

---

## 8. Risk Assessment

### 8.1 Technical Risks

**Risk 1: cert-manager Version Incompatibility**
- **Probability:** Medium (cert-manager version unknown, may be < v1.19)
- **Impact:** High (no automatic certificate issuance for Gateways, manual cert management required)
- **Mitigation:**
  - Check cert-manager version in Phase 1
  - Upgrade to v1.19+ before proceeding with migration
  - Test certificate issuance on test Gateway before production migration
  - Fallback: Use existing wildcard certificate manually referenced in Gateway (already working with rook-ceph and blackbox-exporter)

**Risk 2: external-dns Not Configured for HTTPRoute**
- **Probability:** High (external-dns may only watch Ingress resources currently)
- **Impact:** Medium (DNS records not auto-created, requiring manual DNS updates)
- **Mitigation:**
  - Check external-dns configuration in Phase 1
  - Update HelmRelease to add `--source=gateway-httproute` argument
  - Test with single HTTPRoute before bulk migration
  - Fallback: Manually create DNS records in Cloudflare (one-time effort, 29 records)

**Risk 3: Backend TLS Configuration Complexity**
- **Probability:** Medium (Envoy upstream TLS not as straightforward as NGINX annotation)
- **Impact:** Medium (UniFi and Tesla Proxy may not work without backend HTTPS)
- **Mitigation:**
  - Research Envoy Gateway backend TLS options before Phase 3
  - Test with UniFi first (non-critical service)
  - Options: Service port naming ("https"), BackendTLSPolicy (if supported), EnvoyPatchPolicy (advanced)
  - Fallback: If backend TLS cannot be configured, accept HTTP backend (security regression, but functional)

**Risk 4: Websocket Timeout Configuration**
- **Probability:** Low (Envoy supports websockets natively)
- **Impact:** High (Home Assistant real-time updates broken, critical user-facing issue)
- **Mitigation:**
  - Test Home Assistant websockets early in Phase 3
  - Configure both `requestTimeout` and `idleTimeout` in BackendTrafficPolicy
  - Leave browser tab open for 1+ hour to validate stability
  - Fallback: If timeouts cannot be fixed, roll back Home Assistant specifically while investigating (NGINX remains available for rollback)

**Risk 5: CORS Policy Not Applied Correctly**
- **Probability:** Low (Envoy CORS support is mature)
- **Impact:** Medium (Garmin MCP API calls fail from browser, affecting AI service functionality)
- **Mitigation:**
  - Create SecurityPolicy with CORS in Phase 3, test preflight requests
  - Verify CORS headers in browser DevTools Network tab
  - Fallback: If SecurityPolicy CORS fails, investigate Envoy filter configuration or use EnvoyPatchPolicy

**Risk 6: Bulk Migration Introduces Unexpected Issues**
- **Probability:** Medium (migrating 16 apps at once increases chance of configuration errors)
- **Impact:** High (multiple services down simultaneously)
- **Mitigation:**
  - Migrate in smaller batches (8 apps, test, then next 8)
  - Use template-based approach (copy working HTTPRoute pattern)
  - Validate HTTPRoute status immediately after Flux applies resources
  - Rollback available for entire batch if needed (revert single commit)

**Risk 7: DNS Propagation Delay During Cutover**
- **Probability:** High (DNS caching inevitable)
- **Impact:** Low (temporary inconsistency, but both NGINX and Envoy running in parallel)
- **Mitigation:**
  - Keep NGINX running during DNS propagation (15-20 minutes minimum)
  - Use low TTL on DNS records (300 seconds = 5 minutes)
  - Test with direct IP access to Gateway (bypassing DNS) before updating DNS

**Risk 8: Envoy Gateway Bug or Instability**
- **Probability:** Low (Envoy Gateway v1.7+ is production-ready, but bugs exist)
- **Impact:** High (entire ingress layer affected, all services down)
- **Mitigation:**
  - Review Envoy Gateway release notes for known issues before migration
  - Avoid Envoy Gateway versions with known critical bugs (e.g., v1.5-v1.6 RegularExpression rate limiting bug)
  - Monitor Envoy Gateway controller logs for errors during migration
  - Rollback available via NGINX if Envoy Gateway proves unstable

### 8.2 Business Risks

**Risk 1: Home Automation Downtime**
- **Probability:** Medium (Home Assistant websockets require careful configuration)
- **Impact:** Medium (family inconvenience, automations not working, but not life-critical)
- **Mitigation:**
  - Migrate Home Assistant early in Phase 3 (not bulk migration)
  - Test thoroughly before considering it complete
  - Keep NGINX available for quick rollback if issues occur
  - Communicate with family about potential brief outage during testing

**Risk 2: Media Service Interruption**
- **Probability:** Low (Plex and media apps have simple routing requirements)
- **Impact:** Low (entertainment disruption, but not critical service)
- **Mitigation:**
  - Migrate media apps in Phase 4 after annotation patterns validated
  - Test Plex streaming specifically (most used media service)
  - Schedule migration during low-usage hours if possible

**Risk 3: Monitoring/Observability Gaps**
- **Probability:** Low (Grafana, Prometheus have simple routing)
- **Impact:** Medium (cannot monitor cluster during migration if observability down)
- **Mitigation:**
  - Migrate observability apps early (Phase 2)
  - Keep local kubectl access for troubleshooting (not reliant on Grafana UI)
  - Ensure Prometheus continues collecting metrics even if Grafana UI temporarily inaccessible

**Risk 4: Extended Troubleshooting Delays Timeline**
- **Probability:** Medium (unexpected issues may require debugging, research)
- **Impact:** Low (home lab environment, no business SLA to meet)
- **Mitigation:**
  - Budget extra time in schedule (3 days active work, flexible if needed)
  - Document issues encountered for future reference
  - Leverage community resources (Envoy Gateway Slack, GitHub issues) if stuck

---

## 9. Launch Plan

### 9.1 Go-Live Checklist

**Pre-Migration (Phase 1):**
- [ ] Gateway API CRDs installed and version confirmed (v1.0+)
- [ ] Envoy Gateway controller running and healthy
- [ ] GatewayClass "envoy" status Accepted=True
- [ ] Gateways (envoy-external, envoy-internal) status Programmed=True with IPs assigned
- [ ] Existing HTTPRoutes (rook-ceph, blackbox-exporter) tested and working
- [ ] cert-manager version v1.19+ confirmed (or upgraded)
- [ ] external-dns configured with `--source=gateway-httproute`
- [ ] NGINX LoadBalancer IPs documented for rollback
- [ ] Testing checklist prepared (spreadsheet or markdown)

**During Migration (Phases 2-4):**
- [ ] Each HTTPRoute applied via GitOps (committed to Git, Flux reconciled)
- [ ] HTTPRoute status verified (Accepted=True, parentRef resolved)
- [ ] Application accessibility tested (HTTP 200, UI loads)
- [ ] No unexpected errors in Envoy proxy logs
- [ ] DNS records created by external-dns (or manually if needed)

**Post-Migration Validation (Phase 5):**
- [ ] All 29 applications accessible via original hostnames
- [ ] Critical workflows tested (Home Assistant, Plex, UniFi, Grafana)
- [ ] Envoy Gateway error rate < 1% (5xx responses)
- [ ] TLS certificates valid (cert-manager issuing correctly)
- [ ] No Gateway or HTTPRoute status degradation (Programmed/Accepted remain True)
- [ ] Documentation updated (README.md, CLAUDE.md)
- [ ] HTTPRoute templates created for future use

**Pre-Cleanup (Phase 6):**
- [ ] 48 hours elapsed since migration with no critical issues
- [ ] Monitoring shows stable metrics (no error rate spikes, no pod restarts)
- [ ] No user complaints about service accessibility
- [ ] Rollback no longer anticipated (confident in Envoy Gateway stability)

**NGINX Removal:**
- [ ] NGINX HelmRelease resources deleted from Git
- [ ] All Ingress resources deleted from Git
- [ ] Flux uninstalls NGINX controller successfully
- [ ] NGINX pods terminated (`kubectl get pods -n network | grep ingress-nginx` returns no results)
- [ ] No leftover NGINX resources (`kubectl get all -n network -l app.kubernetes.io/name=ingress-nginx` returns no results)
- [ ] Applications remain accessible via Envoy Gateway (spot check 10 apps)

### 9.2 Rollout Strategy

**Phased Migration Approach:**

**Phase 1 (Day 1 Morning):** Pre-Migration Validation
- **Scope:** Validate existing Envoy Gateway installation, cert-manager, external-dns
- **Success Criteria:** All blockers resolved, baseline state documented

**Phase 2 (Day 1 Afternoon):** Simple Applications
- **Scope:** 9 apps (4 standalone Ingress + 5 simple HelmRelease apps)
- **User Group:** Non-critical services (flux-webhook, rook-ceph, observability, media apps)
- **Success Criteria:** All 9 apps accessible, HTTPRoute pattern validated

**Phase 3 (Day 2 Morning):** Complex Annotations
- **Scope:** 4 apps with NGINX-specific features (Home Assistant, Garmin MCP, UniFi, Tesla Proxy)
- **User Group:** Critical services requiring annotation mapping
- **Success Criteria:** Websockets, CORS, backend TLS, URL rewrites working correctly

**Phase 4 (Day 2 Afternoon):** Bulk Migration
- **Scope:** Remaining 16 apps (mostly media and home apps)
- **User Group:** All remaining services
- **Success Criteria:** All 29 apps migrated, systematic testing completed

**Phase 5 (Day 3):** Validation and Documentation
- **Scope:** Extended testing, documentation updates, NGINX removal preparation
- **User Group:** Platform engineer (self)
- **Success Criteria:** Migration considered complete, NGINX removal commit ready

**Phase 6 (Days 4-5):** Post-Migration Monitoring
- **Scope:** Passive monitoring, NGINX removal after validation period
- **User Group:** All services
- **Success Criteria:** 48 hours elapsed with no issues, NGINX cleanly removed

**Rollback Trigger Points:**
- **Immediate Rollback:** > 50% of apps failing (critical infrastructure issue)
- **Service-Specific Rollback:** Single critical app (e.g., Home Assistant) not working, investigate offline while keeping others on Envoy Gateway
- **Delayed Rollback:** Intermittent issues discovered during 48h monitoring, roll back entire migration to investigate

### 9.3 Post-Launch Activities

**Immediate (Week 1 Post-Migration):**
- Monitor Envoy Gateway metrics daily (error rates, Gateway status, pod health)
- Respond to any user reports of accessibility issues
- Document any unexpected behaviors or workarounds in CLAUDE.md
- Create GitHub issue templates for future HTTPRoute additions

**Short-Term (Month 1):**
- Review Envoy Gateway controller logs for warnings or errors
- Evaluate Envoy Gateway observability (access logs, tracing) for future enhancement
- Test advanced features (rate limiting, JWT auth via SecurityPolicy) on non-production apps
- Contribute learnings back to community (blog post, GitHub discussions) if valuable insights gained

**Long-Term (Months 2-6):**
- Plan Gateway API v1.1+ feature adoption (e.g., BackendLBPolicy, GRPCRoute if needed)
- Evaluate additional Envoy Gateway capabilities (traffic splitting, canary deployments)
- Consider consolidating SecurityPolicy and BackendTrafficPolicy (if many apps use same patterns)
- Monitor Gateway API project for new features or deprecations

---

## 10. Future Roadmap

### 10.1 Phase 2 Features (3-6 months post-migration)

**Advanced Traffic Management:**
- **Traffic Splitting:** Use HTTPRoute weights for canary deployments (e.g., 90% stable, 10% canary)
- **Request Mirroring:** Use HTTPRoute filters to mirror production traffic to test environments
- **Retry Policies:** Configure advanced retry logic in BackendTrafficPolicy (beyond default 2 retries)

**Enhanced Security:**
- **JWT Authentication:** Use SecurityPolicy for JWT validation at Gateway level (replace application-level auth for some services)
- **Rate Limiting:** Implement BackendTrafficPolicy with rate limiting for public-facing services (e.g., flux-webhook, external API endpoints)
- **Client Certificate Validation:** Use SecurityPolicy for mutual TLS (if needed for sensitive services)

**Observability Improvements:**
- **Envoy Access Logs:** Enable detailed access logging for troubleshooting (currently minimal logging)
- **Distributed Tracing:** Integrate Jaeger or Zipkin with Envoy for request tracing across services
- **Custom Metrics:** Export additional Envoy metrics to Prometheus (connection pool stats, upstream health)

### 10.2 Long-term Vision (6-12 months)

**Multi-Gateway Architecture:**
- Evaluate need for additional Gateway resources (e.g., separate Gateway for AI workloads with different TLS/timeout settings)
- Explore Gateway API v1.1+ features like BackendLBPolicy for advanced load balancing strategies

**Policy Consolidation:**
- Create cluster-wide SecurityPolicy and BackendTrafficPolicy defaults (attached to Gateway) to reduce per-HTTPRoute policy duplication
- Investigate Envoy Gateway policy inheritance and override behavior for complex use cases

**Automation Enhancements:**
- Develop Helm chart or Kustomize component for common HTTPRoute patterns (reduce boilerplate)
- Automate HTTPRoute generation from application metadata (e.g., annotation on Service → auto-create HTTPRoute)

**Cross-Cluster Ingress:**
- If cluster expands to multi-cluster architecture, evaluate Gateway API MCS (Multi-Cluster Services) for cross-cluster routing

---

## 11. Appendix

### 11.1 Glossary

- **Gateway API:** Kubernetes API for ingress/egress traffic management, successor to Ingress API (v1.0 released 2023)
- **GatewayClass:** Cluster-scoped resource defining Gateway controller (e.g., Envoy Gateway, Istio)
- **Gateway:** Namespace-scoped resource defining load balancer with listeners (HTTP/HTTPS ports, TLS config)
- **HTTPRoute:** Namespace-scoped resource defining HTTP routing rules (hostname, path, backend Service)
- **Envoy Gateway:** Reference implementation of Gateway API using Envoy proxy as data plane
- **Envoy Proxy:** High-performance L7 proxy (data plane handling actual traffic)
- **SecurityPolicy:** Envoy Gateway extension for CORS, auth, rate limiting (attached to Gateway or HTTPRoute)
- **BackendTrafficPolicy:** Envoy Gateway extension for timeouts, retries, load balancing (attached to Gateway or HTTPRoute)
- **ClientTrafficPolicy:** Envoy Gateway extension for client-facing settings (TLS, HTTP/2, IP detection)
- **ParentRef:** HTTPRoute field referencing Gateway (cross-namespace reference supported)
- **SectionName:** HTTPRoute field specifying Gateway listener name (e.g., "http", "https")
- **Cilium LBIPAM:** Cilium LoadBalancer IP Address Management (assigns static IPs to LoadBalancer Services)
- **cert-manager:** Kubernetes certificate management controller (issues TLS certs from Let's Encrypt, etc.)
- **external-dns:** Kubernetes controller that syncs DNS records with external providers (Cloudflare, Route53, etc.)
- **Flux CD:** GitOps operator for Kubernetes (reconciles cluster state from Git repository)
- **Talos Linux:** Immutable Linux OS designed for Kubernetes (no SSH, API-driven management)

### 11.2 References

**Official Documentation:**
- [Gateway API Documentation](https://gateway-api.sigs.k8s.io/)
- [Envoy Gateway Documentation](https://gateway.envoyproxy.io/)
- [Envoy Proxy Documentation](https://www.envoyproxy.io/docs)
- [cert-manager Gateway API Support](https://cert-manager.io/docs/usage/gateway/)
- [external-dns Gateway HTTPRoute Support](https://github.com/kubernetes-sigs/external-dns/blob/master/docs/tutorials/gateway-api.md)

**Migration Resources:**
- [ingress2gateway Tool](https://github.com/kubernetes-sigs/ingress2gateway) - Automates Ingress → Gateway API conversion
- [NGINX to Gateway API Annotation Mapping](https://gateway.envoyproxy.io/latest/tasks/traffic/nginx-ingress-migration/) - Official Envoy Gateway migration guide
- [CyberArk Production Migration Case Study](https://developer.cyberark.com/blog/ingress-nginx-is-retiring-our-practical-journey-to-gateway-api/)
- [Qovery Multi-Cluster Migration](https://www.qovery.com/blog/migrating-from-nginx-ingress-to-envoy-gateway-gateway-api-behind-the-scenes)

**Cluster-Specific Documentation:**
- Repository README.md - Cluster overview, bootstrap procedures
- CLAUDE.md - Development patterns, task commands, validation procedures
- Existing HTTPRoute examples:
  - `kubernetes/apps/rook-ceph/rook-ceph/cluster/httproute.yaml`
  - `kubernetes/apps/observability/blackbox-exporter/app/httproute.yaml`
- Existing Gateway configuration:
  - `kubernetes/apps/network/envoy-gateway/app/envoy.yaml`

**Community Support:**
- [Envoy Gateway Slack](https://communityinviter.com/apps/envoyproxy/envoy) - #envoy-gateway channel
- [Gateway API Slack](https://kubernetes.slack.com/archives/CR0H13KGA) - #sig-network-gateway-api
- [Talos Linux Discussions](https://github.com/siderolabs/talos/discussions) - For Talos-specific ingress questions

### 11.3 Change Log

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0 | 2026-02-21 | Platform Engineering | Initial PRD created based on cluster analysis and migration research |

### 11.4 Migration Tracking Checklist

**Standalone Ingress Resources (4):**
- [ ] observability/blackbox-exporter (internal) - **ALREADY MIGRATED**
- [ ] rook-ceph/rook-ceph-dashboard (internal) - **ALREADY MIGRATED**
- [ ] flux-system/flux-webhook (external)
- [ ] home/tesla-proxy (external, annotations: force-ssl-redirect, rewrite-target, backend-protocol HTTPS)

**HelmRelease Applications - Home Namespace (8):**
- [ ] home/tesla-proxy (internal, annotations: websocket, timeouts) - **NOTE:** Also has standalone Ingress above
- [ ] home/emhass (internal)
- [ ] home/evcc (internal)
- [ ] home/frigate (internal)
- [ ] home/zigbee2mqtt (internal)
- [ ] home/teslamate (internal)
- [ ] home/home-assistant (external, annotations: websocket, proxy timeouts) - **COMPLEX**
- [ ] home/home-assistant-v2 (if active, otherwise skip)

**HelmRelease Applications - Media Namespace (9):**
- [ ] media/bazarr (internal)
- [ ] media/prowlarr (internal)
- [ ] media/qbittorrent (internal)
- [ ] media/photoprism (internal)
- [ ] media/radarr (internal)
- [ ] media/plex (internal, commented annotation: backend-protocol)
- [ ] media/lidarr (internal)
- [ ] media/overseerr (internal)
- [ ] media/sonarr (internal)

**HelmRelease Applications - AI Namespace (4):**
- [ ] ai/openwebui (internal)
- [ ] ai/mcpo (internal)
- [ ] ai/litellm (internal)
- [ ] ai/garmin-mcp (internal, annotations: ssl-protocols, CORS) - **COMPLEX**

**HelmRelease Applications - Network Namespace (1):**
- [ ] network/unifi (internal, annotations: backend-protocol HTTPS) - **COMPLEX**

**HelmRelease Applications - Observability Namespace (2):**
- [ ] observability/kubernetes-dashboard (internal)
- [ ] observability/grafana (internal) - **NOTE:** HelmRelease ingress, blackbox-exporter standalone Ingress already migrated

**HelmRelease Applications - Kube-System Namespace (1):**
- [ ] kube-system/cilium (check if ingress enabled, likely N/A)

**Validation Checklist:**
- [ ] All HTTPRoute resources show Status: Accepted=True
- [ ] All HTTPRoute parentRefs resolved to Gateway
- [ ] All DNS records created (automated or manual)
- [ ] All TLS certificates valid
- [ ] Critical applications tested (Home Assistant, Plex, UniFi, Grafana)
- [ ] Websockets working (Home Assistant)
- [ ] CORS working (Garmin MCP)
- [ ] Backend TLS working (UniFi, Tesla Proxy)
- [ ] 48-hour validation period completed
- [ ] NGINX Ingress Controller removed
- [ ] Documentation updated

---

**End of PRD**
