#!/bin/bash
# Batch fix schema inconsistencies

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "🔧 Fixing schema inconsistencies..."

# Fix Flux Kustomization schemas
echo "📝 Updating Flux Kustomization schemas..."
find kubernetes/apps -name "ks.yaml" -type f -exec sed -i '' 's|yaml-language-server: \$schema=https://kubernetes-schemas\.devbu\.io/.*|yaml-language-server: $schema=https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/kustomization-kustomize-v1.json|g' {} \;

find kubernetes/apps -name "ks.yaml" -type f -exec sed -i '' 's|yaml-language-server: \$schema=https://kubernetes-schemas\.pages\.dev/.*|yaml-language-server: $schema=https://raw.githubusercontent.com/fluxcd-community/flux2-schemas/main/kustomization-kustomize-v1.json|g' {} \;

# Fix HelmRelease schemas - bjw-s-labs to bjw-s
echo "📝 Updating HelmRelease schemas..."
find kubernetes/apps -name "helmrelease*.yaml" -type f -exec sed -i '' 's|bjw-s-labs/helm-charts|bjw-s/helm-charts|g' {} \;

# Fix HelmRelease schemas - helm-v2beta2 to helm-v2
find kubernetes/apps -name "helmrelease*.yaml" -type f -exec sed -i '' 's|helmrelease-helm-v2beta2\.schema\.json|helmrelease-helm-v2.schema.json|g' {} \;

# Fix app kustomization schemas
echo "📝 Updating app kustomization schemas..."
find kubernetes/apps -name "kustomization.yaml" -type f ! -path "*/flux/*" -exec grep -l "SchemaStore/schemastore" {} \; | xargs sed -i '' 's|https://raw.githubusercontent.com/SchemaStore/schemastore/master/src/schemas/json/kustomization.json|https://json.schemastore.org/kustomization|g'

echo "✅ Schema fixes applied! Run validation script to verify."
