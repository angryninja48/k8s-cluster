# Flux

### Replace ssh key

WIP: Must be a better way to do this

Run the bootstrap command
```
export GITHUB_USER=xxxx
export GITHUB_TOKEN=xxxx

flux bootstrap github \
  --owner=${GITHUB_USER} \
  --repository=k3s-gitops \
  --path=cluster/base \
  --personal \
  --kubeconfig=./kubeconfig -v 0.28.1
```
This will edit the file cluster/base/flux-system/gotk-sync.yaml and remove sops decryption.

Ensure the secret for sops decryption is loaded
```
cat ~/.config/sops/age/keys.txt |
    kubectl --kubeconfig=./provision/kubeconfig \
    -n flux-system create secret generic sops-age \
    --from-file=age.agekey=/dev/stdin
```

`git pull` and add the following snippet
```
  decryption:
    provider: sops
    secretRef:
      name: sops-age
```
