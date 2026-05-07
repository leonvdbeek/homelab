locals {
  # First non-loopback, non-link-local IPv4 reported by the qemu-guest-agent
  # for each VM. Requires `agent.enabled = true` on the VM and the
  # `siderolabs/qemu-guest-agent` extension in the schematic so the agent
  # actually runs in Talos maintenance mode.
  vm_ips = {
    for name, vm in proxmox_virtual_environment_vm.talos : name => [
      for ip in flatten(vm.ipv4_addresses) :
      ip if ip != "" && !startswith(ip, "127.") && !startswith(ip, "169.254.")
    ][0]
  }

  # Use the first control-plane node as the cluster API endpoint and the
  # bootstrap target. Swap in a VIP later if you want HA on the API.
  first_cp_ip = local.vm_ips[keys(local.vm_ips)[0]]

  # Major.minor of the Talos release we're running. The provider's data
  # sources default to the newest schema they know, which emits keys older
  # Talos rejects (e.g. grubUseUKICmdline). Pinning matches the running ISO.
  talos_minor_version = "v${regex("^v?(\\d+\\.\\d+)", var.talos_version)[0]}"
}

resource "talos_machine_secrets" "this" {
  talos_version = local.talos_minor_version
}

data "talos_machine_configuration" "cp" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${local.first_cp_ip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = local.talos_minor_version

  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = var.install_disk
        }
      }
      cluster = {
        # Compact 3-node cluster: control-plane nodes also run workloads.
        allowSchedulingOnControlPlanes = true
      }
    })
  ]
}

resource "talos_machine_configuration_apply" "cp" {
  for_each = local.vm_ips

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.cp.machine_configuration
  node                        = each.value

  # Per-node topology labels — required by proxmox-csi-plugin to know which
  # Proxmox node a PVC's underlying disk should be allocated on. Hostname is
  # also pinned to the Proxmox VM name so the CSI plugin's "look up VM by node
  # name" fallback resolves correctly (we don't run a Proxmox CCM yet).
  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = each.key
        }
        nodeLabels = {
          "topology.kubernetes.io/region" = var.cluster_name
          "topology.kubernetes.io/zone"   = proxmox_virtual_environment_vm.talos[each.key].node_name
        }
      }
    })
  ]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.cp]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.first_cp_ip
}

data "talos_cluster_health" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = values(local.vm_ips)
  control_plane_nodes  = values(local.vm_ips)
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [data.talos_cluster_health.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.first_cp_ip
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = values(local.vm_ips)
  nodes                = values(local.vm_ips)
}
