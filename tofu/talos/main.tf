# Provider reads PROXMOX_VE_ENDPOINT, PROXMOX_VE_USERNAME + PROXMOX_VE_PASSWORD
# (root@pam login on this host) and PROXMOX_VE_INSECURE from the environment,
# injected by secretspec (`secretspec run -- tofu …`); see secretspec.toml at
# the repo root. No SSH block is needed here: unlike tofu/truenas this stack
# does no PCI passthrough, so plain API auth is enough.
provider "proxmox" {}
