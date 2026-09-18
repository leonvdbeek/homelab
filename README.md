# Homelab — TrueNAS on m920x

Clean-slate rebuild. A single Proxmox host (`m920x`) runs a **TrueNAS
Community Edition (SCALE)** VM that owns its storage hardware directly via full
PCIe passthrough.

## Host

| | |
|---|---|
| Node | `m920x` (`m920x.local.leonvdbeek.com`) |
| Platform | Proxmox VE 9.1, kernel 6.17, Intel i7-8700, 15 GiB RAM, UEFI + GRUB |

## What gets passed through

Both devices already sit alone in their own IOMMU group, so **no ACS-override
hack is needed**.

| Device | PCI addr | IDs | IOMMU group |
|---|---|---|---|
| Crucial P1 1TB NVMe | `0000:03:00.0` | `c0a9:2263` | 13 (isolated) |
| ASMedia **ASM1064** SATA controller | `0000:02:00.0` | `1b21:1064` | 12 (isolated) |

> Note: the SATA controller is physically an **ASM1064**, not ASM1664 — it's
> passed through by its real PCI ID above. The NVMe becomes TrueNAS's ZFS pool;
> any disks on the SATA controller appear directly in TrueNAS.

## Layout

```
ansible/pve-passthrough/   host prep: enable IOMMU + vfio (run once)
tofu/truenas/              the TrueNAS VM (OpenTofu, bpg/proxmox)
```

## 1. Prepare the host (once)

Adds `intel_iommu=on iommu=pt` to the kernel cmdline and loads the vfio modules.
This is part of the idempotent base runbook (`ansible/site.yml`); run it alone
with the passthrough playbook. A reboot is needed the first time the cmdline
changes — opt in with `-e pve_allow_reboot=true`.

```sh
cd ansible
ansible-playbook playbooks/pve-passthrough.yml -e pve_allow_reboot=true
```

After it reboots, sanity-check on the host:

```sh
ssh root@m920x.local.leonvdbeek.com \
  'dmesg | grep -e DMAR -e IOMMU | head; lspci -nnk -s 02:00.0; lspci -nnk -s 03:00.0'
```

## 2. Create the VM

Proxmox credentials come from the environment (`PROXMOX_VE_*` in `.env`).

> **Auth must be `root@pam` password login, not an API token.** Proxmox refuses
> two things for token auth, both of which this VM needs: raw PCI passthrough
> and the `args:` QEMU option. So `.env` sets `PROXMOX_VE_USERNAME=root@pam` +
> `PROXMOX_VE_PASSWORD=...` — fill in the real root password before applying.

```sh
# from the repo root, load your proxmox creds:
set -a; source .env; set +a

cd tofu/truenas
tofu init
tofu plan
tofu apply
```

This downloads the TrueNAS installer ISO to the node, creates a q35/OVMF VM
with a 32 GiB boot disk, and attaches both PCI devices. Open the VM console in
the Proxmox UI to run the TrueNAS installer (install onto the small boot disk —
`sdX`/`vdX`, **not** the passed-through NVMe).

### NVMe MSI-X quirk

The Crucial P1 (DRAM-less) packs its MSI-X table and PBA into one BAR, which
QEMU can't map for VFIO (`table & pba overlap`). The VM works around it with
`kvm_arguments = "-set device.hostpci0.x-msix-relocation=bar2"`, relocating
MSI-X to a free BAR. This is why root login is required (`args:` is root-only).

### Defaults (override in `terraform.tfvars`)

| Variable | Default | |
|---|---|---|
| `vm_id` | `100` | |
| `vm_cpu_cores` | `4` | of 12 host threads |
| `vm_memory_mb` | `8192` | TrueNAS floor; host has 15 GiB total |
| `boot_disk_gb` | `32` | on `local-lvm` |
| `truenas_iso_url` | 25.10.6 (Goldeye) | bump for newer releases |

Copy `terraform.tfvars.example` → `terraform.tfvars` to change any of these.
