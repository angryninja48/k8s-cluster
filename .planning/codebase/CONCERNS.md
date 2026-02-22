# Codebase Concerns

**Analysis Date:** 2026-02-22

## Tech Debt

**Dual Home Assistant Deployments:**
- Issue: Two versions of Home Assistant running simultaneously (`home-assistant` and `home-assistant-v2`)
- Files: `kubernetes/apps/home/home-assistant/ks.yaml`, `kubernetes/apps/home/home-assistant-v2/ks.yaml`
- Impact: Resource duplication, potential confusion about which is the active instance, maintenance overhead
- Fix approach: Migrate to single deployment, delete deprecated version, update dependent services

**Commented Talos Image URLs:**
- Issue: Custom Talos factory images commented out across all nodes
- Files: `kubernetes/bootstrap/talos/talconfig.yaml` (lines 29, 47, 65)
- Impact: Cannot use custom Talos builds with specific extensions without uncommenting, unclear if intentional
- Fix approach: Document whether factory images are needed, remove comments or move to configuration notes

**Commented Goldilocks Integration:**
- Issue: Goldilocks resource recommendation tool disabled in security namespace
- Files: `kubernetes/apps/security/namespace.yaml:7`
- Impact: Missing resource optimization insights for security workloads
- Fix approach: Enable if resource recommendations are needed, remove comment if permanently disabled

**Incomplete Plex Setup Documentation:**
- Issue: TODO comment about first-time setup requirements for Plex
- Files: `kubernetes/apps/media/plex/app/helmrelease.yaml:133`
- Impact: Users may not configure globalMounts correctly on initial deployment
- Fix approach: Remove TODO and add proper documentation or create setup validation

**Commented PostgreSQL Dependency:**
- Issue: Home Assistant's CloudNative-PG dependency is commented out
- Files: `kubernetes/apps/home/home-assistant/ks.yaml:15`
- Impact: Home Assistant may start before database is ready if this dependency is needed
- Fix approach: Clarify if database is required, remove comment or restore dependency

**Yamllint Pre-Commit Hook Disabled:**
- Issue: Yamllint hook commented out in pre-commit configuration
- Files: `.pre-commit-config.yaml:14-19`
- Impact: YAML style issues not caught before commit, potential formatting inconsistency
- Fix approach: Enable hook with appropriate configuration or remove if using alternative validation

**Empty Security Namespace:**
- Issue: Security namespace defined but contains no applications
- Files: `kubernetes/apps/security/namespace.yaml`, `kubernetes/apps/security/kustomization.yaml`
- Impact: Unused infrastructure, unclear if security tools were planned but not deployed
- Fix approach: Deploy security applications or remove namespace if not needed

## Known Bugs

**Base64-Encoded Private Keys in Generated Configs:**
- Symptoms: RSA private keys visible as base64 in generated Talos machine configs
- Files: `kubernetes/bootstrap/talos/clusterconfig/home-kubernetes-talos*.yaml:114`
- Trigger: Running `task talos:generate-config` exposes keys in plaintext base64
- Workaround: Ensure clusterconfig/ directory is gitignored and access-controlled
- Fix: Already gitignored, but consider using SOPS encryption for machine configs

## Security Considerations

**Secrets in Configuration Files:**
- Risk: External secrets contain templated tokens/API keys before encryption
- Files: `kubernetes/apps/home/evcc/app/config/evcc.yaml` (lines 32, 47, 101, 107, 113, 121), `kubernetes/apps/ai/litellm/app/config/litellm.yaml` (lines 10, 27, 34, 40)
- Current mitigation: Variables substituted from SOPS-encrypted cluster-secrets
- Recommendations: Verify all secrets use `{{ .VAR }}` substitution pattern, never hardcode

**Grafana Admin Password:**
- Risk: Grafana admin password managed via external secret
- Files: `kubernetes/apps/observability/grafana/app/externalsecret.yaml:19`
- Current mitigation: Password stored in encrypted cluster-secrets.sops.yaml
- Recommendations: Implement password rotation policy, consider OAuth integration

**Cloudflare Tunnel Tokens:**
- Risk: Cloudflare tunnel credentials in SOPS-encrypted secrets
- Files: `kubernetes/apps/network/cloudflared/app/secret.sops.yaml`
- Current mitigation: SOPS age encryption with dedicated key
- Recommendations: Rotate tunnel tokens if age.key is ever compromised

**External DNS API Token:**
- Risk: Cloudflare DNS API token with zone modification permissions
- Files: `kubernetes/apps/network/external-dns/app/secret.sops.yaml`
- Current mitigation: SOPS encryption, scoped to specific zone
- Recommendations: Use minimal permissions token, audit DNS changes regularly

**Rook Ceph Privileged Access:**
- Risk: Rook Ceph namespace requires privileged pod security
- Files: `kubernetes/apps/rook-ceph/namespace.yaml:7-9`
- Current mitigation: Isolated to dedicated namespace with prune disabled
- Recommendations: Monitor for privilege escalation, keep Rook Ceph updated

## Performance Bottlenecks

**CloudNative-PG Shared Buffers:**
- Problem: PostgreSQL shared_buffers set to only 256MB for 4Gi memory limit
- Files: `kubernetes/apps/database/cloudnative-pg/cluster/cluster17.yaml:21`
- Cause: Conservative default setting not optimized for available memory
- Improvement path: Increase to 25% of memory limit (1Gi) for better cache hit ratio

**High Failure Threshold on Frigate Camera Detection:**
- Problem: Frigate camera detection allowed to fail 90 times before restart
- Files: `kubernetes/apps/home/frigate/app/helmrelease.yaml:81`
- Cause: Overly permissive failure tolerance for camera connectivity issues
- Improvement path: Review camera stability, reduce threshold to 30-60 for faster recovery

**Zigbee2MQTT Startup Delay:**
- Problem: Zigbee2MQTT allowed 30 failures (high startup timeout)
- Files: `kubernetes/apps/home/zigbee2mqtt/app/helmrelease.yaml:67`
- Cause: USB device initialization can be slow or unreliable
- Improvement path: Investigate USB passthrough reliability, consider hardware changes

**Media Apps Without Resource Limits:**
- Problem: Most media applications lack CPU/memory limits
- Files: All `kubernetes/apps/media/*/app/helmrelease.yaml` files
- Cause: No resource constraints defined for Plex, Sonarr, Radarr, etc.
- Improvement path: Profile actual usage, set limits to prevent resource starvation

**30-Minute Flux Reconciliation Interval:**
- Problem: 62 of 67 applications use 30m reconciliation interval
- Files: Most `kubernetes/apps/*/*/ks.yaml` files
- Cause: Default conservative interval for GitOps sync
- Improvement path: Critical apps could use 10m interval, use flux reconcile for immediate updates

## Fragile Areas

**Intel GPU Device Plugin Dependency:**
- Files: `kubernetes/apps/tools/intel-device-plugin/gpu/helmrelease.yaml`, `kubernetes/apps/home/frigate/app/helmrelease.yaml:42-45`, `kubernetes/apps/media/plex/app/helmrelease.yaml:69-72`
- Why fragile: Frigate and Plex require Intel GPU for hardware transcoding/detection
- Safe modification: Verify GPU is detected (`kubectl describe node | grep gpu`) before scaling apps
- Test coverage: No automated tests for GPU availability

**Rook Ceph Cluster with Prune Disabled:**
- Files: `kubernetes/apps/rook-ceph/rook-ceph/ks.yaml:16`, `kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml:19` (disableWait: true)
- Why fragile: Storage cluster changes bypass health checks, manual intervention required for issues
- Safe modification: Never delete Rook CRDs manually, backup data before Rook upgrades
- Test coverage: No pre-upgrade validation for storage cluster health

**VolSync Backup/Restore Workflow:**
- Files: `.taskfiles/volsync/Taskfile.yaml`
- Why fragile: Restore requires specific naming convention (Kustomization = HelmRelease = PVC = ReplicationSource), suspends Flux during restore
- Safe modification: Always verify backup exists before restore (`task volsync:snapshot`), check Flux status after restore
- Test coverage: Manual testing only, no automated restore validation

**Custom NFS StorageClasses:**
- Files: `kubernetes/apps/home/frigate/app/nfs-pvc.yaml:7` (storageClassName: frigate), `kubernetes/apps/media/photoprism/app/nfs-photos.yaml:7` (storageClassName: media-nfs-photos)
- Why fragile: Custom storage classes for NFS mounts, dependencies on external NFS server
- Safe modification: Verify NFS server is mounted before deploying apps, check PV/PVC binding status
- Test coverage: No health checks for NFS availability

**Dual Database Strategy:**
- Files: `kubernetes/apps/database/cloudnative-pg/`, `kubernetes/apps/database/dragonfly/`
- Why fragile: Running both CloudNative-PG (PostgreSQL) and Dragonfly (Redis alternative)
- Safe modification: Map application dependencies before modifying either database system
- Test coverage: No cross-database consistency checks

**System Apps with Prune Disabled:**
- Files: `kubernetes/apps/flux-system/flux/ks.yaml:14`, `kubernetes/apps/kube-system/cilium/ks.yaml:14`, `kubernetes/apps/kube-system/coredns/ks.yaml:14`
- Why fragile: Core networking and GitOps components protected from accidental deletion
- Safe modification: Cluster-breaking changes if modified incorrectly, requires manual cleanup
- Test coverage: Bootstrap validation only

## Scaling Limits

**PostgreSQL Connection Limit:**
- Current capacity: 400 max_connections configured
- Limit: Will reject connections when limit reached, no pooling layer visible
- Scaling path: Implement PgBouncer for connection pooling, increase max_connections with proportional shared_buffers increase

**3-Node Cluster:**
- Current capacity: 3 Talos control plane nodes
- Limit: Single node failure tolerance, limited compute/storage capacity
- Scaling path: Add worker nodes for workload scaling, maintain 3-5 control plane nodes for HA

**Rook Ceph Storage:**
- Files: `kubernetes/apps/rook-ceph/rook-ceph/cluster/helmrelease.yaml`
- Current capacity: Depends on node disk capacity (not specified in manifests)
- Limit: Storage exhaustion if disk space consumed
- Scaling path: Add OSDs by expanding node storage or adding storage nodes

**Single LoadBalancer VIP:**
- Current capacity: Single virtual IP for control plane (10.20.0.250)
- Limit: Single point of failure for API access, shared by all control plane nodes
- Scaling path: Already using VIP with failover, add external load balancer for production

## Dependencies at Risk

**Flux Dependency on GitHub:**
- Risk: GitHub outages prevent cluster reconciliation
- Impact: Cannot deploy changes during outages, existing workloads unaffected
- Migration plan: Configure local Git mirror or alternative Git source

**Deprecated Helm Chart Schemas:**
- Risk: Using Helm v2beta2 API version in some health checks
- Files: `kubernetes/apps/home/home-assistant/ks.yaml:23`
- Impact: May break when Flux drops v2beta2 support
- Migration plan: Update all healthChecks to use `helm.toolkit.fluxcd.io/v2`

**Age Encryption Key Management:**
- Risk: Single age.key file for all SOPS decryption
- Impact: Key loss means secrets unrecoverable, key compromise means all secrets exposed
- Migration plan: Implement key rotation strategy, consider multi-key SOPS configuration

## Missing Critical Features

**No Resource Quotas or LimitRanges:**
- Problem: Namespaces lack resource quotas or default limits
- Blocks: Cannot prevent resource exhaustion by single namespace
- Priority: Medium - cluster is small and controlled

**No Network Policies:**
- Problem: No network segmentation between namespaces or pods
- Blocks: Cannot enforce zero-trust networking or isolate workloads
- Priority: Low - single-tenant cluster, but recommended for security

**No Admission Controllers Beyond PSS:**
- Problem: No policy enforcement beyond Pod Security Standards
- Blocks: Cannot enforce custom policies like image registry restrictions
- Priority: Low - pre-commit validation covers most needs

**No Disaster Recovery Testing:**
- Problem: Backup tools configured but no DR testing or runbooks
- Blocks: Unknown RTO/RPO for cluster recovery scenarios
- Priority: High - critical for production workloads

## Test Coverage Gaps

**No Integration Tests for Flux Workflow:**
- What's not tested: End-to-end GitOps workflow from commit to deployment
- Files: All `kubernetes/apps/` manifests
- Risk: Breaking changes to Flux manifests not caught until deployment
- Priority: Medium

**No Validation for External Secrets:**
- What's not tested: External secrets resolution from cluster-secrets.sops.yaml
- Files: All `kubernetes/apps/*/app/externalsecret.yaml` files
- Risk: Missing variables cause pod failures at runtime
- Priority: Medium

**No Hardware Dependency Checks:**
- What's not tested: Intel GPU availability before deploying Frigate/Plex
- Files: `kubernetes/apps/home/frigate/`, `kubernetes/apps/media/plex/`
- Risk: Pods fail to schedule or function without GPU
- Priority: High - affects core media services

**No Storage Class Validation:**
- What's not tested: Custom NFS storage classes exist before PVC creation
- Files: `kubernetes/apps/home/frigate/app/nfs-pvc.yaml`, `kubernetes/apps/media/photoprism/app/nfs-photos.yaml`
- Risk: PVCs remain in Pending state indefinitely
- Priority: High - blocks application startup

**No Backup Restore Testing:**
- What's not tested: VolSync restore workflow actually recovers data
- Files: `.taskfiles/volsync/Taskfile.yaml`
- Risk: Discover backups are invalid during emergency
- Priority: Critical - defeats purpose of backups

---

*Concerns audit: 2026-02-22*
