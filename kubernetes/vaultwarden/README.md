# vaultwarden/

Vaultwarden in k8s, backed by the shared CNPG `pg` cluster, exposed at
`https://vaultwarden.lenovium.leonvdbeek.com`.

This replaces the existing compose-managed instance on the `portainer`
host (`vault.leonvdbeek.com`, SQLite). The migration preserves users,
ciphers, attachments, sends, and the RSA signing key, so every existing
BW client continues to validate sessions and 2FA enrollments after
they're pointed at the new server URL.

## HA shape

True 2-replica HA. The whole stack is multi-writer safe:

| State | Where | Concurrency |
| --- | --- | --- |
| Users, ciphers, orgs, 2FA secrets, sends metadata | CNPG `pg` cluster | DB-level locks |
| Attachment + send blobs, icon cache, RSA signing key | RWX CephFS PVC (`proxmox-cephfs`) | POSIX, both pods mount the same path |

Any client request can land on any pod. Node loss reschedules; rolling
upgrades are zero-downtime (`maxSurge: 1, maxUnavailable: 0`).

## Prerequisites

- `../postgres-cluster/` is deployed and `Database/vaultwarden` exists
  (added to `../postgres-cluster/databases.yaml`).
- The matching `vaultwarden` role is declared in `cluster.yaml`'s
  `managed.roles` and the `vaultwarden-db` Secret it references is
  applied to the `postgres` namespace.
- `../ceph-csi-cephfs/` is deployed and `proxmox-cephfs` StorageClass
  is healthy.
- The wildcard cert `wildcard-lenovium-leonvdbeek-com-tls` is published
  to the `gateway` namespace by cert-manager.

## Apply

```sh
# 1. Make sure the Vault paths exist with the expected keys.
#    Generate values if first deploy:
ROOT=<vault-root-token>
kubectl -n vault exec -i vault-2 -- env VAULT_TOKEN=$ROOT vault kv put \
  -mount=kv vaultwarden/db \
    username=vaultwarden \
    password=$(openssl rand -base64 32 | tr -d '=+/' | cut -c1-32)
kubectl -n vault exec -i vault-2 -- env VAULT_TOKEN=$ROOT vault kv put \
  -mount=kv vaultwarden/app \
    VW_DB_PASSWORD=<same-password-as-above> \
    ADMIN_TOKEN=$(openssl rand -base64 48)

# 2. Re-apply postgres-cluster so CNPG picks up the role + Database CRs,
#    and ESO materializes vaultwarden-db.
kubectl apply -k ../postgres-cluster/
kubectl -n postgres wait database/vaultwarden --for=condition=Ready --timeout=60s

# 3. Apply this kustomization. ESO materializes vaultwarden-secrets.
kubectl apply -k .
```

## Verify the empty deploy

```sh
kubectl -n vaultwarden get pods   # 2× Running
kubectl -n vaultwarden logs deploy/vaultwarden --tail=50
# look for: "Rocket has launched from http://0.0.0.0:8080"

# Outside the cluster
curl -s https://vaultwarden.lenovium.leonvdbeek.com/alive
# → empty 200 OK
```

At this point the new instance is a *blank* Vaultwarden — no users yet.
Don't log in or create accounts. Proceed to the migration runbook.

## Migration runbook (SQLite → Postgres, CephFS-aware)

Run from your workstation:

```sh
# 1. Quiesce the source so SQLite is consistent on disk.
ssh portainer 'cd /home/leon/portainer/vaultwarden && docker compose stop'

# 2. Pull the data dir down.
mkdir -p /tmp/vw-migrate
rsync -av portainer:/home/leon/portainer/vaultwarden/vw-data/ /tmp/vw-migrate/

# 3. Scale to 0 so migrations don't race the file copy.
kubectl -n vaultwarden scale deployment/vaultwarden --replicas=0

# 4. Throwaway pgloader pod with cluster-internal network access.
kubectl -n vaultwarden run vw-pgloader \
  --image=dimitri/pgloader:latest \
  --restart=Never \
  --command -- sleep 7200

# 5. Copy the SQLite file in.
kubectl -n vaultwarden cp /tmp/vw-migrate/db.sqlite3 vw-pgloader:/tmp/db.sqlite3

# 6. Run the migration. The password is in the live k8s Secret that
#    ESO materialized from Vault — read it back at run time.
PG_PW=$(kubectl -n vaultwarden get secret vaultwarden-secrets \
        -o jsonpath='{.data.VW_DB_PASSWORD}' | base64 -d)
kubectl -n vaultwarden exec vw-pgloader -- pgloader \
  --with "quote identifiers" \
  --with "data only" \
  sqlite:///tmp/db.sqlite3 \
  "postgresql://vaultwarden:${PG_PW}@pg-rw.postgres.svc.cluster.local:5432/vaultwarden"

kubectl -n vaultwarden delete pod vw-pgloader

# 7. Copy the data files (RSA key, attachments, sends) onto the shared
#    CephFS PVC. The PVC isn't mounted right now (replicas=0), so we
#    attach it briefly to a one-shot helper pod.
cat <<'EOF' | kubectl apply -f -
apiVersion: v1
kind: Pod
metadata:
  name: vw-data-loader
  namespace: vaultwarden
spec:
  restartPolicy: Never
  containers:
    - name: shell
      image: alpine:3.20
      command: ["sh", "-c", "sleep 600"]
      volumeMounts:
        - name: data
          mountPath: /data
  volumes:
    - name: data
      persistentVolumeClaim:
        claimName: vaultwarden-data
EOF
kubectl -n vaultwarden wait pod/vw-data-loader --for=condition=Ready --timeout=60s

# Clear any junk Vaultwarden auto-created on a prior run, then load.
kubectl -n vaultwarden exec vw-data-loader -- sh -c 'rm -rf /data/*'
kubectl -n vaultwarden cp /tmp/vw-migrate/rsa_key.pem  vw-data-loader:/data/rsa_key.pem
kubectl -n vaultwarden cp /tmp/vw-migrate/attachments  vw-data-loader:/data/
kubectl -n vaultwarden cp /tmp/vw-migrate/sends        vw-data-loader:/data/
# icon_cache is regenerable; skip it.
kubectl -n vaultwarden exec vw-data-loader -- ls -la /data
kubectl -n vaultwarden delete pod vw-data-loader

# 8. Scale up.
kubectl -n vaultwarden scale deployment/vaultwarden --replicas=2
kubectl -n vaultwarden wait deployment/vaultwarden --for=condition=Available --timeout=180s

# 9. Verify a real login works.
# Open https://vaultwarden.lenovium.leonvdbeek.com in incognito, sign in as
# an existing user with the SAME master password as on portainer.
# Entries should decrypt (proves rsa_key + DB are intact).
# 2FA TOTP codes should validate (proves migrated TOTP secrets).
```

## Cutover

Bitwarden clients store the server URL per-account. **Each device has
to log out and re-add the new URL.** This includes browser extensions,
desktop apps, and mobile apps for every user.

Communicate the URL change ahead of time:

> Server URL: https://vaultwarden.lenovium.leonvdbeek.com
> (was: https://vault.leonvdbeek.com)

After all clients have moved over and validated logins:

```sh
ssh portainer 'cd /home/leon/portainer/vaultwarden && docker compose down'
# Leave the data on disk for ~1 week as a rollback safety net, then
# rm -rf /home/leon/portainer/vaultwarden when you're confident.
```

The old `vault.leonvdbeek.com` DNS / Traefik route can be removed
whenever convenient — nothing in this repo references it after cutover.

## Day-2

| Action | How |
| --- | --- |
| Admin UI | `https://vaultwarden.lenovium.leonvdbeek.com/admin` (use `ADMIN_TOKEN`) |
| Bump version | edit `deployment.yaml` `image:`, re-apply `kubectl apply -k .` |
| Rotate DB password | edit `secret.enc.yaml` (both Secrets — must match), re-apply, `kubectl rollout restart deploy/vaultwarden` |
| Rotate RSA key | **don't** unless you accept every user re-logging in everywhere |
| Restore from DB backup | `kubectl -n postgres cnpg restore ...` then bounce vaultwarden |

## Migration completeness check

Compare row counts SQLite → Postgres for the major tables:

```sh
# Source:
sqlite3 /tmp/vw-migrate/db.sqlite3 \
  "select 'users', count(*) from users
   union all select 'ciphers', count(*) from ciphers
   union all select 'organizations', count(*) from organizations
   union all select 'attachments', count(*) from attachments
   union all select 'sends', count(*) from sends;"

# Destination:
kubectl -n postgres exec -it pg-1 -- psql -U vaultwarden -d vaultwarden -c \
  "select 'users', count(*) from users
   union all select 'ciphers', count(*) from ciphers
   union all select 'organizations', count(*) from organizations
   union all select 'attachments', count(*) from attachments
   union all select 'sends', count(*) from sends;"
```

Numbers should match exactly. Spot-check at least one 2FA-enabled
account by signing in and validating a TOTP code.
