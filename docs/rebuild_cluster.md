# Steps to rebuild
1. Create a backup
```sh
velero backup create manually-backup-1 --from-schedule velero-daily-backup
```
2. Run k3s ansible nuke
```sh
task ansible:playbook:k3s-nuke
```
3. Clear ceph disks by logging in to each node and running `cleanup_ceph.sh` script.
*Note* Each node has a different disk
4. Reinstall k3s by running ansible install script
```
task ansible:playbook:k3s-install
```
5. Label each node correctly
```
# Enable auto-upgrades
kubectl label node k3s-0 k3s-1 k3s-2 k3s-3 k3s-upgrade=true
# Label Workers
kubectl label node k3s-0 k3s-1 k3s-2 k3s-3 node-role.kubernetes.io/worker=true
```
6. Remove local-path storage class
```
kubectl delete sc local-path
```
7. Remove all prometheus rules search for `prometheus-rule.yaml` and comment out in kustomization.yaml. Disable all `prometheusRule` in helm charts.
8. Configure flux for private repo
```
export GITHUB_USER=angryninja48  
export GITHUB_TOKEN=xxx

flux bootstrap github \  
  --owner=${GITHUB_USER} \
  --repository=k3s-gitops \
  --path=cluster/base \
  --personal \
  --kubeconfig=./provision/kubeconfig -v v0.38.3
```
9. Add sops-age to cluster
```
cat ~/.config/sops/age/keys.txt |  
    kubectl --kubeconfig=./provision/kubeconfig \
    -n flux-system create secret generic sops-age \
    --from-file=age.agekey=/dev/stdin
```
10. Configure flux to use sops-age to decrypt secrets. Update `gotk-sync.yaml`
```
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```
11. Install flux *Note* run this twice
```
kubectl --kubeconfig=./provision/kubeconfig apply --kustomize=./cluster/base/flux-system
```


# Issues:
## Metallb CRDs
- Have enable the helmrelease to remanage the crds
- Disabled CRD install in kustomization
