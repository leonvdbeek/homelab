# external-dns

Syncs Kubernetes `Gateway` / `HTTPRoute` / `Service` hostnames to
Cloudflare DNS for the `leonvdbeek.com` zone.

The Cloudflare API token is stored sops-encrypted in `secret.enc.yaml`
(same token value as cert-manager's, but a separate Secret object — we
don't share Secrets across namespaces).

## Apply

```sh
# 1. The deployment + RBAC
kustomize build --enable-helm . \
  | kubectl apply --server-side -f -

# 2. The Cloudflare token
sops -d secret.enc.yaml | kubectl apply -f -
```

## Verify

```sh
kubectl -n external-dns logs deploy/external-dns -f
```

Look for lines like `UPDATE foo.leonvdbeek.com 192.168.4.240` after
applying an HTTPRoute that names a `*.leonvdbeek.com` hostname.

## Editing the token

```sh
sops secret.enc.yaml
sops -d secret.enc.yaml | kubectl apply -f -
```
