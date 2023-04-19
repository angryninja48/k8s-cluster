# Velero

!!! note "Work in progress"
This document is a work in progress.

## Install the CLI tool

```sh
brew install velero
```

## Create a backup

Create a backup for all apps:

```sh
velero backup create manually-backup-1 --from-schedule velero-daily-backup
```

Create a backup for a single app:

```sh
velero backup create jackett-test-abc \
    --include-namespaces testing \
    --selector "app.kubernetes.io/instance=jackett-test" \
    --wait
```

## Pause resources

Pause the `HelmRelease`:

```sh
flux suspend hr home-assistant -n home
```

!!! hint "Wait"
Allow the application to be redeployed and create the new resources

Delete the new resources:

```sh
kubectl delete deployment/home-assistant -n home
kubectl delete pvc/home-assistant-config -n home
```

## Restore

```sh
velero restore create \
    --from-backup manually-backup-1 \
    --include-namespaces home \
    --selector "app.kubernetes.io/instance=home-assistant" \
    --wait
```


velero restore create \
    --from-backup velero-daily-backup-20230101040035 \
    --include-namespaces home \
    --selector "app.kubernetes.io/instance=home-assistant" \
    --wait
