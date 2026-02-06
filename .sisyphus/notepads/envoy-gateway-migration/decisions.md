# Decisions - Envoy Gateway Migration

## [2026-02-04T10:34:40Z] Session Start: ses_3d7d5f1abffeMudupwnl7FJJJ2

### Architectural Decisions
- **external-dns approach**: Add gateway-httproute source instead of just annotating Gateways
- **Certificate location**: Move from ingress-nginx/certificates to envoy-gateway/certificates
- **Rollback strategy**: Create HTTPRoutes BEFORE disabling Ingresses for zero-downtime
