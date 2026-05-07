output "vms" {
  description = "Created Talos VMs and their Proxmox node placement."
  value = {
    for name, vm in proxmox_virtual_environment_vm.talos : name => {
      vm_id = vm.vm_id
      node  = vm.node_name
      ip    = local.vm_ips[name]
    }
  }
}

output "talos_iso" {
  description = "Talos ISO downloaded to each node."
  value       = local.talos_iso_filename
}

output "kubeconfig" {
  description = "Cluster kubeconfig. Write with `tofu output -raw kubeconfig > ~/.kube/config`."
  value       = talos_cluster_kubeconfig.this.kubeconfig_raw
  sensitive   = true
}

output "talosconfig" {
  description = "talosctl client config. Write with `tofu output -raw talosconfig > ~/.talos/config`."
  value       = data.talos_client_configuration.this.talos_config
  sensitive   = true
}

