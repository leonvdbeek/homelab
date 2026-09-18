resource "proxmox_virtual_environment_vm" "talos" {
  name      = var.vm_name
  node_name = var.node_name
  vm_id     = var.vm_id
  tags      = ["talos", "tofu"]

  # qemu-guest-agent runs in Talos (baked into the schematic), so PVE can read
  # the VM IP and do graceful shutdowns.
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
  # Prefer the installed disk; fall through to the ISO on first boot when the
  # disk is still empty.
  boot_order = ["scsi0", "ide3"]

  # virtio-scsi-single is required for the per-disk iothread below.
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
    file_id = proxmox_download_file.talos.id
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  operating_system {
    type = "l26"
  }

  on_boot = true

  # Talos doesn't use cloud-init; leave initialization unset.
  started = true

  lifecycle {
    # The guest agent rewrites some fields (e.g. MAC ordering) post-boot.
    ignore_changes = [network_device[0].mac_address]
  }
}
