# macos-host-bootstrap

Go package the CAPI provider ([`cluster-api-provider-tuist`](../cluster-api-provider-tuist/AGENTS.md))
uses to turn a Mac mini into a tart-kubelet Node over SSH (`Run`) and to keep it
converged afterwards (`UpdateTartKubelet`, the drift push).

- `HostConfigHash` fingerprints everything the drift push applies. Every hashed
  part needs a step `UpdateTartKubelet` calls; `hashPartInstaller` in
  `bootstrap_test.go` is that list and its test fails on a gap. Per-host values
  belong in `PerHost`, never in the hashed fleet config.
- A rack host records which env's operator owns its runner runtime in
  `/etc/tuist/runtime-owner` (`runtime_owner.go`). `Run` and
  `UpdateTartKubelet` claim it before changing anything (`PerHost.RuntimeOwner`)
  and refuse a host another env owns; `HandOverRuntime` moves it and the lease
  key together, and only the env that owns the site calls it. See "A host lent
  to another env" in the provider's AGENTS.md.
- Scripts run under the SSH user's login shell, which is zsh on the fleet. Do not
  name a variable `status` (read-only in zsh), do not use a bare glob that may
  match nothing (zsh aborts), and quote expansions (zsh does not word-split).
  Tests that execute a script run it under `/bin/sh` and zsh (`loginShells`).

## Tart

`installTart` (`tart.go`) runs on both paths. It installs a release to
`/usr/local/lib/tart/<version>/tart.app` and renames a new `/usr/local/bin/tart`
wrapper over the old one. It never writes to or removes a bundle a process runs
from, so VMs started by the previous version keep running, and the new CLI
manages them. Bundles nothing runs from are pruned on each install, including
the pre-versioned `/usr/local/lib/tart.app`.

- The tarball is streamed only when `tart --version` differs from
  `Config.TartVersion`, so a push with an unchanged version touches nothing.
- The install refuses a tarball whose `tart --version` is not the version it
  was given, and leaves the wrapper alone.
- Rolling back is installing the older version: an installed bundle is reused,
  never replaced.
- Tart's on-disk compatibility between versions is recorded in "Tart versions"
  in [`tart-kubelet/AGENTS.md`](../tart-kubelet/AGENTS.md). Read it before
  adding a release.
