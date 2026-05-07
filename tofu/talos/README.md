# tofu/talos

3-node Talos cluster on Proxmox. One VM per node, 20 GB disk on `ceph-pool`,
DHCP on `vmbr0`, no VLAN. The Talos ISO is downloaded by Tofu to each node's
`local` storage.

## One-time

1. **Create a Proxmox API token.**
   Datacenter → Permissions → API Tokens → Add. Untick *Privilege Separation*
   (or grant the token a role with `VM.*`, `Datastore.AllocateSpace`,
   `Datastore.Audit`, `Sys.Audit`, `Sys.Modify` across `/`). Copy the resulting
   token string in the form `user@realm!tokenid=uuid` — you'll only see it once.

2. **Add Proxmox vars to `../../.env`** (gitignored). See `.env.example`:
   ```
   PROXMOX_VE_ENDPOINT=https://<pve-host-or-vip>:8006/
   PROXMOX_VE_API_TOKEN=root@pam!tofu=00000000-0000-0000-0000-000000000000
   PROXMOX_VE_INSECURE=true

   # Mirror for tofu — the CSI helm release reads this.
   TF_VAR_proxmox_endpoint=${PROXMOX_VE_ENDPOINT}
   ```

3. **Source it and run Tofu:**
   ```
   cd tofu/talos
   set -a; source ../../.env; set +a
   tofu init
   tofu plan
   tofu apply
   ```

## What it builds

- Posts a schematic to the [Talos Image Factory](https://factory.talos.dev) at
  plan time and downloads the resulting customized `metal-amd64.iso` onto
  `local` of each node. The default schematic bakes in the
  `siderolabs/qemu-guest-agent` extension. Edit `talos_extensions` in
  `variables.tf` to add more (full list:
  https://factory.talos.dev/extensions). Requires `bash`, `curl`, and `jq`
  on the machine running Tofu.
- Creates 3 VMs (`talos-01`..`talos-03`, IDs 9001..9003), one per node, with:
  - 4 vCPU (`x86-64-v2-AES`), 4 GB RAM
  - 20 GB scsi disk on `ceph-pool` (virtio-scsi, discard, ssd flag)
  - virtio NIC on `vmbr0`, untagged, DHCP
  - boot order `scsi0, ide3` so first boot falls through to ISO; subsequent
    boots come from the installed disk

After the VMs are up, Tofu also:
- generates cluster secrets and a controlplane machine config
  (compact 3-node cluster — `allowSchedulingOnControlPlanes: true`, install
  disk `/dev/sda`),
- applies the config to all 3 VMs over the Talos maintenance API, with
  per-node patches that:
  - set `machine.network.hostname` to the Proxmox VM name (`talos-01`..`03`),
    so the K8s node name matches the Proxmox VM name and the CSI plugin's
    "look up VM by node name" fallback resolves,
  - set `topology.kubernetes.io/region` and
    `topology.kubernetes.io/zone=<proxmox node>` for CSI placement,
- bootstraps etcd on the first node,
- waits for cluster health,
- pulls `kubeconfig` and `talosconfig` and exposes them as sensitive outputs.

VM IPs come from the qemu-guest-agent (running because the schematic includes
the `siderolabs/qemu-guest-agent` extension). The cluster API endpoint is the
first CP node's IP — drop in a VIP later for HA on the API.

After `tofu apply`:
```
mkdir -p ~/.kube ~/.talos
tofu output -raw kubeconfig  > ~/.kube/config
tofu output -raw talosconfig > ~/.talos/config
kubectl get nodes
talosctl health
kubectl apply -k ../../kubernetes/csi-test     # smoke-test the CSI driver
```

## Storage: proxmox-csi-plugin

Tofu drives the whole CSI install end-to-end:

- Proxmox side: `Kubernetes-CSI` role, `kubernetes-csi@pve` user, API
  token, ACLs (bpg provider).
- Per-node Talos config patches:
  `topology.kubernetes.io/region=<cluster_name>` and
  `topology.kubernetes.io/zone=<proxmox node>` so the plugin knows
  which Proxmox node a PVC's disk should be allocated on.
- `csi-proxmox` namespace (`privileged` PSA) with a `proxmox-csi-plugin`
  Secret carrying the rendered `config.yaml`.
- The Helm chart itself —
  `oci://ghcr.io/sergelogvinov/charts/proxmox-csi-plugin@0.5.7` — with
  values loaded from `../../kubernetes/proxmox-csi/values.yaml`.

The values file is plain YAML so it's readable, diffable, and
GitOps-ready. Edit it, run `tofu apply`.

The smoke test (`../../kubernetes/csi-test/`) is plain Kustomize —
applied with `kubectl apply -k` after the cluster is up. It's a
workload, not infra, so it stays out of Tofu.

The Proxmox API token in your `.env` needs enough privileges to manage
roles/users/ACLs on Proxmox; easiest is a token without privilege
separation.

### Future work: Proxmox CCM

We don't run a cloud-controller-manager today, so K8s nodes have no
`spec.providerID`. The CSI plugin compensates by matching K8s node name
→ Proxmox VM name (which is why the hostname patch above exists).
Installing the [Proxmox CCM](https://github.com/sergelogvinov/proxmox-cloud-controller-manager)
removes that coupling — providerID becomes the canonical link, the
hostname is free to be anything, and replacing a VM no longer requires
keeping the name in sync.

## Adjusting

Everything is variable-driven in `variables.tf`. Override in
`terraform.tfvars` (gitignored by the root `.gitignore` if added) or with
`-var`:

```
tofu apply -var 'talos_version=v1.10.0' -var 'vm_disk_gb=40'
```
