# VM Image Builder Fleet: Operator Runbook

Bare-metal Mac mini fleet that bakes the Tart VM images for our CI
workflows (today: [`runner-image`](runner-image/),
[`xcresult-processor-image`](xcresult-processor-image/)). Managed
through the same CAPI provider as the rest of the macOS fleet
([`infra/cluster-api-provider-scaleway-applesilicon/`](cluster-api-provider-scaleway-applesilicon/));
scale by editing the `buildersFleet.replicas` chart value or running
`kubectl scale machinedeployment <release>-builders-fleet
--replicas=N`.

## Architecture

Builder hosts are regular Kubernetes Nodes registered by tart-kubelet,
identical to the `macosFleet` (xcresult-processor) and `runnersFleet`
(customer-runner) hosts. The only difference: nothing in the cluster
schedules Pods with `nodeSelector: tuist.dev/fleet=<buildersFleet>`,
so kubelet stays idle. On top of the standard Node bootstrap the
reconciler installs an extra LaunchAgent: a GitHub Actions self-
hosted runner that picks up image-bake workflow jobs from GitHub
and runs `packer build` directly against the host's own Tart daemon.

Why bare-metal Tart instead of a Pod-VM: Apple Silicon
Virtualization.framework doesn't nest macOS guests inside macOS
guests. Packer's `tart run` from inside a macOS Pod-VM fails, so the
agent has to live on the host with kubelet idle.

The `tuist.dev/macos=true:NoSchedule` taint tart-kubelet auto-applies
keeps stray Linux Pods off; the per-fleet `tuist.dev/fleet`
NodeLabel scopes Pod selection away from this fleet.

### Where the build tools come from

The host's `tart`, `packer`, and the Actions runner agent are all
installed by the CAPI reconciler at bootstrap time, never by the
workflows. The workflows assume each tool is on PATH and fail fast
if not:

| Tool                | Install path | Source |
|---|---|---|
| `tart`              | `/usr/local/bin/tart`             | Operator-image-baked `tart.app` tarball (`installTart` in `macos-host-bootstrap`). Same install path the macosFleet and runnersFleet hosts use; Tart's version is pinned by what the operator image ships. |
| `packer`            | `/opt/homebrew/bin/packer`        | Homebrew (`hashicorp/tap/packer`) installed by the builder tail (`installBuilderTooling`) and `brew pin`'d. A follow-up will bake Packer into the operator image too, dropping Homebrew from the bootstrap entirely. |
| Actions runner      | `/opt/actions-runner/`            | Downloaded directly from `actions/runner`'s GitHub releases by `installActionsRunner` and registered as a launchd LaunchAgent under `m1`. |

Nothing in the workflow yaml installs or upgrades any of these.
Implicit `brew upgrade` was the cause of multiple macOS Tahoe TCC
grant invalidations during this fleet's onboarding (see "Local
Network access" below); keeping installs centralized in the
bootstrap is what makes the grants stable across re-runs.

## One-time setup (per env)

1. **Mint a GitHub Actions runner registration token** and stash it
   in 1Password. Per-env vaults (`tuist-k8s-staging`,
   `tuist-k8s-canary`, `tuist-k8s-production`); the chart's
   `ClusterSecretStore "onepassword"` is already pre-scoped to the
   matching vault, so the same 1P item name works across envs:

   ```bash
   gh api -X POST /orgs/tuist/actions/runners/registration-token --jq .token
   # paste the result into 1Password as
   # BUILDERS_FLEET_RUNNER_REGISTRATION_TOKEN.credential
   ```

   Tokens have ~1h TTL but the runner agent only consults the token
   at first registration; once a host has registered, its agent
   stores a long-lived auth token locally and survives reboots and
   token rotations. Rotate the 1P value whenever scaling up or
   when you remember; staleness shows up as a `Bootstrapping` event
   with `GHRunnerTokenUnavailable` on the affected
   `ScalewayAppleSiliconMachine`.

2. **Pre-order Mac minis on Scaleway** with names prefixed
   `tuist-pool-`. Same pre-ordered pool the macosFleet and
   runnersFleet adopt from; the operator's pre-order job sizes for
   the sum of all three fleets' expected demand. Scaleway's Mac
   mini inventory is unreliable and Apple's 24h billing floor makes
   speculative auto-ordering expensive, so the operator does this
   ahead of any scale-up.

3. **Enable the fleet** in the env's values file:

   ```yaml
   # infra/helm/tuist/values-managed-<env>.yaml
   buildersFleet:
     enabled: true
     replicas: 2
     adoptPoolPrefix: "tuist-pool-"
     externalSecrets:
       enabled: true
   ```

   `helm upgrade` rolls the chart; the CAPI reconciler picks up the
   new MachineDeployment + ScalewayAppleSiliconMachineTemplate and
   starts claiming pool hosts.

## Scaling

```bash
kubectl scale machinedeployment <release>-builders-fleet \
  --namespace tuist \
  --replicas=N
```

…or commit a new `replicas: N` in the env values file and let the
deploy workflow apply it. Either way the reconciler claims the
next `tuist-pool-*` host from the pool, bootstraps it (host prep
shared with the other fleets, plus the GH Actions runner agent),
and the host appears in `gh runners` / the GitHub Actions Runners
page within ~10 min once the bake completes.

Scaling down: same command with a smaller `--replicas`. CAPI
deletes the excess Machines; the reconciler's `reconcileDelete`
releases the Scaleway server (which un-adopts it back to the pool
under its `tuist-pool-` name for re-claiming later). The GitHub-
side runner registration goes stale; it auto-cleans after ~14 days
of being offline, or run:

```bash
gh api /orgs/tuist/actions/runners --jq '.runners[] | select(.status == "offline" and (.labels[].name | contains("vm-image-builder"))) | .id' \
  | xargs -I{} gh api -X DELETE /orgs/tuist/actions/runners/{}
```

## One-time per-host: grant Local Network access

macOS Tahoe gates `bridge100`/`192.168.64.0/22` (the vmnet subnet
Tart hands its guests) behind the **Local Network access**
permission. Until granted, the host can route to the guest at L2
(DHCP works, the guest gets an IP) but the host can't open TCP to
the guest. Packer's `tart-cli.runner: Waiting for SSH to become
available...` hangs forever, then times out.

TCC is SIP-protected on Tahoe, so the permission can't be granted
programmatically without MDM. The reconciler can't fix this; the
operator has to grant it once per host:

1. Open a VNC session to the host (Scaleway console -> the
   machine -> "Open VNC" / "Console"). Uses the auto-login Aqua
   session our bootstrap configures.
2. Trigger a workflow run on the host (or any `tart`/`packer`
   invocation). The first invocation that needs vmnet access pops
   a "wants to access devices on your local network" dialog.
3. Click **Allow**. The grant persists across reboots and across
   re-runs of the workflow.

**Grants are keyed on the binary's code-signature.** A binary swap
(e.g. `brew upgrade` replacing `packer` with a new build, or
re-installing Tart) silently revokes the grant and the prompt
re-fires next time the host tries to reach a guest. Two host-side
mitigations live in the bootstrap:

  - **Tart is installed via the operator image's baked tart.app
    tarball**, the same path the macosFleet and runnersFleet
    hosts use. The version is pinned by what the operator image
    ships; a Tart upgrade is a deliberate operator-image bump,
    not a Homebrew side-effect. The workflows no longer touch
    Tart at all; they expect it on PATH at `/usr/local/bin/tart`.

  - **Packer is installed via Homebrew (hashicorp/tap) and
    `brew pin`'d** so subsequent `brew upgrade` calls are no-ops.
    Packer upgrades are an explicit operator action:

    ```bash
    ssh m1@<host> '
      eval "$(/opt/homebrew/bin/brew shellenv)"
      brew unpin packer
      brew upgrade hashicorp/tap/packer
      brew pin packer
    '
    # Then VNC in, dispatch any image workflow, click Allow when prompted.
    ```

A future cleanup will bake Packer into the operator image the
same way Tart is, eliminating Homebrew from the builder bootstrap
entirely.

The same fragility hits the cluster's runners-fleet hosts; look
there for any process improvements that land later.

## Keychain access for `tart login`

For the same family of reasons, `tart login ghcr.io` fails on
Tahoe-host LaunchAgents with `Keychain failed to add item: User
interaction is not allowed`. The workflows in this repo work
around this by using `TART_REGISTRY_USERNAME` /
`TART_REGISTRY_PASSWORD` env-vars on the `tart push` step instead
of writing to keychain; no `tart login` is needed. If you add a
new workflow that pushes to GHCR, follow the same pattern.

## Workflow `runs-on:` selector

Both image-build workflows pin
`runs-on: [self-hosted, macos, bare-metal, vm-image-builder]`. Those
four labels are stamped onto every runner by the chart-default
`ghRunnerLabels`. Changing the workflows' selector and the chart
value must happen together.

## Manual fallback

When the reconciler is unhappy and an operator needs to bootstrap a
host by hand, the same step helpers live in
[`infra/macos-host-bootstrap/`](macos-host-bootstrap/) as exported
Go functions plus the shell scripts they generate. SSH in as the
host's SSH user and run the equivalent commands in the order the
reconciler does; see `bootstrap.Run` in
[`bootstrap.go`](macos-host-bootstrap/bootstrap.go) and the builder
tail in [`actions_runner.go`](macos-host-bootstrap/actions_runner.go).

## Why this lives outside the Pod-as-VM model

[`infra/tart-kubelet/`](tart-kubelet/) is the kubelet replacement
that turns each Pod into a Tart VM on its Node. Image-bake
workflows can't run as Pods on that model because they'd need to
spawn nested macOS guests (Packer → Tart → macOS), which Apple
Silicon Virtualization.framework refuses. So the builder runs as a
host-level LaunchAgent that invokes Tart directly, sitting beside
tart-kubelet on the same host without conflict because no Pods are
ever scheduled there.

The bootstrap helpers in
[`infra/macos-host-bootstrap/`](macos-host-bootstrap/) are shared
between the Node path (`bootstrap.Run` → tart-kubelet install) and
the builder tail (`bootstrap.Run` → tart-kubelet install →
`runActionsRunnerInstall`); the only delta is whether the CR's
`ghActionsRunner` sub-spec is set.

## Migrating from hand-bootstrapped hosts

If you have hand-bootstrapped builder hosts from before this
runbook (named e.g. `vm-image-builder-01`, `vm-image-builder-1`):

1. Stop the GH Actions runner on each: SSH in,
   `cd /opt/actions-runner && ./svc.sh stop && ./svc.sh uninstall`.
2. Delete the GitHub-side runner registration:
   `gh api -X DELETE /orgs/tuist/actions/runners/<id>`.
3. Release the Scaleway server (Scaleway console -> machine ->
   Delete, or `scw apple-silicon server delete <id>`).
4. Drop the host's SSH key from the project SSH-keys list if it was
   per-host (the fleet-level `vm-image-builder-fleet` key stays).
5. Bring up the cluster-managed equivalent via the steps above.

The cluster-managed hosts use new Scaleway-generated server IDs but
take the same names CAPI assigns from the MachineDeployment, so the
GitHub Runners page ends up with the same naming convention without
manual reconciliation.
