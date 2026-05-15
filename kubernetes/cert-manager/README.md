# cert-manager

[cert-manager](https://cert-manager.io/) issues TLS certs for the
cluster. Configured against Let's Encrypt **production** with **DNS-01**
on **Cloudflare** — matches what the existing Traefik on the portainer
host already does, just running in-cluster.

The Cloudflare API token is stored sops-encrypted in `secret.enc.yaml`
and applied out-of-band (kustomize doesn't decrypt on its own).

## Apply

```sh
# 1. The operator + ClusterIssuer + Certificate
kustomize build --enable-helm . \
  | kubectl apply --server-side -f -

# 2. The Cloudflare token (sops-decrypted on the fly)
sops -d secret.enc.yaml | kubectl apply -f -
```

## Verify

```sh
kubectl -n cert-manager get pods
kubectl get clusterissuer letsencrypt -o wide
kubectl -n gateway get certificate wildcard-leonvdbeek-com
kubectl -n gateway describe certificate wildcard-leonvdbeek-com
```

First issuance takes ~1 min while DNS-01 propagates.

## Editing the Cloudflare token

```sh
sops secret.enc.yaml             # opens in $EDITOR; saves re-encrypted
kubectl apply -f <(sops -d secret.enc.yaml)
```

If you need to rotate the Cloudflare token: create the new one in
Cloudflare, `sops secret.enc.yaml`, replace, apply, revoke the old one
in Cloudflare.

## Generating the initial Cloudflare token

1. Cloudflare → My Profile → API Tokens → Create token →
   "Edit zone DNS" template scoped to `leonvdbeek.com`.
2. Copy the token.
3. `sops kubernetes/cert-manager/secret.enc.yaml` → paste into
   `stringData.api-token`, save.
