# TrueNAS VM — passthrough disk benchmarks

Storage benchmarks for the passed-through disks on the TrueNAS SCALE VM (VM 100)
running on the m920x Proxmox host. Run from **inside** TrueNAS (fio 3.33) against
the **raw block devices** — no filesystem, no ZFS ARC — so these are device-level
numbers.

- **Date:** 2026-08-20
- **Host:** Proxmox 9.1 on m920x (i7-8700, 15 GiB RAM)
- **Guest:** TrueNAS SCALE 25.10.6, VM 100 (q35/OVMF, full PCIe passthrough)
- **fio settings:** `--direct=1 --ioengine=libaio --time_based --runtime=30 --ramp_time=5 --group_reporting`
  - Sequential: `bs=1M`, `iodepth=32`, `numjobs=1`
  - 4K random: `bs=4k`, `iodepth=64`, `numjobs=4`

> Devices were wiped (`wipefs`/`sgdisk --zap-all`) before testing — no pools existed.
> Latencies are completion latency (clat).

## Devices under test

| Dev | Model | Bus / passthrough | Capacity | Notes |
|-----|-------|-------------------|----------|-------|
| `nvme0n1` | Crucial P1 `CT1000P1SSD8` (SN 2004E285575C) | NVMe, `0000:03:00.0` (whole device) | 1 TB | DRAM-less QLC; 16% wear, 7059 PoH |
| SanDisk `SD8TB8U256G1001` (SN 174062804891) | — | SATA on ASMedia ASM1064, `0000:02:00.0` | 256 GB | Node shuffles (`sda`/`sdb`); ID by serial. Worn — slow writes |

---

## Crucial P1 1TB NVMe (`nvme0n1`) — valid

| Test | Bandwidth | IOPS | Avg lat | p99 | p99.99 |
|------|-----------|------|---------|-----|--------|
| Seq read (1M, QD32) | **2056 MB/s** | 1,960 | 15.9 ms | 31.1 ms | 72.9 ms |
| Seq write (1M, QD32) | **1386 MB/s** | 1,320 | 23.6 ms | 76.0 ms | 135.3 ms |
| Rand read (4K, QD64×4) | 1339 MB/s | **326,985** | 0.78 ms | 2.77 ms | 4.05 ms |
| Rand write (4K, QD64×4) | 1046 MB/s | **255,470** | 1.00 ms | 1.32 ms | 18.7 ms |

Healthy, near spec for a Gen3 QLC drive. PCIe passthrough (with the
`x-msix-relocation=bar2` MSI-X fix) is performing with no measurable overhead.

**Caveat:** the P1 is DRAM-less QLC with an SLC write cache. The 30 s sequential
write (1386 MB/s) fits inside the SLC cache; sustained writes past the cache will
drop substantially. For a worst-case number, re-run seq write with a much larger
run (e.g. `--runtime=300` or a full-device fill).

---

## SanDisk 256GB SATA SSD — valid (after reseating cable, 2026-08-21)

> Device-node names shuffle across reboots — the SanDisk was `sdb` in the first
> run and `sda` here. **Always identify it by serial (174062804891), never by
> `/dev/sdX`.** (The first run's `/dev/sdb` is the 32 GB VM boot disk after a
> reboot, so a blind re-run of the old command would have hit the boot disk.)

Link now negotiated at **SATA 3.2, 6.0 Gb/s**. `UDMA_CRC_Error_Count` held flat
at 595 across the whole destructive suite (no new interface errors); no ICRC /
ATA-bus errors in dmesg.

| Test | Bandwidth | IOPS | Avg lat | p99 | p99.99 |
|------|-----------|------|---------|-----|--------|
| Seq read (1M, QD32) | 475 MB/s | 452 | 70.9 ms | 263 ms | 312 ms |
| Seq write (1M, QD32) | **77.7 MB/s** | 73 | 434 ms | 1418 ms | 3339 ms |
| Rand read (4K, QD64×4) | 149 MB/s | 36,455 | 6.9 ms | 12.3 ms | 17.4 ms |
| Rand write (4K, QD64×4) | 72 MB/s | 17,571 | 14.3 ms | 57.4 ms | 320.9 ms |

**First run was invalid — flaky SATA cable, now fixed.** Initially the drive threw
`ICRC ABRT` / `ATA bus error`, hard-reset the link repeatedly, and downgraded to
**UDMA/33** (33 MB/s cap) — a marginal **physical connector**, not the flash and
not the passthrough. Reseating the SATA data + power connectors (no config change)
restored full-speed operation, which also confirms the ASM1064 **passthrough path
is healthy** (full-speed reads flow through it).

**Drive-health caveat:** writes are genuinely slow (~78 MB/s seq vs the X400's
~500 MB/s spec) while reads are full-speed. That is *not* a link issue (zero CRC
errors) — it's a worn drive: 34,385 power-on hours, low wear indicator. Fine for
read-mostly / scratch use; don't rely on it for write-heavy workloads.

---

## Proxmox host boot drive (Samsung PM991, `nvme0n1` on host) — read-only

Read-only test on the **live** PVE OS disk (no install, no writes):

```
dd if=/dev/nvme0n1 of=/dev/null bs=1M count=10000 iflag=direct
```

**760 MB/s** sequential read (10 GB).

**Caveat:** `dd` is single-threaded at QD1, which cannot saturate an NVMe drive —
this is a read-throughput *floor*, not the drive's ceiling. It confirms the boot
drive reads healthily; it is not comparable to the queued fio numbers above.

---

## Follow-ups (optional)

- **NVMe sustained-write floor** — long/full-device write run to capture the
  post-SLC-cache number for the DRAM-less QLC P1.
- **SanDisk write speed** — worn drive; treat as read-mostly/scratch, replace if
  write throughput matters.
