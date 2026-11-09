# condukt-egress

Sidecar binary for the `Condukt.Sandbox.NetworkPolicy` egress layer.
Used by `Condukt.Sandbox.Kubernetes` when an agent session declares
a network policy.

## Subcommands

```
condukt-egress netfilter-setup   # init container mode: write iptables, exit
condukt-egress proxy             # sidecar mode: transparent proxy + control channel
```

Both modes live in the same binary so a single container image
(`ghcr.io/tuist/condukt-egress`) handles both the init and the sidecar in
the pod spec, with the subcommand selected by `command:`.

## Building

```
cd native/condukt_egress
cargo build --release
```

The binary lands at `target/release/condukt-egress`. The release pipeline
builds it for `linux/amd64` and `linux/arm64` and pushes a multi-arch
image to `ghcr.io/tuist/condukt-egress:<condukt-version>` on every
Condukt release.

The toolchain is pinned to Rust 1.94.1 in `rust-toolchain.toml`, matching
`native/condukt_bashkit/` and the workspace-wide pin in `mise.toml`.
