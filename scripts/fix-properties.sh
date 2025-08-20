#!/bin/bash
# Fix missing properties in Flux Kustomizations

set -euo pipefail

echo "🔧 Adding missing properties to Flux Kustomizations..."

# Function to add commonMetadata to files that don't have it
add_common_metadata() {
    local file="$1"
    local app_name="$2"

    # Check if file already has commonMetadata
    if ! grep -q "commonMetadata:" "$file"; then
        # Find the line with targetNamespace and add commonMetadata after it
        if grep -q "targetNamespace:" "$file"; then
            sed -i '' "/targetNamespace:/a\\
  commonMetadata:\\
    labels:\\
      app.kubernetes.io/name: *app" "$file"
        fi
    fi
}

# Function to add targetNamespace to files that don't have it
add_target_namespace() {
    local file="$1"
    local namespace="$2"

    # Check if file already has targetNamespace
    if ! grep -q "targetNamespace:" "$file"; then
        # Add targetNamespace after spec:
        sed -i '' "/^spec:/a\\
  targetNamespace: $namespace" "$file"
    fi
}

# Function to add retryInterval to files that don't have it
add_retry_interval() {
    local file="$1"

    # Check if file already has retryInterval
    if ! grep -q "retryInterval:" "$file"; then
        # Add retryInterval after interval
        if grep -q "interval:" "$file"; then
            sed -i '' "/interval:/a\\
  retryInterval: 1m" "$file"
        fi
    fi
}

# Fix files missing targetNamespace and commonMetadata
echo "📝 Fixing home namespace applications..."

# EVCC
if [ -f "kubernetes/apps/home/evcc/ks.yaml" ]; then
    add_target_namespace "kubernetes/apps/home/evcc/ks.yaml" "home"
    add_common_metadata "kubernetes/apps/home/evcc/ks.yaml" "evcc"
fi

# Database namespace
echo "📝 Fixing database namespace applications..."
if [ -f "kubernetes/apps/database/influxdb/ks.yaml" ]; then
    add_target_namespace "kubernetes/apps/database/influxdb/ks.yaml" "database"
    add_common_metadata "kubernetes/apps/database/influxdb/ks.yaml" "influxdb"
fi

# Fix files missing retryInterval
echo "📝 Adding missing retryInterval properties..."

# System applications
for app in flux cert-manager; do
    find kubernetes/apps -name "ks.yaml" -path "*/$app/*" | while read file; do
        add_retry_interval "$file"
    done
done

# Network applications
for file in kubernetes/apps/network/*/ks.yaml; do
    if [ -f "$file" ]; then
        add_retry_interval "$file"
    fi
done

# Observability applications
for file in kubernetes/apps/observability/*/ks.yaml; do
    if [ -f "$file" ]; then
        add_retry_interval "$file"
    fi
done

# Kube-system applications
for file in kubernetes/apps/kube-system/*/ks.yaml; do
    if [ -f "$file" ]; then
        add_retry_interval "$file"
    fi
done

# OpenEBS
if [ -f "kubernetes/apps/openebs-system/openebs/ks.yaml" ]; then
    add_retry_interval "kubernetes/apps/openebs-system/openebs/ks.yaml"
fi

# Media
if [ -f "kubernetes/apps/media/plex/ks.yaml" ]; then
    add_retry_interval "kubernetes/apps/media/plex/ks.yaml"
fi

# Tools
for file in kubernetes/apps/tools/*/ks.yaml; do
    if [ -f "$file" ]; then
        add_retry_interval "$file"
    fi
done

echo "✅ Properties fixes applied!"
