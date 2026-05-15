# cloudnative-pg

[CloudNativePG](https://cloudnative-pg.io/) operator — provides the
`Cluster`, `Pooler`, `Backup` and `ScheduledBackup` CRDs that the actual
Postgres clusters use.

The operator itself lives here. The shared Postgres cluster instance is
defined separately in `../postgres-cluster/` (so cluster-bump/restore
operations don't drag the operator with them).

## Apply

```sh
kustomize build --enable-helm . \
  | kubectl apply --server-side --force-conflicts -f -
```

`--server-side` is needed because the CRDs are large.

## Verify

```sh
kubectl -n cnpg-system get pods
kubectl get crd | grep cnpg.io
```
