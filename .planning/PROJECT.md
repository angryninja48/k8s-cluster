# Persistent OpenCode on Kubernetes

## What This Is

Deploy OpenCode as a persistent, always-on service on the existing Flux/GitOps Kubernetes cluster. Two independent workspace instances — one for the Flux/GitOps repo, one for the Home Assistant repo — each exposed via HTTPS at a subdomain of `opencode.angryninja.cloud` using the existing Envoy Gateway. Session data, project code, and GitHub Copilot OAuth tokens are stored on PersistentVolumeClaims so nothing is lost across pod restarts.

## Core Value

OpenCode sessions and GitHub Copilot auth survive indefinitely and are accessible from any device via browser — no laptop dependency.

## Requirements

### Validated

(None yet — ship to validate)

### Active

- [ ] `https://flux.opencode.angryninja.cloud` loads OpenCode web UI (password-protected)
- [ ] `https://ha.opencode.angryninja.cloud` loads OpenCode web UI (password-protected)
- [ ] GitHub Copilot models are available in both workspaces
- [ ] Each workspace working directory is the correct cloned private repo
- [ ] Deleting a pod and letting it recreate preserves all sessions and code
- [ ] Repo is not re-cloned on pod restart if PVC already contains the code
- [ ] All secrets stored in Kubernetes Secrets, never in committed manifests

### Out of Scope

- Multi-user support — personal use only; single-user sufficient
- Automatic `git push` of changes — out of scope for v1
- CI/CD pipeline integration — not part of OpenCode's role here
- Repo sync / pull automation — manual workflow is fine
- Mobile app — browser access satisfies the requirement

## Context

- Existing cluster: Talos Linux v1.12.1, Kubernetes v1.35.0, managed by Flux CD v2.17.2
- GitOps pattern: All cluster resources live under `kubernetes/apps/<namespace>/<app>/` with `ks.yaml` + `app/` structure
- Existing ingress: Envoy Gateway with cert-manager ClusterIssuer (already in use cluster-wide)
- Secrets management: SOPS + ExternalSecrets pattern cluster-wide; new secrets follow same pattern
- Storage: Rook Ceph for distributed storage; VolSync available for PVC backups
- bjw-s app-template used for most application HelmReleases
- Home Assistant config repo is a reference for deploying this project — no modifications to it
- Cluster repo: `/Users/jbaker/git/k8s-cluster` — PRs must target `main` branch
- OpenCode image: `ghcr.io/anomalyco/opencode` (latest)
- OpenCode runs: `opencode web --hostname 0.0.0.0 --port 4096`
- Auth persistence: `~/.local/share/opencode/auth.json` stores GitHub Copilot OAuth tokens

## Constraints

- **Tech Stack**: Must follow existing cluster patterns (bjw-s app-template, Flux ks.yaml structure, SOPS secrets) — deviating creates drift
- **Secrets**: GitHub PAT, server password, and copilot auth.json must be in Kubernetes Secrets — never committed plaintext
- **Ingress**: Must use existing Envoy Gateway `HTTPRoute` + cert-manager `Certificate` — no new ingress controllers
- **Storage**: PVC per workspace, `ReadWriteOnce`, default storage class (Rook Ceph) — 5Gi each
- **Branching**: All changes via PR targeting `main` branch — never commit directly to main
- **Resource Limits**: Each pod: `requests: cpu 100m, memory 256Mi` / `limits: cpu 500m, memory 512Mi`

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Two separate Deployments (not one multi-repo) | Each workspace needs independent PVC, workingDir, and auth context | — Pending |
| Init container for git clone + auth seeding | Ensures idempotent first-boot without modifying main container | — Pending |
| bjw-s app-template for HelmRelease | Consistent with all other cluster apps; reduces boilerplate | — Pending |
| SOPS ExternalSecret for all secrets | Follows cluster-wide pattern; keeps secrets encrypted at rest in Git | — Pending |
| `opencode` namespace (new) | Isolates OpenCode workloads from other cluster concerns | — Pending |

---
*Last updated: 2026-03-01 after initialization*
