# Kubernetes Cluster Documentation

Welcome to the documentation for the k8s-cluster repository. This documentation is organized into logical sections to help you find what you need quickly.

## 📁 Documentation Structure

### 🚀 [Deployment](./deployment/)
Initial cluster setup and deployment processes
- **[talos-deployment.md](./deployment/talos-deployment.md)** - Complete Talos Kubernetes deployment guide
- **[rebuild_cluster.md](./deployment/rebuild_cluster.md)** - Complete cluster rebuild procedures

### ⚙️ [Cluster Management](./cluster-management/)
Core cluster configuration and GitOps setup
- **[flux.md](./cluster-management/flux.md)** - Flux CD configuration and operations
- **[sops-encryption.md](./cluster-management/sops-encryption.md)** - SOPS encryption for secrets

### 🔧 [Operations](./operations/)
Day-to-day operations, monitoring, and troubleshooting
- **[maintenance.md](./operations/maintenance.md)** - Repository maintenance guide and validation
- **[troubleshooting.md](./operations/troubleshooting.md)** - Common troubleshooting commands
- **[postgres.md](./operations/postgres.md)** - PostgreSQL database operations
- **[pvc.md](./operations/pvc.md)** - Persistent Volume Claims monitoring

### 🛠️ [Development](./development/)
Development guidelines and tools
- **[style-guide.md](./development/style-guide.md)** - Comprehensive coding standards and conventions
- **[references.md](./development/references.md)** - External reference repositories

### 📄 [Templates](./templates/)
Reusable templates for common configurations
- **[app-kustomization.yaml](./templates/app-kustomization.yaml)** - App-level Kustomization template
- **[helmrelease-app-template.yaml](./templates/helmrelease-app-template.yaml)** - HelmRelease template for app-template charts
- **[ks.yaml](./templates/ks.yaml)** - Flux Kustomization template

## 🎯 Quick Start Guide

### For New Users
1. Start with **[Deployment](./deployment/)** to understand cluster setup
2. Review **[Cluster Management](./cluster-management/)** for GitOps configuration
3. Check **[Development/Style Guide](./development/style-guide.md)** for coding standards

### For Operations
1. **[Operations/Maintenance](./operations/maintenance.md)** - Daily maintenance tasks
2. **[Operations/Troubleshooting](./operations/troubleshooting.md)** - Quick troubleshooting reference
3. **[Operations/Velero](./operations/velero.md)** - Backup and restore procedures

### For Development
1. **[Development/Style Guide](./development/style-guide.md)** - Must-read for all contributors
2. **[Templates](./templates/)** - Use these for new applications
3. **[Operations/Maintenance](./operations/maintenance.md)** - Validation and consistency checks

## 🔍 Common Tasks

| Task | Documentation |
|------|---------------|
| Add new application | [Style Guide](./development/style-guide.md) + [Templates](./templates/) |
| Troubleshoot Flux | [Troubleshooting](./operations/troubleshooting.md) + [Flux Management](./cluster-management/flux.md) |
| Backup/Restore | Contact your backup solution documentation |
| Cluster rebuild | [Rebuild Procedures](./deployment/rebuild_cluster.md) |
| Repository maintenance | [Maintenance Guide](./operations/maintenance.md) |
| Setup encryption | [SOPS Encryption](./cluster-management/sops-encryption.md) |

## 📈 Maintenance Status

- ✅ **Repository Consistency**: 100% validated
- ✅ **Documentation**: Organized and up-to-date
- ✅ **Templates**: Available for all common patterns
- ✅ **Automation**: Pre-commit hooks and validation scripts active

## 🆘 Getting Help

1. **Search this documentation** - Use the folder structure above
2. **Check validation status** - Run `task validate:consistency`
3. **Review style guide** - Most issues are covered in [development/style-guide.md](./development/style-guide.md)
4. **Look at existing patterns** - Find similar applications in the cluster

---

**Last Updated**: $(date +"%B %d, %Y")
**Maintainer**: k8s-cluster documentation team
