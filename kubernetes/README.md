# kubernetes/

In-cluster manifests for the Talos cluster. Every directory here is a
single kustomization that you apply with one `kubectl apply -k .` (or
`kustomize build --enable-helm . | kubectl apply -f -` for the helm-
backed ones). Runtime secrets live next to each component as
`secret.enc.yaml`, sops-encrypted with the age recipient declared in
`../.sops.yaml`.

## One-time SOPS bootstrap

Anyone applying these manifests needs the age **private** key. Mine
lives at `~/.config/sops/age/keys.txt`, which is where sops looks by
default.

```sh
# Install sops + age locally
brew install sops age

# If you don't already have a key:
mkdir -p ~/.config/sops/age && age-keygen -o ~/.config/sops/age/keys.txt
# Then add the printed *public* key to ../.sops.yaml as a recipient
# and run `sops updatekeys kubernetes/<dir>/secret.enc.yaml` per file.
```

## Secrets model

All runtime secrets (DB passwords, API tokens, CephX keys, OIDC client
secrets) live in **Vault** under `kv/<app>/<name>`, and are pulled into
k8s `Secret`s on demand by **External Secrets Operator (ESO)** via
`ExternalSecret` CRs in each app's namespace.

The exception is `vault/secret.enc.yaml` — the transit-unseal token
the HA Vault needs to boot. It's sops-encrypted because Vault can't
fetch its own bootstrap key from itself.

To rotate any other secret:

```sh
kubectl -n vault exec -i vault-2 -- env VAULT_TOKEN=<root> \
  vault kv patch -mount=kv <app>/<name> KEY=newvalue
# (ESO refreshes within 1h; force-sync with the annotation trick in
#  kubernetes/external-secrets/README.md)
```

## Bring-up order

Dependencies run deep. Stick to the order below the first time;
re-applies later are order-independent.

1. **Gateway API CRDs first** — see `gateway-api-crds/README.md`.
   Cilium's chart fails its preflight check if the CRDs aren't there
   before `tofu apply`. Use the **experimental** release (TLSRoute is
   required by Cilium 1.16+, and that CRD only lives in experimental).
2. **CNI swap to Cilium** — `tofu -chdir=../tofu/talos apply`
   - Patches Talos: VIP for kube-apiserver, Flannel + kube-proxy off,
     adds the cluster VIP to `apiServer.certSANs`, pins the Talos
     factory installer image so extensions survive upgrades.
   - Installs Cilium via helm (values in `cilium/values.yaml`).
   - After apply: delete the stale Flannel + kube-proxy DaemonSets and
     roll any unmanaged pods. See `cilium/README.md`.
3. **cilium post-install** — `kubectl apply -k cilium/`
   (LB IP pool, L2 announcement policy, shared Gateway)

   At this point the cluster has networking + a Gateway but no secrets
   plumbing. The next four steps stand up the secrets foundation —
   Vault, then ESO — so the rest of the apps can pull from Vault on
   first apply.

4. **vault-unseal** — single-node Vault hosting the `transit` engine
   that auto-unseals the HA cluster. Read `vault-unseal/README.md` for
   the init + transit-bootstrap steps; you'll come out the other side
   with a periodic orphan token to drop into `vault/secret.enc.yaml`.
   ```sh
   kustomize build --enable-helm vault-unseal/ \
     | kubectl apply --server-side -f -
   ```
5. **vault** — 3-replica HA Vault on Raft. Auto-unsealed via transit
   against vault-unseal. The committed `secret.enc.yaml` carries a
   PLACEHOLDER transit token — replace it with the real orphan token
   from step 4 before applying.
   ```sh
   sops -d kubernetes/vault/secret.enc.yaml | kubectl apply -f -
   kustomize build --enable-helm vault/ \
     | kubectl apply --server-side -f -
   # Then `vault operator init -recovery-shares=5 -recovery-threshold=3`
   # inside vault-0. Save the recovery keys + root token offline.
   ```
6. **Bootstrap Vault for ESO** — see
   `external-secrets/README.md` "Vault-side bootstrap" section. Enables
   kv-v2 at `kv/`, kubernetes auth, ESO read policy + role.
7. **external-secrets** — ESO + ClusterSecretStore.
   ```sh
   # First pass: install chart (registers CRDs)
   kustomize build --enable-helm external-secrets/ \
     | kubectl apply --server-side --force-conflicts -f -
   kubectl -n external-secrets wait deploy/external-secrets-webhook \
     --for=condition=Available --timeout=120s
   # Second pass: now ClusterSecretStore CR lands
   kustomize build --enable-helm external-secrets/ \
     | kubectl apply --server-side --force-conflicts -f -
   ```
8. **Seed every app's secret path in Vault**. The previous deploy run
   used these paths; if rebuilding from scratch, populate them with
   real values now (per-app expected keys are in `external-secrets/README.md`).
9. **CloudNativePG operator** —
   `kustomize build --enable-helm cloudnative-pg/ | kubectl apply --server-side -f -`
10. **postgres-cluster** —
    ```sh
    kubectl apply -k postgres-cluster/
    # ESO materializes authentik-db + vaultwarden-db Secrets; CNPG then
    # reconciles roles + databases from them.
    ```
11. **cert-manager**
    ```sh
    kustomize build --enable-helm cert-manager/ \
      | kubectl apply --server-side -f -
    # ESO materializes cloudflare-api-token from kv/cloudflare/api-token.
    ```
12. **external-dns**
    ```sh
    kustomize build --enable-helm external-dns/ \
      | kubectl apply --server-side -f -
    ```
13. **authentik**
    ```sh
    kustomize build --enable-helm authentik/ \
      | kubectl apply --server-side -f -
    ```
14. **ceph-csi-cephfs** — RWX StorageClass `proxmox-cephfs` backed by
    the `homelab` CephFS. The Proxmox-side bootstrap (MDS daemons,
    `pveceph fs create`, CephX user) is documented in
    `ceph-csi-cephfs/README.md` and only needs to be done once per
    cluster.
    ```sh
    kustomize build --enable-helm ceph-csi-cephfs/ \
      | kubectl apply --server-side -f -
    ```
15. **vaultwarden** — 2-replica Deployment on a shared CephFS PVC at
    `vaultwarden.lenovium.leonvdbeek.com`. The migration runbook
    (SQLite → Postgres from the portainer compose stack) lives in
    `vaultwarden/README.md`.
    ```sh
    kubectl apply -k vaultwarden/
    ```

## What each directory is for

| Directory | What it provides |
| --- | --- |
| [`cilium/`](./cilium/) | CNI, kube-proxy replacement, Gateway API impl, LB IPAM, L2 announcements |
| [`gateway-api-crds/`](./gateway-api-crds/) | Upstream Gateway API CRDs (one-shot kubectl apply) |
| [`proxmox-csi/`](./proxmox-csi/) | StorageClass `proxmox-ceph-pool` (Ceph RBD via the CSI plugin) |
| [`ceph-csi-cephfs/`](./ceph-csi-cephfs/) | StorageClass `proxmox-cephfs` (RWX CephFS via upstream ceph-csi, talks directly to mons) |
| [`csi-test/`](./csi-test/) | Smoke test PVC against `proxmox-ceph-pool` |
| [`cloudnative-pg/`](./cloudnative-pg/) | CNPG operator (Cluster/Database/Pooler CRDs) |
| [`postgres-cluster/`](./postgres-cluster/) | The shared 3-replica Postgres `Cluster` + per-app `Database` CRs |
| [`cert-manager/`](./cert-manager/) | cert-manager + Let's Encrypt + Cloudflare DNS-01 + wildcard cert |
| [`external-dns/`](./external-dns/) | Sync `*.leonvdbeek.com` records to Cloudflare from Gateways and Services |
| [`authentik/`](./authentik/) | SSO + forward-auth, with full config-as-code via blueprints |
| [`vault-unseal/`](./vault-unseal/) | Single-node Vault hosting the `transit` key used to auto-unseal the HA cluster. Cluster-internal only. |
| [`vault/`](./vault/) | 3-replica HA Vault on Raft, transit-unsealed. Source of truth for all runtime secrets. |
| [`external-secrets/`](./external-secrets/) | ESO + ClusterSecretStore: materializes k8s `Secret`s on demand from Vault `kv/<app>/*` paths. |
| [`vaultwarden/`](./vaultwarden/) | Vaultwarden (Bitwarden-compatible password manager) on CNPG. Migrated from portainer compose stack. |
| [`kube-prometheus-stack/`](./kube-prometheus-stack/) | In-cluster Prometheus (scraped by the central Grafana on portainer) |

## Apply pattern

For directories that include a `helmCharts:` field:

```sh
kustomize build --enable-helm . \
  | kubectl apply --server-side --force-conflicts -f -
```

`--server-side` is needed for any chart with CRDs because the rendered
manifest is larger than the client-side annotation limit.

For directories without helm:

```sh
kubectl apply -k .
```

For runtime secrets — see `external-secrets/README.md`. Short version:

```sh
# read
kubectl -n vault exec vault-2 -- env VAULT_TOKEN=<root> \
  vault kv get -mount=kv <app>/<name>

# rotate one key
kubectl -n vault exec -i vault-2 -- env VAULT_TOKEN=<root> \
  vault kv patch -mount=kv <app>/<name> KEY=newvalue

# nudge ESO to sync now instead of waiting for the 1h refresh
kubectl -n <app-ns> annotate externalsecret <name> \
  force-sync=$(date +%s) --overwrite
```

For the one remaining sops file (`vault/secret.enc.yaml`, transit
token — bootstrap-only):

```sh
sops -d kubernetes/vault/secret.enc.yaml | kubectl apply -f -
sops kubernetes/vault/secret.enc.yaml      # edit in $EDITOR, re-encrypts on save
```

