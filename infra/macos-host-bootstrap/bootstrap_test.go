package bootstrap

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	"errors"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"

	"golang.org/x/crypto/ssh"
)

// renderSSHReachabilityScript must install a minute-interval probe that reloads
// the ssh socket when loopback :22 stops accepting — draining the exhausted
// accept backlog that wedges the operator's SSH management channel.
func TestRenderSSHReachabilityScript(t *testing.T) {
	s := renderSSHReachabilityScript()
	for _, want := range []string{
		// Must create /usr/local/bin before the tee: on the first-boot path this
		// runs before installTart (which otherwise makes the dir), so a fresh
		// host has no /usr/local/bin and the tee would fail the whole bootstrap.
		"mkdir -p /usr/local/bin",
		"nc -z -G 3 127.0.0.1 22",
		"bootout system/com.openssh.sshd",
		"bootstrap system /System/Library/LaunchDaemons/ssh.plist",
		"dev.tuist.ssh-reachability",
		"<key>StartInterval</key>",
		"<key>RunAtLoad</key>",
	} {
		if !strings.Contains(s, want) {
			t.Errorf("renderSSHReachabilityScript missing %q", want)
		}
	}
	// Dead ends from earlier wrong hypotheses: the app firewall was OFF, and
	// UseDNS was already `no` (the drop-in was a no-op). Make sure neither
	// crept back in.
	for _, forbidden := range []string{"socketfilterfw", "systemsetup -setremotelogin", "UseDNS", "sshd_config.d", "pfctl -d"} {
		if strings.Contains(s, forbidden) {
			t.Errorf("renderSSHReachabilityScript should not include the abandoned %q approach", forbidden)
		}
	}
}

// installTailscale must short-circuit on SkipTailscaleInstall before it
// touches the SSH client — the tailnet-fallback caller relies on this so it
// never stops tailscaled over the session that rides it. A nil client proves
// no client method is reached.
func TestInstallTailscale_SkipShortCircuitsBeforeClient(t *testing.T) {
	cfg := Config{
		SkipTailscaleInstall: true,
		TailscaleBinaries:    []byte("nonempty-archive"),
		TailscaleAuthKey:     "tskey-abc",
	}
	if err := installTailscale(context.Background(), nil, cfg); err != nil {
		t.Fatalf("installTailscale with SkipTailscaleInstall = %v, want nil (no client use)", err)
	}
}

// SkipTailscaleInstall is a transport-only flag: it must not perturb the
// fleet-wide HostConfigHash (else a tailnet-fallback update would look like a
// config drift and re-roll the fleet).
func TestSkipTailscaleInstall_DoesNotAffectHostConfigHash(t *testing.T) {
	base := Config{TailscaleBinaries: []byte("archive"), TailscaleAuthKey: "k"}
	skipped := base
	skipped.SkipTailscaleInstall = true
	if HostConfigHash(base) != HostConfigHash(skipped) {
		t.Fatal("SkipTailscaleInstall changed HostConfigHash; it must be transport-only")
	}
}

func TestHostKeyState_PinnedMismatchReturnsTypedError(t *testing.T) {
	_, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	signer, err := ssh.NewSignerFromKey(priv)
	if err != nil {
		t.Fatal(err)
	}
	pub := signer.PublicKey()
	fp := ssh.FingerprintSHA256(pub)

	// TOFU: an empty pin accepts the first key and records it.
	tofu := NewHostKeyState("")
	if err := tofu.Callback()("host", &net.IPAddr{}, pub); err != nil {
		t.Fatalf("TOFU should accept the first key: %v", err)
	}
	if tofu.Observed() != fp {
		t.Fatalf("Observed = %q, want %q", tofu.Observed(), fp)
	}

	// A pin that doesn't match the presented key is rejected with a typed
	// error so the reinstall-on-release controllers can re-TOFU (errors.Is).
	pinned := NewHostKeyState("SHA256:0000000000000000000000000000000000000000000")
	err = pinned.Callback()("host", &net.IPAddr{}, pub)
	if err == nil {
		t.Fatal("expected a host key mismatch error")
	}
	if !errors.Is(err, ErrHostKeyMismatch) {
		t.Fatalf("error %v does not match ErrHostKeyMismatch", err)
	}
}

func TestEncodeKCPasswordPadsToTwelveBytes(t *testing.T) {
	out := encodeKCPassword("hello")
	// encodeKCPassword returns base64 — decode to inspect ciphertext.
	if len(out) == 0 {
		t.Fatalf("expected non-empty output")
	}
}

func TestRenderLaunchdPlist_OmitsNodeLabelsWhenEmpty(t *testing.T) {
	out := renderLaunchdPlist(Config{NodeName: "n1", SSHUser: "m1"})
	if strings.Contains(out, "--node-labels") {
		t.Fatalf("expected --node-labels to be absent when NodeLabels is empty\n%s", out)
	}
}

func TestRenderLaunchdPlist_OmitsProviderIDWhenEmpty(t *testing.T) {
	out := renderLaunchdPlist(Config{NodeName: "n1", SSHUser: "m1"})
	if strings.Contains(out, "--provider-id") {
		t.Fatalf("expected --provider-id to be absent when ProviderID is empty\n%s", out)
	}
}

func TestRenderLaunchdPlist_RendersProviderID(t *testing.T) {
	out := renderLaunchdPlist(Config{
		NodeName:   "n1",
		SSHUser:    "m1",
		ProviderID: "scw-applesilicon://fr-par-1/abc-123",
	})
	if !strings.Contains(out, "<string>--provider-id=scw-applesilicon://fr-par-1/abc-123</string>") {
		t.Fatalf("expected --provider-id flag in plist\n%s", out)
	}
}

func TestRenderLaunchdPlist_RendersVNCRelayAddress(t *testing.T) {
	out := renderLaunchdPlist(Config{
		NodeName:     "n1",
		SSHUser:      "m1",
		VNCRelayHost: "macmini-1.tailscale-operator.svc.cluster.local",
		VNCRelayPort: 5900,
	})
	if !strings.Contains(out, "<string>--vnc-relay-host=macmini-1.tailscale-operator.svc.cluster.local</string>") {
		t.Fatalf("expected --vnc-relay-host flag in plist\n%s", out)
	}
	if !strings.Contains(out, "<string>--vnc-relay-port=5900</string>") {
		t.Fatalf("expected --vnc-relay-port flag in plist\n%s", out)
	}
}

func TestRenderLaunchdPlist_RendersFleetLabel(t *testing.T) {
	out := renderLaunchdPlist(Config{
		NodeName:   "n1",
		SSHUser:    "m1",
		NodeLabels: map[string]string{"tuist.dev/fleet": "tuist-runners"},
	})
	if !strings.Contains(out, "--node-labels=tuist.dev/fleet=tuist-runners") {
		t.Fatalf("expected --node-labels=tuist.dev/fleet=tuist-runners in plist\n%s", out)
	}
}

func TestRenderLaunchdPlist_RendersMultipleLabelsSorted(t *testing.T) {
	out := renderLaunchdPlist(Config{
		NodeName: "n1",
		SSHUser:  "m1",
		NodeLabels: map[string]string{
			"tuist.dev/fleet":         "tuist-runners",
			"tuist.dev/instance-type": "large",
		},
	})
	// Sorted alphabetically — deterministic plist rendering keeps the
	// host fingerprint stable across reconciles.
	want := "--node-labels=tuist.dev/fleet=tuist-runners,tuist.dev/instance-type=large"
	if !strings.Contains(out, want) {
		t.Fatalf("expected %q in plist\n%s", want, out)
	}
}

func TestRenderLaunchdPlist_OmitsDisableVMGCForPureNode(t *testing.T) {
	out := renderLaunchdPlist(Config{NodeName: "n1", SSHUser: "m1"})
	if strings.Contains(out, "--disable-vm-gc") {
		t.Fatalf("expected --disable-vm-gc to be absent on a pure Node (no GHActionsRunner)\n%s", out)
	}
}

func TestRenderLaunchdPlist_RendersDisableVMGCForBuilder(t *testing.T) {
	out := renderLaunchdPlist(Config{
		NodeName:        "n1",
		SSHUser:         "m1",
		GHActionsRunner: &GHActionsRunnerConfig{},
	})
	if !strings.Contains(out, "<string>--disable-vm-gc</string>") {
		t.Fatalf("expected --disable-vm-gc in plist for a builder host\n%s", out)
	}
}

// The drift-update path re-renders the plist without re-resolving
// GHActionsRunner, so it sets DisableVMGC directly. Without honoring it
// here, a binary roll would strip --disable-vm-gc from a builder and the
// orphan-VM GC would reap the in-flight image-bake VM mid-`tart push`.
func TestRenderLaunchdPlist_RendersDisableVMGCWhenSet(t *testing.T) {
	out := renderLaunchdPlist(Config{
		NodeName:    "n1",
		SSHUser:     "m1",
		DisableVMGC: true,
	})
	if !strings.Contains(out, "<string>--disable-vm-gc</string>") {
		t.Fatalf("expected --disable-vm-gc in plist when DisableVMGC is set\n%s", out)
	}
}

func TestRenderLaunchdPlist_OmitsRunnerCacheWhenDisabled(t *testing.T) {
	out := renderLaunchdPlist(Config{NodeName: "n1", SSHUser: "m1"})
	if strings.Contains(out, "--runner-cache-root") {
		t.Fatalf("expected --runner-cache-root absent when RunnerCacheVolumeGiB is 0\n%s", out)
	}
}

func TestRenderLaunchdPlist_RendersRunnerCacheRoot(t *testing.T) {
	out := renderLaunchdPlist(Config{
		NodeName:                "n1",
		SSHUser:                 "m1",
		RunnerCacheVolumeGiB:    400,
		CacheVolumeMasterCapGiB: 25,
		CacheVolumeCASGiB:       8,
	})
	if !strings.Contains(out, "<string>--runner-cache-root="+runnerCacheMountPoint+"</string>") {
		t.Fatalf("expected --runner-cache-root in plist\n%s", out)
	}
	if !strings.Contains(out, "<string>--cache-volume-cap-gib=25</string>") {
		t.Fatalf("expected --cache-volume-cap-gib in plist\n%s", out)
	}
	if !strings.Contains(out, "<string>--cache-volume-cas-gib=8</string>") {
		t.Fatalf("expected --cache-volume-cas-gib in plist\n%s", out)
	}
}

func TestRenderLaunchdPlist_OmitsCapGiBWhenDefault(t *testing.T) {
	out := renderLaunchdPlist(Config{NodeName: "n1", SSHUser: "m1", RunnerCacheVolumeGiB: 400})
	if !strings.Contains(out, "--runner-cache-root=") {
		t.Fatalf("expected --runner-cache-root when volume enabled\n%s", out)
	}
	if strings.Contains(out, "--cache-volume-cap-gib") {
		t.Fatalf("expected --cache-volume-cap-gib omitted when cap is 0 (tart-kubelet default)\n%s", out)
	}
	if strings.Contains(out, "--cache-volume-cas-gib") {
		t.Fatalf("expected --cache-volume-cas-gib omitted when CAS budget is 0 (compilation cache VM-local)\n%s", out)
	}
}

func TestRenderRunnerCacheVolumeScript_CarriesQuotaAndVolume(t *testing.T) {
	out := renderRunnerCacheVolumeScript(Config{RunnerCacheVolumeGiB: 400})
	if !strings.Contains(out, "VOL="+runnerCacheVolumeName) {
		t.Fatalf("expected volume name in script\n%s", out)
	}
	if !strings.Contains(out, "QUOTA_GIB=400") {
		t.Fatalf("expected quota GiB in script\n%s", out)
	}
	if !strings.Contains(out, `-quota "${QUOTA_GIB}GiB"`) {
		t.Fatalf("expected -quota flag in script\n%s", out)
	}
}

func TestHostConfigHash_ChangesWithRunnerCacheVolume(t *testing.T) {
	base := Config{NodeName: "n1", SSHUser: "m1", TartKubeletBinary: []byte("bin")}
	changed := base
	changed.RunnerCacheVolumeGiB = 400
	if HostConfigHash(base) == HostConfigHash(changed) {
		t.Fatalf("HostConfigHash must change when the runner-cache volume is enabled")
	}
}

// The CAS budget must be part of the fleet fingerprint: if it were omitted, a
// roll that enables the compilation cache would leave the canonical hash
// unchanged, so hosts would look already-applied and never re-push the launchd
// config that turns the CAS on.
func TestHostConfigHash_ChangesWithCASGiB(t *testing.T) {
	base := Config{NodeName: "n1", SSHUser: "m1", TartKubeletBinary: []byte("bin"), RunnerCacheVolumeGiB: 400}
	changed := base
	changed.CacheVolumeCASGiB = 8
	if HostConfigHash(base) == HostConfigHash(changed) {
		t.Fatalf("HostConfigHash must change when the CAS budget is set")
	}
}

func TestRenderTartKubeletLaunchdScript_PreparesVNCControlDir(t *testing.T) {
	out := renderTartKubeletLaunchdScript(Config{SSHUser: "m1"})
	if !strings.Contains(out, "/var/lib/tart-vnc-control") {
		t.Fatalf("expected VNC control directory to be prepared\n%s", out)
	}
	if !strings.Contains(out, "sudo chown -R 'm1':staff") {
		t.Fatalf("expected VNC control directory ownership to follow SSH user\n%s", out)
	}
}

// HostKeyState is the SSH-side TOFU primitive. The first observation
// of a host key on a fresh state is captured; later observations
// against a state seeded with KnownHostFingerprint must match.

func newTestPubKey(t *testing.T) ssh.PublicKey {
	t.Helper()
	pub, _, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate ed25519: %v", err)
	}
	pk, err := ssh.NewPublicKey(pub)
	if err != nil {
		t.Fatalf("ssh public key: %v", err)
	}
	return pk
}

func TestHostConfigHash_StableForSameConfig(t *testing.T) {
	cfg := Config{
		TartKubeletBinary:  []byte("kubelet-v1"),
		TailscaleBinaries:  []byte("ts-v1"),
		NodeExporterBinary: []byte("ne-v1"),
		TailscaleAuthKey:   "auth-key",
		TailscaleTags:      []string{"tag:tuist-macmini"},
		VMKuraEgressCIDR:   "10.96.0.0/12",
		VMCachePNCIDR:      "172.16.0.0/22",
		HostCPU:            8,
		HostMemoryMB:       16384,
		MaxPods:            3,
	}
	if HostConfigHash(cfg) != HostConfigHash(cfg) {
		t.Fatalf("HostConfigHash must be stable for the same config")
	}
}

func TestHostConfigHash_IndependentOfPerHostFields(t *testing.T) {
	base := Config{
		TartKubeletBinary: []byte("kubelet-v1"),
		VMKuraEgressCIDR:  "10.96.0.0/12",
	}
	perHost := base
	// Per-host fields must not move the canonical hash, or every host in
	// a fleet would falsely drift.
	perHost.NodeName = "macmini-7"
	perHost.IP = "51.15.1.2"
	perHost.Kubeconfig = "kubeconfig-yaml"
	perHost.ProviderID = "scw-applesilicon://fr-par-1/abc"
	perHost.VNCRelayHost = "macmini-1.tailscale-operator.svc.cluster.local"
	perHost.VMCachePNVLAN = 4242
	perHost.KnownHostFingerprint = "SHA256:zzz"
	perHost.DisableVMGC = true
	if HostConfigHash(base) != HostConfigHash(perHost) {
		t.Fatalf("HostConfigHash must ignore per-host fields")
	}
}

func TestHostConfigHash_ChangesWhenFleetConfigChanges(t *testing.T) {
	base := Config{
		TartKubeletBinary: []byte("kubelet-v1"),
		VMKuraEgressCIDR:  "10.96.0.0/12",
	}
	changed := base
	changed.VMCachePNCIDR = "172.16.0.0/22"
	if HostConfigHash(base) == HostConfigHash(changed) {
		t.Fatalf("HostConfigHash must change when a fleet-config field changes")
	}

	tags := base
	tags.TailscaleTags = []string{"tag:tuist-macmini-staging"}
	if HostConfigHash(base) == HostConfigHash(tags) {
		t.Fatalf("HostConfigHash must change when TailscaleTags change")
	}

	routes := base
	routes.TailscaleAcceptRoutes = true
	if HostConfigHash(base) == HostConfigHash(routes) {
		t.Fatalf("HostConfigHash must change when TailscaleAcceptRoutes changes")
	}

	vncPort := base
	vncPort.VNCRelayPort = 5900
	if HostConfigHash(base) == HostConfigHash(vncPort) {
		t.Fatalf("HostConfigHash must change when VNCRelayPort changes")
	}
}

func TestHostConfigHash_ChangesWhenBinaryChanges(t *testing.T) {
	base := Config{TartKubeletBinary: []byte("kubelet-v1")}
	changed := Config{TartKubeletBinary: []byte("kubelet-v2")}
	if HostConfigHash(base) == HostConfigHash(changed) {
		t.Fatalf("HostConfigHash must change when the tart-kubelet binary changes")
	}

	ne := base
	ne.NodeExporterBinary = []byte("ne-v1")
	if HostConfigHash(base) == HostConfigHash(ne) {
		t.Fatalf("HostConfigHash must change when the node_exporter binary changes")
	}
}

func TestHostKeyState_TOFUCapturesFingerprint(t *testing.T) {
	hk := NewHostKeyState("")
	pk := newTestPubKey(t)
	cb := hk.Callback()
	if err := cb("host:22", &net.TCPAddr{}, pk); err != nil {
		t.Fatalf("first observation should accept any key: %v", err)
	}
	if hk.Observed() != ssh.FingerprintSHA256(pk) {
		t.Fatalf("expected captured fingerprint to equal observed key, got %q", hk.Observed())
	}
}

func TestHostKeyState_VerifyAcceptsMatchingFingerprint(t *testing.T) {
	pk := newTestPubKey(t)
	hk := NewHostKeyState(ssh.FingerprintSHA256(pk))
	cb := hk.Callback()
	if err := cb("host:22", &net.TCPAddr{}, pk); err != nil {
		t.Fatalf("matching fingerprint should accept: %v", err)
	}
}

func TestHostKeyState_VerifyRejectsMismatchedFingerprint(t *testing.T) {
	hk := NewHostKeyState(ssh.FingerprintSHA256(newTestPubKey(t)))
	cb := hk.Callback()
	if err := cb("host:22", &net.TCPAddr{}, newTestPubKey(t)); err == nil {
		t.Fatalf("mismatched fingerprint should error")
	}
}

func TestHostKeyState_DetectsMidBootstrapKeyRotation(t *testing.T) {
	hk := NewHostKeyState("")
	cb := hk.Callback()
	first := newTestPubKey(t)
	if err := cb("host:22", &net.TCPAddr{}, first); err != nil {
		t.Fatalf("first observation: %v", err)
	}
	// A second dial in the same HostKeyState (e.g. dial after the
	// waitForSSH probe) presenting a different key would mean the
	// host's identity changed between the probe and the real dial.
	// Refuse rather than re-TOFU.
	if err := cb("host:22", &net.TCPAddr{}, newTestPubKey(t)); err == nil {
		t.Fatalf("mid-bootstrap key rotation should error")
	}
}

func TestRenderVMNATScript_AssertsDefaultRouteNATLeg(t *testing.T) {
	out := renderVMNATScript(Config{
		VMKuraEgressCIDR: "10.96.0.0/12",
		VMCachePNCIDR:    "172.16.0.0/22",
	})
	// The general-internet leg must NAT VM egress on the default-route
	// NIC from this anchor, not rely on vmnet/InternetSharing — the
	// 2026-06-26 outage was VMs egressing un-NAT'd (private
	// 192.168.64.x source) after InternetSharing's separate en0 NAT
	// anchor was clobbered, so tailscaled could never reach control.
	if !strings.Contains(out, "route -n get default") {
		t.Fatalf("expected default-route interface discovery\n%s", out)
	}
	if !strings.Contains(out, "nat on $DEFIF from 192.168.64.0/22 to $DEFDST -> ($DEFIF)") {
		t.Fatalf("expected general-internet NAT leg on the default route\n%s", out)
	}
	// ...but the PN must be carved out of its destination, so cache traffic is
	// never masqueraded to the host's public address while the PN route is
	// briefly absent (that source is outside the kura NetworkPolicy's
	// 172.16.0.0/22 ipBlock and gets dropped at ingress with no RST).
	if !strings.Contains(out, `DEFDST="any"`) ||
		!strings.Contains(out, `[ -n "$PNCIDR" ] && DEFDST="! $PNCIDR"`) {
		t.Fatalf("expected the general-internet leg to exclude the PN CIDR\n%s", out)
	}
	// The idempotency short-circuit must re-converge after an external
	// anchor flush: skipping the reload purely on a snapshot match would
	// leave a flushed anchor empty forever (the snapshot still matches).
	if !strings.Contains(out, `pfctl -a "com.apple/tuist.vmnat" -s nat`) {
		t.Fatalf("expected short-circuit to verify the live anchor still holds rules\n%s", out)
	}
}

// renderSSHIngressGuardScript must drop inbound :22 from everything except the
// tailnet, loopback and the configured allow list. The flood that wedges a
// runner arrives on the public interface from scanner ranges, and because
// launchd binds the ssh socket to *:22 an exhausted backlog takes the tailnet
// path down with it, so filtering the SYNs is what keeps the operator's
// management channel alive.
func TestRenderSSHIngressGuardScript(t *testing.T) {
	s, err := renderSSHIngressGuardScript(Config{SSHIngressAllowCIDRs: []string{"203.0.113.7/32"}})
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	for _, want := range []string{
		// The tailnet is the unconditional escape hatch: a wrong allow list must
		// still leave the drift loop a way back in over the fallback path.
		"100.64.0.0/10",
		"203.0.113.7/32",
		// The reachability watchdog probes 127.0.0.1:22 every minute; blocking
		// loopback would read to it as a permanent wedge.
		"pass in quick on lo0 proto tcp to any port 22",
		"block drop in quick proto tcp to any port 22",
		// Must load under com.apple/, which the stock pf.conf already attaches
		// to the live ruleset. See the no-pf.conf assertion below.
		`pfctl -a "com.apple/tuist.sshguard" -f /etc/pf.anchors/tuist.sshguard`,
		// Re-arm on boot and on an interval, so the rules survive a reboot or
		// an external ruleset flush without another SSH round trip.
		"dev.tuist.pfctl-sshguard",
		"<key>RunAtLoad</key>",
		"<key>StartInterval</key>",
	} {
		if !strings.Contains(s, want) {
			t.Errorf("renderSSHIngressGuardScript missing %q", want)
		}
	}
	// The guard MUST NOT rely on a top-level anchor appended to /etc/pf.conf.
	// That file is only read on a full ruleset load, which happens at boot, so
	// on a live host `pfctl -a` would populate an anchor nothing evaluates
	// while the drift update stamped HostConfigHash as converged: the guard
	// would report shipped and silently filter nothing until a reboot.
	if strings.Contains(s, "/etc/pf.conf") {
		t.Error("guard touches /etc/pf.conf; a top-level anchor is not live until the next full load, so the rules would be inert on a running host")
	}
	// pf is first-match-wins across `quick` rules, so a block that renders above
	// the passes would drop every management connection including our own.
	if strings.Index(s, "block drop in quick proto tcp to any port 22") <
		strings.Index(s, "pass in quick proto tcp from <ssh_allowed> to any port 22") {
		t.Error("block rule renders before the pass rules; pf is first-match-wins on quick")
	}
}

// A malformed allow CIDR must fail closed rather than render a creative
// ruleset onto a host we can only reach through the port it governs.
func TestRenderSSHIngressGuardScript_RejectsBadCIDR(t *testing.T) {
	for _, bad := range []string{"not-a-cidr", "203.0.113.7", "2001:db8::/32"} {
		if _, err := renderSSHIngressGuardScript(Config{SSHIngressAllowCIDRs: []string{bad}}); err == nil {
			t.Errorf("renderSSHIngressGuardScript accepted %q; must fail closed", bad)
		}
	}
}

// The guard needs a second path to be safe: without a tailnet, an allow list
// that turns out to be wrong strands the host behind VNC with no way back.
func TestInstallSSHIngressGuard_SkipsWithoutTailnet(t *testing.T) {
	if err := installSSHIngressGuard(context.Background(), nil, Config{}); err != nil {
		t.Fatalf("expected a no-op without a tailscale auth key, got %v", err)
	}
}

// The allow list is fleet config, not per-host state, so a policy change has to
// move the hash or it would never roll to already-bootstrapped minis.
func TestHostConfigHash_ChangesWithSSHIngressAllowCIDRs(t *testing.T) {
	base := Config{}
	changed := Config{SSHIngressAllowCIDRs: []string{"203.0.113.7/32"}}
	if HostConfigHash(base) == HostConfigHash(changed) {
		t.Fatal("HostConfigHash must change when the ssh ingress allow list changes")
	}
}

// The PN NAT leg must be emitted as soon as the VLAN device exists, not only
// once DHCP has given it an address. Gating on the address left a window in
// which the ruleset carried no PN leg at all; a VM booting into that window ran
// its whole job un-NAT'd and every cache request hung, because once the address
// (and route) arrived its packets reached the kura node with a 192.168.64.x
// source that the per-instance NetworkPolicy denies at ingress.
func TestRenderVMNATScript_PNLegKeysOnDeviceExistenceNotAddress(t *testing.T) {
	out := renderVMNATScript(Config{VMCachePNCIDR: "172.16.0.0/22"})

	// An addressed VLAN still wins when several exist, so a leftover device
	// from a re-attachment cannot shadow the live one...
	if !strings.Contains(out, `if ifconfig "$IFACE" 2>/dev/null | grep -q "inet "; then`) {
		t.Fatalf("expected an addressed vlan to be preferred\n%s", out)
	}
	// ...but an unaddressed one is still recorded rather than skipped.
	if !strings.Contains(out, `[ -n "$PNIF" ] || PNIF="$IFACE"`) {
		t.Fatalf("expected an unaddressed vlan to be used as a fallback\n%s", out)
	}
	// pf re-resolves a parenthesised interface, so the rule is correct even
	// when emitted before the address lands.
	if !strings.Contains(out, "nat on $PNIF from 192.168.64.0/22 to $PNCIDR -> ($PNIF)") {
		t.Fatalf("expected a dynamic-interface PN NAT leg\n%s", out)
	}
	// A host with no PN VLAN at all cannot translate cache traffic; that must
	// reach the daemon log instead of degrading silently.
	if !strings.Contains(out, "no vlan* interface for PN") {
		t.Fatalf("expected a missing PN interface to be logged\n%s", out)
	}
}

// The helper the LaunchDaemon runs every 60s is written as a heredoc, so a
// syntax error in it is invisible until pf silently holds no rules on a live
// host — which reads exactly like the outage this leg exists to prevent.
func TestRenderVMNATScript_HelperIsValidSh(t *testing.T) {
	out := renderVMNATScript(Config{
		VMKuraEgressCIDR: "10.96.0.0/12",
		VMCachePNCIDR:    "172.16.0.0/22",
	})
	const open = "<<'VMNAT'\n"
	start := strings.Index(out, open)
	if start < 0 {
		t.Fatalf("no VMNAT heredoc in rendered script\n%s", out)
	}
	body := out[start+len(open):]
	end := strings.Index(body, "\nVMNAT\n")
	if end < 0 {
		t.Fatalf("unterminated VMNAT heredoc\n%s", out)
	}
	body = body[:end]

	script := filepath.Join(t.TempDir(), "tuist-pf-vmnat")
	if err := os.WriteFile(script, []byte(body), 0o600); err != nil {
		t.Fatalf("write helper: %v", err)
	}
	if combined, err := exec.Command("sh", "-n", script).CombinedOutput(); err != nil {
		t.Fatalf("helper is not valid sh: %v\n%s\n---\n%s", err, combined, body)
	}
}

// The guard is delivered as nested heredocs, so a syntax error in it is
// invisible until pf holds no rules on a live host, which reads exactly like
// the wedge the guard exists to prevent.
func TestRenderSSHIngressGuardScript_IsValidSh(t *testing.T) {
	s, err := renderSSHIngressGuardScript(Config{SSHIngressAllowCIDRs: []string{"203.0.113.7/32"}})
	if err != nil {
		t.Fatalf("render: %v", err)
	}
	script := filepath.Join(t.TempDir(), "tuist-ssh-ingress-guard")
	if err := os.WriteFile(script, []byte(s), 0o600); err != nil {
		t.Fatalf("write script: %v", err)
	}
	if combined, err := exec.Command("sh", "-n", script).CombinedOutput(); err != nil {
		t.Fatalf("guard script is not valid sh: %v\n%s", err, combined)
	}
}
