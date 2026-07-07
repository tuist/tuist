// Package bootstrap turns a freshly-provisioned macOS host into a
// tart-kubelet-ready cluster Node.
//
// Provider-agnostic by design: the caller fills in a Config and Run
// does the rest. Anything host-shaped (IP, SSH credentials, the
// SSH user's password used for passwordless-sudoers and
// /etc/kcpassword, the TOFU host-key pin) is an input; everything
// macOS-shaped is the same on every host:
//   - Auto-login (Virtualization.framework requires a live console).
//   - Hostname = CR name (so tart-kubelet's default --node-name
//     lines up with the inventory resource).
//   - Tart install (the caller-supplied tart.app tarball pinned in
//     the operator image is extracted to /usr/local/lib/tart.app
//     with a /usr/local/bin/tart wrapper).
//   - Kubeconfig drop + tart-kubelet binary upload + launchd plist.
//
// Steps, in order, idempotent on retry:
//  1. Wait for SSH (host has just booted from the provider's image).
//  2. Grant the SSH user passwordless sudo using UserPassword.
//  3. Configure GUI auto-login via /etc/kcpassword + autoLoginUser
//     so Virtualization.framework has a live console session.
//  4. Set the macOS hostname to NodeName.
//  5. Install Tart by extracting the operator-pinned tart.app tarball
//     to /usr/local/lib/tart.app + wrapper at /usr/local/bin/tart.
//  6. Install Tailscale's open-source tailscaled (extracted from the
//     operator-baked binaries tarball), register it as a system
//     daemon via `tailscaled install-system-daemon`, and `tailscale
//     up` with the per-fleet auth key — host joins the tailnet
//     before kubelet so the tailnet IP is the only routable address
//     kubelet ever advertises.
//  7. Install node_exporter for host-level (CPU, mem, disk, network,
//     thermal) metrics, scraped over the tailnet on :9100.
//  8. Drop the kubeconfig the controller built for this host.
//  9. Upload the tart-kubelet binary.
//  10. Write the launchd plist with this host's flags + load it.
//
// After the last step the agent on the host registers a Node and
// starts reconciling Pods. The provider's MachineReconciler flips
// Machine.Status.Ready when this returns nil.
package bootstrap

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net"
	"sort"
	"strings"
	"sync"
	"time"

	"golang.org/x/crypto/ssh"
)

// Config drives the bootstrap.
type Config struct {
	IP      string
	SSHUser string

	// UserPassword is the SSH user's password. Used for two
	// macOS-specific bootstrap steps (passwordless-sudoers entry
	// + /etc/kcpassword for auto-login) and nothing else; the
	// caller is responsible for obtaining it.
	UserPassword string

	SSHPrivateKey []byte

	// NodeName is the cluster Node name tart-kubelet should register.
	// Typically matches the CAPI Machine CR name so `kubectl get
	// nodes` reflects the inventory.
	NodeName string

	// ProviderID is the CAPI machine ID (scw-applesilicon://<zone>/<id>)
	// rendered into tart-kubelet's --provider-id flag so it sets
	// Node.spec.providerID — the field CAPI core matches to bind the
	// Machine to its Node. Empty omits the flag (Node left unbound until
	// patched by hand).
	ProviderID string

	// Kubeconfig is the YAML kubeconfig the controller built for this
	// host (contains a long-lived ServiceAccount token + the API
	// server's external URL + CA bundle). Dropped at
	// /etc/tart-kubelet/kubeconfig.
	Kubeconfig string

	// TartKubeletBinary is the in-memory bytes of the darwin/arm64
	// tart-kubelet binary, baked into the operator image and read at
	// startup. We upload these bytes over SSH to /usr/local/bin on the
	// Mac mini — no external URL, no separate release artifact.
	TartKubeletBinary []byte

	// TartTarball is the gzipped tar of the upstream `tart.app` bundle
	// (the asset published as `tart.tar.gz` on each cirruslabs/tart
	// GitHub release), baked into the operator image at build time and
	// read at startup. We ship the whole `.app` rather than the bare
	// executable inside it because Tart's signature + Virtualization.
	// framework entitlements live on the bundle, not the binary alone.
	// Pinning the version in the operator image makes the Tart version
	// reproducible across reboots and re-provisions; bumping it is a
	// deliberate Dockerfile change.
	TartTarball []byte

	// TailscaleBinaries is the gzipped tar of the `tailscale` and
	// `tailscaled` darwin/arm64 binaries cross-compiled from the
	// upstream Go source at the operator-image-pinned version. The
	// open-source "tailscaled" variant (per Tailscale's own docs at
	// https://github.com/tailscale/tailscale/wiki/Tailscaled-on-macOS)
	// is the canonical headless-server install path on macOS — no GUI
	// app, no .pkg postinstall scripts, just two static binaries plus
	// a launchd plist that `tailscaled install-system-daemon` writes
	// itself. Empty disables the Tailscale step entirely — kubelet
	// then falls back to the public interface as NodeIP, which is fine
	// for clusters where the in-cluster scrapers can reach the Mac
	// mini directly (rare). Production deployments always set this.
	TailscaleBinaries []byte

	// TailscaleAuthKey is a per-fleet Tailscale pre-auth key (from
	// 1Password via ESO). Reusable + ephemeral-tagged so each Mac
	// mini in the fleet authenticates without a separate key, and
	// stale node records age out automatically. Empty disables the
	// Tailscale step even when TailscaleBinaries is present — covers
	// chart bring-up where the key hasn't been provisioned yet.
	TailscaleAuthKey string

	// TailscaleTags are the Tailscale ACL tags advertised on this
	// node at `tailscale up` time. Drives which ACL groups can dial
	// it — e.g. `tag:tuist-macmini-xcresult` is reachable from the
	// cluster's `tag:cluster-scraper` group on :9091 + :9100. Empty
	// uses the auth key's default tag.
	TailscaleTags []string

	// TailscaleAcceptRoutes adds `--accept-routes` to `tailscale up`,
	// so the host installs subnet routes advertised into the tailnet
	// by the cluster-side Connector (infra/helm/tailscale-operator) —
	// today the cluster's Service CIDR, which is what lets Tart
	// runner VMs on this host reach the in-cluster Kura runner-cache
	// Service (the VM's traffic NATs through the host's routing
	// table, so a host route via the tailnet is a VM route). Off by
	// default: a host that accepts routes will steer 10.128.0.0/12
	// into whichever env's Connector advertises it, and the shared
	// Service CIDR across envs makes that ambiguous unless exactly
	// one env advertises (see the tailscale-operator chart values).
	TailscaleAcceptRoutes bool

	// VMKuraEgressCIDR, when non-empty, carves a Kura allowance out
	// of the VM egress firewall (installVMEgressFirewall): Tart VMs
	// may reach this CIDR — the cluster's Service CIDR, where the
	// per-account runner-cache Kura ClusterIPs live — on TCP 4000
	// (the co-hosted HTTP + gRPC cache port), mirroring the Linux
	// runner namespace's NetworkPolicy egress carve-out.
	// Everything else in
	// the RFC1918 blocklist stays blocked; per-account isolation is
	// the Kura app layer's JWT tenant check, exactly as on Linux.
	// Must parse as an IPv4 CIDR; bootstrap fails closed otherwise.
	VMKuraEgressCIDR string

	// VMClusterDNSIP, when non-empty (requires VMKuraEgressCIDR),
	// additionally allows VM egress to this single IP on port 53
	// (TCP+UDP) — the cluster's kube-dns ClusterIP, so the runner
	// VM's /etc/resolver entry (written by dispatch-poll.sh when the
	// runners-controller stages TUIST_CLUSTER_DNS_IP) can resolve
	// `*.svc.cluster.local` names. Must parse as an IPv4 address.
	VMClusterDNSIP string

	// VMCachePNCIDR, when non-empty, allows VM egress to the Scaleway
	// Private Network subnet where the kura runner-cache node pool
	// publishes per-account NodePort endpoints — the addresses
	// dispatch hands out as `cache_endpoint_url` for macOS fleets on
	// node-port-data-plane regions. Only the Kubernetes NodePort
	// range (30000-32767) is passed; the rest of the RFC1918
	// blocklist stays blocked. Must parse as an IPv4 CIDR; bootstrap
	// fails closed otherwise.
	VMCachePNCIDR string

	// VMCachePNVLAN is the VLAN ID of this server's Private Network
	// attachment (per-host — Scaleway assigns it at attach time; the
	// CAPI provider reads it from the Apple Silicon Private Networks
	// API). When set together with VMCachePNCIDR, bootstrap creates
	// the macOS VLAN interface on en0 and DHCPs it so Scaleway IPAM
	// hands the host its PN address; the VM NAT leg derives the
	// interface from the route this creates. 0 skips interface
	// management (the firewall pass rule still applies if the CIDR
	// is set, for hosts configured out-of-band).
	VMCachePNVLAN uint32

	// NodeExporterBinary is the darwin/arm64 node_exporter binary
	// (cross-compiled in the operator image from
	// github.com/prometheus/node_exporter at build time). Installed
	// at /usr/local/bin/node_exporter under a launchd plist that
	// binds it to the tailnet interface on :9100. Empty disables
	// the host-metrics step — paired with TailscaleBinaries so that a
	// chart without tailnet plumbing doesn't ship node_exporter
	// listening on a public IP.
	NodeExporterBinary []byte

	// HostCPU / HostMemoryMB / MaxPods are advertised on the Node.
	HostCPU      int
	HostMemoryMB int
	MaxPods      int

	// NodeLabels is the set of labels tart-kubelet stamps on the
	// Node it registers. The bootstrap layer is generic — fleet
	// membership is just one entry the caller adds (typically
	// `{"tuist.dev/fleet": <fleetName>}`). Empty map omits the
	// flag entirely; the Node carries no operator-set labels.
	//
	// Why bootstrap-time and not a post-registration patch: the
	// label has to land atomically with kubelet registration, or
	// there's a race window where a Node is `Ready` but unlabeled
	// and Pods with `nodeSelector: tuist.dev/fleet=<name>` fail to
	// schedule on it. Same convention CAPI bootstrap providers
	// follow with `kubeadm`'s `kubeletExtraArgs.node-labels`.
	NodeLabels map[string]string

	// KnownHostFingerprint is the SHA256 fingerprint of the SSH
	// server's host key, persisted by the controller after the first
	// successful bootstrap. When empty (first reconcile, fleet
	// expansion) the SSH client uses TOFU: it accepts the key the
	// host presents on the first dial and the controller persists it
	// for next time. When non-empty every dial verifies against it
	// and refuses to connect on mismatch. Replaces a prior
	// `ssh.InsecureIgnoreHostKey()` that left every bootstrap open
	// to a network MITM (kubeconfig + tart-kubelet binary injection).
	KnownHostFingerprint string

	// GHActionsRunner, when non-nil, installs a GitHub Actions
	// self-hosted runner agent on the host as the final step of
	// bootstrap, after tart-kubelet is up. Used for the bare-metal
	// vm-image-builder fleet; pure Node hosts leave this nil.
	//
	// The runner agent runs as a LaunchAgent under cfg.SSHUser and
	// picks up image-bake workflow jobs from GitHub. No Pods are ever
	// scheduled to builder Nodes (the per-fleet `tuist.dev/fleet`
	// NodeLabel scopes Pod selection away from the builder fleet
	// name). That same property means tart-kubelet's orphan-VM GC
	// would treat the host-baked build VM as collectable and reap it
	// mid-`tart push`, so renderLaunchdPlist passes `--disable-vm-gc`
	// when this is set.
	//
	// The reconciler is responsible for resolving the registration
	// token from a Secret before populating
	// GHActionsRunner.GHRunnerRegistrationToken.
	GHActionsRunner *GHActionsRunnerConfig

	// DisableVMGC passes `--disable-vm-gc` to tart-kubelet when true.
	// It exists so the drift-update path can preserve the flag without
	// re-resolving GHActionsRunner: `Run` always sets GHActionsRunner on
	// builder hosts (and renderLaunchdPlist follows that), but
	// `UpdateTartKubelet` re-renders the plist on every binary roll
	// without re-resolving the runner config — resolving it would mint a
	// fresh registration token on each drift loop for no reason. Without
	// this field the roll renders a flag-less plist and the orphan-VM GC
	// comes back, reaping the in-flight build VM mid-`tart push`. The
	// reconciler sets it from `machine.Spec.GHActionsRunner != nil` on
	// both the bootstrap and update paths.
	DisableVMGC bool
}

// Run executes the bootstrap. Idempotent: re-running on a partially-
// bootstrapped host completes the missing steps without redoing the
// finished ones.
//
// Returns the SSH host fingerprint observed during the dial. The
// caller persists it so future reconciles verify the same host
// (TOFU). When cfg.KnownHostFingerprint was already set, the returned
// value equals it and Run rejects any mismatch as an error.
func Run(ctx context.Context, cfg Config) (string, error) {
	signer, err := ssh.ParsePrivateKey(cfg.SSHPrivateKey)
	if err != nil {
		return "", fmt.Errorf("parse ssh key: %w", err)
	}

	hk := NewHostKeyState(cfg.KnownHostFingerprint)

	if err := WaitForSSH(ctx, cfg.IP, cfg.SSHUser, signer, hk); err != nil {
		return "", err
	}

	client, err := Dial(cfg.IP, cfg.SSHUser, signer, hk)
	if err != nil {
		return "", err
	}
	defer client.Close()

	if err := EnablePasswordlessSudo(ctx, client, cfg.SSHUser, cfg.UserPassword); err != nil {
		return hk.Observed(), fmt.Errorf("passwordless sudo: %w", err)
	}
	if err := EnableAutoLogin(ctx, client, cfg.SSHUser, cfg.UserPassword); err != nil {
		return hk.Observed(), fmt.Errorf("auto-login: %w", err)
	}
	if err := DisableIdleSleep(ctx, client); err != nil {
		return hk.Observed(), fmt.Errorf("disable idle sleep: %w", err)
	}
	if cfg.NodeName != "" {
		if err := SetHostname(ctx, client, cfg.NodeName); err != nil {
			return hk.Observed(), fmt.Errorf("set hostname: %w", err)
		}
	}
	if err := installTart(ctx, client, cfg.TartTarball); err != nil {
		return hk.Observed(), fmt.Errorf("install tart: %w", err)
	}
	if err := installVMCachePNInterface(ctx, client, cfg); err != nil {
		return hk.Observed(), fmt.Errorf("install vm cache pn interface: %w", err)
	}
	if err := installVMEgressFirewall(ctx, client, cfg); err != nil {
		return hk.Observed(), fmt.Errorf("install vm egress firewall: %w", err)
	}
	if err := installTailscale(ctx, client, cfg); err != nil {
		return hk.Observed(), fmt.Errorf("install tailscale: %w", err)
	}
	if err := installNodeExporter(ctx, client, cfg); err != nil {
		return hk.Observed(), fmt.Errorf("install node_exporter: %w", err)
	}
	if err := writeKubeconfig(ctx, client, cfg.Kubeconfig); err != nil {
		return hk.Observed(), fmt.Errorf("write kubeconfig: %w", err)
	}
	if err := installTartKubelet(ctx, client, cfg.TartKubeletBinary); err != nil {
		return hk.Observed(), fmt.Errorf("install tart-kubelet: %w", err)
	}
	if err := loadTartKubeletLaunchd(ctx, client, cfg); err != nil {
		return hk.Observed(), fmt.Errorf("load launchd job: %w", err)
	}
	// Optional builder-fleet tail: install brew tooling, verify
	// Xcode, set the build-cache env, install + start the GitHub
	// Actions runner agent. Skipped entirely for pure Node hosts
	// (the default fleet).
	if cfg.GHActionsRunner != nil {
		if err := runActionsRunnerInstall(ctx, client, cfg.SSHUser, cfg.NodeName, *cfg.GHActionsRunner); err != nil {
			return hk.Observed(), fmt.Errorf("install gh actions runner: %w", err)
		}
	}
	return hk.Observed(), nil
}

// UpdateTartKubelet rolls a new tart-kubelet binary onto an
// already-bootstrapped Mac mini, plus any operator-managed host
// artifacts whose drift-tracked SHA changed since the last reconcile.
// Today that's tart-kubelet itself and Tailscale; future host-side
// installs hook in here by adding their step + their SHA tracking on
// the Machine status.
//
// Refreshes the kubeconfig (token rotation, server-URL changes, or
// hosts bootstrapped before tart-kubelet existed at all), uploads the
// latest binary, re-runs installTailscale when the host has the
// Tailscale binaries + auth key wired (the install step is itself
// idempotent — it bootouts the running daemon, swaps binaries, and
// re-registers — so re-running is safe; also handles future version
// bumps via the same operator-image-bump → drift-reconcile path),
// and reloads the launchd job.
//
// Skips one-shot host prep (sudo, auto-login, hostname, Tart) —
// those don't change between updates and re-running them would
// either be wasted SSH work or risk disrupting the running VMs
// (Tart). The pf VM-egress firewall IS re-run: its ruleset is now
// config-shaped (the Kura/DNS carve-out CIDRs), the install is
// idempotent, and `pfctl -f` swaps rulesets atomically without
// dropping established states — so a values change reaches existing
// hosts on the next drift roll instead of waiting for
// re-provisioning. The launchd `bootout`+`bootstrap` cycle runs unconditionally
// — it's a ~1-second agent restart and Tart VMs survive
// `nohup`-detached, so workloads are unaffected. The kubelet's startup
// state-recovery pass re-binds them on the new agent.
//
// Returns the observed host fingerprint for the same reason Run does.
// On the update path KnownHostFingerprint is normally already set (the
// bootstrap reconcile populated it), so this is a verification rather
// than a capture.
func UpdateTartKubelet(ctx context.Context, cfg Config) (string, error) {
	signer, err := ssh.ParsePrivateKey(cfg.SSHPrivateKey)
	if err != nil {
		return "", fmt.Errorf("parse ssh key: %w", err)
	}
	hk := NewHostKeyState(cfg.KnownHostFingerprint)
	client, err := Dial(cfg.IP, cfg.SSHUser, signer, hk)
	if err != nil {
		return "", err
	}
	defer client.Close()

	if err := writeKubeconfig(ctx, client, cfg.Kubeconfig); err != nil {
		return hk.Observed(), fmt.Errorf("refresh kubeconfig: %w", err)
	}
	if err := installTartKubelet(ctx, client, cfg.TartKubeletBinary); err != nil {
		return hk.Observed(), fmt.Errorf("install tart-kubelet: %w", err)
	}
	if err := installVMCachePNInterface(ctx, client, cfg); err != nil {
		return hk.Observed(), fmt.Errorf("refresh vm cache pn interface: %w", err)
	}
	if err := installVMEgressFirewall(ctx, client, cfg); err != nil {
		return hk.Observed(), fmt.Errorf("refresh vm egress firewall: %w", err)
	}
	if err := installTailscale(ctx, client, cfg); err != nil {
		return hk.Observed(), fmt.Errorf("install tailscale: %w", err)
	}
	if err := installNodeExporter(ctx, client, cfg); err != nil {
		return hk.Observed(), fmt.Errorf("install node_exporter: %w", err)
	}
	if err := loadTartKubeletLaunchd(ctx, client, cfg); err != nil {
		return hk.Observed(), fmt.Errorf("reload launchd job: %w", err)
	}
	return hk.Observed(), nil
}

// HostConfigHash is a fleet-wide canonical fingerprint of everything the
// operator pushes to a host: the rendered install scripts (firewall +
// vmnat, PN interface, launchd job + plist, Tailscale, node_exporter,
// tart-kubelet install) plus the bytes of every embedded binary. The
// reconciler stamps it on each Machine and re-pushes when it drifts, so
// a change to ANY pushed config — a script tweak, a fleet-config CIDR, or
// a re-baked binary in the operator image — reaches existing hosts on the
// next reconcile rather than only on a tart-kubelet binary roll.
//
// It is computed once at operator startup from a Config that carries
// operator-image + fleet-config inputs. The hash must be identical across
// every host in a fleet or it would falsely drift on each one, so this
// function neutralizes every per-host / volatile field before rendering
// (NodeName, IP, VLAN, kubeconfig, auth key, ...) regardless of what the
// caller passed — the canonical Config built in the manager already
// leaves them empty; zeroing them here makes that a guarantee rather than
// a caller obligation. The renderers are plain string templates, so an
// empty per-host substitution is well-formed; none slice or index a value
// that must be non-empty.
func HostConfigHash(cfg Config) string {
	// Strip per-host / volatile fields so the fingerprint is fleet-wide.
	// Fleet-config fields (CIDRs, tags, accept-routes, host CPU/mem/pods)
	// and the embedded binaries are kept.
	cfg.IP = ""
	cfg.SSHUser = ""
	cfg.UserPassword = ""
	cfg.SSHPrivateKey = nil
	cfg.NodeName = ""
	cfg.ProviderID = ""
	cfg.Kubeconfig = ""
	cfg.TailscaleAuthKey = ""
	cfg.VMCachePNVLAN = 0
	cfg.KnownHostFingerprint = ""
	cfg.GHActionsRunner = nil
	cfg.NodeLabels = nil
	// Per-host role signal (builder hosts set it); the launchd plist
	// renderer keys --disable-vm-gc off it, so neutralize it too.
	cfg.DisableVMGC = false

	var b strings.Builder

	// (a) Rendered scripts, concatenated in a fixed order. A
	// label prefixes each so two scripts can't alias into one
	// another's bytes and hide a change.
	firewall, err := renderVMEgressFirewallScript(cfg)
	if err != nil {
		// A malformed canonical CIDR can't render a script. Fold the
		// error text in instead so the hash stays deterministic and
		// distinct rather than panicking — the operator already
		// validates these inputs before they reach a host.
		firewall = "ERROR:" + err.Error()
	}
	for _, part := range []struct{ name, script string }{
		{"firewall", firewall},
		{"vmnat", renderVMNATScript(cfg)},
		{"pn-interface", renderVMCachePNInterfaceScript(cfg)},
		{"launchd", renderTartKubeletLaunchdScript(cfg)},
		{"launchd-plist", renderLaunchdPlist(cfg)},
		{"tailscale", renderTailscaleScript(cfg)},
		{"node-exporter", renderNodeExporterScript()},
		{"tart-kubelet-install", renderTartKubeletInstallScript()},
	} {
		b.WriteString(part.name)
		b.WriteByte('\x00')
		b.WriteString(part.script)
		b.WriteByte('\x00')
	}

	// (b) SHA of each embedded binary the drift loop actually re-pushes.
	// The bytes themselves ride SSH stdin (not the scripts), so their
	// drift is only visible to the hash through their content SHA.
	//
	// TartTarball is intentionally omitted: Tart is bootstrap-only (the
	// hypervisor can't be swapped under running VMs, so UpdateTartKubelet
	// never re-installs it). Hashing it would force a pointless re-push on
	// a Tart bump that couldn't actually update Tart anyway — that bump
	// rolls via Machine replacement, not config drift.
	for _, bin := range []struct {
		name  string
		bytes []byte
	}{
		{"tart-kubelet", cfg.TartKubeletBinary},
		{"tailscale-binaries", cfg.TailscaleBinaries},
		{"node-exporter-binary", cfg.NodeExporterBinary},
	} {
		b.WriteString(bin.name)
		b.WriteByte('\x00')
		if bin.bytes != nil {
			b.WriteString(sha256Hex(bin.bytes))
		}
		b.WriteByte('\x00')
	}

	return sha256Hex([]byte(b.String()))
}

// SetHostname makes the macOS hostname match the CR name, so
// `os.Hostname()` inside tart-kubelet (the default --node-name) lines
// up with the inventory. The operator passes --node-name explicitly
// regardless; this is belt-and-braces.
func SetHostname(ctx context.Context, client *ssh.Client, name string) error {
	script := fmt.Sprintf(`set -euo pipefail
sudo scutil --set HostName %[1]s
sudo scutil --set LocalHostName %[1]s
sudo scutil --set ComputerName %[1]s
`, shellQuote(name))
	return RunCommand(ctx, client, script)
}

// writeKubeconfig drops the controller-built kubeconfig at the
// well-known path tart-kubelet looks for.
func writeKubeconfig(ctx context.Context, client *ssh.Client, kubeconfig string) error {
	if kubeconfig == "" {
		return fmt.Errorf("empty kubeconfig in bootstrap config")
	}
	script := `set -euo pipefail
sudo mkdir -p /etc/tart-kubelet
sudo tee /etc/tart-kubelet/kubeconfig >/dev/null
sudo chmod 0600 /etc/tart-kubelet/kubeconfig
`
	return RunCommandWithStdin(ctx, client, script, strings.NewReader(kubeconfig))
}

// installTartKubelet uploads the operator-baked tart-kubelet binary
// to /usr/local/bin/tart-kubelet on the Mac mini and marks it
// executable. We pipe the bytes via stdin into `sudo tee` rather than
// downloading from an external URL — the operator's image is the
// single source of truth for the kubelet version, so deploying a new
// operator image rolls a new kubelet across the fleet.
//
// Always overwrites. The reconciler's drift detection prevents
// unnecessary calls (it compares the operator's binary SHA to the
// last-applied SHA in the CR's status).
func installTartKubelet(ctx context.Context, client *ssh.Client, binary []byte) error {
	if len(binary) == 0 {
		return fmt.Errorf("tart-kubelet binary is empty")
	}
	return RunCommandWithStdin(ctx, client, renderTartKubeletInstallScript(), bytes.NewReader(binary))
}

// renderTartKubeletInstallScript is the static SSH script that lands the
// uploaded tart-kubelet binary. The binary bytes themselves ride stdin;
// their drift is tracked by the binary SHA, so this script carries no
// host- or binary-specific input and is included verbatim in the host
// config hash.
func renderTartKubeletInstallScript() string {
	return `set -euo pipefail
sudo mkdir -p /usr/local/bin
sudo tee /usr/local/bin/tart-kubelet >/dev/null
sudo chmod 0755 /usr/local/bin/tart-kubelet
# Re-sign in place. The binary already carries a valid Go linker ad-hoc
# signature, but overwriting /usr/local/bin/tart-kubelet at the same inode
# leaves macOS's AMFI validating the new pages against the previous
# binary's cached cdhash — a mismatch the kernel kills as
# OS_REASON_CODESIGNING on the next launch, stranding the Node NotReady.
# A forced ad-hoc re-sign refreshes the signature and invalidates that
# stale cache so the rolled binary actually runs.
sudo codesign --force --sign - /usr/local/bin/tart-kubelet
`
}

// loadTartKubeletLaunchd writes /Library/LaunchDaemons/dev.tuist.tart-kubelet.plist
// with this host's flags substituted in, fixes ownership on the
// kubelet's writable paths so the SSH user owns them (the launchd job
// runs as that user — see the comment in renderLaunchdPlist), then
// reloads the launchd job and verifies it actually came up. Idempotent
// across reruns.
//
// The reload is the fragile part on a headless Mac, and getting it
// wrong is what strands a fleet Node NotReady:
//
//   - Re-registration churn: every `bootout`+`bootstrap` re-registers
//     the plist with macOS Background Task Management. BTM caps "legacy
//     daemon" notifications and, once exceeded, stops honouring the
//     job's KeepAlive automatic respawn — so a later clean exit never
//     restarts and the Node goes NotReady. We avoid this by only
//     rewriting + bootout/bootstrapping when the plist content actually
//     changed; a binary-only roll (the common drift case) leaves the
//     launchd args identical, so we restart in place with `kickstart -k`
//     instead, which re-execs the new binary without touching BTM.
//
//   - Silent reload failure: `bootout` immediately followed by
//     `bootstrap` can race (or be BTM-throttled) and leave the job
//     booted-out, which KeepAlive cannot recover. The old code returned
//     success regardless, so the reconciler recorded the SHA roll as
//     done and never retried, leaving the Node NotReady indefinitely.
//     We now poll for a live PID, force a `kickstart` if it didn't come
//     up, and exit non-zero if it still won't run — so the caller keeps
//     the drift set and retries instead of recording a roll that never
//     took.
func loadTartKubeletLaunchd(ctx context.Context, client *ssh.Client, cfg Config) error {
	plist := renderLaunchdPlist(cfg)
	return RunCommandWithStdin(ctx, client, renderTartKubeletLaunchdScript(cfg), strings.NewReader(plist))
}

// renderTartKubeletLaunchdScript is the SSH script that installs +
// reloads the launchd job. The plist content rides stdin (see
// renderLaunchdPlist); this script only substitutes the SSH user that
// owns kubelet's writable paths, so it is config-shaped and folds into
// the host config hash.
func renderTartKubeletLaunchdScript(cfg Config) string {
	return fmt.Sprintf(`set -euo pipefail
PLIST=/Library/LaunchDaemons/dev.tuist.tart-kubelet.plist
NEW="$(mktemp)"
trap 'rm -f "$NEW"' EXIT
cat >"$NEW"
# Apple's Virtualization.framework requires the calling process to be
# owned by the user with the live GUI console session — see
# renderLaunchdPlist's UserName field. Hand kubelet-writable paths to
# that user so it can write VM logs / userdata / read its kubeconfig.
sudo mkdir -p /var/log/tart-vms /var/lib/tart-userdata /var/lib/tart-vnc-control /etc/tart-kubelet
sudo touch /var/log/tart-kubelet.log
sudo chown -R %[1]s:staff /var/log/tart-vms /var/lib/tart-userdata /var/lib/tart-vnc-control /var/log/tart-kubelet.log
sudo chown %[1]s:staff /etc/tart-kubelet/kubeconfig
sudo chmod 0600 /etc/tart-kubelet/kubeconfig

# pid prints the launchd-tracked PID (empty when not running). settled
# waits for a NEW pid (different from the pre-reload one) and confirms it
# is still the same a few seconds later. That rules out two false
# positives: a no-op kickstart that leaves the old process running, and a
# crash-looping launch (e.g. an OS_REASON_CODESIGNING kill) that briefly
# shows a transient pid on each respawn — neither must be mistaken for a
# successful roll into the freshly-uploaded binary.
pid() { sudo launchctl print system/dev.tuist.tart-kubelet 2>/dev/null | awk '/^[[:space:]]*pid = [0-9]+/{print $3; exit}' || true; }
OLD="$(pid)"
settled() {
  for _ in $(seq 1 20); do
    p="$(pid)"
    if [ -n "$p" ] && [ "$p" != "$OLD" ]; then
      sleep 5
      [ "$(pid)" = "$p" ] && return 0 || return 1
    fi
    sleep 1
  done
  return 1
}

# Restart in place when the plist is unchanged and a process is running
# (avoids BTM re-registration churn); otherwise rewrite it and
# bootout+bootstrap to pick up the new args / start it fresh.
if cmp -s "$NEW" "$PLIST" && [ -n "$OLD" ]; then
  sudo launchctl kickstart -k system/dev.tuist.tart-kubelet 2>/dev/null || true
else
  sudo cp "$NEW" "$PLIST"
  sudo chown root:wheel "$PLIST"
  sudo chmod 0644 "$PLIST"
  sudo launchctl bootout system "$PLIST" 2>/dev/null || true
  sudo launchctl bootstrap system "$PLIST" 2>/dev/null || true
fi

# Require a fresh, stable process — then force a kickstart and re-check if
# the reload didn't restart it. Exit non-zero if it never settles so the
# reconciler keeps the drift set and retries instead of recording a roll
# that never took.
settled && exit 0
sudo launchctl kickstart -k system/dev.tuist.tart-kubelet 2>/dev/null || true
settled && exit 0
echo "tart-kubelet did not reach a running state after launchd reload" >&2
exit 1
`, shellQuote(cfg.SSHUser))
}

func renderLaunchdPlist(cfg Config) string {
	cpu := cfg.HostCPU
	if cpu == 0 {
		cpu = 8
	}
	mem := cfg.HostMemoryMB
	if mem == 0 {
		mem = 16384
	}
	maxPods := cfg.MaxPods
	if maxPods == 0 {
		// Apple's macOS SLA caps virtualized macOS instances at 2 per
		// bare-metal host (Tart refuses to start a third VM). max-pods
		// is set to 3 (not 2) because it counts every Pod on the Node,
		// not just Tart-VM Pods — host-system DaemonSets like
		// hcloud-csi-node already consume one slot, and the rolling-
		// update surge needs a third for csi(1) + old(1) + new(1).
		// The 2-VM cap is enforced by Tart at the virtualization layer.
		maxPods = 3
	}
	user := cfg.SSHUser
	if user == "" {
		user = "m1"
	}
	// `--node-labels` is rendered conditionally so a host bootstrapped
	// without any labels (or one whose operator wants to retire
	// labels) renders an identical plist. tart-kubelet treats an
	// absent flag as "operator-managed labels = ∅" and drops any
	// labels it previously set, giving us a clean retire path.
	//
	// k=v,k=v,... form (kubelet's --node-labels convention).
	// Sorted for deterministic plist rendering — otherwise map
	// iteration order would dirty the host fingerprint and
	// trigger needless plist rewrites.
	nodeLabelsArg := ""
	if len(cfg.NodeLabels) > 0 {
		keys := make([]string, 0, len(cfg.NodeLabels))
		for k := range cfg.NodeLabels {
			keys = append(keys, k)
		}
		sort.Strings(keys)
		pairs := make([]string, 0, len(keys))
		for _, k := range keys {
			pairs = append(pairs, fmt.Sprintf("%s=%s", k, cfg.NodeLabels[k]))
		}
		nodeLabelsArg = fmt.Sprintf("\n    <string>--node-labels=%s</string>", strings.Join(pairs, ","))
	}
	// Switch tart-kubelet's NodeIP resolution to the Tailscale CLI
	// whenever the operator wired Tailscale into this host. Without
	// the flag kubelet would pick the first non-loopback interface,
	// which on a Scaleway Mac mini is the public IP — Pods' PodIP
	// rewrite would then advertise an unauthenticated host:port to
	// the cluster scrapers, defeating the tailnet boundary. We gate
	// on the auth key (not just the pkg) so a chart bring-up where
	// the key hasn't been provisioned yet falls back cleanly rather
	// than wedging kubelet on a missing `tailscale ip` lookup.
	nodeIPSourceArg := ""
	if len(cfg.TailscaleBinaries) > 0 && cfg.TailscaleAuthKey != "" {
		nodeIPSourceArg = "\n    <string>--node-ip-source=tailscale</string>"
	}
	// providerID binds the Node to its CAPI Machine. Rendered as a flag so
	// freshly-provisioned and re-rolled nodes self-bind without a manual
	// `kubectl patch node ... providerID`. Empty (e.g. before the server
	// is ordered) omits it; tart-kubelet then leaves spec.providerID unset
	// and a later reconcile re-renders the plist once it's known.
	providerIDArg := ""
	if cfg.ProviderID != "" {
		providerIDArg = fmt.Sprintf("\n    <string>--provider-id=%s</string>", cfg.ProviderID)
	}
	// Builder-fleet hosts never have Pods scheduled but bake images with
	// a host-level Packer/`tart` process. tart-kubelet's orphan-VM GC
	// treats every local VM not backed by a Pod as collectable, so it
	// would reap the in-flight build VM mid-`tart push` (the push then
	// fails at the NVRAM layer with `nvram.bin doesn't exist`). Disable
	// the GC there; the image-bake workflow reclaims its own Tart disk.
	//
	// GHActionsRunner != nil identifies a builder on the bootstrap path;
	// DisableVMGC carries the same intent on the drift-update path, which
	// re-renders the plist without re-resolving the runner config (see
	// the field comment). Either is sufficient.
	disableVMGCArg := ""
	if cfg.GHActionsRunner != nil || cfg.DisableVMGC {
		disableVMGCArg = "\n    <string>--disable-vm-gc</string>"
	}
	// Run tart-kubelet as the SSH user (m1). Apple's
	// Virtualization.framework requires the calling process to be the
	// same user that holds the live GUI console session — Tart's
	// "Failed to get current host key" otherwise. The auto-login we
	// configured in `EnableAutoLogin` puts m1 on the console at boot;
	// matching the launchd job's UserName lines tart up with that
	// session.
	return fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>dev.tuist.tart-kubelet</string>
  <key>UserName</key>
  <string>%[5]s</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/tart-kubelet</string>
    <string>--node-name=%[1]s</string>
    <string>--kubeconfig=/etc/tart-kubelet/kubeconfig</string>
    <string>--host-cpu=%[2]d</string>
    <string>--host-memory-mb=%[3]d</string>
    <string>--max-pods=%[4]d</string>%[6]s%[7]s%[8]s%[9]s
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>/var/log/tart-kubelet.log</string>
  <key>StandardErrorPath</key><string>/var/log/tart-kubelet.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>HOME</key><string>/Users/%[5]s</string>
    <key>PATH</key><string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
  </dict>
</dict>
</plist>
`, cfg.NodeName, cpu, mem, maxPods, user, nodeLabelsArg, nodeIPSourceArg, providerIDArg, disableVMGCArg)
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

// HostKeyState wires SSH dials to the persisted-fingerprint TOFU
// flow. The same instance is shared across WaitForSSH retries and the
// real dial: when we capture a fingerprint on a probe dial the real
// dial verifies against it, so an attacker can't inject a different
// host key between the two.
type HostKeyState struct {
	mu       sync.Mutex
	expected string // empty until first observation; persisted by caller
	captured string // SHA256 of the key the host actually presented
}

// ErrHostKeyMismatch is returned by the host-key callback when the host
// presents a key that differs from the operator's pinned fingerprint. Callers
// that adopt boxes from a reinstall-on-release pool match against it (errors.Is)
// to re-TOFU during bootstrap: a freshly-claimed box can be reimaged after its
// key was pinned, legitimately rotating the host key.
var ErrHostKeyMismatch = errors.New("host key fingerprint mismatch")

func NewHostKeyState(known string) *HostKeyState {
	return &HostKeyState{expected: known}
}

// Observed returns the fingerprint the host actually presented during
// the dial, or the expected value if the dial never happened. The
// controller persists this so the next reconcile starts with a known
// host.
func (h *HostKeyState) Observed() string {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.captured != "" {
		return h.captured
	}
	return h.expected
}

func (h *HostKeyState) Callback() ssh.HostKeyCallback {
	return func(_ string, _ net.Addr, key ssh.PublicKey) error {
		got := ssh.FingerprintSHA256(key)
		h.mu.Lock()
		defer h.mu.Unlock()
		// Mid-bootstrap rotation guard: any state that has already
		// observed a key requires every subsequent observation to
		// match it. Without this, two dials in a single bootstrap
		// (probe + real) could see different keys and the second
		// would silently TOFU over the first.
		if h.captured != "" && h.captured != got {
			return fmt.Errorf("host key fingerprint changed mid-bootstrap: previously %s, now %s", h.captured, got)
		}
		// Persisted-fingerprint verification. When the operator
		// already knows what key to expect (Secret carries
		// host-fingerprint from a prior reconcile), refuse anything
		// else regardless of TOFU state.
		if h.expected != "" && got != h.expected {
			return fmt.Errorf("%w: expected %s, got %s", ErrHostKeyMismatch, h.expected, got)
		}
		h.captured = got
		return nil
	}
}

func Dial(ip, user string, signer ssh.Signer, hk *HostKeyState) (*ssh.Client, error) {
	return DialAuth(ip, user, []ssh.AuthMethod{ssh.PublicKeys(signer)}, hk)
}

// DialAuth is Dial parameterised over the auth method list. Use it
// when the caller wants something other than a single in-process
// signer, e.g. SSH agent auth where the keys live in 1Password and
// the agent socket signs on demand. Same host-key TOFU semantics as
// Dial.
func DialAuth(ip, user string, auth []ssh.AuthMethod, hk *HostKeyState) (*ssh.Client, error) {
	cfg := &ssh.ClientConfig{
		User:            user,
		Auth:            auth,
		HostKeyCallback: hk.Callback(),
		Timeout:         15 * time.Second,
	}
	return ssh.Dial("tcp", ip+":22", cfg)
}

func WaitForSSH(ctx context.Context, ip, user string, signer ssh.Signer, hk *HostKeyState) error {
	return WaitForSSHAuth(ctx, ip, user, []ssh.AuthMethod{ssh.PublicKeys(signer)}, hk)
}

// WaitForSSHAuth is WaitForSSH parameterised over the auth method
// list. Same semantics as DialAuth.
func WaitForSSHAuth(ctx context.Context, ip, user string, auth []ssh.AuthMethod, hk *HostKeyState) error {
	deadline := time.Now().Add(5 * time.Minute)
	for {
		if time.Now().After(deadline) {
			return fmt.Errorf("SSH not available after 5m at %s", ip)
		}
		client, err := DialAuth(ip, user, auth, hk)
		if err == nil {
			client.Close()
			return nil
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(10 * time.Second):
		}
	}
}

// EnablePasswordlessSudo writes a sudoers.d entry for the SSH user. We
// authenticate the initial sudo with the SSH user's password supplied
// by the caller; subsequent sudo calls don't need it.
//
// Pre-ordered hosts that sat in the pool longer than Scaleway's
// password-disclosure window won't have a usable password — for those
// the operator is expected to seed /etc/sudoers.d/<user>-nopasswd by
// hand via the prepare-fleet-host script. With no password to feed sudo,
// hammering `sudo -S` every reconcile would consume PAM failure-tally
// slots and lock the account in a loop the controller can never
// escape (the lockout outlives the controller's retry window because
// every retry re-arms it). When we don't have a password to use,
// bail safely so the lockout can drain naturally and the operator's
// out-of-band prep can land.
//
// File-existence check still short-circuits the common case where
// the operator already staged the sudoers entry before adoption.
func EnablePasswordlessSudo(ctx context.Context, client *ssh.Client, user, password string) error {
	if password == "" {
		// Idempotency-only path: if the sudoers file is there, fine;
		// if not, return without touching PAM so we don't ramp the
		// lockout counter on every reconcile.
		check := fmt.Sprintf(`test -f /etc/sudoers.d/%[1]s-nopasswd`, user)
		return RunCommand(ctx, client, check)
	}
	script := fmt.Sprintf(`set -euo pipefail
if [ -f /etc/sudoers.d/%[1]s-nopasswd ]; then exit 0; fi
echo '%[2]s' | sudo -S tee /etc/sudoers.d/%[1]s-nopasswd > /dev/null <<EOF
%[1]s ALL=(ALL) NOPASSWD: ALL
EOF
sudo chmod 440 /etc/sudoers.d/%[1]s-nopasswd
`, user, password)
	return RunCommand(ctx, client, script)
}

// EnableAutoLogin sets the macOS auto-login flag so a desktop session
// exists at boot. Tart's Virtualization.framework requires a live
// console session — without this, every `tart run` returns
// "Virtualization is not available because no graphic console is
// available".
//
// macOS implements auto-login via:
//   - /etc/kcpassword (XOR-encoded password with Apple's well-known key)
//   - com.apple.loginwindow.autoLoginUser preference
func EnableAutoLogin(ctx context.Context, client *ssh.Client, user, password string) error {
	// No password to XOR into /etc/kcpassword means we'd write a
	// broken kcpassword (just the cipher key with no plaintext under
	// it) and macOS would silently fail to auto-login the user. That
	// path is hit on adopted pool hosts where Scaleway no longer
	// surfaces the bootstrap password; the operator is expected to
	// stage `/etc/kcpassword` + autoLoginUser by hand as part of the
	// prep-script flow. Bail before doing damage.
	if password == "" {
		return nil
	}
	encoded := encodeKCPassword(password)
	// Stage the binary kcpassword via base64 to avoid TTY issues.
	//
	// Why we kick loginwindow at the end:
	// On headless Apple Silicon Mac minis (Scaleway, AWS EC2 Mac, etc.)
	// macOS's loginwindow at boot does NOT honor the auto-login
	// preference unless a display device is attached — so the system
	// boots, the console stays at the root user, and no Aqua (GUI)
	// session for the auto-login user comes up. Apple's
	// Virtualization.framework refuses to start macOS guests in that
	// state ("Failed to get current host key" / VZErrorDomain Code=-9),
	// which means tart-kubelet's `tart run` fails on every pod even
	// after Tart and the kubelet are correctly installed.
	//
	// `launchctl kickstart -k system/com.apple.loginwindow` is the
	// modern way to do this and handles both cases uniformly:
	//   * loginwindow IS running: SIGTERM the existing instance and
	//     respawn it.
	//   * loginwindow is NOT running: just spawn it.
	// `killall -HUP loginwindow` (the previous approach) exits 1 with
	// "No matching processes were found" when loginwindow is missing,
	// which is the state we land in if the host had loginwindow exit
	// via SIGHUP earlier (launchd's policy is to not auto-respawn
	// after SIGHUP for a console-bound daemon). kickstart talks to
	// launchd's service registry directly so the missing-process case
	// is a clean start, not an error.
	script := fmt.Sprintf(`set -euo pipefail
echo '%[2]s' | base64 -d | sudo tee /etc/kcpassword > /dev/null
sudo chmod 600 /etc/kcpassword
sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser '%[1]s'
sudo launchctl kickstart -k system/com.apple.loginwindow 2>/dev/null || true
# Wait for the Aqua session to come up. loginwindow respawn typically
# takes <2s; 30s is generous. If it still doesn't appear we still
# proceed to the kcpassword verification below before failing — the
# Aqua check is best-effort because launchctl's session inspection
# semantics vary between macOS releases.
session_up=0
for i in $(seq 1 30); do
  if sudo launchctl print "gui/$(id -u '%[1]s')" 2>/dev/null | grep -q 'session = Aqua'; then
    session_up=1
    break
  fi
  sleep 1
done

# Verify /etc/kcpassword wasn't replaced by macOS Tahoe's "<sealed>"
# marker. When the password we wrote doesn't actually match the
# user's, loginwindow rejects the auto-login attempt and overwrites
# /etc/kcpassword with the XOR-encoded literal string "<sealed>"
# (8 bytes + 3 NUL padding = 11 bytes total). Bootstrap silently
# completes but every subsequent reboot fails to bring up an Aqua
# session — Tart can't start guests, all runner pods hit
# TartCreateFailed indefinitely.
#
# Read kcpassword as root and XOR-decode it; the first 8 bytes are
# the signal. Python exit 1 here propagates via 'set -e' and fails
# the bootstrap loudly, so the operator fixes the bootstrap-Secret-
# vs-host password drift before the host ships.
sudo /usr/bin/python3 - <<'CHECK'
import sys
key = bytes([0x7d, 0x89, 0x52, 0x23, 0xd2, 0xbc, 0xdd, 0xea, 0xa3, 0xb9, 0x1f])
with open('/etc/kcpassword', 'rb') as f:
    enc = f.read()
dec = bytes(b ^ key[i %% len(key)] for i, b in enumerate(enc))
if dec.startswith(b'<sealed>'):
    sys.stderr.write("kcpassword replaced by macOS with <sealed> marker — bootstrap-stored password does not match m1's actual password on this host\n")
    sys.exit(1)
CHECK

if [ "$session_up" = "0" ]; then
  echo "WARN: Aqua session for %[1]s did not appear after loginwindow kick; bootstrap continues — VM-start preflight will retry"
fi
`, user, encoded)
	return RunCommand(ctx, client, script)
}

// DisableIdleSleep stops macOS from tearing the user's Aqua session
// down out from under tart-kubelet. Apple's Virtualization framework
// needs the auto-login user to hold a live console session at the
// moment of `tart run`; if the host idle-sleeps, the screensaver
// triggers an auto-logout, or display-sleep flushes WindowServer,
// the session goes away and every subsequent VM start fails with
// `VZErrorDomain Code=-9 / Failed to create new HostKey` until
// something kicks loginwindow again. tart-kubelet has a runtime
// preflight that re-establishes the session on demand, but
// preventing the teardown in the first place avoids the sub-30s
// reanimation latency on every cold-start Pod and keeps the kubelet
// from spamming sudo against loginwindow under load.
//
// Settings applied:
//   - `pmset -a sleep 0 displaysleep 0 disksleep 0`: disable host
//     idle sleep + display blank-out + disk spindown. These are
//     `-a` (all power sources) because Mac mini servers are AC-only
//     but we don't trust the default profile selection.
//   - `com.apple.screensaver idleTime 0`: disable the screensaver.
//     Without this, even with `displaysleep 0`, the screensaver
//     timer fires and (depending on host policy) can trigger
//     auto-logout.
//   - `com.apple.screensaver askForPassword 0`: don't lock the
//     screen. Locking destroys the GUI/Aqua session in the same way
//     a logout does on Tahoe.
//   - `com.apple.autologout.AutoLogOutDelay 0`: disable auto-logout
//     after inactivity. This is the policy Apple uses for managed
//     fleets; off-by-default on consumer Macs but Scaleway-baked
//     macOS images sometimes ship with it on.
//
// Idempotent: every call writes the same values regardless of prior
// state. Failures here are fatal because there's no point shipping
// a host that will silently fall over an hour after bootstrap.
func DisableIdleSleep(ctx context.Context, client *ssh.Client) error {
	script := `set -euo pipefail
sudo pmset -a sleep 0 displaysleep 0 disksleep 0
sudo defaults write /Library/Preferences/com.apple.screensaver idleTime -int 0
sudo defaults write /Library/Preferences/com.apple.screensaver askForPassword -int 0
sudo defaults write /Library/Preferences/.GlobalPreferences com.apple.autologout.AutoLogOutDelay -int 0
`
	return RunCommand(ctx, client, script)
}

// kcpasswordKey is Apple's well-known XOR cipher used to obfuscate
// the auto-login password in /etc/kcpassword. Not security; just
// unicode/locale safety.
var kcpasswordKey = []byte{0x7d, 0x89, 0x52, 0x23, 0xd2, 0xbc, 0xdd, 0xea, 0xa3, 0xb9, 0x1f}

func encodeKCPassword(password string) string {
	src := []byte(password)
	// Pad to next multiple of len(key) with NULs (matches Apple's behavior).
	pad := len(kcpasswordKey) - (len(src) % len(kcpasswordKey))
	for i := 0; i < pad; i++ {
		src = append(src, 0)
	}
	for i := range src {
		src[i] ^= kcpasswordKey[i%len(kcpasswordKey)]
	}
	// base64 for transport via SSH stdin.
	return b64(src)
}

// installTart unpacks the operator-baked `tart.app` tarball into
// /usr/local/lib/tart.app and writes a /usr/local/bin/tart wrapper
// that execs the binary inside the bundle. Idempotent — overwrites on
// every call, which is fine because the operator image pins the
// version and a re-run on an already-bootstrapped host is rare.
//
// Why a wrapper script instead of a symlink: Tart's
// Virtualization.framework entitlements are scoped to the .app
// bundle's signature, so the executable has to be invoked through its
// bundle path. The wrapper hides that path detail from callers
// (tart-kubelet, operators SSHing in to debug) which all want a
// stable `tart` on PATH.
func installTart(ctx context.Context, client *ssh.Client, tarball []byte) error {
	if len(tarball) == 0 {
		return fmt.Errorf("tart tarball is empty")
	}
	script := `set -euo pipefail
sudo mkdir -p /usr/local/lib /usr/local/bin
sudo rm -rf /usr/local/lib/tart.app
sudo tar -xzf - -C /usr/local/lib
sudo tee /usr/local/bin/tart >/dev/null <<'EOF'
#!/bin/sh
exec /usr/local/lib/tart.app/Contents/MacOS/tart "$@"
EOF
sudo chmod 0755 /usr/local/bin/tart
/usr/local/bin/tart --version
`
	return RunCommandWithStdin(ctx, client, script, bytes.NewReader(tarball))
}

// installVMEgressFirewall configures pfctl rules that drop egress
// from the host's vmnet bridge to cluster-private destinations
// (RFC1918 ranges) while allowing public-internet egress. Tart
// VMs attach to vmnet (Apple's bridged-NAT networking for
// Virtualization.framework) and inherit IPs in the 192.168.64.0/22
// range; without these rules the customer-controlled workload
// inside the VM can reach the K8s Pod/Service network, other
// Mac minis on the same cluster's host network, and any RFC1918
// peer the host can route to.
//
// The runner-namespace NetworkPolicy explicitly cannot help here:
// vmnet bridges packets onto the host's L2 before they touch the
// CNI's iptables chains, so Pod-level policies never see VM
// traffic. The packet filter on the host is the only enforcement
// point.
//
// What the rules allow:
//   - vmnet→public internet egress (DNS, GitHub API, package
//     registries) — the only thing the runner actually needs.
//   - vmnet→vmnet local subnet (one-VM-per-host today; this is
//     a no-op but avoids accidental breakage if we ever bin-pack).
//
// What the rules block:
//   - vmnet→10.0.0.0/8 (typical Pod/Service CIDRs, K8s control
//     plane, intra-VPC peers).
//   - vmnet→172.16.0.0/12 (alt Pod CIDR space, some VPNs).
//   - vmnet→169.254.0.0/16 (cloud metadata endpoints — VMs must
//     never reach the host's IMDS, that's a credential leak).
//
// Why 192.168.0.0/16 isn't blocked wholesale: vmnet itself is on
// 192.168.x. Blocking the entire /16 would also drop intra-VM
// traffic and SSH from the operator network if that ever lives
// on 192.168. Since cluster CIDRs in production are 10.x, the
// blocklist is precise rather than maximal.
//
// One optional carve-out punches through the blocklist: when
// cfg.VMKuraEgressCIDR is set, VMs may reach that CIDR (the
// cluster's Service CIDR, advertised to the host over the tailnet
// by the cluster-side subnet router) on the Kura cache port
// (4000, co-hosted HTTP + gRPC),
// plus — when cfg.VMClusterDNSIP is set — the kube-dns
// ClusterIP on 53 so `*.svc.cluster.local` names resolve inside the
// VM. pf is first-match-wins across `quick` rules, so the pass
// lines render BEFORE the block lines. The inputs are validated as
// CIDR/IP literals before being rendered into the root-owned pf
// anchor (they come from operator flags, but a parse gate keeps a
// chart typo from producing an unparseable — or worse, creative —
// ruleset).
//
// The carve-out needs a second half: NAT. vmnet's built-in NAT only
// translates VM egress toward the default-route interface, so
// packets the host forwards into the tailscale utun keep their
// 192.168.64.x source — pf passes them (observed: pass-rule
// counters increment) but Tailscale's source filtering drops
// foreign-source packets and replies can never route back. A pf
// `nat` rule translates VM→cluster traffic to the host's tailnet
// address. Translation rules must land in pf's translation slot,
// which is ordered before all filter rules — appending a
// `nat-anchor` to /etc/pf.conf would violate that order, so the
// rule is loaded into a `com.apple/tuist.vmnat` sub-anchor instead:
// the stock pf.conf's `nat-anchor "com.apple/*"` line evaluates it
// at the right point. The tailscale utun device number can change
// across daemon restarts, so a small re-arm script re-derives the
// interface from the routing table and reloads the rule; a
// StartInterval LaunchDaemon keeps it converged (the rule load is
// idempotent and pfctl swaps anchor contents atomically).
//
// Idempotent: writes the same anchor file on every call. Enables
// pf if not already enabled. The launchd plist re-loads the
// rules on every boot so a reboot doesn't drop the filter.
func installVMEgressFirewall(ctx context.Context, client *ssh.Client, cfg Config) error {
	script, err := renderVMEgressFirewallScript(cfg)
	if err != nil {
		return err
	}
	if err := RunCommand(ctx, client, script); err != nil {
		return err
	}
	if cfg.VMKuraEgressCIDR == "" && cfg.VMCachePNCIDR == "" {
		return nil
	}
	return RunCommand(ctx, client, renderVMNATScript(cfg))
}

// renderVMEgressFirewallScript builds the pf-anchor install script. It
// validates the carve-out CIDRs/IP as IPv4 literals and fails closed on
// a bad value (a chart typo must never produce an unparseable — or
// creative — ruleset), which is why it returns an error. Folded into the
// host config hash so a carve-out values change re-pushes the filter.
func renderVMEgressFirewallScript(cfg Config) (string, error) {
	carveOut := ""
	if cfg.VMKuraEgressCIDR != "" {
		ip, _, err := net.ParseCIDR(cfg.VMKuraEgressCIDR)
		if err != nil || ip.To4() == nil {
			return "", fmt.Errorf("vm kura egress cidr %q is not an IPv4 CIDR: %v", cfg.VMKuraEgressCIDR, err)
		}
		carveOut = fmt.Sprintf(`
# Runner-cache carve-out: VMs may dial the cluster's Kura cache
# Service ClusterIPs (4000, co-hosted HTTP + gRPC) — and, when wired,
# cluster DNS on 53 — through the host's tailnet route. These pass
# rules are evaluated before the block rules below (first 'quick'
# match wins). Per-account isolation is Kura's app-layer JWT tenant
# check, mirroring the Linux runner namespace's NetworkPolicy
# carve-out.
pass out quick proto tcp from <vm_sources> to %s port 4000 keep state
`, cfg.VMKuraEgressCIDR)

		if cfg.VMClusterDNSIP != "" {
			dnsIP := net.ParseIP(cfg.VMClusterDNSIP)
			if dnsIP == nil || dnsIP.To4() == nil {
				return "", fmt.Errorf("vm cluster dns ip %q is not an IPv4 address", cfg.VMClusterDNSIP)
			}
			carveOut += fmt.Sprintf(`pass out quick proto { tcp, udp } from <vm_sources> to %s port 53 keep state
`, cfg.VMClusterDNSIP)
		}
	} else if cfg.VMClusterDNSIP != "" {
		return "", fmt.Errorf("vm cluster dns ip set without vm kura egress cidr; refusing a DNS-only carve-out")
	}

	if cfg.VMCachePNCIDR != "" {
		ip, _, err := net.ParseCIDR(cfg.VMCachePNCIDR)
		if err != nil || ip.To4() == nil {
			return "", fmt.Errorf("vm cache pn cidr %q is not an IPv4 CIDR: %v", cfg.VMCachePNCIDR, err)
		}
		carveOut += fmt.Sprintf(`
# Runner-cache Private Network carve-out: VMs dial per-account Kura
# NodePorts published by the kura node pool on the Scaleway Private
# Network (the endpoint dispatch hands out on node-port regions).
# 30000:32767 is Kubernetes' default NodePort range. The kura-side
# NetworkPolicies admit only this subnet, and Kura's app-layer JWT
# tenant check is the per-account boundary.
pass out quick proto tcp from <vm_sources> to %s port 30000:32767 keep state
`, cfg.VMCachePNCIDR)
	}

	script := `set -euo pipefail

# Idempotent install of the pf anchor file. The anchor namespaces
# our rules under "tuist.runners" so we don't collide with any
# operator-added entries in /etc/pf.conf.
sudo mkdir -p /etc/pf.anchors
sudo tee /etc/pf.anchors/tuist.runners >/dev/null <<'PFCONF'
# Tuist runner VM egress filter.
#
# vmnet places Tart VMs on 192.168.64.0/22 (Apple's documented
# bridged-NAT range). Block customer-workload egress from those
# source IPs to cluster-private destinations; allow everything
# else (public internet is the workload's actual need).
#
# IMPORTANT: rules are evaluated last-match-wins; the explicit
# block lines run AFTER the default pass via the 'quick' keyword.

table <vm_sources> { 192.168.64.0/22 }
table <blocked_dst> { 10.0.0.0/8, 172.16.0.0/12, 169.254.0.0/16 }
@CARVEOUT@
# Drop VM→private destinations at the host edge.
block drop out quick from <vm_sources> to <blocked_dst>

# Belt-and-suspenders: explicitly block the AWS/cloud metadata
# IP even on hosts where the routing table wouldn't normally
# carry it. A static rule survives any future routing changes
# from the cluster operator.
block drop out quick from <vm_sources> to 169.254.169.254
PFCONF

# Manage the anchor block in /etc/pf.conf via begin/end markers.
# Strip-and-append between markers is idempotent and convergent:
# any number of pre-existing marker-delimited blocks (duplicates
# from a stuttering reconcile, partial writes from a prior crashed
# run) get removed before the canonical block is written.
sudo sed -i.bak '/^# BEGIN tuist.runners$/,/^# END tuist.runners$/d' /etc/pf.conf
sudo rm -f /etc/pf.conf.bak
sudo tee -a /etc/pf.conf >/dev/null <<'PFCONFENTRY'
# BEGIN tuist.runners
# Tuist runner VM egress filter — see /etc/pf.anchors/tuist.runners
anchor "tuist.runners"
load anchor "tuist.runners" from "/etc/pf.anchors/tuist.runners"
# END tuist.runners
PFCONFENTRY

# Enable pf (idempotent; -E pins the enable token so an unrelated disable
# can't silently drop the filter), then load the anchor.
#
# Load the tuist.runners anchor DIRECTLY rather than re-running the whole
# /etc/pf.conf. On a live host (pf already enabled), 'pfctl -f /etc/pf.conf'
# collides with macOS's system-managed main ruleset: pfctl warns it would flush
# the system's startup rules and aborts when the embedded 'load anchor'
# re-defines the vm_sources/blocked_dst tables ("cannot define table
# vm_sources: Resource busy"). That aborts the whole firewall install and, on
# the drift-update path, terminal-fails the machine once the retry cap is hit,
# freezing all further host-config updates. An anchor-scoped load applies the
# same rules atomically without touching the system ruleset, so it succeeds at
# bootstrap AND on every reconcile. The 'anchor'/'load anchor' lines written
# into /etc/pf.conf above still re-activate the filter across reboots via the
# pfctl-runners LaunchDaemon's boot-time load, when pf is freshly disabled and
# there is no live ruleset to collide with.
sudo pfctl -E 2>/dev/null || true
sudo pfctl -a tuist.runners -f /etc/pf.anchors/tuist.runners

# launchd job to re-arm pf on every boot. macOS doesn't persist
# the -E enable across reboots in all configurations; an
# explicit RunAtLoad agent makes the filter durable.
sudo tee /Library/LaunchDaemons/dev.tuist.pfctl-runners.plist >/dev/null <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>dev.tuist.pfctl-runners</string>
  <key>ProgramArguments</key>
  <array>
    <string>/sbin/pfctl</string>
    <string>-f</string>
    <string>/etc/pf.conf</string>
    <string>-E</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardErrorPath</key>
  <string>/var/log/tuist-pfctl-runners.log</string>
</dict>
</plist>
PLIST
sudo chown root:wheel /Library/LaunchDaemons/dev.tuist.pfctl-runners.plist
sudo chmod 0644 /Library/LaunchDaemons/dev.tuist.pfctl-runners.plist
sudo launchctl bootout system/dev.tuist.pfctl-runners 2>/dev/null || true
sudo launchctl bootstrap system /Library/LaunchDaemons/dev.tuist.pfctl-runners.plist
`
	script = strings.Replace(script, "@CARVEOUT@", carveOut, 1)
	return script, nil
}

// renderVMNATScript builds the VM->cache NAT helper + its launchd
// supervisor. Only the configured carve-out CIDRs vary; the derived
// interface is resolved at runtime on the host. Folded into the host
// config hash. Callers gate this on at least one of VMKuraEgressCIDR /
// VMCachePNCIDR being set, matching installVMEgressFirewall.
func renderVMNATScript(cfg Config) string {
	return fmt.Sprintf(`set -euo pipefail
sudo tee /usr/local/bin/tuist-pf-vmnat >/dev/null <<'VMNAT'
#!/bin/sh
# Loads the VM->cache NAT rules into the com.apple/tuist.vmnat pf
# sub-anchor (see installVMEgressFirewall in macos-host-bootstrap).
# Three legs, each skipped when unconfigured or its route is absent:
#   - tailnet: VM -> cluster Service CIDR via the tailscale utun.
#     MSS-clamped: the utun MTU (1280) is smaller than the VM's
#     vmnet MTU (1500) and pf-NAT'd flows don't reliably deliver
#     ICMP frag-needed back to the guest, so full-size segments
#     blackhole (tiny /up probes work, bulk cache reads hang).
#     1200 = 1280 - 40 (TCP/IP headers) with margin.
#   - Private Network: VM -> PN subnet via the macOS VLAN
#     interface (installVMCachePNInterface). No clamp: the VLAN
#     runs at the same 1500 MTU as vmnet.
#   - General internet: VM -> public internet via the default-route
#     NIC. vmnet/InternetSharing is *supposed* to own this leg, but on
#     2026-06-26 its en0 NAT silently stopped translating after heavy
#     VM churn — VMs egressed with their 192.168.64.x source, the
#     upstream gateway dropped it, in-VM tailscaled never reached the
#     control plane (SYN_SENT forever), and the release never booted
#     while the pod still showed Ready. We now assert this leg here
#     too, in this proven-enforced anchor, so it survives a churn that
#     clobbers InternetSharing's separate anchor.
# vmnet's built-in NAT only reliably translates toward the
# default-route interface when freshly set up, so all three legs get
# explicit pf NAT here. Idempotent and cheap; re-run on an interval so
# a tailscaled restart (utun renumber), VLAN recreation, or a
# clobbered default-route NAT re-converges within a minute.
CIDR="%s"
PNCIDR="%s"
RULES=""
NL="
"
if [ -n "$CIDR" ]; then
  TSIF=$(route -n get "${CIDR%%%%/*}" 2>/dev/null | awk '/interface/{print $2}')
  case "$TSIF" in
    utun*)
      RULES="${RULES}scrub from 192.168.64.0/22 to $CIDR max-mss 1200${NL}"
      RULES="${RULES}scrub from $CIDR to 192.168.64.0/22 max-mss 1200${NL}"
      RULES="${RULES}nat on $TSIF from 192.168.64.0/22 to $CIDR -> ($TSIF)${NL}"
      ;;
  esac
fi
if [ -n "$PNCIDR" ]; then
  # route-get on the PN network base address ("${PNCIDR%%%%/*}", e.g.
  # 172.16.0.0) resolves to the parent physical NIC (en0), not the macOS VLAN
  # that owns the subnet, so a 'case vlan*' on its output never matched and the
  # NAT was silently skipped — VM traffic then egressed with its 192.168.64.x
  # source, which the kura node can neither reply to nor admit past its
  # NetworkPolicy. Pick the interface directly: the bootstrap creates exactly
  # one PN VLAN (networksetup -createVLAN pn en0), so it is the vlan* device
  # holding an inet address; skip until DHCP lands one (StartInterval re-runs).
  PNIF=""
  for IFACE in $(ifconfig -l 2>/dev/null); do
    case "$IFACE" in
      vlan*)
        if ifconfig "$IFACE" 2>/dev/null | grep -q "inet "; then
          PNIF="$IFACE"
          break
        fi
        ;;
    esac
  done
  if [ -n "$PNIF" ]; then
    RULES="${RULES}nat on $PNIF from 192.168.64.0/22 to $PNCIDR -> ($PNIF)${NL}"
  fi
fi
# General internet leg (see header): NAT VM egress on the default
# route so a VM that lost vmnet's en0 translation still reaches the
# control plane. "to any" on the default NIC only catches
# internet-bound egress — tailnet/PN traffic leaves via utun/vlan and
# is translated by the interface-scoped legs above (pf nat is
# first-match and interface-scoped, so this never shadows them).
DEFIF=$(route -n get default 2>/dev/null | awk '/interface/{print $2}')
if [ -n "$DEFIF" ]; then
  RULES="${RULES}nat on $DEFIF from 192.168.64.0/22 to any -> ($DEFIF)${NL}"
fi
[ -z "$RULES" ] && exit 0
# pf requires normalization (scrub) before translation (nat) within
# a ruleset load; the legs above append in that order.
#
# Short-circuit only when the desired ruleset is unchanged AND the
# anchor still holds rules. Comparing against the snapshot alone would
# never re-converge after an external flush (precisely the failure
# this leg hardens against) — the snapshot would still match while the
# live anchor sat empty.
if printf '%%s' "$RULES" | cmp -s - /usr/local/etc/tuist-vmnat.loaded 2>/dev/null \
   && pfctl -a "com.apple/tuist.vmnat" -s nat 2>/dev/null | grep -q nat; then
  exit 0
fi
printf '%%s' "$RULES" | pfctl -a "com.apple/tuist.vmnat" -f -
mkdir -p /usr/local/etc
printf '%%s' "$RULES" > /usr/local/etc/tuist-vmnat.loaded
VMNAT
sudo chmod 0755 /usr/local/bin/tuist-pf-vmnat
# Force a reload with the freshly-rendered config on install; the
# cache only short-circuits steady-state interval runs.
sudo rm -f /usr/local/etc/tuist-vmnat.loaded
sudo /usr/local/bin/tuist-pf-vmnat

sudo tee /Library/LaunchDaemons/dev.tuist.pfctl-vmnat.plist >/dev/null <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>dev.tuist.pfctl-vmnat</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/tuist-pf-vmnat</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>StartInterval</key>
  <integer>60</integer>
  <key>StandardErrorPath</key>
  <string>/var/log/tuist-pfctl-vmnat.log</string>
</dict>
</plist>
PLIST
sudo chown root:wheel /Library/LaunchDaemons/dev.tuist.pfctl-vmnat.plist
sudo chmod 0644 /Library/LaunchDaemons/dev.tuist.pfctl-vmnat.plist
sudo launchctl bootout system/dev.tuist.pfctl-vmnat 2>/dev/null || true
sudo launchctl bootstrap system /Library/LaunchDaemons/dev.tuist.pfctl-vmnat.plist
`, cfg.VMKuraEgressCIDR, cfg.VMCachePNCIDR)
}

// installVMCachePNInterface materializes the macOS side of the
// server's Scaleway Private Network attachment: a VLAN interface on
// en0 carrying the attachment's VLAN tag, configured for DHCP so
// Scaleway IPAM hands the host its PN address. The VM NAT leg
// (tuist-pf-vmnat) derives the interface from the route this
// creates, and the kura runner-cache NodePort endpoints live behind
// it. Recreates the interface when the tag changed (a re-attachment
// gets a fresh VLAN). No-op unless both the PN CIDR and VLAN are
// configured.
func installVMCachePNInterface(ctx context.Context, client *ssh.Client, cfg Config) error {
	if cfg.VMCachePNCIDR == "" || cfg.VMCachePNVLAN == 0 {
		return nil
	}
	return RunCommand(ctx, client, renderVMCachePNInterfaceScript(cfg))
}

// renderVMCachePNInterfaceScript materializes the per-host VLAN
// interface. VMCachePNVLAN is a per-host Scaleway-assigned value;
// HostConfigHash zeroes it before rendering, so the host config hash
// fingerprints this script's template (a fix here re-pushes to existing
// hosts) without the per-host VLAN making the hash host-specific.
func renderVMCachePNInterfaceScript(cfg Config) string {
	return fmt.Sprintf(`set -euo pipefail
VLAN_TAG=%d
CURRENT_TAG=$(networksetup -listVLANs 2>/dev/null | awk '/^VLAN User Defined Name: pn$/{found=1; next} found && /^Tag: /{print $2; exit} found && /^VLAN User Defined Name: /{exit}')
if [ "${CURRENT_TAG:-}" != "$VLAN_TAG" ]; then
  if [ -n "${CURRENT_TAG:-}" ]; then
    sudo networksetup -deleteVLAN pn en0 "$CURRENT_TAG" || true
    sleep 2
  fi
  sudo networksetup -createVLAN pn en0 "$VLAN_TAG"
  sleep 3
fi
# The VLAN surfaces as a network service whose name varies by macOS
# version ("pn Configuration" on Tahoe). Force DHCP either way.
sudo networksetup -setdhcp "pn Configuration" 2>/dev/null || sudo networksetup -setdhcp pn
`, cfg.VMCachePNVLAN)
}

// installTailscale joins the Mac mini to the cluster's tailnet using
// Tailscale's open-source `tailscaled` variant — the canonical
// headless-server install path per
// https://github.com/tailscale/tailscale/wiki/Tailscaled-on-macOS.
// Three stages, each idempotent:
//
//  1. Write the auth key to a chmod-0600 file on the host via a
//     dedicated SSH session whose script body doesn't reference the
//     key. The key flows via stdin; the install script reads it back
//     with `$(sudo cat …)` so the formatted script (and any error
//     wrapping it) never contains the literal key.
//  2. Extract the operator-baked `tailscale`+`tailscaled` darwin/arm64
//     binaries to /usr/local/bin and call `tailscaled
//     install-system-daemon`, which writes its own
//     /Library/LaunchDaemons/com.tailscale.tailscaled.plist and starts
//     the daemon. Direct equivalent of `systemctl enable --now
//     tailscaled` on Linux. Idempotent on re-runs (we bootout the old
//     job first so new binaries aren't held open).
//  3. `tailscale up` with the per-fleet pre-auth key. Reusable+
//     ephemeral keys mean every Mac mini in the fleet uses the same
//     key and stale node records age out automatically — the right
//     shape for a CAPI-managed fleet where machines come and go.
//
// No-op when TailscaleBinaries or TailscaleAuthKey is empty: the
// chart's per-env values gate the tailnet end-to-end, and a partial
// config shouldn't half-bring-up a node.
func installTailscale(ctx context.Context, client *ssh.Client, cfg Config) error {
	if len(cfg.TailscaleBinaries) == 0 || cfg.TailscaleAuthKey == "" {
		return nil
	}

	// Stage 1: write the auth key. See function-level comment for the
	// security rationale.
	keyScript := `set -euo pipefail
sudo mkdir -p /etc/tuist
sudo tee /etc/tuist/tailscale-auth-key >/dev/null
sudo chmod 0600 /etc/tuist/tailscale-auth-key`
	if err := RunCommandWithStdin(ctx, client, keyScript, strings.NewReader(cfg.TailscaleAuthKey)); err != nil {
		return fmt.Errorf("stage tailscale auth key: %w", err)
	}

	return RunCommandWithStdin(ctx, client, renderTailscaleScript(cfg), bytes.NewReader(cfg.TailscaleBinaries))
}

// renderTailscaleScript builds the stage-2 SSH script (extract binaries,
// register the daemon, `tailscale up`). The auth key never appears in
// the script — it's read on the host from the stage-1 file — so only the
// fleet-wide tags / accept-routes and the per-host hostname vary. Folded
// into the host config hash; the canonical config leaves NodeName empty,
// so the hostname arg drops out and the hash stays host-independent.
func renderTailscaleScript(cfg Config) string {
	tagsArg := ""
	if len(cfg.TailscaleTags) > 0 {
		// Tailscale accepts a comma-separated list — auth-key-bound
		// tags must already be allowed by the tailnet's tagOwners
		// ACL, which lives in infra/tailscale/acls.json.
		tagsArg = fmt.Sprintf(" --advertise-tags=%s", shellQuote(strings.Join(cfg.TailscaleTags, ",")))
	}
	hostnameArg := ""
	if cfg.NodeName != "" {
		hostnameArg = fmt.Sprintf(" --hostname=%s", shellQuote(cfg.NodeName))
	}
	acceptRoutesArg := ""
	if cfg.TailscaleAcceptRoutes {
		// Install subnet routes the cluster-side Connector advertises
		// (the Service CIDR for the runner-cache path). Host routes
		// are VM routes: vmnet NATs VM egress through the host's
		// routing table.
		acceptRoutesArg = " --accept-routes"
	}

	// Stage 2: extract binaries, register daemon, bring up.
	//
	// NB: explicitly NOT using `set -x` here. `set -x` prints commands
	// after variable expansion, which would echo the `$(sudo cat
	// /etc/tuist/tailscale-auth-key)` substitution as the literal key
	// in the trace — and that trace ends up in the SSH stderr buffer
	// that gets wrapped into the controller's error message, which is
	// in turn written to Machine.status.failureMessage (visible via
	// kubectl) and the controller log stream (which ships to Loki).
	// Per-step diagnostics come from explicit log-file capture on the
	// failure branches below.
	return fmt.Sprintf(`set -euo pipefail
# Always remove the auth key file when this script exits — success
# or failure. Set the trap first thing so a later abort still cleans
# up.
trap 'sudo rm -f /etc/tuist/tailscale-auth-key' EXIT

# Stop any running tailscaled before swapping binaries — a running
# daemon holds file handles on the old executable and replacing it
# while loaded is undefined behaviour. bootout is idempotent; the
# job may not be loaded yet on a fresh host.
sudo launchctl bootout system/com.tailscale.tailscaled 2>/dev/null || true

# Extract tailscale + tailscaled into /usr/local/bin. The operator
# image's tarball contains exactly these two files at the top
# level. Same shape as how installTartKubelet ships its binary.
sudo tar -xzf - -C /usr/local/bin tailscale tailscaled
sudo chmod 0755 /usr/local/bin/tailscale /usr/local/bin/tailscaled

# Make sure the state + socket directories exist before launchd
# tries to spawn tailscaled. Without /var/lib/tailscale the daemon
# exits with EX_CONFIG (78) before it can even write to its log.
sudo mkdir -p /var/lib/tailscale /var/run

# Write our own launchd plist instead of calling
# 'tailscaled install-system-daemon'. The subcommand writes a
# minimal plist with just the binary path — no flags, no
# StandardErrorPath — so when tailscaled crashes early there's
# nowhere to read what went wrong (we hit this in staging: the
# subcommand-written plist exited with EX_CONFIG and the diagnostic
# block found no log file). Our plist:
#   - explicit --state / --socket / --port flags so the daemon
#     never has to guess defaults
#   - StandardErrorPath + StandardOutPath aimed at
#     /var/log/tailscaled.log so the diagnostic block can always
#     read crash logs on the next reconcile
#   - KeepAlive=true + ThrottleInterval=10 so launchd restarts the
#     daemon if it dies (same shape as our other launchd plists)
# Direct equivalent of writing a systemd unit on Linux: we own the
# unit, we know what it says, idempotent on bootout+bootstrap.
sudo tee /Library/LaunchDaemons/com.tailscale.tailscaled.plist >/dev/null <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.tailscale.tailscaled</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/tailscaled</string>
    <string>--state=/var/lib/tailscale/tailscaled.state</string>
    <string>--socket=/var/run/tailscaled.socket</string>
    <string>--port=41641</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>/var/log/tailscaled.log</string>
  <key>StandardErrorPath</key><string>/var/log/tailscaled.log</string>
</dict>
</plist>
PLIST
sudo chown root:wheel /Library/LaunchDaemons/com.tailscale.tailscaled.plist
sudo chmod 0644 /Library/LaunchDaemons/com.tailscale.tailscaled.plist
# Reload via bootout+bootstrap so the new plist is picked up.
sudo launchctl bootout system /Library/LaunchDaemons/com.tailscale.tailscaled.plist 2>/dev/null || true
sudo launchctl bootstrap system /Library/LaunchDaemons/com.tailscale.tailscaled.plist

# Wait for tailscaled to accept IPC before sending it 'up'.
# install-system-daemon returns before the daemon finishes
# initializing — without this wait, 'up' would fail immediately
# with "Tailscale is not running" and set -e would abort the
# script. 30s is generous; in practice the daemon is ready in <2s.
DAEMON_READY=false
for i in $(seq 1 30); do
  if sudo /usr/local/bin/tailscale status --self --json >/dev/null 2>&1; then
    DAEMON_READY=true
    break
  fi
  sleep 1
done
if [ "$DAEMON_READY" != true ]; then
  # tailscaled exists at /usr/local/bin/tailscaled and
  # install-system-daemon returned 0 above, but the daemon never
  # came up enough to answer IPC. Dump the launchd job state and
  # the daemon's own log — the most likely failure modes are
  # binary signature / quarantine rejection by macOS, or a runtime
  # error inside tailscaled that crashes it on start.
  echo "tailscaled never accepted IPC within 30s; diagnostics below:" >&2
  echo "--- launchctl list | grep tailscale ---" >&2
  sudo launchctl list 2>&1 | grep -i tailscale >&2 || echo "(no matching jobs)" >&2
  echo "--- launchctl print system/com.tailscale.tailscaled ---" >&2
  sudo launchctl print system/com.tailscale.tailscaled 2>&1 | head -n 40 >&2 || true
  echo "--- tail -n 80 /var/log/tailscaled.log ---" >&2
  sudo tail -n 80 /var/log/tailscaled.log 2>&1 >&2 || echo "(log file unreadable)" >&2
  echo "--- ls -l /usr/local/bin/tailscaled /Library/LaunchDaemons/com.tailscale.tailscaled.plist ---" >&2
  sudo ls -l /usr/local/bin/tailscaled /Library/LaunchDaemons/com.tailscale.tailscaled.plist 2>&1 >&2 || true
  exit 1
fi

# Capture up's combined stdout+stderr so a failure surfaces
# actionable diagnostics. The auth key is expanded by the remote
# shell from the file Stage 1 wrote; the formatted script body
# sent over SSH never contains the literal key.
TS_UP_LOG=$(mktemp)
trap 'sudo rm -f /etc/tuist/tailscale-auth-key "$TS_UP_LOG"' EXIT
if ! sudo /usr/local/bin/tailscale up \
    --authkey="$(sudo cat /etc/tuist/tailscale-auth-key)" \
    --reset \
    --ssh=false%[1]s%[2]s%[3]s >"$TS_UP_LOG" 2>&1; then
  echo "tailscale up failed (output below):" >&2
  sudo cat "$TS_UP_LOG" >&2
  exit 1
fi

# Block until the daemon advertises a tailnet IPv4 — the kubelet
# launchd job that boots next reads 'tailscale ip -4' to populate
# its --node-ip. A 'tailscale up' that returned 0 but hasn't
# announced an IP yet would race the kubelet startup.
for i in $(seq 1 30); do
  if sudo /usr/local/bin/tailscale ip -4 2>/dev/null | grep -qE '^100\.'; then
    exit 0
  fi
  sleep 1
done
echo "tailscale up returned but no tailnet IPv4 within 30s; current status:" >&2
sudo /usr/local/bin/tailscale status >&2 || true
exit 1
`, hostnameArg, tagsArg, acceptRoutesArg)
}

// installNodeExporter drops the cross-compiled darwin/arm64 binary,
// binds it to the tailnet IP on :9100, and supervises it via launchd.
//
// Bind interface (not 0.0.0.0): the public interface on a Scaleway
// Mac mini is internet-reachable, and `:9100` is the kind of port
// scanners actively probe. The launchd plist resolves the tailnet
// IP at job-start time via `tailscale ip -4`, identical to how
// tart-kubelet resolves its NodeIP — same fail mode, same recovery.
//
// No-op when either Tailscale isn't wired (NodeExporterBinary empty
// implies the operator didn't ship one) or the auth key is missing
// (no tailnet to bind to). Either case falls through cleanly.
func installNodeExporter(ctx context.Context, client *ssh.Client, cfg Config) error {
	if len(cfg.NodeExporterBinary) == 0 || cfg.TailscaleAuthKey == "" {
		return nil
	}
	return RunCommandWithStdin(ctx, client, renderNodeExporterScript(), bytes.NewReader(cfg.NodeExporterBinary))
}

// renderNodeExporterScript is the static SSH script that installs the
// node_exporter wrapper + launchd job. The binary rides stdin and its
// drift is tracked by its own SHA in the host config hash, so this
// script carries no per-host or per-binary input.
func renderNodeExporterScript() string {
	return `set -euo pipefail
sudo mkdir -p /usr/local/bin
sudo tee /usr/local/bin/node_exporter >/dev/null
sudo chmod 0755 /usr/local/bin/node_exporter
sudo tee /usr/local/bin/tuist-node-exporter-wrapper >/dev/null <<'WRAPPER'
#!/bin/sh
# Resolve the Mac mini's tailnet IPv4 fresh on every (re)start so
# Tailscale daemon restarts that re-allocate the address still leave
# node_exporter bound somewhere useful. Block briefly for the daemon
# to settle if launchd raced us during boot.
for i in 1 2 3 4 5; do
  TAILSCALE_IP="$(/usr/local/bin/tailscale ip -4 2>/dev/null | head -1)"
  if [ -n "$TAILSCALE_IP" ]; then break; fi
  sleep 2
done
if [ -z "$TAILSCALE_IP" ]; then
  echo "tailscale ip -4 returned empty; node_exporter cannot bind safely" >&2
  exit 1
fi
exec /usr/local/bin/node_exporter \
  --web.listen-address="${TAILSCALE_IP}:9100" \
  --collector.disable-defaults \
  --collector.cpu \
  --collector.diskstats \
  --collector.filesystem \
  --collector.loadavg \
  --collector.meminfo \
  --collector.netdev \
  --collector.os \
  --collector.time \
  --collector.uname
WRAPPER
sudo chmod 0755 /usr/local/bin/tuist-node-exporter-wrapper
sudo tee /Library/LaunchDaemons/dev.tuist.node-exporter.plist >/dev/null <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>dev.tuist.node-exporter</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/tuist-node-exporter-wrapper</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>/var/log/tuist-node-exporter.log</string>
  <key>StandardErrorPath</key><string>/var/log/tuist-node-exporter.log</string>
</dict>
</plist>
PLIST
sudo chown root:wheel /Library/LaunchDaemons/dev.tuist.node-exporter.plist
sudo chmod 0644 /Library/LaunchDaemons/dev.tuist.node-exporter.plist
sudo launchctl bootout system /Library/LaunchDaemons/dev.tuist.node-exporter.plist 2>/dev/null || true
sudo launchctl bootstrap system /Library/LaunchDaemons/dev.tuist.node-exporter.plist
`
}

// === SSH helpers ===========================================================

func RunCommand(ctx context.Context, client *ssh.Client, cmd string) error {
	return RunCommandWithStdin(ctx, client, cmd, nil)
}

// stdin is an io.Reader rather than a string so callers streaming the
// multi-MB bootstrap binaries can pass bytes.NewReader over the
// operator's resident slice — no per-call copy. The reader is read
// once and never mutated, so concurrent reconciles can share the same
// backing slice safely.
func RunCommandWithStdin(ctx context.Context, client *ssh.Client, cmd string, stdin io.Reader) error {
	session, err := client.NewSession()
	if err != nil {
		return err
	}
	defer session.Close()

	if stdin != nil {
		session.Stdin = stdin
	}

	var stderr bytes.Buffer
	session.Stderr = &stderr

	done := make(chan error, 1)
	go func() {
		done <- session.Run(cmd)
	}()
	select {
	case <-ctx.Done():
		_ = session.Signal(ssh.SIGTERM)
		return ctx.Err()
	case err := <-done:
		if err != nil {
			return fmt.Errorf("ssh exec %q: %w (stderr: %s)", cmd, err, stderr.String())
		}
		return nil
	}
}

func b64(b []byte) string {
	return base64.StdEncoding.EncodeToString(b)
}

func sha256Hex(b []byte) string {
	h := sha256.Sum256(b)
	return hex.EncodeToString(h[:])
}
