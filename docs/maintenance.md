# 🛠️ Repository Maintenance Guide

## 📊 Current Status
✅ **Repository Consistency: 100%**
✅ **All Validation Checks: Passing**
✅ **Total Issues Resolved: 92+**

## 🚀 Quick Start

### Daily Maintenance
```bash
# Run full consistency check
task validate:consistency

# Run all validations
task validate:all

# Fix any issues that arise
task maintain:consistency
```

### Before Committing Changes
```bash
# Validate your changes
task validate:yaml
task validate:kustomize
task validate:consistency

# Or run everything at once
task validate:all
```

## 🔧 Available Tools

### Task Commands
| Command | Description |
|---------|-------------|
| `task validate:consistency` | Run comprehensive consistency checks |
| `task validate:yaml` | Validate YAML syntax |
| `task validate:kustomize` | Validate Kustomize manifests |
| `task validate:all` | Run all validation checks |
| `task fix:schemas` | Auto-fix schema issues |
| `task fix:formatting` | Fix YAML formatting |
| `task maintain:consistency` | Full maintenance cycle |

### Scripts
| Script | Purpose |
|--------|---------|
| `scripts/validate-consistency.sh` | Main validation script |
| `scripts/fix-schemas.sh` | Schema standardization |
| `scripts/fix-timeout-format.sh` | YAML formatting fixes |

### Pre-commit Hooks
Automatically validate changes before commit:
```bash
# Install (one-time setup)
pip install pre-commit
pre-commit install

# Manually run on all files
pre-commit run --all-files
```

## 📈 Monitoring Consistency

### Weekly Review Checklist
- [ ] Run `task validate:consistency`
- [ ] Check for new commented applications
- [ ] Verify schema compliance
- [ ] Review any failed Flux reconciliations
- [ ] Update this README if needed

### Monthly Deep Dive
- [ ] Review and update style guide
- [ ] Check for new schema versions
- [ ] Validate all applications are actively used
- [ ] Update validation scripts if needed
- [ ] Review automation effectiveness

## 🚨 Troubleshooting

### Common Issues & Solutions

#### "YAML syntax errors found"
```bash
# Check specific errors
yamllint kubernetes/ | grep "syntax error"

# Auto-fix formatting issues
task fix:formatting
```

#### "Missing schema declarations"
```bash
# Auto-fix schemas
task fix:schemas

# Manually check
grep -r "yaml-language-server" kubernetes/apps/
```

#### "Missing required properties"
Check that all Flux Kustomizations have:
- `targetNamespace`
- `commonMetadata.labels.app.kubernetes.io/name`
- `retryInterval: 1m`

#### "Commented applications found"
Remove commented lines from kustomization.yaml files:
```bash
# Find commented apps
grep -r "# -" kubernetes/apps/*/kustomization.yaml

# Remove the commented lines
```

### Validation Script Exit Codes
- **0**: All checks passed ✅
- **1**: Issues found that need attention ⚠️

## 📝 Adding New Applications

### Standard Process
1. **Create directory structure**:
   ```bash
   mkdir -p kubernetes/apps/<namespace>/<app-name>/app
   ```

2. **Create Flux Kustomization** (`ks.yaml`):
   ```bash
   # Use style guide template
   cp docs/templates/ks.yaml kubernetes/apps/<namespace>/<app-name>/ks.yaml
   # Edit with app-specific details
   ```

3. **Create app kustomization**:
   ```bash
   # Use style guide template
   cp docs/templates/app-kustomization.yaml kubernetes/apps/<namespace>/<app-name>/app/kustomization.yaml
   ```

4. **Add HelmRelease**:
   ```bash
   # Use appropriate template based on chart type
   cp docs/templates/helmrelease-*.yaml kubernetes/apps/<namespace>/<app-name>/app/helmrelease.yaml
   ```

5. **Update namespace kustomization**:
   ```yaml
   # Add to kubernetes/apps/<namespace>/kustomization.yaml
   resources:
     # ... existing apps
     - ./<app-name>/ks.yaml  # Add in alphabetical order
   ```

6. **Validate**:
   ```bash
   task validate:consistency
   ```

### Templates Location
Find templates in `docs/templates/` or refer to existing apps as examples.

## 🔄 Continuous Integration

### GitHub Actions (Recommended)
Create `.github/workflows/validate.yml`:
```yaml
name: Repository Validation
on: [push, pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Setup Task
        uses: arduino/setup-task@v1
      - name: Install yamllint
        run: pip install yamllint
      - name: Validate Repository
        run: task validate:all
```

### Pre-push Hook
```bash
#!/bin/sh
# .git/hooks/pre-push
task validate:consistency
```

## 📖 Related Documentation

- **Style Guide**: `docs/style-guide.md`
- **Consistency Analysis**: `CONSISTENCY_ANALYSIS.md`
- **Application Docs**: `docs/` directory
- **Flux Documentation**: `docs/flux.md`

## 📞 Support

### Self-Service
1. Check validation output: `task validate:consistency`
2. Review style guide: `docs/style-guide.md`
3. Run auto-fixes: `task maintain:consistency`

### Getting Help
- Check existing patterns in similar applications
- Refer to Flux CD documentation
- Review schema definitions for proper structure

---

**Last Updated**: $(date)
**Validation Status**: ✅ Passing
**Maintainer**: Repository Consistency System
