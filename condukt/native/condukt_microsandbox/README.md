# condukt_microsandbox

Rustler NIF that wraps the
[microsandbox](https://github.com/superradcompany/microsandbox) crate so
Condukt can run a session inside a microVM through
`Condukt.Sandbox.Microsandbox`.

## Distribution

This crate follows the same release model as `condukt_bashkit`: supported
targets are published as precompiled NIF artifacts on GitHub releases, while
`MIX_ENV=dev` and `MIX_ENV=test` build from source in the Condukt repo.

Microsandbox itself is host-platform dependent. Condukt currently exposes this
backend on:

* `aarch64-apple-darwin`
* `aarch64-unknown-linux-gnu`
* `x86_64-unknown-linux-gnu`

Unsupported targets compile the Elixir wrapper as stubs that return
`{:error, :unsupported_target}`.
