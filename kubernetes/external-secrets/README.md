# external-secrets/

[External Secrets Operator](https://external-secrets.io/) (ESO). Every
runtime Secret in this cluster — DB passwords, API tokens, CephX keys,
OIDC client secrets — is stored as a kv-v2 entry in Vault and
materialized into a k8s `Secret` by an `ExternalSecret` CR in the
consuming app's namespace.

Exception: `kubernetes/vault/secret.enc.yaml` (the transit-unseal token)
stays sops-encrypted because the HA Vault needs it to boot; pulling it
from itself would be circular.

## What's in here

- `namespace.yaml` — `external-secrets` namespace
- `kustomization.yaml` + `values.yaml` — Helm chart
- `clustersecretstore.yaml` — `ClusterSecretStore/vault-backend` that
  every `ExternalSecret` references via `secretStoreRef`. Authenticates
  to Vault using the ESO controller's ServiceAccount (k8s auth method).

## Vault-side bootstrap (once, before first apply)

Done already on this cluster — documented for reproducibility / DR.

```sh
# 1. Enable KV v2 at kv/ and the kubernetes auth method
kubectl -n vault exec vault-2 -- env VAULT_TOKEN=<root> sh -c '
  vault secrets enable -path=kv kv-v2
  vault auth enable kubernetes
  KUBE_CA=$(cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)
  vault write auth/kubernetes/config \
    kubernetes_host=https://$KUBERNETES_SERVICE_HOST:$KUBERNETES_SERVICE_PORT \
    kubernetes_ca_cert="$KUBE_CA" \
    disable_iss_validation=true
'

# 2. ESO read-only policy + role binding
kubectl -n vault exec -i vault-2 -- env VAULT_TOKEN=<root> sh -c '
  vault policy write external-secrets-reader - <<EOF
path "kv/data/*"     { capabilities = ["read"] }
path "kv/metadata/*" { capabilities = ["read", "list"] }
EOF
  vault write auth/kubernetes/role/external-secrets \
    bound_service_account_names=external-secrets \
    bound_service_account_namespaces=external-secrets \
    policies=external-secrets-reader \
    ttl=24h
'
```

## Apply

```sh
# First pass: install chart (creates CRDs)
kustomize build --enable-helm . | kubectl apply --server-side --force-conflicts -f -

# Wait for webhook
kubectl -n external-secrets wait deploy/external-secrets-webhook \
  --for=condition=Available --timeout=120s

# Second pass: now that the ClusterSecretStore CRD exists, the CR lands
kustomize build --enable-helm . | kubectl apply --server-side --force-conflicts -f -

# Sanity check
kubectl get clustersecretstore vault-backend \
  -o jsonpath='{.status.conditions[0].reason}'
#   Valid
```

The two-pass apply is only needed on first install — once the CRDs are
registered, future applies are single-pass.

## Day-to-day: putting a value into Vault

Vault is the source of truth. To set or rotate a secret:

```sh
# Write the whole kv path at once (replaces all keys at that path)
ROOT=$(echo $VAULT_ROOT_TOKEN)  # or: pass --address+--token to vault CLI
kubectl -n vault exec -i vault-2 -- env VAULT_TOKEN=$ROOT vault kv put \
  -mount=kv authentik/secrets \
    AUTHENTIK_POSTGRESQL__PASSWORD="$(openssl rand -base64 32)" \
    AUTHENTIK_SECRET_KEY="$(openssl rand -base64 48)" \
    AUTHENTIK_BOOTSTRAP_PASSWORD="..." \
    ...

# Or patch a single key (preserves the rest)
kubectl -n vault exec vault-2 -- env VAULT_TOKEN=$ROOT vault kv patch \
  -mount=kv authentik/secrets \
    AUTHENTIK_BOOTSTRAP_PASSWORD="newpassword"

# Force ESO to pick up the change now (default refresh is 1h)
kubectl -n authentik annotate externalsecret authentik-secrets \
  force-sync=$(date +%s) --overwrite
```

## Day-to-day: reading a value from Vault

```sh
ROOT=$(echo $VAULT_ROOT_TOKEN)
kubectl -n vault exec vault-2 -- env VAULT_TOKEN=$ROOT \
  vault kv get -mount=kv authentik/secrets
```

## Path convention

```
kv/<app-name>/<secret-name>
```

| Vault path | Materializes as | Consumer |
| --- | --- | --- |
| `kv/authentik/secrets` | `authentik-secrets` (authentik ns) | authentik chart envFrom |
| `kv/postgres-cluster/authentik-db` | `authentik-db` (postgres ns, basic-auth) | CNPG managed.roles |
| `kv/vaultwarden/db` | `vaultwarden-db` (postgres ns, basic-auth) | CNPG managed.roles |
| `kv/vaultwarden/app` | `vaultwarden-secrets` (vaultwarden ns) | Vaultwarden envFrom |
| `kv/cloudflare/api-token` | `cloudflare-api-token` (cert-manager ns + external-dns ns) | cert-manager + external-dns |
| `kv/ceph-csi-cephfs/csi-cephfs-secret` | `csi-cephfs-secret` (ceph-csi-cephfs ns) | proxmox-cephfs StorageClass |

## Auth model

- One ClusterSecretStore (`vault-backend`) for the whole cluster
- It auths as ESO's controller SA (`external-secrets/external-secrets`)
- That SA's bound Vault role has read on `kv/data/*` — i.e. any ESO
  ExternalSecret in any namespace can read any path.

This is broad — fine for a homelab. To tighten later: split into
per-namespace SecretStore CRs each using its own SA + Vault policy
scoped to that app's path prefix.

## When ESO can't reach Vault

Failure modes you'll see in `kubectl get externalsecret -A`:

| Status | Cause | Fix |
| --- | --- | --- |
| `SecretSyncedError` + `permission denied` | k8s auth role not bound to ESO's SA, or policy missing the path | Re-check role/policy in Vault (see bootstrap section) |
| `SecretSyncedError` + `service unavailable` | HA Vault sealed (all 3 pods Not Ready) | Unseal `vault-unseal-0` (`kubectl -n vault-unseal exec -it vault-unseal-0 -- vault operator unseal`) — HA pods auto-recover |
| Status empty / stuck Pending | ESO controller pod down | `kubectl -n external-secrets get pods` and `logs deploy/external-secrets` |
| `Conflict` adopting existing Secret | Secret has a non-ESO controller owner (e.g. helm) | Set `creationPolicy: Merge` or delete the existing Secret and let ESO recreate |
