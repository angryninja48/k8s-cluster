# Testing Patterns

**Analysis Date:** 2026-02-22

## Test Framework

**Runner:**
- Not applicable - This repository contains Kubernetes YAML configurations with no traditional test framework

**Validation Framework:**
- Custom shell scripts for consistency validation
- Pre-commit hooks for automated checks
- Task runner for validation orchestration

**Run Commands:**
```bash
task validate:all              # Run all validation checks
task validate:consistency      # Repository consistency checks
task validate:yaml             # YAML syntax validation
task validate:kustomize        # Kustomize manifest validation
task maintain:consistency      # Fix and validate (includes formatting fixes)
```

## Test File Organization

**Location:**
- Validation scripts in `scripts/` directory
- No co-located test files
- Validation runs against entire `kubernetes/` directory tree

**Naming:**
- `validate-consistency.sh` - Main validation script
- `fix-*.sh` - Auto-remediation scripts

**Structure:**
```
scripts/
├── validate-consistency.sh      # Comprehensive validation
├── fix-schemas.sh              # Schema declaration fixes
├── fix-properties.sh           # Required property additions
├── fix-timeout-format.sh       # YAML formatting fixes
└── fix-helmrelease-schemas.sh  # HelmRelease schema updates
```

## Test Structure

**Suite Organization:**
```bash
#!/bin/bash
set -euo pipefail

echo "🔍 Running validation checks..."

# Check 1: YAML syntax validation
echo "🔍 Checking YAML syntax..."
# validation logic

# Check 2: Schema consistency
echo "🔍 Checking Flux Kustomization schemas..."
# validation logic

# Check 3: Required properties
echo "🔍 Checking required properties..."
# validation logic

# Summary
echo "📊 Validation Summary:"
if [ $ERRORS -eq 0 ]; then
    log_success "All consistency checks passed! 🎉"
    exit 0
else
    echo "❌ Found $ERRORS issues"
    exit 1
fi
```

**Patterns:**
- Sequential check execution with descriptive headers
- Error counting with `ERRORS` variable incremented per issue
- Helper functions for logging: `log_error()`, `log_success()`, `log_info()`
- Emoji-prefixed output for visual clarity
- Exit codes reflect pass/fail status

## Validation Categories

**1. YAML Syntax Validation:**
```bash
if command -v yamllint >/dev/null 2>&1; then
    if yamllint kubernetes/ 2>&1 | grep -q "syntax error"; then
        log_error "YAML syntax errors found"
    else
        log_success "All YAML files have valid syntax"
    fi
fi
```

**2. Schema Consistency Checks:**
- Validates schema declarations on all files
- Checks for deprecated schemas (bjw-s-labs → bjw-s, helm-v2beta2 → helm-v2)
- Location: Lines 40-126 in `scripts/validate-consistency.sh`

**3. Required Property Validation:**
- Flux Kustomizations must have: `targetNamespace`, `retryInterval`, `commonMetadata`
- Enforced across all `kubernetes/apps/**/ks.yaml` files
- Location: Lines 77-89 in `scripts/validate-consistency.sh`

**4. Pattern Compliance:**
- No commented applications in kustomization files
- Consistent schema URLs across file types
- Location: Lines 92-101 in `scripts/validate-consistency.sh`

## Mocking

**Not applicable** - No mocking framework. Validation runs against actual repository files.

## Fixtures and Factories

**Test Data:**
- Templates in `docs/templates/` serve as reference implementations:
  - `docs/templates/ks.yaml` - Flux Kustomization template
  - `docs/templates/app-kustomization.yaml` - App kustomization template
  - `docs/templates/helmrelease-app-template.yaml` - HelmRelease template

**Location:**
- Templates directory: `docs/templates/`
- Used for creating new applications following established patterns
- Not traditional test fixtures but serve as canonical examples

## Coverage

**Requirements:** 100% validation coverage enforced via pre-commit hooks

**Validation Coverage:**
- All YAML files: Syntax validation
- All `ks.yaml` files: Schema + required properties + timeout format
- All `kustomization.yaml` files: Schema consistency
- All `helmrelease.yaml` files: Schema version validation
- All namespace kustomizations: No commented resources

**View Validation Results:**
```bash
task validate:all           # Comprehensive validation report
task validate:consistency   # Detailed consistency check output
```

## Test Types

**Validation Tests:**
- Scope: Repository-wide consistency and compliance checks
- Approach: Shell script pattern matching and YAML parsing
- Files: All files in `kubernetes/` directory
- Execution: Pre-commit hook and manual via Task commands

**Integration Tests:**
- Scope: Kustomize manifest building
- Approach: `kustomize build` on all app directories
- Files: All `kubernetes/apps/*/app/` directories
- Command: `task validate:kustomize`

**Deployment Tests:**
- Scope: Flux reconciliation validation
- Approach: `flux diff kustomization` to preview changes
- Files: Flux kustomization manifests
- Command: `task validate:flux`

## Common Patterns

**Error Counting Pattern:**
```bash
ERRORS=0

log_error() {
    echo "❌ ERROR: $1" >&2
    ERRORS=$((ERRORS + 1))
}

# After checks
if [ $ERRORS -eq 0 ]; then
    log_success "All checks passed"
    exit 0
else
    echo "❌ Found $ERRORS issues"
    exit 1
fi
```

**File Iteration Pattern:**
```bash
FLUX_FILES=$(find kubernetes/apps -name "ks.yaml" -type f)

for file in $FLUX_FILES; do
    if ! grep -q "targetNamespace:" "$file"; then
        log_error "Missing targetNamespace in $file"
    fi
done
```

**Conditional Tool Check:**
```bash
if command -v yamllint >/dev/null 2>&1; then
    # Run validation
else
    log_info "yamllint not found. Install with: pip install yamllint"
fi
```

**Grep Pattern Validation:**
```bash
if grep -q "yaml-language-server.*$EXPECTED_SCHEMA" "$file"; then
    continue
else
    log_error "Inconsistent schema in $file"
fi
```

## Auto-Remediation

**Fix Scripts:**
- `scripts/fix-schemas.sh` - Updates schema URLs to current versions
- `scripts/fix-properties.sh` - Adds missing required properties
- `scripts/fix-timeout-format.sh` - Corrects malformed timeout lines
- `scripts/fix-helmrelease-schemas.sh` - Updates HelmRelease schemas

**Remediation Pattern:**
```bash
#!/bin/bash
set -euo pipefail

echo "🔧 Fixing schema inconsistencies..."

# Fix pattern using sed
find kubernetes/apps -name "ks.yaml" -type f -exec sed -i '' \
  's|old-pattern|new-pattern|g' {} \;

echo "✅ Schema fixes applied! Run validation script to verify."
```

**Usage:**
```bash
task fix:schemas              # Auto-fix schema declarations
task fix:formatting           # Fix YAML formatting issues
task maintain:consistency     # Run all fixes + validation
```

## Pre-commit Hook Integration

**Configuration (`.pre-commit-config.yaml`):**
```yaml
hooks:
  - id: trailing-whitespace
  - id: end-of-file-fixer
  - id: check-yaml
    args: [--unsafe]
  - id: check-added-large-files
  - id: check-merge-conflict
  - id: consistency-check
    name: Repository Consistency Check
    entry: ./scripts/validate-consistency.sh
    language: script
    pass_filenames: false
    always_run: true
    stages: [commit]
```

**Validation Flow:**
1. Developer commits changes
2. Pre-commit runs `trailing-whitespace`, `end-of-file-fixer`, `check-yaml`
3. Pre-commit runs `scripts/validate-consistency.sh`
4. If validation fails, commit is rejected
5. Developer runs `task maintain:consistency` to auto-fix
6. Developer re-attempts commit

## Validation as Testing

**This repository treats validation as testing:**
- **Unit Tests** = Individual file schema validation
- **Integration Tests** = Kustomize build validation
- **System Tests** = Flux reconciliation preview
- **Compliance Tests** = Consistency validation script

**Test Pyramid:**
```
     Flux Reconciliation (Deployment Validation)
            /\
           /  \
          /    \
         /      \
        / Kustomize Build (Integration)
       /          \
      /            \
     /              \
    / Schema + Consistency (Unit)
   /____________________________\
```

## Continuous Validation

**Automated Triggers:**
- Every commit: Pre-commit hooks run validation
- Manual execution: `task validate:all` before push
- Repository maintenance: `task maintain:consistency` for cleanup

**Validation Stages:**
1. **Pre-commit**: Syntax, schemas, consistency
2. **Pre-push**: Kustomize builds, Flux diffs
3. **Post-merge**: Full reconciliation in cluster

## Success Criteria

**Validation passes when:**
- All YAML files have valid syntax
- All files have appropriate schema declarations
- All Flux Kustomizations have required properties
- All schemas use current (non-deprecated) URLs
- No commented applications in kustomizations
- Kustomize successfully builds all manifests
- Exit code 0 from `scripts/validate-consistency.sh`

**Remediation succeeds when:**
- Auto-fix scripts complete without errors
- Subsequent validation passes
- No manual intervention required

---

*Testing analysis: 2026-02-22*
