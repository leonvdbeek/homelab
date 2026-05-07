# tofu

OpenTofu stacks that turn three already-provisioned Proxmox nodes into a
running Talos Kubernetes cluster with usable storage.

```
tofu/
└── talos/   Talos VMs, cluster bootstrap, Proxmox CSI install
```

Today there's only one stack. If a second one shows up later (e.g. a
separate stack for a Proxmox CCM, or a non-Talos cluster) it lives next
to `talos/` with its own state.

## Layering

```
bare metal ──(stacks/, ipxe/, ansible/)──► Proxmox node
Proxmox node ──(tofu/talos/)──► Talos VM, K8s control-plane, CSI driver
K8s cluster ──(kubernetes/)──► workloads & helm releases
```

`tofu/talos/` reaches across all three layers a little: it provisions
VMs (Proxmox), bootstraps Talos (Talos API), and installs the CSI Helm
chart (Kubernetes API). That's deliberate — it's the one stack with
visibility into all three credentials needed to make storage work
end-to-end. After that point everything else lives in `kubernetes/` as
plain manifests.

## Running

See `talos/README.md` — secrets in `../.env`, then `tofu apply` from
inside `talos/`.

## State

State is stored locally as `terraform.tfstate` next to each stack and
gitignored. It contains cluster secrets and the Proxmox API token —
back it up the same way you'd back up a `.env`. If you ever move to
remote state (e.g. an S3-compatible bucket on the homelab itself),
configure it with at-rest encryption.
