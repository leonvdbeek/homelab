###############################################################################
# Proxmox-side: dedicated user + token the CSI plugin uses to allocate disks.
###############################################################################

resource "proxmox_virtual_environment_role" "csi" {
  role_id = "Kubernetes-CSI"
  privileges = [
    "VM.Audit",
    "VM.Config.Disk",
    "Datastore.Allocate",
    "Datastore.AllocateSpace",
    "Datastore.Audit",
    # Required by GetCapacity which calls /cluster/resources.
    "Sys.Audit",
  ]
}

resource "proxmox_virtual_environment_user" "csi" {
  user_id = "kubernetes-csi@pve"
  comment = "Proxmox CSI plugin"

  acl {
    path      = "/"
    propagate = true
    role_id   = proxmox_virtual_environment_role.csi.role_id
  }
}

resource "proxmox_user_token" "csi" {
  user_id    = proxmox_virtual_environment_user.csi.user_id
  token_name = "csi"
  comment    = "Proxmox CSI plugin"
}

# Token's own ACL — required because user_token defaults to privsep=true,
# so token permissions are evaluated separately from the user's.
resource "proxmox_acl" "csi_token" {
  token_id  = proxmox_user_token.csi.id
  role_id   = proxmox_virtual_environment_role.csi.role_id
  path      = "/"
  propagate = true
}

###############################################################################
# Kubernetes-side bridge: namespace + Secret holding the rendered config.yaml.
# The proxmox-csi-plugin Helm chart consumes this Secret via its
# `existingConfigSecret` value. Helm release itself lives in
# kubernetes/proxmox-csi/.
###############################################################################

provider "kubernetes" {
  host                   = talos_cluster_kubeconfig.this.kubernetes_client_configuration.host
  cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate)
  client_certificate     = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate)
  client_key             = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key)
}

resource "kubernetes_namespace" "csi_proxmox" {
  metadata {
    name = "csi-proxmox"
    labels = {
      "pod-security.kubernetes.io/enforce" = "privileged"
    }
  }
}

resource "kubernetes_secret" "proxmox_csi_config" {
  metadata {
    name      = "proxmox-csi-plugin"
    namespace = kubernetes_namespace.csi_proxmox.metadata[0].name
  }

  type = "Opaque"

  data = {
    "config.yaml" = yamlencode({
      clusters = [{
        url          = "${trimsuffix(var.proxmox_endpoint, "/")}/api2/json"
        insecure     = true
        token_id     = "${proxmox_virtual_environment_user.csi.user_id}!${proxmox_user_token.csi.token_name}"
        # bpg returns value as the full "user@realm!name=uuid" string; the
        # CSI plugin only wants the uuid after the "=".
        token_secret = element(split("=", proxmox_user_token.csi.value), 1)
        region       = var.cluster_name
      }]
    })
  }
}

###############################################################################
# CSI driver: helm chart installed by Tofu, values pinned to the YAML file in
# kubernetes/proxmox-csi/ (source of truth — easy to read, easy to point a
# GitOps tool at later).
###############################################################################

provider "helm" {
  kubernetes {
    host                   = talos_cluster_kubeconfig.this.kubernetes_client_configuration.host
    cluster_ca_certificate = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.ca_certificate)
    client_certificate     = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_certificate)
    client_key             = base64decode(talos_cluster_kubeconfig.this.kubernetes_client_configuration.client_key)
  }
}

resource "helm_release" "proxmox_csi" {
  name       = "proxmox-csi-plugin"
  namespace  = kubernetes_namespace.csi_proxmox.metadata[0].name
  repository = "oci://ghcr.io/sergelogvinov/charts"
  chart      = "proxmox-csi-plugin"
  version    = "0.5.7"

  values = [file("${path.module}/../../kubernetes/proxmox-csi/values.yaml")]

  depends_on = [
    kubernetes_secret.proxmox_csi_config,
    talos_machine_configuration_apply.cp,
  ]
}
