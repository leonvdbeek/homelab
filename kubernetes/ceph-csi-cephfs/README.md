# ceph-csi-cephfs/

RWX StorageClass backed by the `homelab` CephFS on the Proxmox-managed
Ceph cluster. Use this for any state multiple pods need to share —
unlike `proxmox-ceph-pool` (RBD, RWO only) which is the right choice
for single-writer workloads like databases.

The driver talks **directly** to the Ceph cluster's mons (192.168.4.79
/.76/.29) using a CephX user, bypassing the Proxmox API. This is a
different code path from `proxmox-csi/` (which provisions RBD images
via the Proxmox API).

## Topology

```
k8s pod ─► ceph-csi-cephfs node DaemonSet (per node)
            │ mount.ceph (kernel client)
            ▼
        homelab CephFS (3 MDS daemons, lenovo-01/02/03)
            │
            ▼
   homelab_data + homelab_metadata RADOS pools (3x replication)
```

## Bootstrap (already done once)

These steps were run on `lenovo-01` to create the FS and the CephX user.
Documented here so you can rebuild from scratch.

```sh
# 1. MDS daemon on each node
ssh lenovo-01 pveceph mds create
ssh lenovo-02 pveceph mds create
ssh lenovo-03 pveceph mds create

# 2. Filesystem + pools
ssh lenovo-01 'pveceph fs create --name homelab --pg_num 32 --add-storage 0'

# 3. CephX user for k8s. Caps are the minimum that lets ceph-csi
#    create / mount subvolumes on the `homelab` FS:
#      - mon "allow r"                      — read cluster map
#      - mgr "allow rw"                     — invoke `fs subvolume *` API
#      - osd "allow rw tag cephfs metadata=homelab,
#             allow rw tag cephfs data=homelab"  — write both pools
#      - mds "allow rw"                     — open file caps on the FS
#
#    fsname-scoped mds/mon caps don't work — ceph-csi's subvolume
#    operations need the broader form.
ssh lenovo-01 'ceph fs authorize homelab client.kubernetes-cephfs / rw'
ssh lenovo-01 'ceph auth caps client.kubernetes-cephfs \
  mon "allow r" \
  mgr "allow rw" \
  osd "allow rw tag cephfs metadata=homelab, allow rw tag cephfs data=homelab" \
  mds "allow rw"'

# 4. Get the key — goes into secret.enc.yaml
ssh lenovo-01 'ceph auth get-key client.kubernetes-cephfs'
```

## Apply

```sh
# 1. Bootstrap the Secret
cp secret.example.yaml secret.enc.yaml
# paste the CephX key into userKey + adminKey
sops --encrypt --in-place secret.enc.yaml

# 2. Apply everything
sops -d secret.enc.yaml | kubectl apply -f -
kustomize build --enable-helm . | kubectl apply --server-side -f -
```

## Verify

```sh
# Driver pods up?
kubectl -n ceph-csi-cephfs get pods

# StorageClass registered?
kubectl get sc proxmox-cephfs

# Smoke test — provision a RWX PVC and consume it from two pods.
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: cephfs-smoketest
  namespace: default
spec:
  accessModes: [ReadWriteMany]
  storageClassName: proxmox-cephfs
  resources:
    requests:
      storage: 1Gi
EOF
kubectl get pvc cephfs-smoketest -w
# wait for Bound, then delete:
kubectl delete pvc cephfs-smoketest
```

The first mount on each node downloads kernel-side dependencies — give
the first PVC ~30s before declaring it broken.

## When to use this StorageClass

| Workload | Use |
| --- | --- |
| Postgres / Vault Raft / Etcd / anything single-writer | `proxmox-ceph-pool` (RBD, RWO) |
| Shared filesystem state (Vaultwarden attachments, NextCloud /data, photo libraries) | `proxmox-cephfs` (RWX) |
| Tiny config that changes once a week | ConfigMap / Secret, not a PV |

## Rotation

To rotate the CephX key:

```sh
ssh lenovo-01 'ceph auth get-or-create-key client.kubernetes-cephfs --gen-key'
# Update secret.enc.yaml with the new key
sops kubernetes/ceph-csi-cephfs/secret.enc.yaml   # edits in-place
sops -d kubernetes/ceph-csi-cephfs/secret.enc.yaml | kubectl apply -f -
# Mounts auto-pick up the new key on the next reconnect (~minutes).
```

## Day-2 trouble

| Symptom | Likely cause |
| --- | --- |
| PVC stuck in `Pending` | provisioner pod can't reach mons — check NetworkPolicy / firewall on the LAN |
| Pod stuck in `ContainerCreating` with mount error | node plugin can't reach mons, or wrong key — `kubectl -n ceph-csi-cephfs logs ds/ceph-csi-cephfs-nodeplugin -c csi-cephfsplugin` |
| `permission denied` on writes | CephX caps regressed — re-run `ceph auth caps` from the bootstrap section |
| Slow first mount | Cold kernel module load — expected, only first time per node per reboot |
