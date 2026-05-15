# postgres-cluster

The shared HA Postgres backing every app in the cluster — 3 CNPG
instances spread across the 3 Talos nodes, on the
`proxmox-ceph-pool` StorageClass.

Apps add a logical database here instead of running their own Postgres
container. See `databases.yaml` for the existing list.

Requires the operator (`../cloudnative-pg/`) and the Ceph CSI
(`../proxmox-csi/`) to be installed first.

## Apply

```sh
kubectl apply -k .
```

## Connect from an app

```yaml
env:
  - name: POSTGRES_HOST
    value: pg-rw.postgres.svc.cluster.local
  - name: POSTGRES_PORT
    value: "5432"
  - name: POSTGRES_DB
    value: authentik
  - name: POSTGRES_USER
    valueFrom: { secretKeyRef: { name: authentik-db, key: username } }
  - name: POSTGRES_PASSWORD
    valueFrom: { secretKeyRef: { name: authentik-db, key: password } }
```

The CNPG operator auto-publishes three Services in the `postgres`
namespace: `pg-rw` (primary), `pg-ro` (replicas only), `pg-r` (any).

## Add a database

1. Add a `Database` block to `databases.yaml`.
2. Add a matching `roles:` entry under `managed:` in `cluster.yaml`,
   pointing `passwordSecret.name` at a `kubernetes.io/basic-auth` Secret
   in this namespace (CNPG keeps the role password in sync with the
   Secret).
3. Add the role Secret to `secret.enc.yaml` (sops-encrypted, basic-auth
   shape with `username` + `password`). The same `password` value goes
   into the app's runtime Secret so the connection string matches.
4. In the app's directory, drop a `secret.enc.yaml` holding the DB
   password and any other runtime secrets (sops-encrypted, see
   `../authentik/secret.enc.yaml` for shape).
5. Apply: `sops -d secret.enc.yaml | kubectl apply -f -` (this dir's
   role Secret), `kubectl apply -k .`, then
   `sops -d ../<app>/secret.enc.yaml | kubectl apply -f -`.

## Backups

Not configured yet — Ceph 3x replication is the only durability story
right now. Future: add a `Backup` / `ScheduledBackup` CR with a
`barmanObjectStore` pointing at an S3-compatible bucket (e.g. MinIO on
another node, or restic-on-Hetzner).
