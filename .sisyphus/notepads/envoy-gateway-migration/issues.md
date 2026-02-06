# Issues - Envoy Gateway Migration

## [2026-02-04T10:34:40Z] Session Start: ses_3d7d5f1abffeMudupwnl7FJJJ2

Tracking problems and gotchas during migration.

## [2026-02-04T10:35:00Z] Pre-flight Validation FAILED

**CRITICAL**: Envoy Gateway is not deployed!

### Root Cause
- `kubernetes/apps/network/envoy-gateway/` directory exists with all configuration
- BUT `./envoy-gateway/ks.yaml` is NOT referenced in `kubernetes/apps/network/kustomization.yaml`
- Result: Gateway API CRDs not installed, no Gateway resources, no Envoy deployment

### Findings
- ❌ Gateway API CRDs (gateway.networking.k8s.io) NOT installed
- ❌ Envoy Gateway HelmRelease NOT found
- ❌ envoy-gateway-crds Kustomization NOT found
- ✅ TLS certificate exists: `angryninja-cloud-production-tls`
- ✅ external-dns pod Running (v0.20.0)

### Required Action
Before proceeding with migration tasks, must ADD envoy-gateway to network kustomization:
```yaml
resources:
  - ./envoy-gateway/ks.yaml
```

This is a prerequisite - cannot migrate to Envoy Gateway if it's not deployed!
