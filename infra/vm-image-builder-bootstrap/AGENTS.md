# vm-image-builder-bootstrap

One-shot CLI that turns a freshly-ordered Scaleway Apple Silicon Mac
mini into a working bare-metal `vm-image-builder` GitHub Actions
self-hosted runner. Invoked manually by the operator; not part of the
Kubernetes control loop.

Operator runbook: [`../vm-image-builder.md`](../vm-image-builder.md).

## Why a separate binary

The Scaleway CAPI provider
([`../cluster-api-provider-scaleway-applesilicon/`](../cluster-api-provider-scaleway-applesilicon/))
already bootstraps Mac minis as Kubernetes nodes via
[`../macos-host-bootstrap/`](../macos-host-bootstrap/). The image
builder needs the same first-mile prep (passwordless sudo, auto-login
for Tart's Virtualization.framework, disable idle sleep, set
hostname), so this binary imports and re-uses those helpers.

It can't reuse the rest of the CAPI bootstrap because the builder is
deliberately *outside* the cluster: it runs `packer build` against
the host's own Tart daemon, which doesn't fit the
"Pod-is-a-VM" abstraction tart-kubelet enforces. So the GitHub Actions
runner registration + Homebrew + Xcode verification + LaunchAgent
install live here rather than as a `MachineDeployment` shape.

## Layout

```
infra/vm-image-builder-bootstrap/
├── go.mod              # module, replace ../macos-host-bootstrap
├── main.go             # CLI: flag parsing, TTY password prompt
├── bootstrap.go        # Config, Run, builder-specific steps
└── bootstrap_test.go   # template + validation tests (no live SSH)
```

`Run(ctx, Config)` runs the same nine-step sequence the runbook
documents. Re-running on a partially-bootstrapped host completes the
missing steps without redoing the finished ones (each step is
idempotent the same way the kubelet bootstrap's are).

## Adding a step

1. Add an `installFoo`/`verifyFoo`/etc. function in `bootstrap.go`.
   Use `runStreaming` for long-running remote commands; the per-line
   `[step]` prefix on stdout is what tells the operator which stage
   is currently making progress.
2. Chain it from `Run` in the correct order. Order matters: e.g.
   `installActionsRunner` has to run after `EnableAutoLogin` because
   `svc.sh install m1` needs m1's GUI session to be up.
3. Mirror the step in the runbook's manual fallback section so
   operators have a path when the CLI breaks.

## Pinned constants

`DefaultRunnerVersion` and `DefaultRunnerLabels` mirror values in:

- `.github/workflows/runner-image.yml` (`runs-on:` selector, default `runner_version` input)
- `.github/workflows/xcresult-processor-image.yml` (`runs-on:` selector)
- `infra/runner-image/runner.pkr.hcl` (`runner_version` variable)

A test in `bootstrap_test.go` pins `DefaultRunnerLabels` to the
exact CSV so a change to one without the other trips CI before it
makes the host invisible to the GitHub scheduler.
