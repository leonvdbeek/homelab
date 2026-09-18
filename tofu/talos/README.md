# tofu/talos

A single-node Talos Kubernetes cluster on the `m920x` Proxmox host: one
control-plane VM that also runs workloads (`allowSchedulingOnControlPlanes`),
with the `qemu-guest-agent` extension baked in. The Talos ISO is built by the
Talos Image Factory and downloaded to the node by Tofu.

It is deliberately minimal — default Talos CNI (Flannel) and `kube-proxy`, no
Ceph/CSI/Cilium — so `tofu apply` gives a working cluster with no manual helm
steps. Everything is variable-driven, so growing the VM's CPU/RAM/disk (or
adding nodes later) is a small edit.

## Prerequisites

- `tofu`, plus `bash`, `curl` and `jq` on the machine running it (Tofu POSTs the
  image schematic to the factory at plan time).
- Proxmox credentials via [secretspec](https://secretspec.dev) — the same
  `PROXMOX_VE_*` used by `tofu/truenas`, declared in the repo-root
  `secretspec.toml` and injected by `secretspec run`. The password lives in
  Bitwarden (`bw` provider); unlock the CLI once per shell:
  `export BW_SESSION=$(bw unlock --raw)`.
- A **free** IP on `192.168.4.0/24` for the API VIP (default `192.168.4.60`) —
  `ping` it first. See `cluster_vip` in `variables.tf`.

## Run

```sh
export BW_SESSION=$(bw unlock --raw)   # once per shell
cd tofu/talos
tofu init
secretspec run -- tofu plan
secretspec run -- tofu apply
```

## What it builds

1. Posts a schematic (default extension: `siderolabs/qemu-guest-agent`) to
   [factory.talos.dev](https://factory.talos.dev) and downloads the resulting
   `metal-amd64.iso` onto the node's `local` storage.
2. Creates VM `talos-cp-01` (ID 9000) on `m920x`:
   - 4 vCPU (`host`), 4 GiB RAM, 40 GiB disk on `local-lvm`
   - virtio-scsi disk, virtio NIC on `vmbr0` (untagged, DHCP)
   - boot order `scsi0, ide3` — falls through to the ISO on first boot, boots
     the installed disk after
   - `onboot`, qemu-guest-agent enabled
3. Generates cluster secrets and a control-plane machine config, then over the
   Talos maintenance API:
   - pins the hostname to `talos-cp-01` (so the K8s node name matches the VM),
   - declares the API **VIP** on the NIC — a stable API address despite DHCP,
     and real HA if control-plane nodes are added later,
   - sets `allowSchedulingOnControlPlanes: true` so the node runs workloads.
4. Bootstraps etcd, waits for cluster health, and exposes `kubeconfig` /
   `talosconfig` as sensitive outputs.

The VM IP comes from the qemu-guest-agent; the kube-API endpoint is the VIP.

## After apply

```sh
mkdir -p ~/.kube ~/.talos
tofu output -raw kubeconfig  > ~/.kube/config
tofu output -raw talosconfig > ~/.talos/config
kubectl get nodes
talosctl health
```

## Adjusting / extending

Everything is in `variables.tf`. Override in `terraform.tfvars` (gitignored) or
with `-var`:

```sh
# Give it more room for workloads:
secretspec run -- tofu apply -var 'vm_cpu_cores=6' -var 'vm_memory_mb=8192' -var 'vm_disk_gb=80'

# Newer Talos, extra extension:
secretspec run -- tofu apply -var 'talos_version=v1.11.0' \
  -var 'talos_extensions=["siderolabs/qemu-guest-agent","siderolabs/iscsi-tools"]'
```

> **RAM budget:** the host has 15 GiB and the TrueNAS VM pins 8 GiB, so keep
> `vm_memory_mb` around 4 GiB unless you free up RAM elsewhere.

Adding worker nodes later: add a `workers.tf` with a `for_each` VM resource and
a `worker` machine config (`machine_type = "worker"`), applied to each worker's
IP — the VIP endpoint and secrets here are already HA-ready.

## State

`terraform.tfstate` is written locally and gitignored. It holds the cluster
secrets and the resolved Proxmox credentials — back it up securely.
