# cert-manager deployment for the homelab cluster.
#
# Deployed via the official Helm chart (CRDs included):
#   helm repo add jetstack https://charts.jetstack.io
#   helm install cert-manager jetstack/cert-manager \
#     --namespace cert-manager --create-namespace --set installCRDs=true

## Apply the issuer
# Prereq: the `cloudflare-api-token` Secret (key `api-token`) must exist in the
# `cert-manager` namespace. Provision it (never commit the value):
#   kubectl -n cert-manager create secret generic cloudflare-api-token \
#     --from-literal=api-token=<CF_API_KEY>   # global Cloudflare API key (same as .73 traefik)
#
#   kubectl apply -k k8s/cert-manager

## Wiring into traefik
# Each IngressRoute references a cert-manager-managed cert via `tls.secretName`.
# A Certificate (or automatic cert via `tls.certManager` on the route) requests
# the cert from the 'letsencrypt' ClusterIssuer below using DNS-01 (wildcard-capable
# via a matching Certificate resource).