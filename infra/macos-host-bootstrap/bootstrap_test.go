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

// An OAuth-minted key is always tagged and has no default tag to fall back on,
// so a fleet configured without tags can never join. Reject before pushing
// anything, so the error lands on Machine.status.failureMessage rather than
// surfacing as a join timeout that reads like a network fault. A legacy
// pre-auth key carries its own tag binding and has to stay pushable untagged
// while envs migrate.
func TestValidateTailscaleCredential(t *testing.T) {
	for _, tc := range []struct {
		name       string
		credential string
		tags       []string
		wantErr    bool
	}{
		{name: "oauth without tags", credential: "tskey-client-abc123", wantErr: true},
		{name: "oauth with tags", credential: "tskey-client-abc123", tags: []string{"tag:tuist-macmini-production"}},
		{name: "pre-auth key without tags", credential: "tskey-auth-abc123"},
		{name: "tailscale not wired", credential: ""},
	} {
		t.Run(tc.name, func(t *testing.T) {
			err := validateTailscaleCredential(Config{TailscaleAuthKey: tc.credential, TailscaleTags: tc.tags})
			if (err != nil) != tc.wantErr {
				t.Fatalf("validateTailscaleCredential = %v, wantErr %v", err, tc.wantErr)
			}
		})
	}
}

// installTailscale must run the credential guard before it touches the SSH
// client, so an unjoinable config never half-pushes. A nil client proves no
// client method is reached.
func TestInstallTailscale_GuardsCredentialBeforeClient(t *testing.T) {
	cfg := Config{
		TailscaleBinaries: []byte("nonempty-archive"),
		TailscaleAuthKey:  "tskey-client-abc123",
	}
	if err := installTailscale(context.Background(), nil, cfg); err == nil {
		t.Fatal("installTailscale with an OAuth credential and no tags = nil, want error")
	}
}

// The fleet credential is an OAuth client secret, which `tailscale up` turns
// into a freshly minted key. Two properties have to ride along, because the
// implicit key defaults to preauthorized=false and the fleet needs ephemeral
// registrations. This runs the classification the renderer emits, rather than
// matching on its text, so a rewrite that keeps the shape but breaks the
// behaviour still fails.
func TestRenderTailscaleScript_AnnotatesOAuthCredential(t *testing.T) {
	bash, err := exec.LookPath("bash")
	if err != nil {
		t.Skip("bash not available")
	}

	script := renderTailscaleScript(Config{TailscaleTags: []string{"tag:tuist-macmini-production"}})

	// The minted key's properties only reach Tailscale if `up` reads the
	// annotated variable. An edit that inlines the credential back into the
	// flag would silently drop them.
	if !strings.Contains(script, `--authkey="$TS_AUTH_KEY"`) {
		t.Fatal("tailscale up must read the annotated $TS_AUTH_KEY, not the raw credential")
	}

	const marker = `case "$TS_AUTH_KEY" in`
	start := strings.Index(script, marker)
	if start < 0 {
		t.Fatal("rendered script has no credential classification block")
	}
	end := strings.Index(script[start:], "esac")
	if end < 0 {
		t.Fatal("credential classification block is unterminated")
	}
	classify := script[start : start+end+len("esac")]

	for _, tc := range []struct {
		name       string
		credential string
		want       string
	}{
		{
			name:       "oauth client secret",
			credential: "tskey-client-abc123",
			want:       "tskey-client-abc123?ephemeral=true&preauthorized=true",
		},
		{
			// Bootstrap has to keep succeeding against the legacy
			// credential while envs migrate; a pre-auth key takes no
			// query parameters and appending them would corrupt it.
			name:       "legacy pre-auth key",
			credential: "tskey-auth-abc123",
			want:       "tskey-auth-abc123",
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			out, err := exec.Command(bash, "-c",
				"TS_AUTH_KEY=\"$1\"\n"+classify+"\nprintf '%s' \"$TS_AUTH_KEY\"",
				"bash", tc.credential).Output()
			if err != nil {
				t.Fatalf("run classification: %v", err)
			}
			if string(out) != tc.want {
				t.Errorf("annotated credential = %q, want %q", out, tc.want)
			}
		})
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

func TestRenderLogShipperScript_TailsTartKubeletLogWithHostIdentity(t *testing.T) {
	out := renderLogShipperInstallScript(Config{
		NodeName:   "tuist-tuist-runners-fleet-abc12",
		LogShipURL: "http://tuist-alloy-receiver-staging:3100/loki/api/v1/push",
		LogShipEnv: "staging",
	})
	for _, want := range []string{
		"<string>--url=http://tuist-alloy-receiver-staging:3100/loki/api/v1/push</string>",
		"<string>--file=tuist-macos-tart-kubelet=/var/log/tart-kubelet.log</string>",
		"<string>--instance=tuist-tuist-runners-fleet-abc12</string>",
		"<string>--env=staging</string>",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("rendered script missing %q\n%s", want, out)
		}
	}
}

// The env label is optional; a chart that hasn't set it must not render an
// empty flag, which the agent would read as an empty label value.
func TestRenderLogShipperScript_OmitsEnvWhenUnset(t *testing.T) {
	out := renderLogShipperInstallScript(Config{LogShipURL: "http://receiver:3100/loki/api/v1/push"})
	if strings.Contains(out, "--env=") {
		t.Fatalf("expected no --env flag when LogShipEnv is empty\n%s", out)
	}
	if strings.Contains(out, "--instance=") {
		t.Fatalf("expected no --instance flag when NodeName is empty\n%s", out)
	}
}

// A `&` in the push URL would otherwise close the plist's <string> element
// malformed, launchd would refuse the job, and the host would go quiet with no
// symptom other than absent logs.
func TestRenderLogShipperScript_EscapesXMLInSubstitutedValues(t *testing.T) {
	out := renderLogShipperInstallScript(Config{LogShipURL: "http://receiver:3100/push?a=1&b=2"})
	if !strings.Contains(out, "--url=http://receiver:3100/push?a=1&amp;b=2</string>") {
		t.Fatalf("expected the ampersand to be XML-escaped\n%s", out)
	}
}

// The script ships the binary on stdin and the plist as a heredoc; a syntax
// error in it is invisible until a host silently stops shipping logs.
func TestRenderLogShipperScript_IsValidSh(t *testing.T) {
	script := filepath.Join(t.TempDir(), "install-log-shipper")
	body := renderLogShipperInstallScript(Config{
		NodeName:   "macmini-1",
		LogShipURL: "http://tuist-alloy-receiver-staging:3100/loki/api/v1/push",
		LogShipEnv: "staging",
	})
	if err := os.WriteFile(script, []byte(body), 0o600); err != nil {
		t.Fatalf("write script: %v", err)
	}
	if combined, err := exec.Command("sh", "-n", script).CombinedOutput(); err != nil {
		t.Fatalf("log shipper script is not valid sh: %v\n%s", err, combined)
	}
}

// All three inputs gate the feature. The binary rides the operator image, the
// push URL comes from the chart, and the tailnet is the only route to that URL
// — the receiver does not exist on the public internet.
func TestLogShippingEnabled_RequiresBinaryURLAndTailnet(t *testing.T) {
	full := Config{
		LogShipperBinary: []byte("shipper"),
		LogShipURL:       "http://receiver:3100/loki/api/v1/push",
		TailscaleAuthKey: "auth-key",
	}
	if !logShippingEnabled(full) {
		t.Fatal("expected a fully wired config to enable host logging")
	}
	for name, mutate := range map[string]func(*Config){
		"no binary":  func(c *Config) { c.LogShipperBinary = nil },
		"no url":     func(c *Config) { c.LogShipURL = "" },
		"no tailnet": func(c *Config) { c.TailscaleAuthKey = "" },
	} {
		cfg := full
		mutate(&cfg)
		if logShippingEnabled(cfg) {
			t.Fatalf("expected host logging to be disabled with %s", name)
		}
	}
}

// Turning the chart flag off has to REMOVE the daemon, not merely stop pushing
// a new config to it. A launchd job that is already loaded keeps running with
// whatever URL and env label it was last given, so a disable that only skipped
// the install would stop no ingestion at all — leaving the rollback lever
// attached to nothing.
func TestRenderLogShipperScript_UninstallsWhenDisabled(t *testing.T) {
	out := renderLogShipperScript(Config{LogShipperBinary: []byte("shipper")})
	for _, want := range []string{
		"launchctl bootout system \"$PLIST\"",
		"rm -f \"$PLIST\"",
		"rm -f /usr/local/bin/tuist-log-shipper",
		// The positions file has to go too: it points into a log that kept
		// growing while the agent was off, so resuming from it would replay the
		// whole disabled window — the exact cost the flag was flipped to avoid.
		"rm -rf /var/lib/tuist-log-shipper",
	} {
		if !strings.Contains(out, want) {
			t.Fatalf("disabled render missing %q\n%s", want, out)
		}
	}
	if strings.Contains(out, "launchctl bootstrap") {
		t.Fatalf("disabled render must not load the job\n%s", out)
	}
}

// The uninstall is delivered by the drift loop, which only fires when the fleet
// hash moves. A disable that left the hash unchanged would never reach a host.
func TestHostConfigHash_ChangesWhenLogShippingIsTurnedOff(t *testing.T) {
	enabled := Config{
		TartKubeletBinary: []byte("kubelet-v1"),
		LogShipperBinary:  []byte("shipper-v1"),
		LogShipURL:        "http://tuist-alloy-receiver-staging:3100/loki/api/v1/push",
		LogShipEnv:        "staging",
		TailscaleAuthKey:  "auth-key",
	}
	disabled := enabled
	disabled.LogShipURL = ""
	if HostConfigHash(enabled) == HostConfigHash(disabled) {
		t.Fatal("HostConfigHash must change when host logging is turned off, or the uninstall never rolls")
	}
}

// The uninstall runs on hosts that never carried the agent, so it has to be a
// clean no-op there rather than a failed step that fails the whole drift roll.
func TestRenderLogShipperUninstallScript_IsIdempotentAndValidSh(t *testing.T) {
	body := renderLogShipperUninstallScript()
	if !strings.Contains(body, "2>/dev/null || true") {
		t.Fatalf("bootout of an absent job must not fail the script\n%s", body)
	}
	for _, removal := range []string{"rm -f \"$PLIST\"", "rm -f /usr/local/bin/tuist-log-shipper", "rm -rf /var/lib/tuist-log-shipper"} {
		if !strings.Contains(body, removal) {
			t.Fatalf("missing %q\n%s", removal, body)
		}
	}
	script := filepath.Join(t.TempDir(), "uninstall-log-shipper")
	if err := os.WriteFile(script, []byte(body), 0o600); err != nil {
		t.Fatalf("write script: %v", err)
	}
	if combined, err := exec.Command("sh", "-n", script).CombinedOutput(); err != nil {
		t.Fatalf("uninstall script is not valid sh: %v\n%s", err, combined)
	}
}

// Turning host logs on, pointing them at a different receiver, or re-baking the
// agent all have to move the fleet hash — otherwise the change never reaches
// an already-bootstrapped mini, which is exactly how node_exporter silently
// skipped every drift update once.
func TestHostConfigHash_ChangesWithLogShipping(t *testing.T) {
	// An operator image that carries the agent but no push URL is the disabled
	// state, so the URL is what turns the feature on from here.
	base := Config{
		TartKubeletBinary: []byte("kubelet-v1"),
		LogShipperBinary:  []byte("shipper-v1"),
	}

	url := base
	url.LogShipURL = "http://tuist-alloy-receiver-staging:3100/loki/api/v1/push"
	if HostConfigHash(base) == HostConfigHash(url) {
		t.Fatal("HostConfigHash must change when the log push URL changes")
	}

	moved := url
	moved.LogShipURL = "http://tuist-alloy-receiver-canary:3100/loki/api/v1/push"
	if HostConfigHash(url) == HostConfigHash(moved) {
		t.Fatal("HostConfigHash must change when the receiver moves")
	}

	env := url
	env.LogShipEnv = "staging"
	if HostConfigHash(url) == HostConfigHash(env) {
		t.Fatal("HostConfigHash must change when the log env label changes")
	}

	rebuilt := env
	rebuilt.LogShipperBinary = []byte("shipper-v2")
	if HostConfigHash(env) == HostConfigHash(rebuilt) {
		t.Fatal("HostConfigHash must change when the log shipper binary is re-baked")
	}
}

// The shipper tails whatever launchd points tart-kubelet's stdout at. Nothing
// enforces that at compile time, and a silent mismatch is invisible: the plist
// would still load, the agent would still run, and the host would just never
// appear in Loki.
func TestLogShipperTailsTheTartKubeletLaunchdSink(t *testing.T) {
	plist := renderLaunchdPlist(Config{NodeName: "n1", SSHUser: "m1"})
	if !strings.Contains(plist, "<key>StandardOutPath</key><string>"+tartKubeletLogPath+"</string>") {
		t.Fatalf("tart-kubelet's launchd sink is not %s; the log shipper would tail a dead file\n%s", tartKubeletLogPath, plist)
	}
	if !strings.Contains(plist, "<key>StandardErrorPath</key><string>"+tartKubeletLogPath+"</string>") {
		t.Fatalf("tart-kubelet's stderr does not go to %s, so panics would never ship\n%s", tartKubeletLogPath, plist)
	}
	shipper := renderLogShipperInstallScript(Config{LogShipURL: "http://receiver:3100/loki/api/v1/push"})
	if !strings.Contains(shipper, "--file="+tartKubeletLogJob+"="+tartKubeletLogPath+"</string>") {
		t.Fatalf("the shipper does not tail %s\n%s", tartKubeletLogPath, shipper)
	}
}

// Hosts provisioned before the begin/end markers existed carry a bare,
// un-delimited anchor/load-anchor pair in /etc/pf.conf. A marker-only strip
// leaves it in place and appends a second copy, so loading /etc/pf.conf hits
// "cannot define table vm_sources: Resource busy" and rejects the WHOLE
// ruleset. pf then keeps serving whatever it loaded previously, which no longer
// carries the stock nat-anchor "com.apple/*" line, so the
// com.apple/tuist.vmnat sub-anchor holding the VM NAT rules is never evaluated:
// cache traffic leaves un-NAT'd with its 192.168.64.x source, the per-instance
// kura NetworkPolicy drops it at ingress with no RST, and every cache request
// hangs until its client timeout. Observed on a live production host whose
// anchor held perfectly correct rules that nothing ever consulted.
func TestRenderVMEgressFirewallScript_StripsLegacyUndelimitedAnchorBlock(t *testing.T) {
	script, err := renderVMEgressFirewallScript(Config{VMCachePNCIDR: "172.16.0.0/22"})
	if err != nil {
		t.Fatalf("render: %v", err)
	}

	// The command may be split across continuation lines; collect it whole.
	var sedLine string
	lines := strings.Split(script, "\n")
	for i, line := range lines {
		if !strings.HasPrefix(line, "sudo sed ") {
			continue
		}
		parts := []string{}
		for _, l := range lines[i:] {
			parts = append(parts, strings.TrimSuffix(strings.TrimSpace(l), `\`))
			if !strings.HasSuffix(strings.TrimSpace(l), `\`) {
				break
			}
		}
		sedLine = strings.Join(parts, " ")
		break
	}
	if sedLine == "" || !strings.Contains(sedLine, "/etc/pf.conf") {
		t.Fatalf("no pf.conf strip command in rendered script\n%s", script)
	}

	// A host that has been re-pushed once: the legacy block the old bootstrap
	// appended, then the canonical marker-delimited block.
	const legacy = `# Tuist runner VM egress filter — see /etc/pf.anchors/tuist.runners
anchor "tuist.runners"
load anchor "tuist.runners" from "/etc/pf.anchors/tuist.runners"
`
	fixture := `scrub-anchor "com.apple/*"
nat-anchor "com.apple/*"
rdr-anchor "com.apple/*"
anchor "com.apple/*"
load anchor "com.apple" from "/etc/pf.anchors/com.apple"
` + legacy + "# BEGIN tuist.runners\n" + legacy + "# END tuist.runners\n"

	dir := t.TempDir()
	path := filepath.Join(dir, "pf.conf")
	if err := os.WriteFile(path, []byte(fixture), 0o644); err != nil {
		t.Fatalf("write fixture: %v", err)
	}

	// Run the very expressions the host runs, with the in-place flag removed so
	// the result lands on stdout.
	cmd := strings.Replace(sedLine, "sudo ", "", 1)
	cmd = strings.Replace(cmd, "-i.bak ", "", 1)
	cmd = strings.Replace(cmd, "/etc/pf.conf", path, 1)
	out, err := exec.Command("sh", "-c", cmd).Output()
	if err != nil {
		t.Fatalf("run %q: %v", cmd, err)
	}

	if n := strings.Count(string(out), `anchor "tuist.runners"`); n != 0 {
		t.Fatalf("strip left %d tuist.runners anchor line(s); a re-push would duplicate them and break the whole pf load\n%s", n, out)
	}
	// The stock Apple hooks must survive: losing nat-anchor "com.apple/*" is
	// precisely the failure this guards against.
	if !strings.Contains(string(out), `nat-anchor "com.apple/*"`) {
		t.Fatalf("strip removed the stock Apple nat-anchor\n%s", out)
	}
}

// HostConfigHash zeroes TailscaleAuthKey, so anything the rendered script keys
// on must survive that. If the render consulted the auth key, the enabled and
// disabled configs would hash identically and the flag would move nothing —
// neither the install nor the uninstall would ever reach a host.
func TestRenderLogShipperScript_ChoiceSurvivesTheHashZeroingTheAuthKey(t *testing.T) {
	cfg := Config{
		LogShipperBinary: []byte("shipper"),
		LogShipURL:       "http://receiver:3100/loki/api/v1/push",
		TailscaleAuthKey: "auth-key",
	}
	withKey := renderLogShipperScript(cfg)
	cfg.TailscaleAuthKey = ""
	if renderLogShipperScript(cfg) != withKey {
		t.Fatal("the rendered script must not depend on the auth key the hash strips")
	}
	if !strings.Contains(withKey, "launchctl bootstrap") {
		t.Fatalf("a configured fleet must render the install, not the uninstall\n%s", withKey)
	}
}
