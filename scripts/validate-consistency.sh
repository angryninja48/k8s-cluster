#!/bin/bash
# Repository consistency validation script

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ERRORS=0

echo "🔍 Running Kubernetes repository consistency checks..."

# Function to log errors
log_error() {
    echo "❌ ERROR: $1" >&2
    ERRORS=$((ERRORS + 1))
}

log_info() {
    echo "ℹ️  INFO: $1"
}

log_success() {
    echo "✅ SUCCESS: $1"
}

# Check 1: YAML syntax validation
echo
echo "🔍 Checking YAML syntax..."
if command -v yamllint >/dev/null 2>&1; then
    # Check only for critical syntax errors, not style issues
    if yamllint kubernetes/ 2>&1 | grep -q "syntax error"; then
        log_error "YAML syntax errors found. Run 'yamllint kubernetes/ | grep \"syntax error\"' for details"
    else
        log_success "All YAML files have valid syntax"
    fi
else
    log_info "yamllint not found. Install with: pip install yamllint"
fi

# Check 2: Schema consistency for Flux Kustomizations
echo
echo "🔍 Checking Flux Kustomization schemas..."
EXPECTED_FLUX_SCHEMA="https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/kustomization-kustomize-v1.json"
FLUX_FILES=$(find kubernetes/apps -name "ks.yaml" -type f)

for file in $FLUX_FILES; do
    if grep -q "yaml-language-server.*$EXPECTED_FLUX_SCHEMA" "$file"; then
        continue
    else
        log_error "Inconsistent schema in $file. Expected: $EXPECTED_FLUX_SCHEMA"
    fi
done

if [ $ERRORS -eq 0 ]; then
    log_success "All Flux Kustomization schemas are consistent"
fi

# Check 3: Schema consistency for app kustomizations
echo
echo "🔍 Checking app kustomization schemas..."
EXPECTED_APP_SCHEMA="https://json.schemastore.org/kustomization"
APP_KUST_FILES=$(find kubernetes/apps -name "kustomization.yaml" -type f)

for file in $APP_KUST_FILES; do
    if grep -q "yaml-language-server.*$EXPECTED_APP_SCHEMA" "$file" || \
       grep -q "yaml-language-server.*https://raw.githubusercontent.com/SchemaStore/schemastore/master/src/schemas/json/kustomization.json" "$file"; then
        continue
    else
        log_error "Missing or inconsistent schema in $file. Expected: $EXPECTED_APP_SCHEMA"
    fi
done

if [ $ERRORS -eq 0 ]; then
    log_success "All app kustomization schemas are consistent"
fi

# Check 4: Required properties in Flux Kustomizations
echo
echo "🔍 Checking required properties in Flux Kustomizations..."
for file in $FLUX_FILES; do
    if ! grep -q "targetNamespace:" "$file"; then
        log_error "Missing targetNamespace in $file"
    fi
    if ! grep -q "retryInterval:" "$file"; then
        log_error "Missing retryInterval in $file"
    fi
    if ! grep -q "commonMetadata:" "$file"; then
        log_error "Missing commonMetadata in $file"
    fi
done

# Check 5: Commented applications cleanup
echo
echo "🔍 Checking for commented applications..."
COMMENTED_APPS=$(find kubernetes/apps -name "kustomization.yaml" -exec grep -l "# - \\./" {} \;)
if [ -n "$COMMENTED_APPS" ]; then
    for file in $COMMENTED_APPS; do
        log_error "Commented applications found in $file"
    done
else
    log_success "No commented applications found"
fi

# Check 6: HelmRelease schema consistency
echo
echo "🔍 Checking HelmRelease schemas..."
EXPECTED_HELM_SCHEMA="https://raw.githubusercontent.com/bjw-s/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json"
EXPECTED_FLUX_HELM_SCHEMA="https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/helmrelease-helm-v2.json"
HELM_FILES=$(find kubernetes/apps -name "helmrelease*.yaml" -type f)

for file in $HELM_FILES; do
    if grep -q "yaml-language-server.*bjw-s-labs" "$file"; then
        log_error "Deprecated bjw-s-labs schema in $file. Use bjw-s instead"
    elif grep -q "yaml-language-server.*helm-v2beta2" "$file"; then
        log_error "Deprecated helm-v2beta2 schema in $file. Use helm-v2 instead"
    elif grep -q "yaml-language-server.*$EXPECTED_HELM_SCHEMA" "$file"; then
        continue
    elif grep -q "yaml-language-server.*$EXPECTED_FLUX_HELM_SCHEMA" "$file"; then
        continue
    else
        log_error "Missing or inconsistent HelmRelease schema in $file"
    fi
done

if [ $ERRORS -eq 0 ]; then
    log_success "All HelmRelease schemas are consistent"
fi

# Summary
echo
echo "📊 Validation Summary:"
if [ $ERRORS -eq 0 ]; then
    log_success "All consistency checks passed! 🎉"
    exit 0
else
    echo "❌ Found $ERRORS issues that need attention"
    exit 1
fi
