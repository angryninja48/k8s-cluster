# Learnings - Envoy Gateway Migration

## [2026-02-04T10:34:40Z] Session Start: ses_3d7d5f1abffeMudupwnl7FJJJ2

Starting migration from nginx-ingress to Envoy Gateway for all cluster applications.

## [2026-02-04 10:42] Task 1a: Blocker Fix - Enable Envoy Gateway Deployment

### Problem Solved
Envoy Gateway was never deployed despite existing configuration. Root cause: `./envoy-gateway/ks.yaml` was not referenced in `kubernetes/apps/network/kustomization.yaml`.

### Solution Applied
1. Added `- ./envoy-gateway/ks.yaml` to network kustomization.yaml
2. Committed and pushed change to Git
3. Forced Flux reconciliation: `flux reconcile kustomization cluster-apps --with-source`

### Deployment Cascade
The envoy-gateway/ks.yaml contains 3 Flux Kustomizations with dependency chain:
1. `envoy-gateway-crds` - Installs Gateway API CRDs (v1.2.1)
   - Created CRDs: gatewayclasses, gateways, grpcroutes, httproutes, referencegrants
2. `envoy-gateway` - Deploys HelmRelease (v1.6.3)
   - Depends on: envoy-gateway-crds
   - Creates deployment in network namespace (not envoy-gateway-system)
   - Uses config: `provider.kubernetes.deploy.type: GatewayNamespace`
3. `envoy-gateway-config` - Creates Gateway resources
   - Depends on: envoy-gateway
   - Creates: GatewayClass "envoy", Gateways "envoy-external" & "envoy-internal"

### Verification Results
✅ Gateway API CRDs installed (5 CRDs)
✅ GatewayClass "envoy" created and ACCEPTED
✅ Gateway "envoy-external" created (PROGRAMMED=True, IP: 10.213.0.53)
✅ Gateway "envoy-internal" created (PROGRAMMED=True, IP: 10.213.0.52)
✅ envoy-gateway controller pod Running (1/1)
✅ envoy-external proxy pods Running (2/2 each)
✅ envoy-internal proxy pods Running (2/2 each)
✅ evcc app dependency resolved and reconciled

### Key Learnings
- GitOps requires Git commits for changes to take effect
- Flux dependency chains work correctly: CRDs → HelmRelease → Config
- Envoy Gateway with `GatewayNamespace` deploys proxies in the same namespace as Gateway resources
- Gateway resources get LoadBalancer IPs automatically (MetalLB in this cluster)
- All 3 envoy-gateway kustomizations must be Ready before dependent apps (like evcc) can reconcile

### Time to Deploy
- CRDs: ~5 seconds
- HelmRelease: ~30 seconds
- Gateway resources: ~30 seconds
- Total: ~1 minute from commit to fully operational


## [2026-02-04 10:48] Task 2: Update external-dns for gateway-httproute

### Change Applied
Added `gateway-httproute` to external-dns sources list in HelmRelease.

**File**: `kubernetes/apps/network/external-dns/app/helmrelease.yaml`
```yaml
sources:
  - ingress
  - gateway-httproute
```

### Verification Results
✅ HelmRelease updated successfully
✅ external-dns pod recreated (d749bdfb6-tkfrm)
✅ Pod status: Running
✅ Deployment args include both sources:
   - `--source=ingress`
   - `--source=gateway-httproute`

### Key Learnings
- external-dns v0.20.0 supports gateway-httproute source natively
- No additional configuration needed beyond adding to sources list
- Keeping both sources during migration allows gradual transition
- Pod restarts automatically when HelmRelease values change
- annotation-filter applies to both Ingress and HTTPRoute resources

### Next Steps Ready
external-dns now ready to create DNS records for HTTPRoute resources with annotation:
`external-dns.home.arpa/enabled: "true"`


## [2026-02-04 11:00] Tasks 3 & 4: Certificate Management for Envoy Gateway

### Changes Applied
1. Created `kubernetes/apps/network/envoy-gateway/certificates/` directory
2. Copied production certificate from ingress-nginx
3. Created kustomization.yaml referencing production.yaml only
4. Added envoy-gateway-certificates Flux Kustomization to ks.yaml
5. Updated envoy-gateway-config to depend on envoy-gateway-certificates

**Files Modified**:
- `kubernetes/apps/network/envoy-gateway/certificates/production.yaml` (new)
- `kubernetes/apps/network/envoy-gateway/certificates/kustomization.yaml` (new)
- `kubernetes/apps/network/envoy-gateway/ks.yaml` (updated)

### Verification Results
✅ envoy-gateway-crds: Applied
✅ envoy-gateway: Applied
✅ envoy-gateway-certificates: Applied (depends on cert-manager-issuers)
✅ envoy-gateway-config: Applied (depends on envoy-gateway + envoy-gateway-certificates)
✅ evcc: Applied (dependency chain resolved)

### Dependency Chain
```
cert-manager → cert-manager-issuers → envoy-gateway-certificates
envoy-gateway-crds → envoy-gateway → envoy-gateway-config
                                   ↗
envoy-gateway-certificates ────────┘
```

### Key Learnings
- Flux Kustomization dependencies are strict - must wait for Ready=True
- Forcing reconciliation cascades through dependency chain
- Certificate is namespace-scoped (network), managed by cert-manager
- Production certificate covers both staging and production (wildcard *.${SECRET_DOMAIN})
- Separation of concerns: certificates separate from gateway config

### Issues Encountered
- Initial Flux reconciliation didn't cascade automatically
- Had to manually reconcile cert-manager → cert-manager-issuers chain
- evcc required explicit reconcile after envoy-gateway-config was ready (caching)

### Resolution
Forced reconciliation sequence:
1. `flux reconcile ks cert-manager`
2. `flux reconcile ks cert-manager-issuers`
3. `flux reconcile ks envoy-gateway`
4. `flux reconcile ks envoy-gateway-config`
5. `flux reconcile ks evcc --with-source`

### Next Steps Ready
Infrastructure (Phase 1) complete. Ready to create HTTPRoute resources for all apps.


## [2026-02-04 11:10] Task 2a: Update k8s-gateway for HTTPRoute Support

### Critical Discovery
User identified missing configuration: k8s-gateway (internal DNS) was only watching Ingress and Service, not HTTPRoute!

### The Problem
- **external-dns**: Handles EXTERNAL DNS (Cloudflare public records) ✅ Updated in Task 2
- **k8s-gateway**: Handles INTERNAL DNS (split-horizon for cluster) ❌ Was missing HTTPRoute support

Without HTTPRoute in watchedResources:
- External DNS would work (Cloudflare records created)
- Internal DNS would FAIL (pods couldn't resolve HTTPRoute hostnames)
- Pod-to-pod communication would break for migrated apps

### Change Applied
Updated `kubernetes/apps/network/k8s-gateway/app/helmrelease.yaml`:
```yaml
# Changed from:
watchedResources: ["Ingress", "Service"]

# To:
watchedResources: ["Ingress", "Service", "HTTPRoute"]
```

### Verification Results
✅ HelmRelease updated and reconciled
✅ watchedResources includes HTTPRoute: ["Ingress","Service","HTTPRoute"]
✅ k8s-gateway pod restarted (544f8f67c6-r84tk)
✅ Pod status: Running (1/1)
✅ HelmRelease Ready: True

### Key Learnings
- TWO DNS systems in play: external-dns (public) + k8s-gateway (internal)
- k8s-gateway v2.4.0 supports HTTPRoute natively (confirmed in upstream docs)
- Both DNS systems must watch HTTPRoute for complete migration
- Internal DNS is CRITICAL for pod-to-pod communication
- Original migration plan missed this requirement - caught by user review

### Next Steps Ready
Infrastructure (Phase 1) fully complete:
- ✅ Task 1: Pre-flight validation + Envoy Gateway deployment
- ✅ Task 2: external-dns watches gateway-httproute
- ✅ Task 2a: k8s-gateway watches HTTPRoute
- ✅ Task 3: Certificates kustomization created
- ✅ Task 4: Envoy Gateway dependencies updated

Ready to create HTTPRoute resources (Phase 2).
