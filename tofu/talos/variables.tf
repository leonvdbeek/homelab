variable "proxmox_nodes" {
  description = "Proxmox node names, one VM per node, in this order."
  type        = list(string)
  default     = ["lenovo-01", "lenovo-02", "lenovo-03"]
  validation {
    condition     = length(var.proxmox_nodes) == 3
    error_message = "Need exactly 3 nodes for the 3-VM layout."
  }
}

variable "talos_version" {
  description = "Talos release to download (https://github.com/siderolabs/talos/releases)."
  type        = string
  default     = "v1.9.5"
}

variable "talos_arch" {
  description = "Talos image architecture."
  type        = string
  default     = "amd64"
}

variable "talos_extensions" {
  description = "Official Talos system extensions to bake into the image (https://factory.talos.dev/extensions)."
  type        = list(string)
  default     = ["siderolabs/qemu-guest-agent"]
}

variable "cluster_name" {
  description = "Talos / Kubernetes cluster name."
  type        = string
  default     = "homelab"
}

variable "cluster_vip" {
  description = "Shared IP for the Kubernetes API. Talos floats it across control-plane nodes via ARP, so the kube-API survives any single node being down. Must be a free IP on the VM's L2 segment (same subnet as the DHCP-assigned node IPs)."
  type        = string
  default     = "192.168.4.60"
}

variable "vm_network_interface" {
  description = "Interface name inside the Talos VM that the VIP attaches to. virtio NICs on PVE 8+ get predictable names; `ens18` is correct for our single-NIC layout."
  type        = string
  default     = "ens18"
}

variable "install_disk" {
  description = "Disk Talos installs to. With virtio-scsi the first disk is /dev/sda."
  type        = string
  default     = "/dev/sda"
}

variable "proxmox_endpoint" {
  description = "Proxmox API URL — mirrors PROXMOX_VE_ENDPOINT, used by the CSI helm release."
  type        = string
  validation {
    condition     = length(var.proxmox_endpoint) > 0
    error_message = "Set TF_VAR_proxmox_endpoint=\"$PROXMOX_VE_ENDPOINT\" in .env."
  }
}


variable "iso_datastore" {
  description = "Per-node datastore that holds ISOs (must be content_type=iso)."
  type        = string
  default     = "local"
}

variable "disk_datastore" {
  description = "Shared datastore for VM disks."
  type        = string
  default     = "ceph-pool"
}

variable "network_bridge" {
  description = "Linux bridge for VM NICs."
  type        = string
  default     = "vmbr0"
}

variable "vm_id_base" {
  description = "First VM ID; subsequent VMs increment from here."
  type        = number
  default     = 9001
}

variable "vm_name_prefix" {
  description = "Hostname prefix; VMs are <prefix>-01, -02, -03."
  type        = string
  default     = "talos"
}

variable "vm_cpu_cores" {
  type    = number
  default = 2
}

variable "vm_cpu_type" {
  description = "Proxmox CPU model. 'host' is fastest, 'x86-64-v2-AES' is portable."
  type        = string
  default     = "host"
}

variable "vm_memory_mb" {
  type    = number
  default = 4096
}

variable "vm_disk_gb" {
  type    = number
  default = 20
}
