# TrueNAS CSI (iSCSI) storage for the Talos cluster.
# Durable, rebuild-surviving RWO block volumes on the `fast` pool (zvols under
# fast/k8s/iscsi/). Used for stateful DBs & app data (Wave A+).

## Install
Chart + instructions: github.com/truenas/truenas-csi (official).
```sh
# 1. Secret with the TrueNAS API key (value NOT committed; provision via secretspec):
kubectl -n truenas-csi create secret generic truenas-csi-api-key \
  --from-literal=api-key=<TRUENAS_API_KEY>

# 2. Deploy the driver (chart from the repo's charts/ dir):
helm install truenas-csi charts/truenas-csi \
  -n truenas-csi --create-namespace -f values.yaml
```

## StorageClass
`truenas-iscsi-fast` (default) — iSCSI on pool `fast`, thin zvols under
`fast/k8s/iscsi/<pvc>`, LZ4, expandable. WaitForFirstConsumer.

## Notes / requirements
- iSCSI needs the `open-iscsi` initiator on worker nodes (Talos ships it).
- TrueNAS API key scoped to `truenas_admin`; values in `values.yaml` reference the
  managed Secret `truenas-csi-api-key` (key `api-key`) so the key never hits git.