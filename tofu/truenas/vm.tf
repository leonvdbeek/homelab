resource "proxmox_virtual_environment_vm" "truenas" {
  name      = var.vm_name
  node_name = var.node_name
  vm_id     = var.vm_id
  tags      = ["truenas", "tofu"]

  # q35 + OVMF (UEFI) is required for clean PCIe passthrough.
  machine = "q35"
  bios    = "ovmf"

  # The Crucial P1 (DRAM-less) crams its MSI-X table + PBA into BAR0, which
  # QEMU can't map for VFIO ("table & pba overlap"). Relocate MSI-X to the
  # free BAR2 on hostpci0 (the NVMe) so it starts.
  kvm_arguments = "-set device.hostpci0.x-msix-relocation=bar2"

  # Disabled during provisioning so tofu doesn't block waiting for a guest agent
  # that only exists after TrueNAS is installed. Flip to true once installed and
  # the agent is enabled inside TrueNAS (it ships qemu-guest-agent by default).
  agent {
    enabled = false
  }

  # Default std VGA renders the TrueNAS installer's framebuffer as garbage under
  # OVMF; VirtIO-GPU displays it cleanly in the noVNC console.
  vga {
    type = "virtio"
  }

  cpu {
    cores = var.vm_cpu_cores
    type  = "host" # expose full CPU flags to the guest for passthrough.
  }

  # No ballooning for a ZFS box: give it the RAM and keep it.
  memory {
    dedicated = var.vm_memory_mb
    floating  = 0
  }

  operating_system {
    type = "l26"
  }

  scsi_hardware = "virtio-scsi-single"

  # Prefer the boot disk; fall through to the installer ISO while it's empty.
  boot_order = ["scsi0", "ide3"]

  efi_disk {
    datastore_id = var.boot_disk_datastore
    type         = "4m"
  }

  # Boot / OS disk. The 1TB NVMe is passed through separately for the pool.
  disk {
    interface    = "scsi0"
    datastore_id = var.boot_disk_datastore
    size         = var.boot_disk_gb
    iothread     = true
    discard      = "on"
    ssd          = true
  }

  cdrom {
    file_id = proxmox_download_file.truenas_iso.id
  }

  network_device {
    bridge = var.network_bridge
    model  = "virtio"
  }

  # --- Full PCIe passthrough -------------------------------------------------
  # Raw device passthrough — allowed because the provider logs in as root@pam
  # (see provider.tf / .env). Whole 1TB NVMe (Crucial P1): TrueNAS sees the raw
  # NVMe for its ZFS pool.
  hostpci {
    device = "hostpci0"
    id     = var.passthrough_nvme_pci_id
    pcie   = true
  }

  # Whole ASMedia ASM1064 SATA controller — any SATA disks on it appear
  # directly in TrueNAS.
  hostpci {
    device = "hostpci1"
    id     = var.passthrough_sata_pci_id
    pcie   = true
  }

  started = true

  lifecycle {
    # The guest agent rewrites some fields (e.g. MAC ordering) post-boot.
    ignore_changes = [network_device[0].mac_address]
  }
}
