output "vm_id" {
  description = "TrueNAS VM ID."
  value       = proxmox_virtual_environment_vm.truenas.vm_id
}

output "vm_name" {
  description = "TrueNAS VM name."
  value       = proxmox_virtual_environment_vm.truenas.name
}

output "passthrough_devices" {
  description = "PCI devices passed through to the VM."
  value = {
    nvme_1tb = var.passthrough_nvme_pci_id
    sata_ctl = var.passthrough_sata_pci_id
  }
}
