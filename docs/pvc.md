# Check PVC available bytes
kubelet_volume_stats_available_bytes{persistentvolumeclaim="your-pvc"}

# Check capacity of PVC
kubelet_volume_stats_capacity_bytes{persistentvolumeclaim="your-pvc"}
