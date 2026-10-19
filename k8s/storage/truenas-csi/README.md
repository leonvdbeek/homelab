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

## iSCSI port (important)
The TrueNAS iSCSI listener runs on **3261**, NOT the standard 3260: `proxmox-nvme`
(NVMe-oF) already owns 192.168.4.111:3260, so iSCSI was moved to 3261 to avoid the
serverside port collision. Keep the driver's `iscsiPortal` and the TrueNAS iSCSI
`listen_port` in agreement.

## StorageClass
`truenas-iscsi-fast` (default) — iSCSI on pool `fast`, thin zvols under
`fast/k8s/iscsi/<pvc>`, LZ4, expandable. WaitForFirstConsumer.

## Notes / requirements
- iSCSI needs the `open-iscsi` initiator on worker nodes (Talos ships it).
- TrueNAS API key scoped to `truenas_admin`; values in `values.yaml` reference the
  managed Secret `truenas-csi-api-key` (key `api-key`) so the key never hits git.