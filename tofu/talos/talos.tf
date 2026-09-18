locals {
  # First non-loopback, non-link-local IPv4 the qemu-guest-agent reports for the
  # VM. Requires agent.enabled on the VM and the siderolabs/qemu-guest-agent
  # extension in the schematic (so the agent runs in Talos maintenance mode).
  vm_ip = [
    for ip in flatten(proxmox_virtual_environment_vm.talos.ipv4_addresses) :
    ip if ip != "" && !startswith(ip, "127.") && !startswith(ip, "169.254.")
  ][0]

  # Major.minor of the Talos release. The provider's data sources otherwise
  # default to the newest schema they know, which emits keys older Talos rejects.
  # Pinning matches the running ISO.
  talos_minor_version = "v${regex("^v?(\\d+\\.\\d+)", var.talos_version)[0]}"

  # Factory installer image matching the ISO schematic. Without it Talos would
  # pull the upstream installer at `talosctl upgrade` time, dropping the
  # extensions — so qemu-guest-agent would vanish from the installed system.
  talos_installer_image = "factory.talos.dev/installer/${local.talos_schematic_id}:${var.talos_version}"
}

resource "talos_machine_secrets" "this" {
  talos_version = local.talos_minor_version
}

data "talos_machine_configuration" "cp" {
  cluster_name     = var.cluster_name
  cluster_endpoint = "https://${var.cluster_vip}:6443"
  machine_type     = "controlplane"
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = local.talos_minor_version

  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk  = var.install_disk
          image = local.talos_installer_image
        }
      }
      cluster = {
        # Single-node cluster: the control plane also runs workloads.
        allowSchedulingOnControlPlanes = true
        # kube-apiserver serving cert must cover the VIP and the node IP,
        # otherwise clients hitting the VIP get a cert mismatch.
        apiServer = {
          certSANs = [var.cluster_vip, local.vm_ip]
        }
      }
    })
  ]
}

resource "talos_machine_configuration_apply" "cp" {
  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.cp.machine_configuration
  node                        = local.vm_ip

  # Pin the hostname to the Proxmox VM name so the K8s node name matches it, and
  # declare the VIP on the NIC (Talos holds it via ARP and, with more CP nodes
  # later, fails it over).
  config_patches = [
    yamlencode({
      machine = {
        network = {
          hostname = var.vm_name
          interfaces = [
            {
              interface = var.vm_network_interface
              dhcp      = true
              vip = {
                ip = var.cluster_vip
              }
            },
          ]
        }
      }
    })
  ]
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [talos_machine_configuration_apply.cp]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.vm_ip
}

data "talos_cluster_health" "this" {
  depends_on = [talos_machine_bootstrap.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [local.vm_ip]
  control_plane_nodes  = [local.vm_ip]
}

resource "talos_cluster_kubeconfig" "this" {
  depends_on = [data.talos_cluster_health.this]

  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = local.vm_ip
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [local.vm_ip]
  nodes                = [local.vm_ip]
}
