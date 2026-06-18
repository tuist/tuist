# VM Image Builder Fleet: Operator Runbook

Bare-metal Mac mini fleet that bakes the Tart VM images for our CI
workflows (today: [`runner-image`](runner-image/),
[`xcresult-processor-image`](xcresult-processor-image/)). Managed
through the same CAPI provider as the rest of the macOS fleet
([`infra/cluster-api-provider-scaleway-applesilicon/`](cluster-api-provider-scaleway-applesilicon/));
scale by editing the `buildersFleet.replicas` chart value or running
`kubectl scale machinedeployment <release>-builders-fleet
--replicas=N`.

## Which environments run a builder

Production only. The baked Tart images are global GHCR artifacts, so
a single fleet bakes them for every environment. More to the point,
every builder registers the same `vm-image-builder` label set to the
same `tuist` org with no per-env scoping (see the
[`runs-on:` selector](#workflow-runs-on-selector) section), so a
builder running in staging or canary would pick up production
image-release jobs indiscriminately, including pushing production
image tags from a non-prod host. Staging and canary therefore pin
`buildersFleet.enabled: false`; only `values-managed-production.yaml`
runs the fleet, sized at 2 so the release's two parallel bakes (runner
image + xcresult-processor image) run concurrently instead of
serializing on one host.

The GitHub App and the setup steps below are still written per-env
because the App is a single shared identity any env could borrow for a
throwaway builder in a pinch. In steady state, apply the enablement
steps to production alone.

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
| `crane`             | `/opt/homebrew/bin/crane`         | Homebrew core, installed by `installBuilderTooling`. Used by the image-build workflows to write GHCR credentials into `~/.docker/config.json` for `tart push` (`crane auth login`), and by `release.yml`'s runner-image leg to resolve a pushed tag to its immutable digest (`crane digest`). |
| `oras`              | `/opt/homebrew/bin/oras`          | Homebrew core, installed by `installBuilderTooling`. Used by `macos-xcode-image.yml` to pull the pre-mirrored Xcode `.xip` artifacts from `ghcr.io/tuist/xcode-xips`. |
| Actions runner      | `/opt/actions-runner/`            | Downloaded directly from `actions/runner`'s GitHub releases by `installActionsRunner` and registered as a launchd LaunchAgent under `m1`. |

Nothing in the workflow yaml installs or upgrades any of these.
Implicit `brew upgrade` was the cause of multiple macOS Tahoe TCC
grant invalidations during this fleet's onboarding (see "Local
Network access" below); keeping installs centralized in the
bootstrap is what makes the grants stable across re-runs.

## One-time setup

1. **Create the "Tuist Builders Fleet" GitHub App** on the tuist
   org (one-time, shared across all envs). Settings → Developer
   settings → GitHub Apps → New GitHub App:

   - Name: `Tuist Builders Fleet`
   - Homepage URL: anything (not consumed)
   - Webhook: **Disable** ("Active" unchecked) — the App isn't a
     webhook consumer, it's just an identity for minting runner-
     registration tokens.
   - Permissions → **Organization** → **Self-hosted runners: Read
     and write**. Nothing else.
   - Where can this GitHub App be installed: **Only on this account**.

   Submit, then on the App's settings page:

   - Note the **App ID** (top of the page).
   - Click **Generate a private key**; save the `.pem` it downloads.
   - **Install App** → select tuist → install. The URL becomes
     `…/installations/<installation-id>`. Note the installation ID.

2. **Stash the App credentials in 1Password.** Production is the
   only env that runs a builder (see
   [Which environments run a builder](#which-environments-run-a-builder)),
   so the item only needs to live in the `tuist-k8s-production`
   vault. The `ClusterSecretStore "onepassword"` is pre-scoped to
   the matching vault per env, so the same item name works in the
   `tuist-k8s-staging` / `tuist-k8s-canary` vaults too if you ever
   stand up a throwaway non-prod builder. Each item has three fields:

   ```
   BUILDERS_FLEET_GITHUB_APP
     app-id           = <App ID from step 1>
     installation-id  = <Installation ID from step 1>
     private-key      = <contents of the .pem file>
   ```

   The App is one shared identity, so the same triple works in any
   env vault that needs it. No expiry to track, no rotation on
   scale-up; the reconciler mints a fresh ~1h runner-registration
   token from these on every builder-host bootstrap via the GitHub
   App JWT -> installation token -> registration token flow.

3. **Pre-order Mac minis on Scaleway** with names prefixed
   `tuist-pool-`. Same pre-ordered pool the macosFleet and
   runnersFleet adopt from; the operator's pre-order job sizes for
   the sum of all three fleets' expected demand. Scaleway's Mac
   mini inventory is unreliable and Apple's 24h billing floor makes
   speculative auto-ordering expensive, so the operator does this
   ahead of any scale-up.

4. **Enable the fleet** in production's values file (staging and
   canary keep `enabled: false`, per
   [Which environments run a builder](#which-environments-run-a-builder)):

   ```yaml
   # infra/helm/tuist/values-managed-production.yaml
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

## Seeding pre-existing pool hosts for a new fleet

This is only relevant when **adding a brand-new fleet to a cluster
that already has `tuist-pool-` hosts ordered**, which is rare —
on the order of once per product line. For day-2 scaling of an
existing fleet, skip this section.

Scaleway only bakes the project's SSH key set into a Mac mini's
`~m1/.ssh/scw_authorized_keys` at the host's *original* create
time, and never refreshes it. The buildersFleet's per-fleet
Ed25519 key gets registered in the Scaleway project the first time
the controller reconciles a buildersFleet Machine, but pool hosts
that pre-date that registration won't have it. Adoption hangs at
the SSH step with `BootstrapFailed: SSH not available after 5m`
until the new fleet's pubkey is on the host.

Two ways to seed it:

  - **Order fresh pool hosts after the fleet is enabled** —
    simplest. The chart's first reconcile (helm upgrade with
    `buildersFleet.enabled: true`) registers the SSH key; any
    `tuist-pool-*` hosts ordered *after* that point inherit it
    automatically. No host-side work needed.

  - **Plant the key onto existing pool hosts manually.** SSH into
    each existing pool host using a key that's *already* on it (a
    sibling fleet's key, or an operator personal key in the
    project) and append the buildersFleet pubkey:

    ```bash
    # Pull the new pubkey from the cluster.
    KUBECONFIG=$(op read op://tuist-k8s-<env>/.../kubeconfig) \
      kubectl -n tuist-<env> get secret \
      <release>-builders-fleet-ssh -o jsonpath='{.data.id_ed25519\.pub}' \
      | base64 -d

    # Append it to each pool host.
    ssh m1@<pool-host-ip> "echo '<pubkey>' >> ~/.ssh/scw_authorized_keys && chmod 600 ~/.ssh/scw_authorized_keys"
    ```

While you're SSH'd in, also confirm the pool host has passwordless
sudo configured for `m1`. The pre-order workflow normally sets
this up via VNC (see the [Local Network access section](#one-time-per-host-grant-local-network-access)),
but it's worth checking before adoption hits a PAM lockout from
repeated wrong-password retries:

```bash
ssh m1@<pool-host-ip> "ls /etc/sudoers.d/m1-nopasswd && sudo -n true && echo OK"
```

If the sudoers file isn't there, plant it once (VNC in via the
Scaleway console, since SSH-time sudo needs the m1 password):

```bash
sudo tee /etc/sudoers.d/m1-nopasswd <<'EOF'
m1 ALL=(ALL) NOPASSWD: ALL
EOF
sudo chmod 440 /etc/sudoers.d/m1-nopasswd
```

Once the pubkey is in `scw_authorized_keys` and passwordless sudo
is wired up, the next CAPI reconcile (within ~30s) adopts the host
cleanly. Same caveat applies one time per new fleet; existing
fleets keep working untouched.

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
tart-kubelet on the same host.

The one place this isn't conflict-free: tart-kubelet's orphan-VM
GC (`internal/podagent/garbage.go`) deletes every local Tart VM
not backed by a Pod scheduled to the Node. Because no Pods ever
land on a builder, the host-baked build VM looks orphaned and the
GC would `tart delete` it mid-`tart push` — the push then fails at
the NVRAM layer with `The file "nvram.bin" doesn't exist`. The
bootstrap therefore starts tart-kubelet with `--disable-vm-gc` on
builder Nodes (`renderLaunchdPlist` keys this off `GHActionsRunner`
being set); the image-bake workflow's own "Reclaim Tart disk" step
handles disk reclamation there instead.

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
