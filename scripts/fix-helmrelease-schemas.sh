#!/bin/bash
# Add schemas only to app-template HelmReleases

set -euo pipefail

echo "🔧 Adding schemas to app-template HelmReleases..."

# Find all HelmRelease files using app-template
APP_TEMPLATE_FILES=$(find kubernetes/apps -name "helmrelease*.yaml" -type f -exec grep -l "chart: app-template" {} \;)

for file in $APP_TEMPLATE_FILES; do
    # Check if it already has a bjw-s schema
    if ! grep -q "bjw-s/helm-charts.*helmrelease-helm-v2.schema.json" "$file"; then
        # Check if it has any schema line to replace
        if grep -q "yaml-language-server.*schema" "$file"; then
            # Replace existing schema
            sed -i '' 's|# yaml-language-server: \$schema=.*|# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json|g' "$file"
            echo "  Updated schema in $file"
        else
            # Add schema after the --- line
            sed -i '' '1a\
# yaml-language-server: $schema=https://raw.githubusercontent.com/bjw-s/helm-charts/main/charts/other/app-template/schemas/helmrelease-helm-v2.schema.json' "$file"
            echo "  Added schema to $file"
        fi
    fi
done

echo "✅ App-template HelmRelease schemas updated!"
