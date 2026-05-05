# `base` role

Applied to every PVE host. Composed of a set of independently-idempotent task files included from `tasks/main.yml`. Run on demand to refresh state, or on a schedule via cron / systemd / GitHub Actions.

## Current task files

| File | What it does |
|---|---|
| `tasks/netbox-register.yml` | Register/refresh the host as a Device in NetBox — manufacturer, device-type, custom fields (CPU/RAM/BIOS), interfaces with MACs, primary IPv4, disks as inventory items. |

## Adding new functionality

Drop a new `tasks/<feature>.yml` file and import it from `tasks/main.yml`:

```yaml
- name: Whatever the feature is
  ansible.builtin.import_tasks: <feature>.yml
  tags: [<feature>, base]
```

Each task file MUST be idempotent — safe to run on every play.
