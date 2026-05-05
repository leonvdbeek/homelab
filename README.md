# homelab

Infrastructure-as-code for a small home Proxmox lab. Lets a fresh bare-metal box go from "plugged into the LAN" to "registered Proxmox node with no-subscription repos and no nag banner" by selecting a single iPXE menu entry.

## Architecture

```
┌───────────────────────────────┐                     ┌──────────────────────┐
│         UniFi (DHCP)          │   Network Boot:OFF  │   192.168.4.0/24     │
│        192.168.4.1            │  ─────────────────► │      LAN clients      │
└────────────────┬──────────────┘                     └──────────┬───────────┘
                 │                                               │
                 │            ┌─────────────────────────────┐    │
                 └────────────► portainer host (192.168.4.73)│◄───┘
                              │                             │
                              │  ┌──────────────────────┐   │
                              │  │   netboot.xyz        │   │  TFTP+proxyDHCP
                              │  │   ─ TFTP/UDP 69      │   │  arch detection
                              │  │   ─ proxyDHCP/UDP 67 │   │  serves iPXE
                              │  │   ─ http :8181       │   │  + assets
                              │  └──────────────────────┘   │
                              │  ┌──────────────────────┐   │
                              │  │   autopve :8282      │   │  per-MAC answer.toml
                              │  │   ─ /answer (POST)   │   │  + post-install webhook
                              │  │   ─ /playbook/<n>    │   │  → Ansible
                              │  │   ─ /files/<n>       │   │  first-boot script host
                              │  └──────────────────────┘   │
                              │  ┌──────────────────────┐   │
                              │  │   NetBox :8484       │   │  device registry
                              │  │   ─ Postgres + Redis │   │
                              │  └──────────────────────┘   │
                              └─────────────────────────────┘
```

**Boot flow**
```
PXE firmware → proxyDHCP → arch-correct netboot.xyz iPXE binary
            → iPXE local menu (TFTP from .73)
            → "Proxmox VE 9.1 (auto-install)"
            → kernel + initrd + ISO (HTTP from :8181)
            → installer fetches answer.toml POST→ autopve :8282
            → autopve matches by MAC, returns answer with right FQDN
            → unattended install
            → first-boot script (autopve :8282/files/setup-pve.sh):
                  · disable enterprise repo
                  · enable pve-no-subscription
                  · patch nag banner
            → post-install webhook → autopve :8282/playbook/register-netbox
                  · SSH back to host, gather facts
                  · push device + interfaces + MACs + IP + disks to NetBox
```

## Repo layout

```
stacks/
  netbootxyz/   docker-compose for the netboot.xyz container (proxyDHCP + TFTP + nginx)
  autopve/      docker-compose + thin Dockerfile (adds pynetbox + sshpass)
  netbox/       docker-compose.override (port + superuser bootstrap)
ipxe/           iPXE menu additions + autoexec.ipxe served by netboot.xyz
ansible/        playbooks autopve runs on post-install webhook
files/          first-boot scripts served by autopve at /files/<name>
docs/           runbook-style notes
.env.example    env vars consumed by playbooks (NETBOX_TOKEN etc.)
```

## One-time setup

1. Clone this repo on the Docker host (`portainer` in the layout above).
2. Create persistent directories:
   ```
   mkdir -p ~/portainer/netboot/{config,assets} \
            ~/portainer/autopve/{data,logs} \
            ~/portainer/netbox
   ```
3. Copy `.env.example` to `.env`, fill in real values.
4. Copy each `*.example` file to its real name and edit the placeholders:
   - `stacks/autopve/storage-general.json.example` → `stacks/autopve/storage-general.json` (drop into `~/portainer/autopve/data/`)
   - `stacks/netbox/docker-compose.override.yml.example` → `stacks/netbox/docker-compose.override.yml`
5. `cd stacks/netbootxyz && docker compose up -d` — wait for menus to download (~30s on first start).
6. `cd stacks/autopve && docker compose up -d --build`
7. `cd stacks/netbox && docker compose up -d` — first start runs DB migrations (~3 min).
8. Provision NetBox:
   - `curl -X POST -d '{"username":"admin","password":"$NETBOX_SUPERUSER_PASSWORD"}' http://<host>:8484/api/users/tokens/provision/` — capture `token` (and `key`) for `NETBOX_TOKEN=nbt_<key>.<token>` in `.env`.
   - Seed Site/Role/CustomFields (see `docs/netbox-seed.md`).
9. UniFi → Networks → DHCP → Network Boot **OFF**. proxyDHCP from netboot.xyz handles it.

## Provisioning a new machine

1. **Decide the hostname.** Add it to autopve's `storage-general.json` (or via the UI):
   ```jsonc
   "lenovo-04": {
     "must_contain": ["aa:bb:cc:dd:ee:ff"],   // lowercase MAC of the new box
     "global": { "fqdn": "lenovo-04.local.leonvdbeek.com" }
   }
   ```
   `docker restart autopve` to reload.

2. **Boot the box** via PXE (F12 / firmware boot menu → network boot).
3. iPXE menu loads → pick **Proxmox VE 9.1 (auto-install)**.
4. Walk away — install + first-boot + NetBox registration are unattended.
5. When the box reboots, it has:
   - Hostname `lenovo-04.local.leonvdbeek.com`
   - Repos pointing at `pve-no-subscription` (no enterprise 401s)
   - No subscription nag in the web UI
   - A device entry in NetBox with manufacturer, model, S/N, CPU, RAM, BIOS, NICs, MACs, primary IP, disks

## Customizing the install

- **Different disk** — set `disk-list` in the per-host or Default answer.
- **Static network** — `[network] source = "from-answer"` + `cidr/gateway/dns` block in the answer.
- **Different first-boot script** — replace `files/setup-pve.sh` and `docker restart autopve`.
- **Different post-install action** — drop a new playbook under `ansible/playbooks/<name>/` and point the answer's `[post-installation-webhook] url` at `http://<host>:8282/playbook/<name>`.

## Adding a tool the autopve image doesn't ship

Edit `stacks/autopve/Dockerfile` (`apt-get install …` or `pip install …`), then `docker compose up -d --build` from `stacks/autopve/`. Use `--pull` to also refresh the upstream base.

## Troubleshooting

- **iPXE prompts for `p` and times out** — proxyDHCP detected but iPXE didn't see itself. Check `dhcp-userclass=set:ipxe,iPXE` in `TFTPD_OPTS`.
- **`autoexec.ipxe... Permission denied`** — file in `/config/menus/` isn't owned by `nbxyz`. `docker exec netbootxyz chown -R nbxyz:nbxyz /config/menus`.
- **`failed loading first-boot executable from ISO`** — your answer has `[first-boot] source = "from-iso"` but the ISO wasn't prepared with `--on-first-boot=...`. Either remove the section, switch to `source = "from-url"`, or rebuild the ISO with the script embedded.
- **NetBox returns `Invalid v1 token`** — the v2 token format is `Bearer nbt_<key>.<token>` (Bearer, not Token). Provision via `/api/users/tokens/provision/`.
- **Post-install playbook fails on `pynetbox` not found** — autopve image was upgraded and lost the extras. `docker compose up -d --build` from `stacks/autopve/`.

## Security note

This setup assumes a trusted LAN. Plain HTTP for the answer file means the root password is on the wire during install. For anything internet-exposed, use HTTPS with cert pinning (`proxmox-auto-install-assistant prepare-iso ... --cert-fingerprint`).

## Standalone runbook (refresh data on demand)

The autopve flow registers each host once on first install. To re-pull live facts on demand (after a hardware change, periodically, etc.) there's a separate playbook driven from a static inventory.

```
cd ansible
ansible-galaxy collection install -r requirements.yml          # one-time
export NETBOX_URL=http://<host>:8484
export NETBOX_TOKEN=nbt_<key>.<token>
export PVE_ROOT_PASSWORD=<pw>

ansible-playbook playbooks/site.yml                            # all hosts
ansible-playbook playbooks/site.yml -l lenovo-02               # one host
ansible-playbook playbooks/site.yml --tags netbox              # one task slice
```

Inventory lives in `ansible/inventory/`:
- `hosts.yml` — group memberships
- `host_vars/<name>.yml` — per-host IP

Add a new host: drop a `host_vars/<name>.yml` with the IP and add the name under `pve_hosts:` in `hosts.yml`. Then add a matching MAC-keyed entry in autopve's storage so the install side picks the right FQDN.

The work itself lives in the `base` role (`ansible/roles/base/`). It's composed of independently-idempotent task files (currently only `netbox-register.yml`). Add new task files there and import them from `roles/base/tasks/main.yml` to grow the role.

