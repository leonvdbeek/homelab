variable "node_name" {
  description = "Proxmox node hosting the TrueNAS VM."
  type        = string
  default     = "m920x"
}

variable "vm_id" {
  description = "VM ID for the TrueNAS guest."
  type        = number
  default     = 100
}

variable "vm_name" {
  description = "TrueNAS VM name."
  type        = string
  default     = "truenas"
}

variable "vm_cpu_cores" {
  description = "vCPUs. Host is an i7-8700 (6c/12t); leave headroom for PVE."
  type        = number
  default     = 4
}

variable "vm_memory_mb" {
  description = "RAM for the VM. Host has 15 GiB; 8 GiB is the TrueNAS floor and leaves room for the hypervisor."
  type        = number
  default     = 8192
}

variable "boot_disk_gb" {
  description = "TrueNAS boot/OS disk (the 1TB NVMe is passed through separately for the data pool)."
  type        = number
  default     = 32
}

variable "boot_disk_datastore" {
  description = "Datastore for the VM boot disk + EFI disk."
  type        = string
  default     = "local-lvm"
}

variable "iso_datastore" {
  description = "Datastore that holds ISOs (content_type=iso)."
  type        = string
  default     = "local"
}

variable "truenas_iso_url" {
  description = <<-EOT
    TrueNAS Community Edition (SCALE) installer ISO URL. Check
    https://www.truenas.com/download-truenas-community-edition/ for the current
    release and update this if a newer one is out.
  EOT
  type        = string
  default     = "https://download.sys.truenas.net/TrueNAS-SCALE-Goldeye/25.10.6/TrueNAS-SCALE-25.10.6.iso"
}

variable "network_bridge" {
  description = "Linux bridge for the VM NIC."
  type        = string
  default     = "vmbr0"
}

# --- PCIe passthrough targets (verified on m920x, 2026-08-20) -----------------
# Both devices already sit alone in their own IOMMU group, so no ACS override is
# required. Enable IOMMU + vfio first via ansible/ (playbooks/pve-passthrough.yml).

variable "passthrough_nvme_pci_id" {
  description = "PCI address of the 1TB NVMe (Crucial P1, group 13) to pass through whole."
  type        = string
  default     = "0000:03:00.0"
}

variable "passthrough_sata_pci_id" {
  description = "PCI address of the ASMedia ASM1064 SATA controller (group 12) to pass through whole."
  type        = string
  default     = "0000:02:00.0"
}
