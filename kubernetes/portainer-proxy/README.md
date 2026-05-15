# portainer-proxy

Cluster-side reverse proxy that exposes the portainer/Traefik services
under a parallel `*.lenovium.leonvdbeek.com` namespace. The original
`*.leonvdbeek.com` URLs keep working for everyone (phones, friends,
external integrations); the `*.lenovium` URLs are reachable only via
Tailscale and never see the company VPN.

| Public hostname (existing) | Tailscale-private hostname (new) |
| --- | --- |
| `vault.leonvdbeek.com` | `vault.lenovium.leonvdbeek.com` |
| `grafana.leonvdbeek.com` | `grafana.lenovium.leonvdbeek.com` |
| `nextcloud.leonvdbeek.com` | `nextcloud.lenovium.leonvdbeek.com` |
| … any first-level subdomain works | … |

Both hostnames hit the same backend service running on portainer; the
only difference is the network path.

## How it works

```
laptop                                 cluster (.240)               portainer (.73)
  │  https://vault.lenovium...           │                            │
  ├──── tailscale tunnel ────────────────►                            │
  │                                  Gateway terminates TLS           │
  │                                  with *.lenovium cert             │
  │                                      │                            │
  │                                  HTTPRoute matches                │
  │                                  *.lenovium.leonvdbeek.com        │
  │                                      │ HTTP                       │
  │                                  nginx pod                        │
  │                                  - regex-captures `vault`         │
  │                                  - rewrites Host: vault.leon…     │
  │                                  - SNI = vault.leon…              │
  │                                      ├──── LAN HTTPS ──────────────►
  │                                      │                       Traefik
  │                                      │                       routes by Host
  │                                      ◄──── HTTP 200 ───────────────┤
  ◄──────────────────────────────────────┤                            │
```

- `kubernetes/cilium/gateway.yaml`'s `https-lenovium` listener
  terminates TLS with the `*.lenovium.leonvdbeek.com` cert from
  cert-manager.
- A single wildcard `HTTPRoute` (`httproute.yaml`) attaches to that
  listener and forwards to an in-cluster `nginx` Service.
- The `nginx` Deployment runs a tiny config (`deployment.yaml`) that
  uses a regex `server_name` to capture the first label, rewrites the
  `Host` header to `<svc>.leonvdbeek.com`, sets matching SNI, and
  proxies to portainer's Traefik on `192.168.4.73:443`.
- Traefik on portainer routes by `Host` header — same as for the
  public URLs — and serves the underlying app.

We landed on nginx-in-the-middle because Cilium 1.16's Gateway
`URLRewrite`/`RequestHeaderModifier` filters didn't actually mutate
the Host header when the backend is HTTPS via `BackendTLSPolicy`.
The earlier per-service HTTPRoute + URLRewrite approach is in git
history (`git show $(git log --diff-filter=D --format=%h -1 -- httproutes.yaml)`)
if Cilium ever fixes it and we want to revert.

## Apply

```sh
kubectl apply -k kubernetes/portainer-proxy/
```

## Verify

From a Tailscale-connected client:

```sh
curl -kI https://vault.lenovium.leonvdbeek.com    # → 200/302
curl -kI https://grafana.lenovium.leonvdbeek.com  # → 302 to login
curl -kI https://portainer.lenovium.leonvdbeek.com # → 200
```

In a browser: open `https://<any-svc>.lenovium.leonvdbeek.com`. The
cert chain is `*.lenovium.leonvdbeek.com` (Let's Encrypt, via the
cluster's cert-manager).

## Specific routes win over the wildcard

If a service moves from portainer to the cluster proper, add a
specific HTTPRoute in its own namespace with hostname
`<svc>.lenovium.leonvdbeek.com`. Gateway API's matching rules pick
the more specific hostname over the wildcard, so the proxy stops
catching that name automatically. Then decommission the portainer
copy.

`authentik.lenovium.leonvdbeek.com` already works this way — see
`kubernetes/authentik/httproute.yaml`.

## Adding a service

Nothing to do here — any `<new>.lenovium.leonvdbeek.com` works the
moment portainer's Traefik has a router for `<new>.leonvdbeek.com`.
