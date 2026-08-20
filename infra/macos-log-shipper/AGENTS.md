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

## Guest stdout reaches Loki through tart-kubelet, not through this agent

The runner VMs' `dispatch-poll.sh` output does **not** ride this agent directly,
and cannot: the guest redirects to a file inside itself
(`exec >>/var/log/tuist-runner/poll.log 2>&1`), the host's
`/var/log/tart-vms/<vm>.log` holds `tart run`'s own output rather than the
guest's, and Tart 2.32.1 has no macOS-guest console capture (`--serial` attaches
a virtio console a macOS guest never writes to).

It arrives anyway, by a shorter route. The guest mirrors its log into the
writable status share it already owns (`/Volumes/My Shared Files/status` → the
host's `VolumeStatusDir`) as `runner.log`, and **tart-kubelet re-emits a bounded
tail to its own stdout at teardown**, just before `deleteByKey` removes the
share. That stdout is `/var/log/tart-kubelet.log` — the file this agent already
tails. So the trail lands in Loki with no change here.

That indirection is deliberate. Tailing the shares directly was the obvious
design and is the worse one: the share is per-VM and ephemeral, so the agent
would need glob discovery, per-file position churn, and its own answer for the
pools where cache volumes are off and no share exists. Routing through
tart-kubelet costs one bounded read on a path that already had to touch the
share to recover the exit code, and this agent stays a single-file tailer.

The tradeoffs to know: the tail is emitted at teardown, so it is forensics after
the fact, not a live stream; a VM that never terminates, or one killed before its
EXIT trap runs, publishes nothing this way. The second case still reaches the
cluster distinguishably, as `TartRunExited` rather than a reported exit code.

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
