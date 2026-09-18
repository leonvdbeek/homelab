output "vm" {
  description = "The Talos control-plane VM."
  value = {
    vm_id = proxmox_virtual_environment_vm.talos.vm_id
    node  = proxmox_virtual_environment_vm.talos.node_name
    ip    = local.vm_ip
  }
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint (the VIP)."
  value       = "https://${var.cluster_vip}:6443"
}

output "talos_iso" {
  description = "Talos ISO downloaded to the node."
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
