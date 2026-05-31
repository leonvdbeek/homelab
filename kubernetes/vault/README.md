# vault/

HashiCorp Vault HA on Raft, auto-unsealed via transit against the
single-node Vault in `../vault-unseal/`. Exposed at
`https://vault.lenovium.leonvdbeek.com` via the shared Cilium Gateway.

This Vault holds infrastructure secrets (DB passwords, API tokens, PKI).
End-user password management lives in `../vaultwarden/`.

## Prerequisites

- `../vault-unseal/` is deployed, initialized, unsealed, and has the
  `transit/keys/autounseal` key + `autounseal` policy + orphan token
  created. See `../vault-unseal/README.md` first.
- `proxmox-ceph-pool` StorageClass is available (default for stateful
  workloads — see `../proxmox-csi/`).
- Wildcard cert `wildcard-lenovium-leonvdbeek-com-tls` is published to
  the `gateway` namespace by cert-manager.

## Apply

```sh
# 1. Fill in the transit token from vault-unseal, then encrypt.
cp secret.example.yaml secret.enc.yaml
# edit secret.enc.yaml — paste the orphan token from vault-unseal
sops --encrypt --in-place secret.enc.yaml

# 2. Apply the Secret first, then the chart.
sops -d secret.enc.yaml | kubectl apply -f -
kustomize build --enable-helm . | kubectl apply --server-side -f -
```

## First-time init

Once the first pod is `Running` (it will appear sealed; that's expected
until init runs):

```sh
kubectl -n vault wait pod/vault-0 --for=condition=PodReadyToStartContainers --timeout=120s

# Transit-sealed Vaults use recovery keys, not unseal keys.
kubectl -n vault exec -it vault-0 -- vault operator init \
  -recovery-shares=5 -recovery-threshold=3
```

Save the 5 recovery keys + root token OFFLINE. They are needed only for:
- Generating new root tokens once the bootstrap one expires
- Rekeying / disaster recovery if transit ever fails

The other two pods auto-join the Raft cluster via the `retry_join`
stanzas in `values.yaml`. Verify:

```sh
kubectl -n vault exec -it vault-0 -- vault operator raft list-peers
# should show 3 voters
```

## Day-2

| Action | Command |
| --- | --- |
| Status | `kubectl -n vault exec -it vault-0 -- vault status` |
| Login | `kubectl -n vault exec -it vault-0 -- vault login` (paste root token) |
| Raft peers | `vault operator raft list-peers` |
| Snapshot | `vault operator raft snapshot save /tmp/vault.snap` then `kubectl cp` it off-cluster |
| Rotate transit token | recreate in `vault-unseal`, update `secret.enc.yaml`, `kubectl rollout restart sts/vault` |
| Bump image | edit `values.yaml` `server.image.tag`, re-apply. Roll one pod at a time and confirm `Sealed: false` after each. |

## Snapshot backups (follow-up)

The Raft data is on Ceph (3x replication, durable) but a logical
snapshot is also worth keeping off-cluster. Suggested approach (not yet
implemented):

- CronJob in this namespace that execs `vault operator raft snapshot
  save` and rsyncs the output to the NAS / S3 / object storage of choice.
- Retention: 14 daily, 8 weekly.

Add it as a follow-up rather than blocking the initial bring-up.

## DR notes

If the transit unseal Vault is permanently lost:
1. Stand up a new transit Vault, create a new `autounseal` key
2. From a HA pod: `vault operator seal-rewrap` is NOT enough; you need
   to use the recovery keys: `vault operator generate-root` + rekey
3. Easier in practice: restore the unseal Vault from its PVC backup
   (Ceph replication makes a full loss very unlikely)

If the HA cluster is permanently lost:
1. New cluster, transit-unseal works automatically
2. Restore the latest snapshot: `vault operator raft snapshot restore`
   (needs the original transit key, which is in vault-unseal — so keep
   that Vault alive!)
