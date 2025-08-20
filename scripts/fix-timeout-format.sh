#!/bin/bash

# Fix malformed retryInterval and timeout lines in ks.yaml files

echo "🔧 Fixing malformed retryInterval/timeout lines..."

# List of files with the issue
files=(
    "kubernetes/apps/flux-system/flux/ks.yaml"
    "kubernetes/apps/tools/generic-device-plugin/ks.yaml"
    "kubernetes/apps/network/ingress-nginx/ks.yaml"
    "kubernetes/apps/observability/kube-prometheus-stack/ks.yaml"
    "kubernetes/apps/kube-system/reloader/ks.yaml"
    "kubernetes/apps/kube-system/metrics-server/ks.yaml"
    "kubernetes/apps/kube-system/coredns/ks.yaml"
    "kubernetes/apps/kube-system/spegel/ks.yaml"
    "kubernetes/apps/openebs-system/openebs/ks.yaml"
)

for file in "${files[@]}"; do
    if [ -f "$file" ]; then
        echo "Fixing $file..."
        # Replace the malformed line with proper YAML formatting
        sed -i '' 's/retryInterval: 1m  timeout: 5m/retryInterval: 1m\
  timeout: 5m/g' "$file"
        echo "✅ Fixed $file"
    else
        echo "⚠️  File not found: $file"
    fi
done

echo "🎉 All files fixed!"
