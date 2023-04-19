In the event traefik gets installed run the following:

# Helm charts
```
kubectl -n kube-system get helmcharts.helm.cattle.io
```

Delete helm charts
```
kubectl -n kube-system delete helmcharts.helm.cattle.io traefik-crd
kubectl -n kube-system delete helmcharts.helm.cattle.io traefik
```

Check resources are removed
```
kubectl get all -n kube-system | grep tra
```

# Disable in execstart
Edit service file `sudo nano /etc/systemd/system/k3s.service` and add this line to `ExecStart`
```
        '--disable' \
        'traefik' \
```
Reload k3s server

```
sudo systemctl daemon-reload
sudo service k3s start
```
