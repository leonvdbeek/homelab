###############################################################################
# Cilium CNI install — replaces Flannel and kube-proxy on Talos.
#
# Talos config patches that go with this (cluster.network.cni.name = "none"
# and cluster.proxy.disabled = true) live in talos.tf.
#
# Values are read from kubernetes/cilium/values.yaml — same pattern as
# proxmox-csi. Edit values.yaml, run `tofu apply` here.
#
# The Gateway API CRDs that Cilium consumes are installed manually because
# the standard-install.yaml is too large for kubernetes_manifest. See
# kubernetes/gateway-api-crds/README.md.
###############################################################################

resource "helm_release" "cilium" {
  name             = "cilium"
  namespace        = "kube-system"
  repository       = "https://helm.cilium.io"
  chart            = "cilium"
  version          = "1.16.5"
  create_namespace = false

  values = [file("${path.module}/../../kubernetes/cilium/values.yaml")]

  # Don't try to install Cilium until the Talos config patch that disables
  # Flannel + kube-proxy has been applied to every node.
  depends_on = [
    talos_machine_configuration_apply.cp,
    data.talos_cluster_health.this,
  ]
}
