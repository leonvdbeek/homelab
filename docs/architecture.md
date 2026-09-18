# Architecture

The homelab is a single Proxmox host (`m920x`) whose only job is to run one
**TrueNAS Community Edition (SCALE)** VM. TrueNAS owns the storage hardware
directly through full PCIe passthrough — Proxmox never touches the data disks.

```text
┌─ m920x (Proxmox VE 9.1) ─────────────────────────────────────────┐
│  i7-8700 6c/12t · 15 GiB RAM · UEFI + GRUB                        │
│                                                                   │
│  local      (dir)     ISOs                                        │
│  local-lvm  (lvmthin) VM boot disk + EFI disk                     │
│                                                                   │
│  I219-LM 1GbE (onboard, vPro/AMT) ── 192.168.4.164 (mgmt, DHCP)   │
│                                                                   │
│  ConnectX-3 10GbE ── vmbr0 ── 192.168.4.54 ── 192.168.4.0/24 LAN  │
│    │                                                              │
│    ├── VM 100  truenas  (q35 / OVMF)  4 vCPU · 8 GiB · 192.168.4.111
│    │     ├─ scsi0  32 GiB boot disk  (on local-lvm)              │
│    │     │                                                       │
│    │     │   ── full PCIe passthrough (vfio-pci) ──             │
│    │     ├─ hostpci0  Crucial P1 1TB NVMe   → ZFS data pool      │
│    │     └─ hostpci1  ASM1064 SATA controller → any SATA disks   │
│    └── ...                                                        │
└───────────────────────────────────────────────────────────────────┘
```

## Physical host

| | |
|---|---|
| Node | `m920x` (`m920x.local.leonvdbeek.com`) |
| Platform | Proxmox VE 9.1, kernel 6.17 |
| CPU | Intel i7-8700 — 6 cores / 12 threads |
| RAM | 15 GiB |
| Firmware / boot | UEFI, boots via **GRUB** (not systemd-boot / proxmox-boot-tool) |

The GRUB detail matters: the passthrough playbook edits `/etc/default/grub` and
runs `update-grub`. A systemd-boot host would need `proxmox-boot-tool` instead.

## Network

The host has two wired NICs (plus unused onboard WiFi), on two roles:

| NIC | Hardware | Driver | Role | Address |
|---|---|---|---|---|
| `nic2` | Mellanox ConnectX-3 10 GbE (port 1) | `mlx4_en` | bridge port for `vmbr0` — all host + guest LAN traffic | (via `vmbr0`) |
| `nic3` | Mellanox ConnectX-3 10 GbE (port 2) | `mlx4_en` | unused, no link | — |
| `nic1` | Intel I219-LM 1 GbE (onboard) | `e1000e` | out-of-band mgmt / **vPro (AMT)**, DHCP | `192.168.4.164` |
| `wlp4s0` | Intel Wireless-AC 3165 | `iwlwifi` | unused, down | — |
| `vmbr0` | Linux bridge over `nic2` | — | host + all guests | `192.168.4.54/24` (gw `.1`) |
| VM 100 | virtio NIC on `vmbr0` | — | TrueNAS, DHCP on the LAN | `192.168.4.111` |

The data path is the **10 GbE Mellanox** — `vmbr0` bridges `nic2`, so both the
host and the TrueNAS VM reach the LAN at 10 Gb/s. The **onboard I219-LM** is the
vPro/AMT-capable port and serves as an independent 1 GbE management link; it and
`vmbr0` both sit on the same flat `192.168.4.0/24` LAN.

There is no isolated VM network or firewalling at the PVE layer (`firewall=0`).

## Storage

Two tiers, kept deliberately separate:

**Hypervisor storage** (Proxmox-managed, for the VM itself):

| Datastore | Type | Holds |
|---|---|---|
| `local` | dir | installer ISOs |
| `local-lvm` | lvmthin | the 32 GiB TrueNAS boot disk + 4 MB EFI disk |

**Data storage** (owned entirely by TrueNAS via passthrough — Proxmox does not
see these as datastores):

| Device | PCI addr | IOMMU group | Role in TrueNAS |
|---|---|---|---|
| Crucial P1 1TB NVMe | `0000:03:00.0` | 13 (isolated) | ZFS data pool |
| ASMedia ASM1064 SATA controller | `0000:02:00.0` | 12 (isolated) | any attached SATA disks appear raw |

Both devices already sit alone in their own IOMMU group, so **no ACS-override
hack is needed**. On the running host both are bound to `vfio-pci` (their normal
`nvme` / `ahci` drivers are held off), which is what makes clean passthrough
possible.

Device-level benchmarks for the passed-through disks are in
[`benchmarks.md`](benchmarks.md).

## The VM (VM 100, `truenas`)

| Setting | Value | Why |
|---|---|---|
| Machine / BIOS | `q35` + OVMF (UEFI) | required for clean PCIe passthrough |
| vCPU | 4 cores, `type=host` | expose full CPU flags; leaves headroom for PVE |
| RAM | 8192 MiB, ballooning off | ZFS wants fixed RAM; host has 15 GiB total |
| Boot disk | 32 GiB on `local-lvm`, boot order `scsi0` | installer ISO removed post-install |
| Display | VirtIO-GPU | std VGA renders the TrueNAS installer garbled under OVMF |
| Guest agent | enabled | lets PVE read the guest IP and do graceful shutdowns |
| `onboot` | yes | comes back up automatically after a host reboot |

### The two root-only quirks

Both of these force the Proxmox provider to authenticate as **`root@pam` with a
password**, not an API token — token auth refuses raw PCI passthrough and the
`args:` QEMU option.

1. **Raw PCI passthrough** (`hostpci*`) is a root-only operation.
2. **NVMe MSI-X relocation.** The DRAM-less Crucial P1 packs its MSI-X table and
   PBA into one BAR, which QEMU can't map for VFIO (`table & pba overlap`). The
   VM sets `args: -set device.hostpci0.x-msix-relocation=bar2` to move MSI-X to a
   free BAR so the device starts. `args:` is also root-only.

## How it's managed (Infrastructure as Code)

Two layers, each idempotent and re-runnable:

| Layer | Tool | Scope |
|---|---|---|
| `ansible/` | Ansible | host prep — one base runbook (`site.yml`) |
| `tofu/truenas/` | OpenTofu (`bpg/proxmox`) | the TrueNAS VM definition |

**`ansible/site.yml`** is the base runbook — the set of tweaks kept applied to
the host. It imports:
- `pve-passthrough.yml` — adds `intel_iommu=on iommu=pt` to the kernel cmdline
  and loads the `vfio` modules. Reboots are **opt-in** (`pve_allow_reboot=true`);
  otherwise it prints a "reboot pending" notice.
- `pve-subscription-nag.yml` — patches the client-side "No valid subscription"
  popup out of the PVE web UI. Reverted by any `proxmox-widget-toolkit` apt
  upgrade — just re-run.

**`tofu/truenas/`** downloads the TrueNAS installer ISO to the node and creates
the VM with both PCI devices attached. Proxmox credentials (`PROXMOX_VE_*`) are
injected by [secretspec](https://secretspec.dev) — `secretspec run -- tofu …` —
with the password held in Bitwarden; the provider also SSHes to the node (root
key/agent) to apply `hostpci`.

## Boot / dependency order

1. Host prep must run **once** before the VM can start: IOMMU + vfio via
   `ansible-playbook site.yml -e pve_allow_reboot=true`, then a reboot to bind
   the passthrough devices to `vfio-pci`.
2. `tofu apply` creates VM 100. TrueNAS is installed once interactively via the
   noVNC console (onto the small boot disk, **not** the passed-through NVMe).
3. Thereafter the VM starts on host boot (`onboot: 1`) and ZFS imports its pool
   from the passed-through NVMe automatically.

## Related docs

- [`../README.md`](../README.md) — build-from-scratch runbook
- [`benchmarks.md`](benchmarks.md) — passthrough disk benchmarks
- [`../ansible/README.md`](../ansible/README.md) — the base runbook
