# authentik

[Authentik](https://goauthentik.io/) running against the shared CNPG
Postgres cluster, with all customisations expressed as **blueprints**
checked into `blueprints/`. Runtime secrets (DB password, secret_key,
bootstrap admin password, per-app OIDC client secrets) live
sops-encrypted in `secret.enc.yaml`.

## Layout

| File | Purpose |
| --- | --- |
| `values.yaml` | helm chart values; points at the shared CNPG and turns on blueprints |
| `secret.enc.yaml` | sops-encrypted `Secret` (DB password, secret_key, OIDC client secrets, …) |
| `httproute.yaml` | `HTTPRoute` exposing `authentik.leonvdbeek.com` on the shared Gateway |
| `blueprints/brand.yaml` | Brand: "Léon's hosting" |
| `blueprints/groups.yaml` | `authentik Admins`, `authentik Read-only`, `public services` |
| `blueprints/proxy-outpost.yaml` | Forward-auth proxy provider + embedded outpost |
| `blueprints/apps-oidc.yaml` | OIDC providers + applications for Grafana, Nextcloud, immich, lenovium, portainer, proxmox |

The kustomization glues every `blueprints/*.yaml` into a single
`authentik-blueprints` ConfigMap that the chart mounts at
`/blueprints/local/`.

## Prerequisites

1. Postgres operator + shared cluster up — `kubernetes/cloudnative-pg/`
   and `kubernetes/postgres-cluster/`.
2. Gateway + cert-manager + ExternalDNS up.
3. Real values pasted into `secret.enc.yaml`. Pull existing OIDC client
   secrets from the running Authentik:
   ```sh
   ssh portainer 'docker exec authentik-postgresql-1 psql -U authentik -d authentik \
     -c "SELECT p.name, op.client_secret FROM \
         authentik_providers_oauth2_oauth2provider op \
         JOIN authentik_core_provider p ON op.provider_ptr_id=p.id;"'
   ```
   Then `sops secret.enc.yaml`, paste each into the matching
   `AUTHENTIK_<APP>_CLIENT_SECRET` key.

## Apply

```sh
# 1. ns + helm release + blueprints ConfigMap + HTTPRoute
kustomize build --enable-helm . \
  | kubectl apply --server-side -f -

# 2. The runtime Secret
sops -d secret.enc.yaml | kubectl apply -f -
```

## Verify

```sh
kubectl -n authentik get pods
kubectl -n authentik get httproute authentik
kubectl -n authentik logs deploy/authentik-server -f
```

In the Authentik admin UI → System → Blueprints, every file in
`blueprints/` should show up as `successful`. After applying the
blueprint there's no manual click-through: the proxy provider, the
outpost, the OIDC providers and the applications are all created.

## Migrating from the old instance

We picked **"export blueprints + fresh DB"**, so the new instance
starts empty and the blueprints repopulate it. What's lost vs. a
`pg_dump` restore:
- **User accounts** (except the bootstrap `akadmin` + anyone you add
  back by hand). You can re-add users or wire up an LDAP/OIDC source.
- **Sessions and consents** — users sign in once more.
- **Audit / event history.**

Everything else (apps, providers, flows, outpost, brand, groups) is
recreated structurally identical, so existing OIDC clients keep
working **provided the OIDC client secrets in `secret.enc.yaml` match
what those clients already have**.
