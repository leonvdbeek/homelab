# Provider reads PROXMOX_VE_ENDPOINT, PROXMOX_VE_API_TOKEN and
# PROXMOX_VE_INSECURE from the environment (see .env at the repo root).
provider "proxmox" {
  # PCIe passthrough (hostpci) is applied by the provider over SSH to the
  # target node, so an SSH agent / key to root@<node> must be available.
  ssh {
    agent = true
    # Map the PVE node name to the address tofu should SSH to for hostpci.
    node {
      name    = "m920x"
      address = "m920x.local.leonvdbeek.com"
    }
  }
}
