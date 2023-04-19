# Installing Kubernetes

### Install k3s with k3sup

Install controller
```
k3sup install \
    --ip=10.20.0.13 \
    --user=jbaker \
    --cluster \
    --k3s-version=v1.21.8+k3s1 \
    --k3s-extra-args="--disable servicelb --disable traefik --disable local-storage"
```

Join additional controller
```
k3sup join \
  --ip 10.20.0.12 \
  --user=jbaker \
  --server-user jbaker \
  --server-ip 10.20.0.13 \
  --server \
  --k3s-version v1.22.5+k3s2 \
  --k3s-extra-args="--disable servicelb --disable traefik --disable local-storage"

```

Join Workers
```
k3sup join \
    --ip=10.20.0.10 \
    --server-ip=10.20.0.13 \
    --k3s-version=v1.21.8+k3s1 \
    --user=jbaker

k3sup join \
    --ip=10.20.0.12 \
    --server-ip=10.20.0.10 \
    --k3s-version=v1.21.8+k3s1 \
    --user=jbaker

k3sup join \
    --ip=10.20.0.13 \
    --server-ip=10.20.0.10 \
    --k3s-version=v1.21.8+k3s1 \
    --user=jbaker

k3sup join \
    --ip=10.20.0.14 \
    --server-ip=10.20.0.10 \
    --k3s-version=v1.21.8+k3s1 \
    --user=jbaker
```

### Label nodes for k3s-upgrade
```
kubectl label node k3s-0 k3s-1 k3s-2 k3s-3 k3s-4 k3s-upgrade=true
```
### Label Workers
```
kubectl label node k3s-0 node-role.kubernetes.io/worker=true
kubectl label node k3s-1 node-role.kubernetes.io/worker=true
kubectl label node k3s-2 node-role.kubernetes.io/worker=true

kubectl label node k3s-3 node-role.kubernetes.io/worker=true
kubectl label node k3s-3 k3s-upgrade=true

```
