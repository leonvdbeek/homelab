# tailscale

[Tailscale Kubernetes operator](https://tailscale.com/kb/1236/kubernetes-operator)
running two subnet-router replicas that advertise the Cilium LB pool
(`192.168.4.240/28`) onto our tailnet. Public DNS at Cloudflare already
resolves `*.leonvdbeek.com` and `*.lenovium.leonvdbeek.com` to the
Gateway LB IP (`192.168.4.240`), so any tailnet device — phone with
WiFi off, laptop on coffee-shop WiFi — reaches the cluster's HTTP
services on the real hostnames with the real Let's Encrypt cert.

The rest of the LAN stays off-tailnet: only `.240-.255` is advertised.

## One-time setup in the Tailscale admin console

1. **ACL** — merge into your ACL file at
   https://login.tailscale.com/admin/acls/file:
   ```json
   {
     "tagOwners": {
       "tag:k8s-operator": ["autogroup:admin"],
       "tag:k8s":          ["tag:k8s-operator"]
     },
     "autoApprovers": {
       "routes": {
         "192.168.4.240/28": ["tag:k8s"]
       }
     }
   }
   ```
   `tag:k8s-operator` is the operator itself; `tag:k8s` is what
   Connector-spawned subnet routers wear. autoApprovers means
   you never have to click "approve route" in the admin console.

2. **OAuth client** —
   https://login.tailscale.com/admin/settings/oauth → Generate.
   - Scopes: `Devices: Write`, `Auth Keys: Write`
   - Tags this client can apply: `tag:k8s-operator`
   - Save the `client_id` and `client_secret` — Tailscale doesn't
     show them again.

## Apply

```sh
# 1. Drop the OAuth client_id / client_secret into the Secret
sops kubernetes/tailscale/secret.enc.yaml   # paste into stringData
sops -d kubernetes/tailscale/secret.enc.yaml | kubectl apply -f -

# 2. Operator + Connector CRs
kustomize build --enable-helm kubernetes/tailscale/ \
  | kubectl apply --server-side --force-conflicts -f -
```

## Verify

```sh
kubectl -n tailscale get pods
kubectl -n tailscale get connector
```

Then from a tailnet device with WiFi off:

```sh
tailscale status              # should list k8s-operator, k8s-lb-pool-a, k8s-lb-pool-b
dig authentik.lenovium.leonvdbeek.com    # 192.168.4.240
curl https://authentik.lenovium.leonvdbeek.com   # 302 to /flows/...
```

## Rotating the OAuth client

1. Generate a new OAuth client in the admin console with the same
   tag/scopes.
2. `sops kubernetes/tailscale/secret.enc.yaml`, replace the values.
3. `sops -d ... | kubectl apply -f -`
4. The operator pod hot-reloads the secret; nothing to restart.
5. Delete the old OAuth client.
