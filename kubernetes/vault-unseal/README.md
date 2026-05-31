# vault-unseal/

A single-replica HashiCorp Vault whose only purpose is to host a `transit`
key that the HA Vault (`../vault/`) uses for auto-unseal. Cluster-internal
only — no HTTPRoute, no public DNS.

The HA cluster cannot start sealed pods on its own (Raft + Shamir would
need a human at every pod restart). With transit auto-unseal, you only
ever unseal **this** Vault by hand, and only after a full power-loss
event. Pod restarts on the HA side (image upgrades, evictions, drains)
are automatic.

## Apply

```sh
kustomize build --enable-helm . | kubectl apply --server-side -f -
```

## First-time init (once, ever)

```sh
# Wait for the pod
kubectl -n vault-unseal wait pod/vault-unseal-0 --for=condition=Ready --timeout=120s

# Initialize — 5 keys, threshold 3. Save the printed output OFFLINE
# (1Password, paper, anywhere not in this repo). You cannot recover
# without these.
kubectl -n vault-unseal exec -it vault-unseal-0 -- vault operator init \
  -key-shares=5 -key-threshold=3
```

Output gives you 5 unseal keys + 1 initial root token. Stash them now.

## Day-2: unseal after a power-on

```sh
# Repeat 3 times, supplying a different unseal key each time.
kubectl -n vault-unseal exec -it vault-unseal-0 -- vault operator unseal
kubectl -n vault-unseal exec -it vault-unseal-0 -- vault operator unseal
kubectl -n vault-unseal exec -it vault-unseal-0 -- vault operator unseal

# Verify
kubectl -n vault-unseal exec -it vault-unseal-0 -- vault status
#   Sealed   false
```

## Bootstrap the transit engine (once, after first init)

```sh
kubectl -n vault-unseal exec -it vault-unseal-0 -- /bin/sh
# inside the pod:
export VAULT_ADDR=http://127.0.0.1:8200
vault login                 # paste the root token

vault secrets enable transit
vault write -f transit/keys/autounseal

# Policy that grants exactly the two operations needed for transit unseal.
vault policy write autounseal - <<'EOF'
path "transit/encrypt/autounseal" { capabilities = ["update"] }
path "transit/decrypt/autounseal" { capabilities = ["update"] }
EOF

# Long-lived periodic orphan token — the HA cluster uses this to call
# transit. Save the output token — it goes into ../vault/secret.enc.yaml.
vault token create -policy=autounseal -orphan -period=24h
```

The `period=24h` means the token auto-renews indefinitely as long as
something keeps using it (the HA Vault pods do). If you ever rotate it,
update `../vault/secret.enc.yaml` and roll the HA pods.

## Snapshots

File storage is on `proxmox-ceph-pool` (3x Ceph replication) so the data
itself is safe. There is intentionally no off-cluster backup of the
unseal Vault — re-initializing is acceptable in the worst case, since
losing the transit key only means the HA Vault has to be rekeyed using
its recovery keys.

## Why no HA here

The unseal Vault has no continuous workload — the HA pods only call
`transit/decrypt/autounseal` on boot, which is a single round-trip.
Running 3 replicas of this would 3x the manual unseal burden on each
power loss for zero availability benefit (Raft auto-unseal still
depends on a quorum of unseal-vault replicas being unsealed).
