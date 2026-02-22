# External Integrations

**Analysis Date:** 2026-02-22

## APIs & External Services

**Secret Management:**
- Doppler - Secret synchronization to Kubernetes
  - SDK/Client: external-secrets-operator
  - Auth: `DOPPLER_TOKEN` (stored in `kubernetes/apps/external-secrets/external-secrets/stores/secret.sops.yaml`)
  - Project: k3s-cluster, Config: prd
  - ClusterSecretStore: `doppler-secrets`

**DNS & CDN:**
- Cloudflare - DNS management and tunnel services
  - SDK/Client: external-dns, cloudflared, cert-manager
  - Auth: `CF_API_TOKEN` (via external-secrets)
  - Used for: DNS01 challenges, DNS record management, secure tunnels

**Version Control:**
- GitHub - GitOps source repository
  - SDK/Client: Flux CD GitRepository
  - Auth: SSH deploy key (`github-deploy-key.sops.yaml`)
  - Repository: https://github.com/angryninja48/k8s-cluster
  - Branch: main

**Container Registries:**
- ghcr.io (GitHub Container Registry) - Primary container images
- docker.io (Docker Hub) - Third-party images
- OCI registries - Helm charts via OCI protocol

## Data Storage

**Databases:**
- PostgreSQL 17 (CloudNativePG)
  - Connection: `postgres17-rw.database.svc.cluster.local`
  - Client: CloudNativePG Operator
  - Instances: 3 (high availability cluster)
  - Storage: openebs-hostpath (50Gi per instance)
  - Backup: S3-compatible (MinIO)

**Redis:**
- Dragonfly - Redis-compatible in-memory database
  - Location: `kubernetes/apps/database/dragonfly/`
  - Used for: Caching, session storage

**Time Series:**
- InfluxDB - Time-series database
  - Location: `kubernetes/apps/database/influxdb/`
  - Used for: Metrics storage

**File Storage:**
- Rook Ceph - Distributed storage cluster
  - Storage classes: `ceph-block`, `ceph-filesystem`
  - Deployment: `kubernetes/apps/rook-ceph/`
- OpenEBS - Local persistent volumes
  - Storage class: `openebs-hostpath`
  - Used for: Local node storage
- MinIO (S3-compatible) - Object storage
  - Endpoint: `${SECRET_S3_URL}`
  - Used for: PostgreSQL backups, VolSync backups
  - Credentials: `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`

**Caching:**
- Spegel v0.6.0 - Distributed container image cache
  - Purpose: Local caching of container images across cluster nodes
  - Location: `kubernetes/apps/kube-system/spegel/`

## Authentication & Identity

**Auth Provider:**
- External Secrets Operator with Doppler integration
  - Implementation: ClusterSecretStore syncs secrets from Doppler
  - Location: `kubernetes/apps/external-secrets/`

**Certificate Management:**
- Let's Encrypt - SSL/TLS certificates
  - Implementation: cert-manager with ACME DNS01 challenges
  - Issuers: `letsencrypt-production`, `letsencrypt-staging`
  - DNS Provider: Cloudflare
  - Email: `${SECRET_ACME_EMAIL}`

## Monitoring & Observability

**Error Tracking:**
- None detected (self-hosted monitoring only)

**Logs:**
- Loki - Log aggregation
  - Location: `kubernetes/apps/observability/loki/`
  - Scraper: Promtail
- Promtail - Log shipping to Loki
  - Location: `kubernetes/apps/observability/promtail/`

**Metrics:**
- Prometheus - Metrics collection and storage
  - Stack: kube-prometheus-stack
  - Location: `kubernetes/apps/observability/kube-prometheus-stack/`
  - ServiceMonitors: Enabled for Cilium, Flux, Rook Ceph, and applications

**Dashboards:**
- Grafana - Metrics and log visualization
  - Location: `kubernetes/apps/observability/grafana/`
  - URL: `https://grafana.${SECRET_DOMAIN}`
  - Database: PostgreSQL (grafana database in postgres17 cluster)
  - Data sources: Prometheus, Loki
- Kubernetes Dashboard - Native K8s web UI
  - Location: `kubernetes/apps/observability/kubernetes-dashboard/`

**Network Observability:**
- Hubble (Cilium) - eBPF-based network observability
  - Metrics: DNS queries, drops, TCP, flow, HTTP, ICMP
  - UI: Hubble Relay with Prometheus integration

## CI/CD & Deployment

**Hosting:**
- Self-hosted bare metal
  - 3-node Talos Linux cluster
  - Control plane VIP: 10.20.0.250

**CI Pipeline:**
- GitHub Actions
  - Workflows:
    - `flux-diff.yaml` - Flux resource diffs on PRs
    - `label-sync.yaml` - Label synchronization
    - `release.yaml` - Monthly automated releases
  - Tools: flux-local for validation

**GitOps:**
- Flux CD - Continuous deployment
  - Reconciliation interval: 30m
  - Git source: `home-kubernetes` GitRepository
  - Path: `./kubernetes/flux`
  - Decryption: SOPS with age encryption
  - Post-build substitution from cluster-settings and cluster-secrets

## Environment Configuration

**Required env vars:**
- `KUBECONFIG` - Kubernetes cluster access
- `SOPS_AGE_KEY_FILE` - SOPS encryption key location
- `TALOSCONFIG` - Talos cluster configuration
- `TIMEZONE` - Cluster timezone (Australia/Sydney)
- `SECRET_DOMAIN` - Base domain for services
- `SECRET_ACME_EMAIL` - Let's Encrypt email
- `SECRET_S3_URL` - MinIO S3 endpoint

**Secrets location:**
- SOPS-encrypted files (`.sops.yaml` extension) in `kubernetes/` tree
- Doppler remote secret store (synced via external-secrets)
- Local `age.key` file (never committed to git)

## Webhooks & Callbacks

**Incoming:**
- Flux webhook receiver - GitHub push notifications
  - Location: `kubernetes/apps/flux-system/flux/github/webhooks/`
  - Triggers: Flux reconciliation on git push

**Outgoing:**
- External DNS webhooks to Cloudflare API
  - Purpose: Automatic DNS record creation/updates
- Let's Encrypt ACME DNS01 challenges to Cloudflare
  - Purpose: Certificate validation
- Doppler API polling by external-secrets
  - Purpose: Secret synchronization
- Home Assistant webhooks (via Discord)
  - Webhook URL: `${HA_DISCORD_WEBHOOK_URL}`

## Backup & Recovery

**VolSync v0.14.0:**
- Restic - Backup engine
  - Destination: S3-compatible storage (MinIO)
  - Replication: ReplicationSource/ReplicationDestination CRDs
  - Location: `kubernetes/apps/volsync-system/volsync/`

**Snapshot Controller:**
- CSI Volume Snapshots
  - Location: `kubernetes/apps/volsync-system/snapshot-controller/`
  - Used by: Rook Ceph, VolSync

**PostgreSQL Backups:**
- Barman Object Store (CloudNativePG)
  - Destination: S3 (`s3://postgresql/`)
  - Retention: 30 days
  - Compression: bzip2
  - Credentials: MinIO access/secret keys

---

*Integration audit: 2026-02-22*
