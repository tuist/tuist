# VM Image Builder: Bare-Metal Mac mini Onboarding

Stand up a new `vm-image-builder` Mac mini that builds the runner and
xcresult-processor Tart images on the
`[self-hosted, macos, bare-metal, vm-image-builder]` label set.

Today the fleet is hand-bootstrapped. Hosts are bare-metal Mac minis
ordered out-of-band, configured by this runbook, and registered as
GitHub Actions self-hosted runners. There is no `MachineDeployment`
for the builder fleet, deliberately: these hosts sit outside the
workload Kubernetes clusters because they run Packer-driven Tart
builds, not cluster Pods. The Scaleway CAPI provider
(`infra/cluster-api-provider-scaleway-applesilicon/`) manages the
in-cluster macOS fleet; the builder fleet is intentionally separate.

GitHub load-balances queued jobs across every healthy runner that
matches the label set, so adding a second matching host needs no
workflow or chart change.

## Why bare-metal

Both image builds invoke `tart create` and `tart run`, which call into
Apple's Virtualization.framework. The framework refuses to start a
guest unless the calling process owns a live Aqua (GUI) console
session. Hosted GitHub runners can't satisfy this, and the
nested-virt restrictions on cloud macOS rule out running Tart inside
a Tart VM. A real Mac mini with auto-login configured is the only
shape that works.

## Hardware

- **Provider:** Scaleway Apple Silicon (project `tuist-mac-builders`:
  reuse if it exists, create otherwise).
- **SKU:** M4-S (`8 vCPU / 16 GB RAM / 256 GB SSD`).
- **OS image:** `macOS 15 Sequoia` (or whatever Scaleway currently
  ships preinstalled on Apple Silicon; the bootstrap below pins
  package versions, the OS just needs to be a recent supported
  release).

The 16 GB ceiling matters: `runner.pkr.hcl` and
`xcresult-processor.pkr.hcl` both bake `cpu_count = 4 / memory_gb = 8`
so the build VM fits under Tart's `maximumAllowedMemorySize` on a
16 GB host. Don't downsize below M4-S.

## 1. Order the machine

1. In the Scaleway console under the `tuist-mac-builders` project,
   order one **Apple silicon M4-S**.
2. Note the public IPv4 and the root password Scaleway emails once
   provisioning completes (~10 min for a fresh order).
3. Add the IPv4 to the `tuist-mac-builders` SSH allowlist in 1Password
   (vault `tuist-infra`, item `vm-image-builder-fleet`) so we don't
   lose track of which hosts are part of the fleet.

## 2. First-time SSH and create the `m1` user

Scaleway boots Apple Silicon hosts with `m1` as the default admin
user; password is the one Scaleway emailed.

```bash
ssh m1@<host-ip>
# accept the host key; record the SHA256 fingerprint in 1Password
# under vm-image-builder-fleet -> <hostname> -> ssh-fingerprint
```

Pick a hostname that distinguishes the builder from the cluster
fleet. Convention: `vm-image-builder-<n>` (e.g. `vm-image-builder-2`
for the second host).

```bash
sudo scutil --set HostName vm-image-builder-2
sudo scutil --set LocalHostName vm-image-builder-2
sudo scutil --set ComputerName vm-image-builder-2
```

## 3. Host configuration

The auto-login, sudoers, idle-sleep, and GUI-session prep is the
same shape `infra/macos-host-bootstrap/bootstrap.go` runs on
in-cluster Mac minis. For the builder fleet we run it by hand
rather than through the operator, but the steps mirror that file's
documented order: if you change one, mirror the other.

### 3.1 Passwordless sudo

```bash
sudo tee /etc/sudoers.d/m1-nopasswd > /dev/null <<'EOF'
m1 ALL=(ALL) NOPASSWD: ALL
EOF
sudo chmod 440 /etc/sudoers.d/m1-nopasswd
```

### 3.2 Auto-login and live Aqua session

Tart's Virtualization.framework requires the calling process to be
the user holding the GUI console session, so auto-login is what puts
`m1` on the console at boot.

```bash
# /etc/kcpassword is XOR-encoded with Apple's well-known key. The
# encoded payload matches `encodeKCPassword` in
# infra/macos-host-bootstrap/bootstrap.go.
sudo /usr/bin/python3 -c '
import sys
key = bytes([0x7d, 0x89, 0x52, 0x23, 0xd2, 0xbc, 0xdd, 0xea, 0xa3, 0xb9, 0x1f])
pwd = sys.argv[1].encode()
pad = len(key) - (len(pwd) % len(key))
pwd += b"\x00" * pad
out = bytes(b ^ key[i % len(key)] for i, b in enumerate(pwd))
sys.stdout.buffer.write(out)
' "$M1_PASSWORD" | sudo tee /etc/kcpassword > /dev/null
sudo chmod 600 /etc/kcpassword
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser 'm1'
sudo killall -HUP loginwindow
```

Reboot the host. After it comes back, SSH in and confirm `m1` holds
an Aqua session:

```bash
sudo launchctl print "gui/$(id -u m1)" | grep 'session = Aqua'
```

If this prints nothing, Tart will fail every build with
`VZErrorDomain Code=-9 / Failed to get current host key`. Don't
proceed.

### 3.3 Disable idle sleep and lock

```bash
sudo pmset -a sleep 0 displaysleep 0 disksleep 0
sudo defaults write /Library/Preferences/com.apple.screensaver idleTime -int 0
sudo defaults write /Library/Preferences/com.apple.screensaver askForPassword -int 0
sudo defaults write /Library/Preferences/.GlobalPreferences \
  com.apple.autologout.AutoLogOutDelay -int 0
```

## 4. Install build tooling

```bash
# Homebrew (Apple silicon path).
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)" >> ~/.zprofile

# mise. The workflow's `jdx/mise-action` installs Erlang and Elixir
# on demand, but mise itself must be on PATH for the action's
# bootstrap to succeed.
brew install mise

# Tart and Packer. Both invoked directly by the image workflows.
brew install cirruslabs/cli/tart packer

# Xcode. The xcresult-processor build runs the Swift NIF build
# scripts (server/native/xcresult_nif/build.sh) on the host, so a
# full Xcode (not just Command Line Tools) is required. Install
# from the Mac App Store, then accept the license.
sudo xcodebuild -license accept
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

## 5. Persist runner environment

The xcresult-processor workflow honors `$TUIST_MIX_BUILD_ROOT` to
share the BEAM build cache across runs. Set it on the host so every
job sees the same value:

```bash
sudo mkdir -p /opt/tuist-build-cache
sudo chown m1:staff /opt/tuist-build-cache
echo 'export TUIST_MIX_BUILD_ROOT=/opt/tuist-build-cache' >> ~/.zprofile
```

Don't put runner-private state under `~/Library/Caches`. The
runner's `actions/checkout` cleanup occasionally walks the home
directory and we don't want it touching the BEAM cache.

## 6. Register the GitHub Actions runner

1. In `tuist/tuist` -> Settings -> Actions -> Runners -> **New
   self-hosted runner** -> macOS / ARM64.
2. Copy the download URL and the registration token from that page
   (token is one-shot, ~1 hour TTL).
3. On the host:

   ```bash
   sudo mkdir -p /opt/actions-runner
   sudo chown m1:staff /opt/actions-runner
   cd /opt/actions-runner

   RUNNER_VERSION=2.334.0   # match runner-image.yml's pin
   curl -fsSLO "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-osx-arm64-${RUNNER_VERSION}.tar.gz"
   tar xzf "actions-runner-osx-arm64-${RUNNER_VERSION}.tar.gz"

   ./config.sh \
     --url https://github.com/tuist/tuist \
     --token <REGISTRATION_TOKEN> \
     --name vm-image-builder-2 \
     --labels self-hosted,macos,bare-metal,vm-image-builder \
     --work _work \
     --unattended \
     --replace
   ```

   The label set must match `runner-image.yml` and
   `xcresult-processor-image.yml` exactly. Those workflows pin
   `runs-on: [self-hosted, macos, bare-metal, vm-image-builder]`,
   and any drift here makes the new host invisible to the GitHub
   scheduler.

4. Install as a launchd service so it survives reboots:

   ```bash
   ./svc.sh install m1
   ./svc.sh start
   ./svc.sh status
   ```

5. Confirm the runner is online in GitHub. The Runners page should
   show two `Idle` rows with the `vm-image-builder` label.

## 7. Smoke-test

Trigger both image workflows on a throwaway branch and check that
the new host picks at least one of them up:

```bash
gh workflow run runner-image.yml --ref <branch>
gh workflow run xcresult-processor-image.yml --ref <branch>
```

GitHub round-robins across matching idle runners, so two
simultaneous dispatches typically land one on each host. Watch the
job log header for `Runner name: vm-image-builder-2` to confirm.

If either job fails before Packer launches the VM, the most likely
cause is a missing live Aqua session: re-verify section 3.2.

## 8. Decommission

Removing a host:

1. In GitHub -> Settings -> Actions -> Runners, click the host ->
   **Remove** to deregister.
2. On the host:

   ```bash
   cd /opt/actions-runner
   ./svc.sh stop
   ./svc.sh uninstall
   ./config.sh remove --token <REMOVAL_TOKEN>
   ```

3. Release the Scaleway machine from the console.

The remaining hosts pick up the slack automatically, since the
`vm-image-builder` label set survives any individual host going
away.

## Future: Cluster-API automation

When the builder fleet grows past two hosts, this runbook should be
ported to a `MachineDeployment` shape under
`infra/cluster-api-provider-scaleway-applesilicon/`. The provider
already knows how to order a Scaleway Mac mini and run a bootstrap
script; the work is teaching it to bootstrap a Packer host (instead
of a tart-kubelet host) and to register the GitHub Actions runner
agent rather than `tart-kubelet`. Until that exists, this runbook
is the source of truth.
