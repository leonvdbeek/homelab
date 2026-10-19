# Migrate Talos cluster to a dedicated UniFi VLAN network "talos"

Status: **BLOCKED on Phase A (UniFi network creation)** — needs authenticated
UniFi Network App access (Network Integration API key) or manual Console steps.

## Target
- UniFi network `talos`: VLAN 40, subnet `10.0.0.0/24`, gateway `10.0.0.1`
- Node ens18: static `10.0.0.10/24`, gw `10.0.0.1`
- Cluster VIP (talos-native, ARP): `10.0.0.60`
- Remove `lenovium` network.
- Inter-VLAN routing default(192.168.4.0/24) <-> talos(10.0.0.0/24), because the
  cluster depends on: trueNAS .111:3260 (iSCSI - ALL PVC storage), odysseus .200:445
  (SMB stash media), gateway .1.

## Pre-migration baseline (2026-10-19)
All PVCs Bound (truenas-iscsi-fast + odysseus-smb). trueNAS:3260 + odysseus:445
reachable. VIP .60 / node .230 (DHCP) today.

## Phase A - UniFi Console / API key (requires admin)
1. Delete `lenovium`.
2. Create `talos`: VLAN 40, 10.0.0.0/24, DHCP off.
3. Inter-VLAN routing on + LAN_IN allow rules BOTH directions (default<->talos).
4. Switch port hosting m920x = trunk: tagged VLAN 40 + native/default.
5. Confirm VPN clients can route to 10.0.0.0/24.
-> Then `secret/homelab/unifi` holds the API key; wire UniFi MCP.

## Phase B - Proxmox bridge + VM tag (apply AFTER A)
Add to /etc/network/interfaces (vmbr0) and ifreload, or via PVE:
```
iface vmbr0 inet static
    bridge-ports nic2
    bridge-vlan-aware yes
    bridge-vids 40
    bridge-vlan-only no       # keep default VLAN for the .4.x VMs
```
Then tag the Talos VM net0: `qm set 9000 -net0 ... ,tag=40`
(MAC unchanged BC:24:11:94:B4:A9). Keep # the machine MAC in the doc.

## Phase C - tofu/talos changes
- In `talos.tf` ens18 interface block: addresses `["10.0.0.10/24"]`, gateway
  `10.0.0.1`, keep `vip: {ip = var.cluster_vip}`.
- In `variables.tf`: `cluster_vip` = `10.0.0.60`.
- Regenerate machine config + `tofu apply`; node reboots onto VLAN 40.
- Point talosctl/TALOSCONFIG endpoint at `https://10.0.0.60:6443`.

## Phase D - verify on new network
- `talosctl ... get nodes` + kube-apiserver at 10.0.0.60:6443
- traefik serves 10.0.0.60:443; all pods Running
- iSCSI PVCs still Bound; stash-media (odysseus SMB) still mounts
- NodePort test URLs -> 10.0.0.10:30055/30883/30999/30966/30900
- update hosts-file / client refs from .60/.230 -> 10.0.0.60/.10

## Phase E - rollback (reversible until DNS cutover)
- qm set 9000 net0 without tag; tofu revert static->DHCP + cluster_vip .60
- apply -> cluster back on .230/.60.

## Notes
- Cross-VLAN storage (iSCSI/.111 + SMB/.200) is the fragile part; verify routing
  BEFORE cutting the VM over.
- Certs use Cloudflare DNS-01 (outbound) - unaffected by subnet change.
- service/pod CIDRs (10.96/10.244) unchanged; only host/VIP move.
## DONE (2026-10-19)
Cluster successfully moved to VLAN 40 / 10.0.0.0/24:
- node talos-r7i-a74 = 10.0.0.10 (static), VIP = 10.0.0.60 (Talos-native ARP)
- kube-apiserver 10.0.0.60:6443; kubeconfig/talosconfig updated
- cross-VLAN storage verified FROM talos subnet: trueNAS :3260, odysseus :445
- 9 apps Running, 11 PVCs Bound
- HOW: qm set net0 tag=40; talosctl apply-config --file <full config
  extracted from `get machineconfig` spec-block, edited endpoint/certSANs/
  interface> (DHCP safety-net on the talos UniFi network caught the first
  apply misstep at 10.0.0.245; kept as resilience net)
REMAINING (declarative catch-up):
- tofu state/plan still references old .230/.60 + repo drift (v1.10 default,
  schematic) -> reconcile tofu to v1.14.4 + 10.0.0.x before next tofu use
- DNS cutover still deferred (last step)
- NodePort test URLs now http://10.0.0.10:30055/30883/30999/30966/30900
