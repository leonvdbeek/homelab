# Ansible — Proxmox host base runbook

One shared inventory, multiple playbooks. `site.yml` is the **base runbook**: the
set of tweaks we keep applied to the PVE host(s). It's idempotent — safe to run
repeatedly, and it never reboots unless you opt in.

## Layout

```
ansible.cfg          # points at ./inventory.yml
inventory.yml        # the one inventory (group: proxmox → m920x)
site.yml             # base runbook: imports every playbook below
playbooks/
  pve-passthrough.yml       # IOMMU + vfio for PCIe passthrough
  pve-subscription-nag.yml  # remove the "No valid subscription" popup
```

## Usage

Run from this directory (so `ansible.cfg` is picked up):

```bash
cd ansible

# Preview only — reports what would change (diffs), changes nothing:
ansible-playbook site.yml --check --diff

# Apply the base runbook:
ansible-playbook site.yml

# Apply and allow a reboot (needed the first time passthrough flags change):
ansible-playbook site.yml -e pve_allow_reboot=true

# Just one component:
ansible-playbook playbooks/pve-subscription-nag.yml
```

## Notes

- **Reboots are opt-in.** `pve_allow_reboot` defaults to `false` (see
  `inventory.yml`). The passthrough playbook requests a reboot only when the
  kernel cmdline / vfio config actually changes; without the opt-in it prints a
  "reboot pending" notice instead of rebooting.
- **The nag patch is client-side JS** and is reverted whenever
  `proxmox-widget-toolkit` is upgraded via apt — just re-run the runbook after
  a PVE update.
- Adding a host: put it under the `proxmox` group in `inventory.yml`; every
  playbook targets that group.
