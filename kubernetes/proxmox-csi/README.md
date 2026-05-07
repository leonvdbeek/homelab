# proxmox-csi-plugin

[sergelogvinov/proxmox-csi-plugin](https://github.com/sergelogvinov/proxmox-csi-plugin)
gives Kubernetes PVCs backed by Proxmox storage (here: the Ceph RBD pool
`ceph-pool`).

`values.yaml` is the source of truth for the chart's values. Tofu reads
it via `file()` and applies it as part of `tofu apply` — see
`../../tofu/talos/csi.tf`. Edit `values.yaml`, run `tofu apply`. Same
file works unchanged with Flux/Argo when you switch to GitOps later.

The Proxmox API config (URL + token) is rendered into a Secret by Tofu
and consumed via `existingConfigSecret`, so this file has no secrets.

## Verify

```
kubectl -n csi-proxmox get pods
kubectl get sc
kubectl get csidrivers
```

The `proxmox-ceph-pool` StorageClass uses `WaitForFirstConsumer`, so a
PVC only binds once a pod is scheduled.

## Smoke test

See `../csi-test/`.
