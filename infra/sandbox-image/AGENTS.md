# sandbox-image

Guest side of the Firecracker sandboxes run by `infra/sandboxd`: the kernel,
the rootfs and the three binaries that live in it. The host side, the vsock
protocol and the node layout are specified in `infra/sandboxd/AGENTS.md`; this
node only covers what is inside the VM and how the template reaches a node.

## Contents

| Path | What |
|---|---|
| `cmd/sbx-init` | PID 1. Mounts proc, sysfs, devtmpfs, devpts, /dev/shm, /run, /tmp and cgroup2; names the guest from the kernel command line; configures `lo` and `eth0` (`10.0.0.2/30`, default route `10.0.0.1`, MAC left to the VMM) with netlink; writes `/etc/resolv.conf`, `/etc/hostname` and `/etc/hosts`; creates `/workspace` and `/mnt/memory`; supervises `sbx-agent` with 1s to 30s backoff; reaps orphans; powers off on SIGTERM (and on SIGINT, which is what Firecracker's ctrl-alt-del becomes). Logs to the console and `/dev/kmsg`. Linux-only; the non-Linux build is a stub. |
| `cmd/sbx-agent` | vsock server on port 5000. `-listen tcp://127.0.0.1:5000` runs it on a TCP socket for development. When the guest has a virtio balloon (sandboxd's `BALLOON_FREE_PAGE_REPORTING`), it also checks every 30 s and, after two intervals with the guest's CPU under 5% busy, writes the page cache above 64 MiB to the root cgroup's `memory.reclaim` (`internal/guest/reclaim.go`); free page reporting then hands those pages back to the host. Without a balloon it never reclaims. |
| `cmd/sbx-worker` | Runs one already-claimed Managed Agents work item with the Anthropic Go SDK's `EnvironmentWorker.HandleItem`, or, with `SBX_CLAUDE_CODE_WORK_ORDER`, one Claude Code session's `claude self-hosted-runner` (see `infra/claude-code-runners/README.md`). Started by that runner with `CLAUDE_RUNNER_CLAUDE_BIN`, it is the session wrapper: it adds `TUIST_OIDC_TOKEN` and execs Claude Code, keeping stdin and fd 3. It must stay root-owned in the guest so sessions cannot change it. With `SBX_CHECKOUT_PATH` and `SBX_CHECKOUT_COMMIT` (`checkout.go`), it copies the host's checkout master to the runner's clone before the runner starts (macOS: the image in `SBX_CHECKOUT_SHARE`; Linux: a tar over vsock port `SBX_CHECKOUT_VSOCK`, accepted only with its end-of-archive blocks) and exports that commit's objects in CI's export format after the runner exits. A repository already at the path that holds `.git/sbx-checkout-prepared.json` came from the host's prepared workspace: the worker moves that marker to its export state instead of seeding. A failed checkout only costs the clone; it never stops the session. |
| `cmd/sbx-macos` | Darwin-only stdin bridge for Tart guest execution and managed workers. Process-group fencing tests must run on macOS; the provider image workflow gates publication on that suite. |
| `internal/protocol` | Request and response frames, newline-delimited JSON. |
| `internal/exec` | Command registry: process groups, streamed stdout/stderr, timeouts (exit 124), kill by exec id. |
| `internal/agent` | Op dispatch behind a `System` interface, tested over `net.Pipe`. |
| `internal/guest` | The Linux implementation of `System`: `clock_settime`, `sethostname`, neighbour flush, workspace disk, cache drive. Stubs elsewhere. |
| `internal/sysconfig` | Rendering of the hostname, hosts and resolver files and kernel command line parsing. |
| `Dockerfile`, `install-template.sh` | Template image and its entrypoint. |
| `agent-home` | The skill installed into `user`'s home. |

The rootfs is Ubuntu 24.04 with the apt toolchain listed in the Dockerfile plus
Node.js 22 (nodesource), the GitHub CLI, `mise` (activated from
`/etc/profile.d/mise.sh`, shims in non-interactive shells) and the Anthropic
`ant` CLI 1.30.0 as a fallback worker; its .deb installs a single `/usr/ant`
binary, symlinked to `/usr/local/bin/ant`. Claude Code is installed at
`/usr/local/bin/claude`, pinned by `CLAUDE_CODE_VERSION`/`CLAUDE_CODE_SHA256`
to the version `sbx-worker` expects (`claudeCodeVersion` and
`claudeCodeChecksums` in `cmd/sbx-worker/claude_code.go`). The copies here, in
`infra/claude-code-runners/Dockerfile` and in tart-kubelet's
`internal/macosandbox/tools.go` must match; `claude_code_pins_test.go` fails
when one drifts, so bump all of them together. `agent-browser` (pinned by
`AGENT_BROWSER_VERSION`, matching Amp's default orb image) is installed
globally, with its Chrome for Testing in `/home/user/.agent-browser` and the
browser's system libraries from apt. Amp Desktop's stack is baked in too:
`/opt/amp-wayland` (labwc and waymote, one layer of Amp's orb image fetched by
`AMP_WAYLAND_LAYER` digest) and the apt packages Amp's custom-image contract
lists. Nothing of it runs until Amp starts the Desktop session, and Amp
installs Google Chrome on that first start. `sbx-init` creates `/run/lock`,
which Amp's app installer locks.

Agents get the project's Tuist data without setup. The Tuist CLI is at
`/usr/local/bin/tuist`, pinned by `TUIST_VERSION`/`TUIST_SHA256` to a release
that signs in with the sandbox's workload identity.
`.github/workflows/update-tuist-cli.yml` bumps both with `mise.toml`'s pin.
Struo is at `/usr/local/bin/struo`, pinned by `STRUO_VERSION`/`STRUO_SHA256`, with
`libasound2t64`, which its binary links. Thread agents build and test with it
first (`Tuist.Threads.Agent`), and it reports progress to the file every
sandbox command names in `STRUO_PROGRESS` (`Tuist.Sandboxes.Commands`).
`agent-home/skills/` becomes `~/.claude/skills/`, which both Amp and Claude
Code read. The image deliberately ships no MCP configuration: a preinstalled
server adds its tools to every session, fails for accounts that did not connect
the sandbox, and duplicates connectors users already have. The server still
accepts sandbox identity tokens at `/mcp` for anyone who adds it themselves.

## Boot contract

- Kernel command line: `console=ttyS0 reboot=k panic=1 pci=off root=/dev/vda rw
  rootfstype=ext4 init=/sbin/sbx-init sbx.dns=<ip,ip> sbx.hostname=<name>`.
  `sbx.dns` is comma separated and falls back to `1.1.1.1`; `sbx.hostname`
  falls back to `sandbox`.
- `/dev/vda` is the rootfs. `/dev/vdb` is the workspace disk: attached but not
  mounted when the template snapshot is taken. `sbx-init` never touches it.
- `configure` over vsock owns `/dev/vdb`. With `format_workspace: true` it
  unmounts anything already at `/workspace`, runs `BLKFLSBUF` on the device,
  `mkfs.ext4 -q -F -L workspace` and mounts it. Without the flag it flushes and
  mounts only when nothing is mounted at `/workspace` yet, and otherwise leaves
  it alone. The flush is there because the block layer may still hold zero
  sectors it cached from the empty template disk before the sandbox's own disk
  file was substituted under the same device.
- `/dev/vdc`, when sandboxd attaches one, is a private clone of a runner-cache
  volume (or, in a template snapshot built with `CACHE_DRIVE_IN_TEMPLATE`, a
  blank 1 MiB placeholder). After the workspace, `configure` runs `BLKFLSBUF`
  on it and, when it holds ext4 and nothing is mounted at `/mnt/tuist-cache`,
  mounts it there read-write with `noatime`. Each `~/` spelling of its
  `.tuist-paths` manifest (tuist-cache-volume's layout: `data` or the
  spelling's sha256) is bound at that path under `user`'s home, with the
  missing directories created and the subtree handed to `user`. Absolute and
  home-escaping spellings are skipped, and so is a symlinked path component.
  Relative spellings (`server/deps`) are relative to the CI job's checkout:
  `sbx-worker` binds them into the session's checkout after seeding it
  (`BindCheckoutCache`), only where the checkout has nothing or an empty
  directory at that path, so a repository snapshot's own deps win.
  `validate-checkout-cache.sh` in sandboxd proves it on KVM.
  A cache problem is logged and never fails `configure`; a resume finds the
  mount in place and does nothing, and a cold reboot mounts it again.
- `sbx-agent` listens on vsock port 5000, one request per connection. The
  frames are the ones in `infra/sandboxd/AGENTS.md` plus the optional boolean
  `format_workspace` on `configure`. `exec` runs as root with `/workspace` as the
  default cwd and `PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`,
  `HOME=/root`, `LANG=C.UTF-8` merged under the request's env. A `started`
  frame carries the exec id that `kill` targets; a timed out command is
  killed and reported as exit 124.
- `sbx-worker` reads `ANTHROPIC_SESSION_ID`, `ANTHROPIC_WORK_ID`,
  `ANTHROPIC_ENVIRONMENT_ID`, `ANTHROPIC_ENVIRONMENT_KEY`,
  `ANTHROPIC_WORK_SECRET` and optionally `ANTHROPIC_BASE_URL` (honoured by the
  SDK client itself), plus `SBX_WORKDIR` (default `/workspace`) and
  `SBX_MAX_IDLE` (Go duration, default `30s`). It exits 0 after a clean end,
  an idle timeout, a session termination or a SIGTERM, and 1 otherwise.

## Building

The module is not listed in the repository `go.work`, so run Go with
`GOWORK=off` from this directory:

```
GOWORK=off go vet ./... && GOWORK=off go test ./...
GOWORK=off CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build ./cmd/...
docker build --platform linux/amd64 -t sandbox-template:dev .
```

`go test ./...` runs on macOS: vsock and the Linux syscalls sit behind build
tags and the `System` interface. The Dockerfile builds the binaries natively
and cross-compiles them, assembles the Ubuntu 24.04 guest under emulation when
the host is not amd64, and formats the rootfs natively with `mkfs.ext4 -d`.
Build args: `KERNEL_URL` (Firecracker CI 6.1.155 by default), `KERNEL_SHA256`
(verified when non-empty), `NODE_MAJOR`, `ANT_VERSION`, `AGENT_BROWSER_VERSION`, `AMP_WAYLAND_LAYER`,
`VERSION` (stamped into `sbx-agent`'s `agent_version`), `AMP_VERSION` (pinned
Linux amd64 CLI, verified against its published SHA-256), `TUIST_VERSION` and
`TUIST_SHA256` (the release's `tuist-linux-x86_64.tar.gz` and its line in
`SHASUMS256.txt`), `STRUO_VERSION` and `STRUO_SHA256` (the release's
`struo-<version>-x86_64-unknown-linux-gnu.tar.gz` and its `.sha256`).

`GUEST_IMAGE` (default `guest`, the stage above) names what the template
boots, and `TEMPLATE_NAME` (default `default`) what `metadata.json` records.
Any linux/amd64 image pinned by digest works: the `agents` stage copies the
guest binaries in and runs `scripts/guest-contract.sh`, which installs nothing
and fails naming what the image lacks (`/bin/bash`, `git`, `sudo`,
`mkfs.ext4`, `resize2fs`, a UID/GID 1000 account and the like). It names UID
1000 `user` as well when the image calls it something else (the Linux runner
image's `runner`), adds `builder` on 2000 and `user`'s passwordless sudo, and
writes the image's `ENV` to `/etc/profile.d/00-image-env.sh`, since a rootfs
has no image config. Install the result with the same `TEMPLATE_NAME`.
`validate-ci-template.sh` in sandboxd boots the published runner image this
way on KVM (`sandbox-orbs-validation.yml`, `ci_template` input).

## Template init container

The final stage is Alpine with GNU coreutils and e2fsprogs and carries
`/template/vmlinux`, `/template/vmlinux.config`, `/template/rootfs.ext4` and
`/template/metadata.json`, which records the guest `user`'s `runner_uid` and
`runner_gid` (1000, the Linux runner image's `runner` UID, so CI-written
caches and checkouts need no ownership change) for sandboxd's prepared
checkout workspaces. The sandboxes chart runs it as the init container
of a template installer DaemonSet, separate from sandboxd's so a template
upgrade never restarts the daemon, with the node's `/data/sandboxes` mounted
at `/host` and `TEMPLATE_TAG` set
(`TEMPLATE_NAME` defaults to `default`, `TEMPLATE_DIR` to
`/host/templates/<name>/<tag>`, `ROOTFS_SIZE` to `12G`; the tuist chart sets
`sandboxes.rootfsGiB`, 20, and remote execution's `bazel` template keeps the
default). `install-template.sh` copies the files with `cp --sparse=always`
only when `rootfs.ext4` is missing from the target, into
`/host/template-staging/<name>-<tag>` (`TEMPLATE_STAGING_DIR`, which must share
the target's filesystem), renamed into place whole so a running daemon never
sees a partial tag, then writes `metadata.json` with `tag` and the installed
`rootfs_bytes` added and finally names the tag in `templates/<name>/current`,
which sandboxd without `TEMPLATE_TAG` follows. sandboxd
boots the template, snapshots it and writes the `ready` marker itself.

The rootfs travels dense inside the image layer, so the build sizes it to its
contents plus a quarter and 1 GiB, and a pull costs the node's image store
only that. The installer then grows the copy to `ROOTFS_SIZE` with `truncate`
and `resize2fs`, which leaves the file sparse at its used size on `/data`.
`RESIZE2FS_FORCE_ITABLE_INIT=1` zeroes the new inode tables as holes and marks
them initialised; without it the guest kernel's lazy init would write those
zeros, a few hundred MiB, into every sandbox's rootfs clone. A new size applies
to template tags installed afterwards; sandboxd grows the rootfs of existing
sandboxes to it online on their next resume or cold boot ("Rootfs growth" in
`infra/sandboxd/AGENTS.md`), which needs `resize2fs` in the rootfs.

## Deliberately not installed yet

No Android SDK, no Swift toolchain, no JDK, no Docker, no Xcode-adjacent
tooling. Erlang and Elixir are pinned under `/opt/erlang` and `/opt/elixir`,
with OTP-compatible Hex and Rebar under `/opt/mix`, for no-network actions.
Other language runtimes come from `mise` inside the sandbox. Ordinary vsock execs still run as root.
Amp bootstrap runs as `user` with passwordless sudo; see
[`../amp-orbs/README.md`](../amp-orbs/README.md) for its lifecycle, persistent
workspace, required egress, Desktop and rollout.
REAPI commands run as `builder` (UID/GID 2000, not `user`'s 1000, which has
sudo); preserve explicit command environments, `no_new_privs`, and host-only
vsock access so actions cannot obtain the root worker's scoped CAS credential. See [remote execution](remote-execution.md)
for the separate gateway, deployment and qualification workflow.
