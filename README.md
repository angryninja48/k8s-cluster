# Self-Hosted Kubernetes Cluster

A GitOps-managed Kubernetes cluster running on Talos Linux with Flux CD for automated deployments.

## Overview

This repository contains the complete configuration for a self-hosted Kubernetes cluster using:

- **Talos Linux** - Immutable, secure Kubernetes OS
- **Flux CD** - GitOps operator for continuous deployment
- **SOPS** - Secret management with age encryption
- **Task** - Task runner for cluster operations

## Quick Start

### Prerequisites

- Install [mise](https://mise.jdx.dev/) for tool management
- 3+ nodes with Talos Linux installed
- Domain with Cloudflare DNS (optional)

### Setup

1. **Install dependencies**
   ```bash
   mise trust
   mise install
   mise run deps
   ```

2. **Configure cluster**
   ```bash
   task init
   # Edit config.yaml with your settings
   task configure
   ```

3. **Bootstrap cluster**
   ```bash
   task bootstrap:talos
   task bootstrap:apps
   task bootstrap:flux
   ```

## Applications

The cluster includes organized applications by namespace:

- **AI** - Machine learning workloads
- **Database** - PostgreSQL, Redis
- **Media** - Plex, Jellyfin, *arr stack
- **Network** - Ingress, DNS, VPN
- **Observability** - Monitoring and logging
- **Security** - Authentication and security tools
- **Self-hosted** - Personal productivity apps
- **Storage** - Rook Ceph, OpenEBS
- **Tools** - Development and admin utilities

## Key Features

- **GitOps Workflow** - All changes via Git commits
- **Automated Dependency Updates** - Renovate bot integration
- **Encrypted Secrets** - SOPS with age encryption
- **High Availability** - Multi-node control plane
- **Persistent Storage** - Ceph distributed storage
- **SSL Certificates** - Automated Let's Encrypt certs
- **Backup & Sync** - VolSync for data protection

## Management

```bash
# Force Flux reconciliation
task reconcile

# View cluster resources
kubectl get nodes -o wide
kubectl get pods -A

# Check Flux status
flux get sources git -A
flux get kustomizations -A
```

## Storage

- **Rook Ceph** - Distributed block/object/filesystem storage
- **OpenEBS** - Local persistent volumes
- **VolSync** - Backup and replication

## Networking

- **Cilium** - CNI with eBPF dataplane
- **Ingress NGINX** - HTTP/HTTPS ingress controller
- **External DNS** - Automatic DNS record management
- **Cloudflare Tunnel** - Secure external access

---

Built with ❤️ for self-hosting enthusiasts
