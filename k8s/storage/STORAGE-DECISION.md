# Stateful storage on the cluster — decision record (2026-10-17)

Backend: TrueNAS SCALE 25.10 (`192.168.4.111`, pool `fast`) via the **official
`truenas/truenas-csi`** CSI driver (iSCSI/NFS/NVMe-oF). Dataset `fast/k8s` created.

## Protocols investigated

### NVMe-oF/TCP — NOT usable (driver-level fault), though fully present
Research + live checks establish NVMe/TCP is **compiled into the Talos kernel**
(`CONFIG_NVME_TCP=y` on the siderolabs pkgs kernel config; `/sys/module/nvme_tcp`
and `/dev/nvme-fabrics` exist on the node; `nvme-cli` ships in the CSI node
container; `modprobe nvme_tcp` is a no-op exit 0). TrueNAS listens on
`.111:4420` (nvmet port id 2, base NQN
`nqn.2011-06.com.truenas:uuid:80c282de-...`).
Despite all prerequisites, the driver's `nvme connect` **reproducibly fails**:
`failed to write to /dev/nvme-fabrics: I/O error / could not add new controller`.
This is a driver/Talos-kernel interaction issue (cp. ceph-csi #6158 & NetApp
Trident KB, where CSI drivers mishandle built-in nvme_tcp). Flagged for a
driver-level fix; not blocking since iSCSI works.

### iSCSI — WORKING path (needs one Talos extension)
Driver stages by `nsenter`-ing to the host and running `iscsiadm`, which the
Talos base image does **not** ship → earlier mount failed
(`nsenter: failed to execute iscsiadm`). Fix: add the **`siderolabs/iscsi-tools`**
official extension.

## Applying extensions WITHOUT rebuilding/uploading the ISO
System extensions are baked into the immutable rootfs at build time and **cannot
be loaded at runtime** — but you do **not** need to rebuild/re-upload an ISO.
Extensions release via the factory **installer image**, applied as an in-place
`talosctl upgrade` (no data loss, no re-provisioning, no new ISO on Proxmox):

```sh
# schematic id for qemu-guest-agent + iscsi-tools (see tofu local.talos_schematic)
talosctl upgrade --image=factory.talos.dev/installer/<NEW_SCHEMATIC_ID>:<talos_version>
```

Declarative source of truth: `var.talos_extensions` in the tofu (already
defaulted to include `siderolabs/iscsi-tools` for when we choose to apply).

## TrueNAS PVC plugin landscape
- **`truenas/truenas-csi`** — the official iX CSI driver (25.10+); this is what we
  use. Recommended by iX and the TrueNAS Terraform provider.
- `hpe-storage/truenas-csp` — TrueNAS Container Storage Provider (iSCSI via the
  HPE CSI Driver); the only notable alternative.
- `terricain/truenas-scale-csi` — community, older.

## Decision
Use **iSCSI** (`truenas-iscsi-fast`, default) now. To enable it: apply the
`siderolabs/iscsi-tools` extension via the in-place `talosctl upgrade` above, then
re-point node volume `/etc/iscsi` hostPath to `DirectoryOrCreate` (still required).
NVMe-oF stays configured (`truenas-nvmeof-fast`) as the preferred target once the
driver connect bug is resolved upstream. NFS remains the zero-extension fallback.