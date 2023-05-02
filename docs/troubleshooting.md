# Troubleshooting Helm release
kubectl -n monitoring get events --sort-by='{.lastTimestamp}'

# Restart Helm Release
flux suspend hr thanos -n monitoring
flux resume hr thanos -n monitoring

# Restart kustomization
flux suspend kustomization cluster-apps-grafana
flux resume kustomization cluster-apps-grafana