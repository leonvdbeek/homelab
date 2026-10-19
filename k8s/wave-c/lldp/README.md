# UniFi topology (LLDP) for VMs behind m920x

UniFi builds the device tree from **LLDP** advertisements. For VMs/LXCs to nest
under the m920x entry, each must run `lldpd`, and the Linux bridges must be told
to *forward* LLDP (Linux bridges filter it by default).

## Host (m920x, Proxmox)
```bash
apt install lldpd && systemctl enable --now lldpd
# A Linux bridge drops LLDP (mac group 0x0180c200000e) unless group_fwd_mask bit 14 set:
for br in vmbr0 fwbr102i0 fwbr105i0 fwbr101i0; do
  echo 16384 > /sys/class/net/$br/bridge/group_fwd_mask
done
# persist: add 'net.bridge.bridge-nf-call-*' note + script, or set in ifupdown hooks
```

## VMs / LXC (these run `lldpd` so UniFi nests them under m920x)
- portainer (101), vault (106), hermes (105): `apt install lldpd`
- cluster/node: `k8s/wave-c/lldp/lldp.yaml` DaemonSet (privileged + hostNetwork)
  runs lldpd bound to the node NIC, advertising the talos VM's identity.

## Verify
```bash
lldpcli show neighbors   # on m920x: should list UCG-Fiber, USW switch, machines
```

## Caveats (known UniFi behavior)
- Topology is L2-only and imperfect: can take minutes to settle and may "jitter".
- Stable chassis IDs reduce flapping: `lldpcli configure system chassisid <name>`.
- trueNAS / Home Assistant don't ship lldpd easily -> they may stay at top level.
- Needs UniFi switch/gateway LLDP enabled; non-UniFi virtual bridges often ignored.

## Note on the VIP / tree behind talos
The UniFi tree is L2 (LLDP). The cluster VIP (.60) is an L2/L3 *address*, not a
device, so it won't appear as a node behind talos. Making pods/services appear
as a sub-tree would need per-pod LLDP (unusual). BGP (Cilium BGP CP) is about
routing/LB-HA, orthogonal to the L2 tree. UCG-Fiber (OSA 4.1.13+) supports BGP
peering for if/when we want HA VIP + dynamic LoadBalancer IP advertisement.