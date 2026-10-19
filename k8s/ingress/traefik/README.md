# Traefik ingress (cluster: homelab)

In-cluster Traefik v3 ingress controller for the Talos cluster, replacing the
docker-host `.73` traefik.

- `hostNetwork: true` so it binds 80/443 on the node IP **and** the Talos VIP
  (`192.168.4.60`) directly — no LoadBalancer/kube-vip needed on a single node.
- TLS via Cloudflare **DNS-01** ACME resolver (`le`), reusing the docker-host
  Cloudflare API key. Certs stored in `/data/acme.json` (emptyDir; will move to
  durable PV later).
- Per-service routing is via Traefik `IngressRoute` CRDs (no file provider).

## Prereqs
The `cf-dns` Secret (keys `CF_API_KEY`, `CF_API_EMAIL`) must exist in the
`traefik` namespace **before** apply — it is NOT committed; provision via
secretspec/Bitwarden (same creds the `.73` traefik uses).

## Apply
```sh
kubectl kustomize k8s/ingress/traefik | kubectl apply -f -
# or
kubectl apply -k k8s/ingress/traefik
```

## Notes
- Runs in namespace `traefik`, labeled `pod-security.kubernetes.io/enforce=privileged`
  (required: hostNetwork is disallowed by the Talos `baseline` policy).
- Renames `k8s/ingress/` prefix-per-concern for separate MRs (storage, wave A/B/...).