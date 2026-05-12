# Observability stack

Central Prometheus + Grafana for the homelab, running on the portainer
host (192.168.4.73). Replaces the older Portainer-managed `prometheus`
and `grafana` stacks; reuses both data volumes so history is preserved.

## What this stack scrapes

- **Itself + Traefik + cAdvisor** on the portainer docker host
- **node_exporter** on every PVE host + portainer (`:9100`)
- **pve-exporter** on lenovo-01 only — fanned out to all 3 PVE nodes via
  `?target=...` (`:9221`)
- **Ceph mgr** on every PVE node (only the active mgr answers; `:9283`)

K8s metrics live in a separate Prometheus inside the Talos cluster (see
[`../../kubernetes/kube-prometheus-stack/`](../../kubernetes/kube-prometheus-stack/)).
Grafana has both Prometheus instances configured as datasources, so K8s
dashboards query the in-cluster one directly.

## Layout

```
docker-compose.yml             # prom + grafana (proxy network, traefik labels)
.env                           # gitignored — bootstrapped from the running grafana on first deploy
prometheus/prometheus.yml      # scrape config
grafana/provisioning/          # Grafana datasources + dashboard provider
grafana/dashboards/*.json      # checked-in dashboard sources
```

## Deploy / re-sync

```sh
cd ansible
set -a; source ../.env; set +a
ansible-playbook playbooks/site.yml --tags observability
```

The role syncs this directory to `portainer:/home/leon/portainer/observability/`
(excluding `.env`), tears down the legacy single-stack containers if they
still exist, runs `docker compose -p observability up -d`, and waits for
both services to be healthy. Idempotent.

## Adding a dashboard

Drop a JSON file in `grafana/dashboards/`. Grafana's provisioner picks it
up within 30 s (no restart needed). Make sure the dashboard's panels point
to the right datasource UID:

- `prometheus` for the central Prom (PVE / Ceph / hosts)
- `prometheus-k8s` for the in-cluster Prom (K8s)
