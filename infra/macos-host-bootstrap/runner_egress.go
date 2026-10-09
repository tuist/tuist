package bootstrap

import (
	"context"
	"encoding/base64"
	"fmt"
	"net"
	"regexp"
	"sort"
	"strconv"
	"strings"

	"golang.org/x/crypto/ssh"
)

// RunnerEgressGateway is a dedicated egress gateway the host keeps a
// WireGuard tunnel to. tart-kubelet routes the VMs of the gateway's account
// through it. See infra/runner-egress-gateway/DESIGN.md.
type RunnerEgressGateway struct {
	Name      string `json:"name"`
	Index     int    `json:"index"`
	Endpoint  string `json:"endpoint"`
	PublicKey string `json:"publicKey"`
}

const (
	runnerEgressStateDir  = "/var/db/tuist-egress"
	runnerEgressStatusDir = "/var/run/tuist-egress"
	runnerEgressLabel     = "dev.tuist.runner-egress"
	runnerEgressAnchor    = "com.apple/0.tuist.egress"
)

var runnerEgressNamePattern = regexp.MustCompile(`^[a-z0-9]([a-z0-9-]{0,22}[a-z0-9])?$`)

// ValidateRunnerEgressGateways rejects any gateway list that would render an
// ambiguous launchd label, utun unit, endpoint or key. The same rules hold in
// tart-kubelet's egress package.
func ValidateRunnerEgressGateways(gateways []RunnerEgressGateway) error {
	names := map[string]bool{}
	indexes := map[int]bool{}
	for _, gateway := range gateways {
		if !runnerEgressNamePattern.MatchString(gateway.Name) {
			return fmt.Errorf("runner egress gateway name %q must be a lowercase DNS label of at most 24 characters", gateway.Name)
		}
		if names[gateway.Name] {
			return fmt.Errorf("runner egress gateway %q is listed twice", gateway.Name)
		}
		names[gateway.Name] = true
		if gateway.Index < 0 || gateway.Index > 99 {
			return fmt.Errorf("runner egress gateway %q: index %d must be between 0 and 99", gateway.Name, gateway.Index)
		}
		if indexes[gateway.Index] {
			return fmt.Errorf("runner egress gateway %q: index %d is already used", gateway.Name, gateway.Index)
		}
		indexes[gateway.Index] = true
		host, port, err := net.SplitHostPort(gateway.Endpoint)
		if err != nil {
			return fmt.Errorf("runner egress gateway %q: endpoint %q: %w", gateway.Name, gateway.Endpoint, err)
		}
		if ip := net.ParseIP(host); ip == nil || ip.To4() == nil {
			return fmt.Errorf("runner egress gateway %q: endpoint %q must be an IPv4 address and port", gateway.Name, gateway.Endpoint)
		}
		if n, err := strconv.Atoi(port); err != nil || n < 1 || n > 65535 {
			return fmt.Errorf("runner egress gateway %q: endpoint %q has an invalid port", gateway.Name, gateway.Endpoint)
		}
		if key, err := base64.StdEncoding.DecodeString(gateway.PublicKey); err != nil || len(key) != 32 {
			return fmt.Errorf("runner egress gateway %q: public key is not a WireGuard key", gateway.Name)
		}
	}
	return nil
}

func sortedRunnerEgressGateways(gateways []RunnerEgressGateway) []RunnerEgressGateway {
	sorted := append([]RunnerEgressGateway(nil), gateways...)
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].Name < sorted[j].Name })
	return sorted
}

// runnerEgressExcludeCIDRs are the runner-cache carve-outs that stay off the
// tunnels, on top of the private ranges tart-kubelet always excludes.
func runnerEgressExcludeCIDRs(cfg Config) []string {
	cidrs := []string{}
	for _, value := range append([]string{cfg.VMKuraEgressCIDR, cfg.VMClusterDNSIP, cfg.VMCachePNCIDR}, cfg.VMCacheGatewayCIDRs...) {
		if value != "" {
			cidrs = append(cidrs, value)
		}
	}
	return cidrs
}

// runnerEgressKubeletArgs turns dedicated egress on in tart-kubelet. It needs
// the tailnet node IP, so it is only rendered when Tailscale is wired.
func runnerEgressKubeletArgs(cfg Config, tailscaleNodeIP bool) string {
	if len(cfg.RunnerEgressGateways) == 0 || !tailscaleNodeIP {
		return ""
	}
	args := fmt.Sprintf("\n    <string>--runner-egress-status-dir=%s</string>\n    <string>--runner-egress-state-dir=%s</string>",
		runnerEgressStatusDir, runnerEgressStateDir)
	if exclude := runnerEgressExcludeCIDRs(cfg); len(exclude) > 0 {
		args += fmt.Sprintf("\n    <string>--runner-egress-exclude-cidrs=%s</string>", xmlEscape(strings.Join(exclude, ",")))
	}
	return args
}

func renderRunnerEgressPlist(gateway RunnerEgressGateway) string {
	label := runnerEgressLabel + "." + gateway.Name
	return fmt.Sprintf(`<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>%[1]s</string>
  <key>ProgramArguments</key>
  <array>
    <string>/usr/local/bin/tart-kubelet</string>
    <string>egress-tunnel</string>
    <string>--gateway=%[2]s</string>
    <string>--index=%[3]d</string>
    <string>--endpoint=%[4]s</string>
    <string>--gateway-public-key=%[5]s</string>
    <string>--state-dir=%[6]s</string>
    <string>--status-dir=%[7]s</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>5</integer>
  <key>StandardOutPath</key><string>/var/log/tuist-runner-egress-%[2]s.log</string>
  <key>StandardErrorPath</key><string>/var/log/tuist-runner-egress-%[2]s.log</string>
</dict>
</plist>
`, label, gateway.Name, gateway.Index, gateway.Endpoint, xmlEscape(gateway.PublicKey), runnerEgressStateDir, runnerEgressStatusDir)
}

// renderRunnerEgressScript installs one root LaunchDaemon per gateway running
// `tart-kubelet egress-tunnel`, retires daemons for gateways no longer
// configured, and restarts the daemons when the tart-kubelet binary they run
// changed. tart-kubelet owns the pf anchor; this script only flushes it when
// the host has no gateways left, so no stale table can route a VM.
func renderRunnerEgressScript(cfg Config) (string, error) {
	gateways := sortedRunnerEgressGateways(cfg.RunnerEgressGateways)
	if err := ValidateRunnerEgressGateways(gateways); err != nil {
		return "", err
	}
	names := make([]string, 0, len(gateways))
	for _, gateway := range gateways {
		names = append(names, gateway.Name)
	}

	var b strings.Builder
	// The SSH session runs zsh, which aborts on a glob that matches nothing,
	// so existing daemons are listed with find rather than a bare glob.
	fmt.Fprintf(&b, `set -euo pipefail
WANT=%s
find /Library/LaunchDaemons -maxdepth 1 -name '%s.*.plist' | while read -r plist; do
  name="${plist#/Library/LaunchDaemons/%s.}"
  name="${name%%.plist}"
  case " $WANT " in *" $name "*) continue ;; esac
  sudo launchctl bootout "system/%s.$name" 2>/dev/null || true
  sudo rm -f "$plist" "%s/$name.json" "%s/.binary-$name"
done
`, shellQuote(strings.Join(names, " ")), runnerEgressLabel, runnerEgressLabel, runnerEgressLabel, runnerEgressStatusDir, runnerEgressStateDir)

	if len(gateways) == 0 {
		fmt.Fprintf(&b, "sudo /sbin/pfctl -a %s -F all 2>/dev/null || true\n", runnerEgressAnchor)
		return b.String(), nil
	}

	fmt.Fprintf(&b, `sudo mkdir -p %[1]s %[2]s
sudo chmod 0755 %[1]s %[2]s
BINARY_SHA=$(shasum -a 256 /usr/local/bin/tart-kubelet | awk '{print $1}')
`, runnerEgressStateDir, runnerEgressStatusDir)
	for _, gateway := range gateways {
		label := runnerEgressLabel + "." + gateway.Name
		fmt.Fprintf(&b, `
PLIST=/Library/LaunchDaemons/%[1]s.plist
TMP=$(mktemp)
cat >"$TMP" <<'PLIST'
%[2]sPLIST
if ! sudo cmp -s "$TMP" "$PLIST"; then
  sudo install -o root -g wheel -m 0644 "$TMP" "$PLIST"
  sudo launchctl bootout system/%[1]s 2>/dev/null || true
fi
rm -f "$TMP"
if ! sudo launchctl print system/%[1]s >/dev/null 2>&1; then
  sudo launchctl bootstrap system "$PLIST"
elif [ "$(sudo cat %[3]s/.binary-%[4]s 2>/dev/null || true)" != "$BINARY_SHA" ]; then
  sudo launchctl kickstart -k system/%[1]s
fi
echo "$BINARY_SHA" | sudo tee %[3]s/.binary-%[4]s >/dev/null
`, label, renderRunnerEgressPlist(gateway), runnerEgressStateDir, gateway.Name)
	}
	return b.String(), nil
}

func installRunnerEgress(ctx context.Context, client *ssh.Client, cfg Config) error {
	script, err := renderRunnerEgressScript(cfg)
	if err != nil {
		return err
	}
	return RunCommand(ctx, client, script)
}
