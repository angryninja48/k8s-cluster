# Multus CNI

Multus CNI enables attaching multiple network interfaces to pods in Kubernetes.

## Overview

This deployment uses Multus CNI v4.2.2, which provides:

- Support for CNI spec v1.2.0
- Multiple network interface attachment to pods
- Network isolation per namespace
- Integration with Cilium as the primary CNI

## Configuration

Multus is configured with:

- **CNI Version**: 1.2.0
- **Cluster Network**: Cilium (primary CNI)
- **Config Directory**: `/var/lib/cni/conf.d` (Talos default)
- **Binary Directory**: `/var/lib/cni/bin` (Talos default)
- **Namespace Isolation**: Enabled
- **Log Level**: Verbose

## Usage

### Creating a NetworkAttachmentDefinition

To attach additional networks to your pods, create a `NetworkAttachmentDefinition`:

```yaml
apiVersion: k8s.cni.cncf.io/v1
kind: NetworkAttachmentDefinition
metadata:
  name: macvlan-conf
  namespace: home
spec:
  config: |
    {
      "cniVersion": "0.3.1",
      "type": "macvlan",
      "master": "eth0",
      "mode": "bridge",
      "ipam": {
        "type": "host-local",
        "subnet": "192.168.1.0/24",
        "rangeStart": "192.168.1.200",
        "rangeEnd": "192.168.1.216",
        "gateway": "192.168.1.1"
      }
    }
```

### Attaching Networks to Pods

Add the `k8s.v1.cni.cncf.io/networks` annotation to your pod:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: my-pod
  annotations:
    k8s.v1.cni.cncf.io/networks: macvlan-conf
spec:
  containers:
  - name: app
    image: nginx
```

### Using with bjw-s App Template (Home Assistant Example)

For the bjw-s app-template (like Home Assistant), add the annotation to `defaultPodOptions`:

```yaml
defaultPodOptions:
  annotations:
    k8s.v1.cni.cncf.io/networks: home/macvlan-conf
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    fsGroupChangePolicy: OnRootMismatch
    seccompProfile: { type: RuntimeDefault }
```

### Multiple Networks

To attach multiple networks, separate them with commas:

```yaml
annotations:
  k8s.v1.cni.cncf.io/networks: macvlan-conf,ipvlan-conf
```

### Network Status

Check the network status of a pod:

```bash
kubectl get pod <pod-name> -o jsonpath='{.metadata.annotations.k8s\.v1\.cni\.cncf\.io/network-status}' | jq
```

## Common Network Types

### MacVLAN

Best for: Direct Layer 2 connectivity to your physical network

```yaml
{
  "type": "macvlan",
  "master": "eth0",
  "mode": "bridge",
  "ipam": {
    "type": "host-local",
    "subnet": "192.168.1.0/24"
  }
}
```

### IPvLAN

Best for: Similar to MacVLAN but with shared MAC address

```yaml
{
  "type": "ipvlan",
  "master": "eth0",
  "mode": "l2",
  "ipam": {
    "type": "host-local",
    "subnet": "192.168.1.0/24"
  }
}
```

### Bridge

Best for: Custom bridge networks

```yaml
{
  "type": "bridge",
  "bridge": "br0",
  "ipam": {
    "type": "host-local",
    "subnet": "10.10.0.0/16"
  }
}
```

## Troubleshooting

### Check Multus Pods

```bash
kubectl get pods -n kube-system -l app.kubernetes.io/name=multus-cni
```

### View Multus Logs

```bash
kubectl logs -n kube-system -l app.kubernetes.io/name=multus-cni
```

### List Network Attachment Definitions

```bash
kubectl get network-attachment-definitions -A
```

### Verify CNI Configuration

```bash
# SSH into a Talos node
talosctl shell

# Check CNI config
cat /var/lib/cni/conf.d/00-multus.conflist
```

## References

- [Multus CNI Documentation](https://github.com/k8snetworkplumbingwg/multus-cni)
- [Network Plumbing Working Group](https://github.com/k8snetworkplumbingwg)
- [Talos Linux CNI Documentation](https://www.talos.dev/v1.7/kubernetes-guides/network/multus/)
