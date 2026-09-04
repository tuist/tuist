# sandbox-image

Guest side of the Firecracker sandboxes run by `infra/sandboxd`: the kernel,
the rootfs and the three binaries that live in it. The host side, the vsock
protocol and the node layout are specified in `infra/sandboxd/AGENTS.md`; this
node only covers what is inside the VM and how the template reaches a node.

## Contents

| Path | What |
|---|---|
| `cmd/sbx-init` | PID 1. Mounts proc, sysfs, devtmpfs, devpts, /dev/shm, /run, /tmp and cgroup2; names the guest from the kernel command line; configures `lo` and `eth0` (`10.0.0.2/30`, default route `10.0.0.1`, MAC left to the VMM) with netlink; writes `/etc/resolv.conf`, `/etc/hostname` and `/etc/hosts`; creates `/workspace` and `/mnt/memory`; supervises `sbx-agent` with 1s to 30s backoff; reaps orphans; powers off on SIGTERM (and on SIGINT, which is what Firecracker's ctrl-alt-del becomes). Logs to the console and `/dev/kmsg`. Linux-only; the non-Linux build is a stub. |
| `cmd/sbx-agent` | vsock server on port 5000. `-listen tcp://127.0.0.1:5000` runs it on a TCP socket for development. |
| `cmd/sbx-worker` | Runs one already-claimed Managed Agents work item with the Anthropic Go SDK's `EnvironmentWorker.HandleItem`. |
| `internal/protocol` | Request and response frames, newline-delimited JSON. |
| `internal/exec` | Command registry: process groups, streamed stdout/stderr, timeouts (exit 124), kill by exec id. |
| `internal/agent` | Op dispatch behind a `System` interface, tested over `net.Pipe`. |
| `internal/guest` | The Linux implementation of `System`: `clock_settime`, `sethostname`, neighbour flush, workspace disk. Stubs elsewhere. |
| `internal/sysconfig` | Rendering of the hostname, hosts and resolver files and kernel command line parsing. |
| `Dockerfile`, `install-template.sh` | Template image and its entrypoint. |

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
(verified when non-empty), `NODE_MAJOR`, `ANT_VERSION`, `ROOTFS_SIZE`,
`VERSION` (stamped into `sbx-agent`'s `agent_version`).

## Template init container

The final stage is Alpine with GNU coreutils and carries `/template/vmlinux`,
`/template/vmlinux.config`, `/template/rootfs.ext4` (sparse, 8 GiB) and
`/template/metadata.json`. sandboxd's DaemonSet runs it as an init container
with the node's `/data/sandboxes` mounted at `/host` and `TEMPLATE_TAG` set
(`TEMPLATE_NAME` defaults to `default`, `TEMPLATE_DIR` to
`/host/templates/<name>/<tag>`). `install-template.sh` copies the files with
`cp --sparse=always` only when `rootfs.ext4` is missing from the target, each
under a temporary name that is renamed into place with the rootfs last, then
writes `metadata.json` with `tag` added. sandboxd boots the template, snapshots
it and writes the `ready` marker itself.

The rootfs travels dense inside the image layer (the registry compresses the
zeros away, but a pull materialises the full 8 GiB in the node's image store);
the sparse copy keeps the per-template footprint on `/data` at the used size.

## Deliberately not installed yet

No Android SDK, no Swift toolchain, no JDK, no Docker, no Xcode-adjacent
tooling. Language runtimes beyond system Python 3 and Node.js 22 are expected
to come from `mise` inside the sandbox. No non-root user: everything runs as
root, matching the sandboxd spec's "not yet" list.
