# VM Image Builder: Bare-Metal Mac mini Onboarding

Stand up a new `vm-image-builder` Mac mini that builds the runner and
xcresult-processor Tart images on the
`[self-hosted, macos, bare-metal, vm-image-builder]` label set.

The bootstrap is a single command:

```bash
mise run vm-image-builder:bootstrap -- \
  --ip <scaleway-ipv4> \
  --hostname vm-image-builder-<n> \
  --use-ssh-agent \
  --gh-token "$(gh api -X POST /repos/tuist/tuist/actions/runners/registration-token --jq .token)"
# Prompts for the m1 password from the Scaleway provisioning email.
```

`--use-ssh-agent` sources the SSH signers from `$SSH_AUTH_SOCK`, so
the private key never lands on disk; 1Password's SSH agent serves
the fleet keypair (stored in the `Founders` vault as item
`vm-image-builder-fleet`) on demand. Pass `--ssh-key <path>` instead
if you've materialised the key to a file for some reason; the two
flags are mutually exclusive.

Behind it lives
[`infra/vm-image-builder-bootstrap/`](vm-image-builder-bootstrap/),
which re-uses the SSH + sudo + auto-login + idle-sleep helpers from
[`infra/macos-host-bootstrap/`](macos-host-bootstrap/) (the same
substrate the Scaleway CAPI provider runs on cluster nodes) and
layers the builder-specific steps on top: Homebrew, Tart + Packer +
mise, an Xcode sanity check, `TUIST_MIX_BUILD_ROOT` in `/etc/zshenv`,
and the GitHub Actions runner registration + LaunchAgent install.

Today the builder fleet is provisioned by hand: hosts are ordered
on Scaleway one at a time and bootstrapped with this command. There
is no `MachineDeployment` for the builder fleet, deliberately:
these hosts sit outside the workload Kubernetes clusters because
they run Packer-driven Tart builds, not cluster Pods. The Scaleway
CAPI provider
([`infra/cluster-api-provider-scaleway-applesilicon/`](cluster-api-provider-scaleway-applesilicon/))
manages the in-cluster macOS fleet; the builder fleet is
intentionally separate.

GitHub load-balances queued jobs across every healthy runner that
matches the label set, so adding a second matching host needs no
workflow or chart change.

## Why bare-metal, why outside the cluster

Both image builds invoke `tart create` and `tart run`, which call
into Apple's Virtualization.framework. The framework refuses to
start a guest unless the calling process owns a live Aqua (GUI)
console session, so hosted GitHub runners can't satisfy this and
nested-virt on cloud macOS rules out running Tart inside a Tart VM.
A real Mac mini with auto-login configured is the only shape that
works.

Bringing the builder into the cluster doesn't help either:

- **Tart-in-Tart.** Each cluster Pod becomes a Tart VM (the
  tart-kubelet model); Packer inside that VM would have to spawn its
  own Tart VM. Apple Silicon Virtualization.framework doesn't nest
  macOS guests inside macOS guests, so this just doesn't work.
- **Host-Tart-from-Pod.** A Pod could mount the host's Tart binary
  and drive the host daemon, but the Pod still needs the *host
  process's* live Aqua session, which is a property of the host, not
  the Pod. The tart-kubelet abstraction breaks down: Pods are
  supposed to *be* VMs, not orchestrate them.

So the builder lives outside Kubernetes. The first ~70% of its
bootstrap is identical to the in-cluster fleet (auto-login, sudoers,
idle-sleep), so that code is shared via
[`infra/macos-host-bootstrap/`](macos-host-bootstrap/).

## One-time fleet setup

The fleet keypair lives in 1Password (vault `Founders`, item
`vm-image-builder-fleet`, category `SSH Key`); it's shared across
operators and hosts. The public half is registered as a project SSH
key in Scaleway named `vm-image-builder-fleet`, alongside the
auto-generated `tuist-tuist-runners-fleet` and
`tuist-tuist-macos-fleet` keys the CAPI provider manages.

These steps happen once per fleet, not per host. If 1Password
already has the item and Scaleway already has the project key, skip
to "Per-host steps".

1. **Generate the keypair** (locally, in `/tmp`):

   ```bash
   ssh-keygen -t ed25519 -C "vm-image-builder-fleet" -f /tmp/vm-image-builder-fleet -N ""
   ```

2. **Upload the private half to 1Password.** Via `op` CLI v2.33+:

   ```bash
   jq --arg key "$(cat /tmp/vm-image-builder-fleet)" '.title="vm-image-builder-fleet" | .fields[1].value=$key' \
     <(op item template get "SSH Key") \
     | op item create --vault=Founders --tags=infra,vm-image-builder
   ```

   Older `op` CLI versions can't read SSH Key fields back, so verify
   from the 1Password GUI that the `private key` field is populated
   with the BEGIN/END OPENSSH PRIVATE KEY block.

3. **Register the public half with Scaleway.** Console -> the Tuist
   project -> Project Settings -> SSH keys -> Add an SSH key. Paste
   `cat /tmp/vm-image-builder-fleet.pub`, name it
   `vm-image-builder-fleet`. From then on every Apple Silicon Mac
   mini ordered in this project comes up with this public key in
   `m1`'s `authorized_keys`.

4. **Shred the on-disk copies:**

   ```bash
   rm -P /tmp/vm-image-builder-fleet /tmp/vm-image-builder-fleet.pub
   ```

## One-time operator setup

Once per operator, not per host:

1. **Enable the fleet key for 1Password's SSH agent.** Open the
   `vm-image-builder-fleet` item in 1Password, click the "Enable
   key for SSH agent" banner, follow the prompt to add the agent
   socket path to `~/.ssh/config`. Confirm:

   ```bash
   ssh-add -l | grep vm-image-builder-fleet
   ```

   This is what makes `--use-ssh-agent` work; without it the
   bootstrap CLI has no way to reach the private key.

2. **Confirm `gh` is authenticated** against `tuist/tuist` with at
   least `admin:org` scope (needed to mint runner registration
   tokens):

   ```bash
   gh auth status
   ```

## Per-host steps

### 1. Order the Mac mini

- **Provider:** Scaleway Apple Silicon, in the same Tuist organization
  project that hosts the in-cluster macOS fleet. The CAPI provider's
  per-env IAM tokens are scoped to that project, so it's the natural
  home for the builders too (the `project-id` is in 1Password under
  `op://tuist-k8s-production/SCALEWAY_API/project-id` if you need it).
- **SKU:** **M2-L** (M2 Pro, 12 vCPU, 32 GB RAM, 256 GB SSD). Same
  default the CAPI provider uses for in-cluster hosts.
- **OS image:** the Scaleway **macOS + Xcode preinstalled** image
  (Sequoia or later). The bootstrap verifies a full Xcode is present
  in `/Applications/Xcode.app` and aborts with a clear error if the
  vanilla macOS image was ordered by mistake.

Note the public IPv4 and the `m1` password Scaleway emails once
provisioning completes (~10 min for a fresh order). The password is
only needed for the bootstrap's two password-consuming steps
(installing the sudoers file + XOR-encoding `/etc/kcpassword`); after
bootstrap, SSH is key-based and sudo is passwordless, so the password
is not stored anywhere persistent.

### 2. Mint a runner registration token

Tokens have a ~1h TTL. Mint immediately before running the
bootstrap:

```bash
gh api -X POST /repos/tuist/tuist/actions/runners/registration-token --jq .token
```

If the bootstrap fails after the GitHub Actions runner step and you
need to re-run, mint a fresh token first.

### 3. Run the bootstrap

```bash
mise run vm-image-builder:bootstrap -- \
  --ip <scaleway-ipv4> \
  --hostname vm-image-builder-<n> \
  --use-ssh-agent \
  --gh-token "$(gh api -X POST /repos/tuist/tuist/actions/runners/registration-token --jq .token)"
```

The command prompts for the `m1` password (paste from the Scaleway
email). On success it prints the host's SSH SHA256 fingerprint. Save
that in 1Password under the host's item, field `ssh-fingerprint`, so
future re-runs against this host pass `--known-fingerprint <value>`
and verify against it instead of TOFU-accepting whatever key the
host presents.

What the bootstrap does, in order:

1. Wait for SSH on `:22`. Capture the host key (TOFU) or verify
   against `--known-fingerprint`.
2. Install `/etc/sudoers.d/m1-nopasswd` (passwordless sudo for m1).
3. Configure auto-login: write `/etc/kcpassword`, set
   `autoLoginUser=m1`, kick `loginwindow`, wait for m1's Aqua
   session to come up. Tart will fail every subsequent VM start
   with `VZErrorDomain Code=-9` unless this succeeds.
4. Disable idle sleep, display sleep, screensaver, and auto-logout.
5. Set the macOS hostname.
6. Install Homebrew (NONINTERACTIVE), then `tap cirruslabs/cli` and
   `brew install mise packer tart`.
7. Verify a full Xcode is present and the license is accepted.
8. Append `export TUIST_MIX_BUILD_ROOT=/opt/tuist-build-cache` to
   `/etc/zshenv`. The xcresult-processor build workflow shares the
   BEAM build cache across runs via this env var.
9. Download `actions-runner-osx-arm64-<version>.tar.gz`, run
   `./config.sh` with the operator-supplied registration token, and
   `./svc.sh install m1 && ./svc.sh start` to load the runner as a
   LaunchAgent under m1's auto-login session.

Each step is idempotent: re-running on a partially-bootstrapped
host completes the missing steps without redoing the finished ones.

### 4. Smoke-test

Trigger both image workflows on a throwaway branch and confirm both
hosts pick up jobs:

```bash
gh workflow run runner-image.yml --ref <branch>
gh workflow run xcresult-processor-image.yml --ref <branch>
```

GitHub round-robins across matching idle runners, so two
simultaneous dispatches typically land one on each host. Watch the
job log header for `Runner name: vm-image-builder-<n>` to confirm.

If either job fails before Packer launches the VM, the most likely
cause is a missing live Aqua session: SSH in and run
`sudo launchctl print "gui/$(id -u m1)" | grep 'session = Aqua'`.
Empty output means the auto-login session didn't come up; re-run
the bootstrap, which re-kicks `loginwindow`.

## Decommission

Removing a host:

1. In GitHub -> Settings -> Actions -> Runners, click the host ->
   **Remove** to deregister.
2. On the host:

   ```bash
   cd /opt/actions-runner
   ./svc.sh stop
   ./svc.sh uninstall
   ./config.sh remove --token <removal-token>
   ```

3. Release the Scaleway machine from the console.
4. Drop the host's 1Password item.

The remaining hosts pick up the slack automatically, since the
`vm-image-builder` label set survives any individual host going
away.

## Manual fallback

If the bootstrap CLI fails partway and you need to finish by hand,
each step's underlying commands live in
[`infra/vm-image-builder-bootstrap/bootstrap.go`](vm-image-builder-bootstrap/bootstrap.go).
SSH in as m1 and run them in the same order. The
auto-login/sudoers/idle-sleep helpers are in
[`infra/macos-host-bootstrap/bootstrap.go`](macos-host-bootstrap/bootstrap.go)
and behave the same way the in-cluster fleet's reconcile loop runs
them, just composed differently.

## Future: Cluster-API automation

If the builder fleet grows past a handful of hosts, this CLI
should be ported to a `MachineDeployment` shape under
[`infra/cluster-api-provider-scaleway-applesilicon/`](cluster-api-provider-scaleway-applesilicon/).
The provider already knows how to order a Scaleway Mac mini and run
a bootstrap script; the work is teaching it to run the
builder-specific steps (Homebrew, Xcode verification, GitHub Actions
runner registration) instead of the kubelet steps, and to register
the host as a self-hosted runner rather than a Kubernetes Node. The
shared helpers in `infra/macos-host-bootstrap/` are already factored
to support that; the CLI's `Run` function in `bootstrap.go` is the
shape that would lift into a controller. Until that exists, this
runbook is the source of truth.
