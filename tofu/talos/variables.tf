variable "node_name" {
  description = "Proxmox node hosting the Talos VM."
  type        = string
  default     = "m920x"
}

# --- Talos image -------------------------------------------------------------

variable "talos_version" {
  description = "Talos release to run (https://github.com/siderolabs/talos/releases). Bump for newer releases; `talosctl upgrade` uses the matching factory installer."
  type        = string
  default     = "v1.10.4"
}

variable "talos_arch" {
  description = "Talos image architecture."
  type        = string
  default     = "amd64"
}

variable "talos_extensions" {
  description = "Official Talos system extensions baked into the image (https://factory.talos.dev/extensions). qemu-guest-agent lets Proxmox read the VM IP and do graceful shutdowns."
  type        = list(string)
  default     = ["siderolabs/qemu-guest-agent"]
}

# --- Cluster -----------------------------------------------------------------

variable "cluster_name" {
  description = "Talos / Kubernetes cluster name."
  type        = string
  default     = "homelab"
}

variable "cluster_vip" {
  description = "Shared IP for the Kubernetes API. Talos floats it via ARP, giving a stable API endpoint even though the node gets its address from DHCP — and it becomes real HA if more control-plane nodes are added later. Must be a FREE IP on the VM's L2 segment (same 192.168.4.0/24 subnet)."
  type        = string
  default     = "192.168.4.60"
}

variable "vm_network_interface" {
  description = "Interface name inside the Talos VM that the VIP attaches to. A single virtio NIC on PVE 8+ comes up as ens18."
  type        = string
  default     = "ens18"
}

variable "install_disk" {
  description = "Disk Talos installs to. With virtio-scsi the first (and only) disk is /dev/sda."
  type        = string
  default     = "/dev/sda"
}

# --- Proxmox placement -------------------------------------------------------

variable "iso_datastore" {
  description = "Datastore that holds ISOs (must be content_type=iso)."
  type        = string
  default     = "local"
}

variable "disk_datastore" {
  description = "Datastore for the VM disk."
  type        = string
  default     = "local-lvm"
}

variable "network_bridge" {
  description = "Linux bridge for the VM NIC."
  type        = string
  default     = "vmbr0"
}

# --- VM sizing (bump any of these and `tofu apply` to resize) ----------------

variable "vm_id" {
  description = "VM ID for the Talos guest."
  type        = number
  default     = 9000
}

variable "vm_name" {
  description = "VM name. Also pinned as the Talos hostname, so the Kubernetes node name matches the Proxmox VM name."
  type        = string
  default     = "talos-cp-01"
}

variable "vm_cpu_cores" {
  description = "vCPUs. Host is an i7-8700 (6c/12t), shared with the TrueNAS VM."
  type        = number
  default     = 4
}

variable "vm_cpu_type" {
  description = "Proxmox CPU model. 'host' is fastest on a single-host lab; 'x86-64-v2-AES' is portable if you migrate."
  type        = string
  default     = "host"
}

variable "vm_memory_mb" {
  description = "RAM for the VM. Host has 15 GiB total and the TrueNAS VM pins 8 GiB, so ~4 GiB is the safe default here — raise it (and/or lower TrueNAS) if you want more room for workloads."
  type        = number
  default     = 4096
}

variable "vm_disk_gb" {
  description = "Boot/OS + workload disk. Talos, images and ephemeral workload data all live here."
  type        = number
  default     = 40
}
