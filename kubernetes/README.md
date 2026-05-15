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
4. **CloudNativePG operator** —
   `kustomize build --enable-helm cloudnative-pg/ | kubectl apply --server-side -f -`
5. **postgres-cluster** —
   ```sh
   sops -d kubernetes/postgres-cluster/secret.enc.yaml | kubectl apply -f -
   kubectl apply -k postgres-cluster/
   ```
6. **cert-manager**
   ```sh
   kustomize build --enable-helm cert-manager/ | kubectl apply --server-side -f -
   sops -d kubernetes/cert-manager/secret.enc.yaml | kubectl apply -f -
   ```
7. **external-dns**
   ```sh
   kustomize build --enable-helm external-dns/ | kubectl apply --server-side -f -
   sops -d kubernetes/external-dns/secret.enc.yaml | kubectl apply -f -
   ```
8. **authentik**
   ```sh
   kustomize build --enable-helm authentik/ | kubectl apply --server-side -f -
   sops -d kubernetes/authentik/secret.enc.yaml | kubectl apply -f -
   ```

## What each directory is for

| Directory | What it provides |
| --- | --- |
| [`cilium/`](./cilium/) | CNI, kube-proxy replacement, Gateway API impl, LB IPAM, L2 announcements |
| [`gateway-api-crds/`](./gateway-api-crds/) | Upstream Gateway API CRDs (one-shot kubectl apply) |
| [`proxmox-csi/`](./proxmox-csi/) | StorageClass `proxmox-ceph-pool` (Ceph RBD via the CSI plugin) |
| [`csi-test/`](./csi-test/) | Smoke test PVC against `proxmox-ceph-pool` |
| [`cloudnative-pg/`](./cloudnative-pg/) | CNPG operator (Cluster/Database/Pooler CRDs) |
| [`postgres-cluster/`](./postgres-cluster/) | The shared 3-replica Postgres `Cluster` + per-app `Database` CRs |
| [`cert-manager/`](./cert-manager/) | cert-manager + Let's Encrypt + Cloudflare DNS-01 + wildcard cert |
| [`external-dns/`](./external-dns/) | Sync `*.leonvdbeek.com` records to Cloudflare from Gateways and Services |
| [`authentik/`](./authentik/) | SSO + forward-auth, with full config-as-code via blueprints |
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

For sops-encrypted Secrets:

```sh
sops -d secret.enc.yaml | kubectl apply -f -
```

## Editing an encrypted secret

```sh
sops kubernetes/<dir>/secret.enc.yaml
```

`sops` opens the decrypted file in `$EDITOR`, re-encrypts on save. To
print the decrypted contents: `sops -d kubernetes/<dir>/secret.enc.yaml`.
