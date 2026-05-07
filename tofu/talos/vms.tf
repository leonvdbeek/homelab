locals {
  vms = {
    for idx, node in var.proxmox_nodes :
    format("%s-%02d", var.vm_name_prefix, idx + 1) => {
      node = node
      vmid = var.vm_id_base + idx
    }
  }
}

resource "proxmox_virtual_environment_vm" "talos" {
  for_each = local.vms

  name      = each.key
  node_name = each.value.node
  vm_id     = each.value.vmid
  tags      = ["talos", "tofu"]

  agent {
    enabled = true
  }

  cpu {
    cores = var.vm_cpu_cores
    type  = var.vm_cpu_type
  }

  memory {
    dedicated = var.vm_memory_mb
  }

  bios = "seabios"
  # Prefer disk; fall through to ISO on first boot when disk is empty.
  boot_order = ["scsi0", "ide3"]

  # virtio-scsi-single is required for per-disk iothread.
  scsi_hardware = "virtio-scsi-single"

  disk {
    interface    = "scsi0"
    datastore_id = var.disk_datastore
    size         = var.vm_disk_gb
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  cdrom {
    file_id = proxmox_download_file.talos[each.value.node].id
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  # Talos doesn't use cloud-init; leave initialization unset.
  started = true
}
