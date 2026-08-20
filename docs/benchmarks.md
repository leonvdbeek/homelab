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
| `sdb` | SanDisk `SD8TB8U256G1001` (SN 174062804891) | SATA on ASMedia ASM1064, `0000:02:00.0` | 256 GB | **Flaky SATA link — see below** |

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

## SanDisk 256GB SATA SSD (`sdb`) — INVALID: flaky SATA link

The SSD, freshly wired to the ASMedia ASM1064 controller, throws **SATA
interface CRC errors** under load. The kernel logs `ICRC ABRT` / `interface fatal
error` / `ATA bus error`, hard-resets the link, and downgrades it to **UDMA/33**
(33 MB/s cap). That degradation — not the flash — is why fio saw single-digit
MB/s and multi-second latencies (and one run failed outright).

Evidence:
- `dmesg`: `ata10.00: error: { ICRC ABRT }`, `interface fatal error`, repeated
  `hard resetting link`, `configured for UDMA/33`.
- SMART `199 UDMA_CRC_Error_Count = 595` (interface CRC errors accumulating).
- On a freshly-reset clean link, a short seq read hit **184 MB/s** — i.e. the
  drive is fine when the link holds.
- SMART health **PASSED**: 0 reallocated, 0 pending, 0 reported-uncorrect. Media
  is healthy (power-on 34,385 h).

**Root cause:** marginal SATA **data cable / power / connector** (classic ICRC +
UDMA-downgrade signature), not the disk or the controller.

**Action:** reseat or replace the SATA data cable (and check the power lead),
then re-run the fio suite. Numbers above for `sdb` should be discarded.

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

## Pending

- **SanDisk SSD re-benchmark** after the SATA cable is fixed.
