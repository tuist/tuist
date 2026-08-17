# macos-log-shipper

`tuist-log-shipper` — the host-side log agent installed on every Mac mini in
the macOS fleets. It tails `/var/log/tart-kubelet.log` and pushes new lines to
a Loki-compatible endpoint over the tailnet.

Installed by [`infra/macos-host-bootstrap`](../macos-host-bootstrap)
(`installLogShipper` / `renderLogShipperScript`) as the launchd daemon
`dev.tuist.log-shipper`, from a darwin/arm64 binary cross-built into the CAPI
operator image. Same lifecycle as `node_exporter`: baked into the operator
image, uploaded over SSH at bootstrap, re-pushed on every drift roll because
its bytes are in `bootstrap.HostConfigHash`.

## Why a host agent and not a DaemonSet

`tart-kubelet` turns a Pod scheduled to a macOS Node into a Tart VM. A log
collector deployed as a DaemonSet therefore lands *inside a virtual machine*
with no view of the host filesystem, so the whole standard
collector-on-every-node pattern is unavailable here. `kubectl logs` does not
help either: the apiserver cannot resolve these kubelets' tailnet-only
hostnames.

The consequence, before this existed, was that everything `tart-kubelet` logs
— the pod reconciler, the node agent, the cache-volume manager — was reachable
only by SSHing to the mini. Investigations that needed it (why a host declines
cache-volume convergence, why a CAS lane goes cold) dead-ended, and each one
was answered by designing a bespoke counter in advance instead.

## Why not Alloy or Promtail

The operator uploads every host binary over SSH on each drift roll, so binary
size is roll time multiplied by the fleet. Alloy is two orders of magnitude
larger than what "tail a file, POST it" needs, and its config surface is
mostly components that cannot run here anyway. Promtail is the right size but
upstream has ended its life. What is left is ~500 lines of stdlib Go and a
~6MB binary.

## Direction, and why there is no credential on the host

Metrics are **pulled**: `alloy-metrics` dials each mini's `:9100` through the
Tailscale operator's egress ProxyGroup. Logs are **pushed**, because a file has
no scrapeable surface.

They are pushed to the in-cluster Alloy receiver's `loki.source.api` (port
3100) at its tailnet hostname — not to Grafana Cloud. Alloy already holds the
Grafana Cloud token and forwards, so no ingest credential is ever distributed
to nine internet-facing Mac minis; the tailnet ACL
([`infra/tailscale/acls.json`](../tailscale/acls.json), `tag:tuist-macmini-<env>`
→ `tag:tuist-k8s-<env>` on `tcp:3100`) is the access control. This is the same
path the xcresult processor's Tart guests already use for their own logs.

## Design

- **The file on disk is the buffer.** There is no in-memory queue, so a Loki
  outage cannot grow the agent's memory. It stops advancing its offset and
  catches up later in ≤1MiB chunks.
- **Offsets advance only after a successful push**, so a crash re-ships at most
  one batch instead of losing it. Loki deduplicates identical
  `(stream, timestamp, line)` entries, so the overlap is invisible.
- **A retryable failure retries forever** (capped backoff). A permanent
  rejection (4xx that is not 429 — a malformed body, or entries older than the
  tenant's accepted window, which is what a long catch-up produces) drops the
  batch and advances, because blocking on it would stall every later line
  behind lines that can never land.
- **A file seen for the first time starts at its END.**
  `/var/log/tart-kubelet.log` is never rotated, so byte 0 on a long-lived host
  is months of history Grafana Cloud would mostly reject as too old.
- **The file is re-opened per poll, not held open.** Holding the descriptor is
  how a tailer follows a rotated file to its end, and also how it pins a
  deleted multi-gigabyte file against a disk that already needs a golden-image
  GC to stay ahead. The trade is the last few lines of a rotated file.
- **The agent's own diagnostics are not shipped** (they go to
  `/var/log/tuist-log-shipper.log`). Shipping push failures through the shipper
  turns an outage into a loop.

## The agent publishes its own health through node_exporter

The agent is the thing that reports, so when it breaks nothing reports.
"Installed but failing" and "not installed" look identical from off-host, and
that produced two multi-day outages: the agent shipped and never delivered a
line, while `launchctl print` reported the job `running` with correct arguments
throughout; the first fix landed on a misread test and production kept failing
for another day at attempt 494 per host. Through both investigations SSH to the
minis hung and production `kubectl` through the Pomerium gateway never returned,
while `:9100` answered instantly, every time. So the health signal rides `:9100`.

It goes out as a Prometheus textfile at
`/var/lib/node_exporter/textfile/tuist-log-shipper.prom`
(`shipper.DefaultHealthPath`, `--metrics` to override), which node_exporter's
textfile collector reads on every scrape. Per tailed source, labelled
`source_job` and **not** `job` (see below):

| Metric | What it answers |
| --- | --- |
| `tuist_log_shipper_last_success_timestamp_seconds` | When a push last returned 2xx. **`0` means this source has never delivered a line** — the state both outages were in. |
| `tuist_log_shipper_consecutive_failures` | Failed read or push attempts since the last accepted push. Counted per attempt from inside the retry loop, so it matches the `attempt N` in the agent's log. |
| `tuist_log_shipper_position_offset_bytes` | How far the agent has read **and** pushed. |
| `tuist_log_shipper_source_size_bytes` | The source file's size right now. The gap to the offset is the lag. |
| `tuist_log_shipper_build_info` | `binary_sha256` of the on-host executable and the Go version. Which binary a host carries was itself an open question during the last incident, and the place that answers it (`HostConfigHash` on the Machine) sits behind the kubectl gateway that did not answer. |

Six things about the implementation are load-bearing:

- **The source label is `source_job`, not `job`.** `job` is a reserved target
  label. The scrape runs with `honor_labels=false` (the default; the fleet's
  scrape does not override it), so a `job` in the exposition collides with the
  scrape's own `job_name`: the sample would arrive carrying
  `job="tuist-macos-node-exporter"` with our value silently moved to
  `exported_job`, and every query grouping by `job` would collapse all sources
  into one and label them with the scrape job. The *value* is still the Loki
  `job` label the source's lines carry, so it joins straight against
  `{job="tuist-macos-tart-kubelet"}` in Loki.
- **The write is atomic** — temp file in the same directory, then `os.Rename` —
  so a scrape landing mid-write reads the previous complete document instead of a
  half-written one. What that protects is narrower than it first appears: see the
  measurements below.
- **The temp file must not end in `.prom`** (it is `.tmp`). node_exporter selects
  files by that suffix, so a `.prom` temp is parsed too and the rename stops
  being atomic from the collector's point of view. Stale temps from an earlier
  crash are swept at construction.
- **The count comes from inside the push retry loop, not from poll boundaries.**
  `push` retries a retryable failure forever, so during a receiver outage `poll`
  never returns. A poll-boundary-only writer would publish nothing for the
  duration of the exact failure this exists to expose.
- **The published size is re-stat'd on every failed attempt** (`Shipper.observe`),
  for the same reason: a size captured when the blocked poll started would report
  a constant lag through an outage of any length.
- **A failure to write the textfile does not stop shipping**, and is logged once.
  Losing the logs to keep the metric would be strictly worse than not having the
  metric.

### What the collector actually does with a bad file

Measured against node_exporter 1.8.2 on a production mini, because the intuitive
answers are wrong in both directions:

| Situation | What happens |
| --- | --- |
| A file fails to parse (a partial write) | Only that file is lost. `node_textfile_scrape_error` goes to 1, no `node_textfile_mtime_seconds` is emitted for it, the parse error is logged per file, and **every other file and collector is unaffected** — `node_scrape_collector_success{collector="textfile"}` even stays 1. |
| Two files hold the same series with **different** values | The collector serves whichever the directory walk reaches first and **silently drops the other**, with `node_textfile_scrape_error` staying **0**. |

So a malformed file does *not* take the host's `node_*` series down with it, which
is a claim worth not repeating. The severe case is the second row: a `.prom` temp
abandoned by a crash is a complete document with stale values, so a leftover
sorting before the real file pins this agent's health at whatever it said —
including a healthy-looking zero — with no error metric anywhere. A lost scrape is
a gap; a leftover is a lie. That is why the suffix matters more than the
atomicity, and why the sweep exists.

One useful consequence: a permanently corrupt `.prom` emits no mtime series, so
it does not merely stall the heartbeat rule, it trips the absence rule instead.

Two node_exporter metrics complete the picture without costing us anything:
`node_textfile_mtime_seconds` is a heartbeat (the file is rewritten on every poll
outcome, so a dead agent stops advancing it), and `node_textfile_scrape_error`
catches a malformed file. Both, plus `tuist_log_shipper_.*`, are in the Alloy
keep-list in [`infra/helm/k8s-monitoring`](../helm/k8s-monitoring)'s
`values.yaml` — a series not named there is dropped before Grafana Cloud, so
adding a metric here means adding it there. Recommended alert rules are in that
chart's `alerts.md` under *Runner host log shipper*; note that neither the
failure-count rule nor the heartbeat rule can see an agent that died before its
first write, which is what *Runner host log shipper absent* is for.

The uninstall removes the `.prom` file along with the binary. node_exporter keeps
reading the directory whether or not the agent exists, so a left-behind file
would publish a frozen `last_success` forever — a phantom agent alerting about a
host that carries none.

**A positions offset that equals the file size proves nothing shipped.** `poll`
on first sight of a file calls `ReadNew` with `exists=false`, which returns the
end-of-file position and zero lines, persists it, and returns without pushing —
no network call happens. That is what a "successful push" was read from once. The
test that exercises the network appends a line *after* first sight and checks the
offset advances past the first-sight mark; confirm any new metric the same way,
by asserting `last_success_timestamp` moves after an append.

## Labels

Every line carries `job`, `instance`, `env` and `level`. Nothing else, and
nothing unbounded — `level` is matched against an allow-list precisely because
it is an index label and a line claiming `"level":"<anything>"` would otherwise
mint a stream per distinct value.

`tart-kubelet` logs through controller-runtime's zap in production mode (JSON
per line), so `level` and the event's own `ts` are read from the line rather
than invented. A timestamp implausibly far from the agent's clock falls back to
read time, so one bad line cannot make its whole batch a permanent rejection.

## Querying

```
{job="tuist-macos-tart-kubelet", env="production"}
{job="tuist-macos-tart-kubelet"} |= "converge"
{job="tuist-macos-tart-kubelet", instance="tuist-tuist-runners-fleet-abc12", level="error"}
```

`instance` is the CAPI Machine / Node name, so it joins directly against the
`node_*` and `tart_kubelet_*` metrics scraped from the same host.

## What lands in Loki is documented as stored data

`tart-kubelet`'s cache-volume lines carry the Tuist **account id** (from the
`tuist.dev/runner-account` label the server stamps at dispatch), so this stream
is account-correlated operational telemetry, not just infrastructure noise. It
is written up in [`server/data-export.md`](../../server/data-export.md) under
Non-Exportable Data, alongside the Kura traces in Tempo.

Adding a new tailed file, or a new field to an existing line, is a change to
what Tuist stores about an account. Update that document in the same change.

## Rollout

Gated per env by `macosFleet.hostLogs.enabled` in
[`infra/helm/tuist`](../helm/tuist), mirroring `macosFleet.tailscale.enabled`,
with the receiver's tailnet hostname in `macosFleet.hostLogs.url`. The
receiver has to be exposed on the tailnet in the matching env — the
`tailscale.com/expose` annotations on `alloy-receiver` in
[`infra/helm/k8s-monitoring`](../helm/k8s-monitoring)'s per-env values.

All three managed envs are on.

## The URL is a MagicDNS name, and this binary resolves it itself

**No MagicDNS name resolves on a Mac mini through the OS.** `tailscale dns
status` reports `Tailscale DNS: enabled`, but tailscaled installs no resolver:
`scutil --dns` contains no `100.100.100.100` entry and `/etc/resolv.conf`
carries only Scaleway's DHCP nameservers. On a production host, `curl
http://tuist-alloy-receiver-production:3100/...` fails, and so does the FQDN
form. Nothing on the host can turn a tailnet name into an address.

tailscaled's own MagicDNS server is listening at `100.100.100.100:53`
regardless, and answers. So `internal/shipper/dial.go` gives the push client a
resolver that asks it directly, falling back to the system resolver when it is
unreachable — the agent is `RunAtLoad`, so it can start before tailscaled is
listening, and a `--url` that is a plain address or a public name must still
work.

**`--url` must carry the fully qualified name** (`<host>.<tailnet>.ts.net`).
MagicDNS answers only fully-qualified queries, and these hosts have no `search`
domain to complete a short one, so a bare hostname `NXDOMAIN`s even when asked
directly. Both halves are required: the right resolver and the right name.

Three consequences worth keeping in mind:

- **A name that resolves from your laptop says nothing about a mini.** Your Mac
  runs a tailscaled that does configure the OS resolver; these hosts do not.
  Check with `scutil --dns | grep 100.100.100.100` on the host itself before
  assuming a tailnet name is reachable from it.
- **Do not swap the dialer out for `http.DefaultClient`.** It resolves through
  `/etc/resolv.conf` and every push fails with `no such host`, once a minute,
  while `launchctl print` reports the job `running`.

The flag is reversible. Turning it off moves the fleet host-config hash, and
the drift roll that follows unloads `dev.tuist.log-shipper` and removes the
binary and its positions file from every mini — so the rollback lever actually
stops ingestion instead of only stopping config pushes to a daemon that keeps
running. The uninstall is convergent, so it also runs on hosts that never had
the agent; it is a no-op there.

Positions go with the uninstall on purpose: the tailed log keeps growing while
the agent is off, so a re-enable that resumed from the stale offset would
replay the whole disabled window in one burst. A re-enable starts at the end of
the file, the same as a first install.

## Guest stdout is a separate problem — `tart run` cannot capture it

The runner VMs' `dispatch-poll.sh` output (the `cache dirty=` /
`cache image detached` lines that a CAS-poisoning investigation wants) does
**not** ride this agent, and cannot be made to without new plumbing. Two
independent reasons, both checked against what is actually deployed:

1. **The guest redirects before anything reaches a console.** `dispatch-poll.sh`
   opens with `exec >>/var/log/tuist-runner/poll.log 2>&1`, so its output goes
   to a file *inside* the guest. The host's `/var/log/tart-vms/<vm>.log` (which
   tart-kubelet already captures) holds `tart run`'s own output, not the
   guest's.
2. **Tart has no macOS-guest console capture.** At the pinned 2.32.1, the only
   options are `--serial` / `--serial-path`, which attach a
   `VZVirtioConsoleDeviceSerialPortConfiguration` and are documented upstream as
   "useful for debugging Linux Kernel". A macOS guest boots to the framebuffer
   and puts nothing on that device.

The cheapest path if this is picked up: the guest already has a **writable**
host share (`/Volumes/My Shared Files/status` → the host's `VolumeStatusDir`,
where it writes `cache-dirty` and `volume-head.json`), so `dispatch-poll.sh`
could `tee` into it and this agent could tail that directory. That is a real
design step, not a free one — the share is per-VM and ephemeral, so the agent
would need glob discovery, per-file position churn, and a story for the pools
where cache volumes are off and the share does not exist at all.

## Do not add log rotation for the tailed file

`/var/log/tart-kubelet.log` grows unbounded, and adding a `newsyslog.d` entry
looks like the obvious fix. It is not: launchd holds the `StandardOutPath`
descriptor open for the lifetime of the job, so a rename-style rotation leaves
tart-kubelet writing into the rotated inode and the new file empty until the
job restarts — silently ending host logging entirely. The agent handles
rotation and truncation if something else causes them; it must not be the
reason someone introduces them.

## Build

```bash
cd infra/macos-log-shipper
go test ./...
GOOS=darwin GOARCH=arm64 CGO_ENABLED=0 go build ./cmd/tuist-log-shipper
```

Stdlib only — no `go.sum`, nothing to `go mod download`. Keep it that way; the
whole argument for a purpose-built agent is that it stays small enough to ride
every SSH drift roll.
