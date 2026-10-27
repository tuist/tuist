# Long-uptime macOS TCP clock stalls

The durable remediation is a drained upgrade of affected **host** operating
systems to a fixed kernel. Safe executable installation limits the damage from
a slow or interrupted transfer; it cannot fix the kernel. Rebooting an affected
kernel only resets the clock until another wrap. Updating a Tart guest image or
changing a fleet's provisioning OS family does not upgrade existing hosts.

## Evidence from October 26, 2026

`tuist-tuist-runners-fleet-mndbc-jl28k` was terminal Failed with
`TartKubeletUpdateExceededRetries`, while its Node was Ready. Read-only SSH,
process, stack and packet diagnostics showed:

| Signal | Affected `jl28k` | Healthy peer `2p44w` |
| --- | --- | --- |
| macOS / Darwin | 26.3.2 / 25.3.0 | 26.6.2 / 25.6.0 |
| Uptime | 102 days | 61 days |
| TCP TIME_WAIT sockets | 12,714 | 1 |
| TCP timestamps | TSval 2913531167 unchanged across samples minutes apart | no comparable stall observed |
| Transfers | roughly 10 KiB/s on the operator's public-IP SSH upload; tailnet also slow | 4 MiB to `/dev/null` in 0.87 seconds |

Two diagnostic connections stayed in TIME_WAIT for over four minutes. Root disk
had about 130 GiB free, and the operator upload did not show retransmission or
packet loss explaining the stall. The live `tee` process waited for stdin in
`read()`, its SSH process waited in `pselect`, and no code-signing process was
running. This isolates the delay to delivery of the stream rather than a stuck
disk write or signature operation.

This strongly matches the TCP clock wraparound described in
[the original investigation](https://photon.codes/blog/we-found-a-ticking-time-bomb-in-macos-tcp-networking).
Apple's [older XNU source](https://github.com/apple-oss-distributions/xnu/blob/xnu-12377.81.4/bsd/netinet/tcp_subr.c)
advances the 32-bit millisecond `tcp_now` using ordinary unsigned comparison.
The [corrected source](https://github.com/apple-oss-distributions/xnu/blob/xnu-12377.101.15/bsd/netinet/tcp_subr.c)
uses `TSTMP_LT` for modular arithmetic. The counter wraps every approximately
49.7 days. The exact affected host's XNU source tag was not published, and an
upgrade/recovery experiment was not performed during the read-only diagnosis;
the frozen timestamps, persistent socket timers and slow transfers are the
strongest direct evidence. The healthy peer establishes a tested fleet baseline
of macOS 26.6.2 / Darwin 25.6.0, not the earliest Apple release containing the fix.

The installer amplified the kernel failure. It streamed into
`sudo tee /usr/local/bin/tart-kubelet`, truncating the live inode. A previous
writer nearly twelve hours old and a current writer targeted the same inode.
The installed file was partial and failed signature verification while the old
process still ran. A restart at that point could strand the Node. All ten fleet
machines reported the same desired binary SHA in status: unrelated config drift
had unnecessarily triggered another 48,525,264-byte upload.

## Repository safeguards

- `macos-host-bootstrap` verifies the executable on disk before deciding to
  upload. A matching SHA-256, executable bit and valid signature skip the upload;
  status alone never does. A damaged file is eligible for repair even when the
  recorded SHA matches.
- Uploads go to a unique private directory on the destination filesystem. Only
  complete, checksum-matching, signature-valid bytes replace the executable,
  using rename. The old inode remains available to the running process. No
  in-place re-signing is necessary.
- A five-minute host-side watchdog terminates a stalled install independently
  of SSH disconnect handling. Its trap removes its own partial directory and
  writer. SIGKILL can leave a staging directory, but there is no promotion before
  checksum and signature verification. After a power failure, the next probe
  rechecks the file on disk. This does not retroactively terminate writers
  started by the legacy installer.
- `macos-host-sensors` reports installed OS/kernel, uptime, TIME_WAIT count and
  collection success. Each source has a bounded read; failed values are absent.
- The monitoring chart retains those four metric families. The
  [Grafana rule payload](../helm/k8s-monitoring/runner-macos-host-alert-rules.json)
  warns after 40 days on Darwin 25.0–25.3, after TIME_WAIT stays above 5,000 for
  15 minutes on any kernel, and on failed/stale collection. The risk rule is
  deliberately limited to the affected Tahoe family, not a claim that all other
  macOS releases are safe. TCP counts alone do not identify this bug.

## Rollout and operating-system remediation

1. Inventory installed versions, uptime and active workloads. Use macOS 26.6.2
   or a later approved Tahoe release as the fleet maintenance floor. Test the
   selected release's console login, Tart networking, cache volumes and runner
   acceptance on a drained host before expanding the wave. Do not guess a
   versioned Scaleway image identifier: `spec.os` must remain a release family.
2. On already-affected hosts, cordon and drain before recovery. With approved
   host access, inspect existing installer process trees. Stop only confirmed
   abandoned legacy writers and prevent overlapping drift attempts during the
   repair. Verify a complete operator-matching tart-kubelet binary and valid
   signature **before rebooting or restarting the service**. A CR status SHA
   and a currently running process do not prove the file is safe to launch.
3. Release the operator with the staged installer and host-health collector.
   Its changed `HostConfigHash` makes existing hosts reconverge, including hosts
   terminal on an older hash. Check operator logs for the actual failed step;
   a new installer does not make a frozen TCP stack fast enough to transfer a
   damaged binary. Use a separately approved repair/replacement path if needed.
4. Deploy the monitoring allow-list and provision the three Grafana rules in
   `Runner host health`. The JSON file is not installed by Helm. Keep existing
   exporter-availability alerts: the collection rule cannot detect a file that
   has never been written or a target that disappeared. Confirm every intended
   host emits all four metrics and `macos_host_health_collection_success == 1`.
5. Upgrade **existing** hosts one drained machine at a time, retaining spare
   capacity. Rack machines support the explicit `tuist.dev/os-update=<version>`
   workflow described in [Host macOS updates](AGENTS.md#host-macos-updates).
   ScalewayAppleSiliconMachine does not support that annotation: use the
   established planned CAPI replacement/pool lifecycle, checking the selected
   provider image and the replacement's installed version. Do not mass-delete
   Machines or assume a template change updates an `OnDelete` fleet. A spare
   pool machine must also meet the installed OS baseline; adoption matches only
   the family.
6. Before uncordoning each host, verify Node Ready, the expected OS/kernel,
   valid on-disk binary, successful config convergence, advancing TCP timestamps
   and normal transfer throughput. Run runner acceptance, then proceed to the
   next host. Retain a longer-term watch across 50 days uptime: a reboot alone
   temporarily hides the old kernel defect.

The terminal-state retry cooldown is already 30 minutes. Increasing retries,
clearing failure fields or changing SSH routes cannot repair this kernel bug.
Prefer automatic cooldown/new-hash recovery after fixing the cause over a
manual status reset; any CAPI status write remains a break-glass operation.

Rollback of an operator change must preserve the staged installer: returning to
the legacy writer reintroduces executable corruption. Stop the rollout and keep
an unhealthy host drained if OS acceptance fails; use a known-good spare rather
than repeatedly rebooting an old kernel or downgrading onto it.
