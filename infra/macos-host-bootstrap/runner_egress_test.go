package bootstrap

import (
	"os/exec"
	"strings"
	"testing"
)

const testRunnerEgressKey = "HIgo9xNzJMWLKASShiTqIybxZ0U3wGLiUeJ1PKf8ykw="

func testRunnerEgressGateway(name string, index int) RunnerEgressGateway {
	return RunnerEgressGateway{Name: name, Index: index, Endpoint: "203.0.113.10:51821", PublicKey: testRunnerEgressKey}
}

func TestValidateRunnerEgressGateways(t *testing.T) {
	if err := ValidateRunnerEgressGateways([]RunnerEgressGateway{testRunnerEgressGateway("dedicated-1", 1), testRunnerEgressGateway("dedicated-2", 2)}); err != nil {
		t.Fatal(err)
	}
	for name, gateways := range map[string][]RunnerEgressGateway{
		"bad name":       {testRunnerEgressGateway("Dedicated", 1)},
		"shell in name":  {testRunnerEgressGateway("a;rm", 1)},
		"duplicate name": {testRunnerEgressGateway("a", 1), testRunnerEgressGateway("a", 2)},
		"duplicate idx":  {testRunnerEgressGateway("a", 1), testRunnerEgressGateway("b", 1)},
		"index range":    {testRunnerEgressGateway("a", 100)},
		"hostname":       {{Name: "a", Index: 1, Endpoint: "gw.example.com:51821", PublicKey: testRunnerEgressKey}},
		"no port":        {{Name: "a", Index: 1, Endpoint: "203.0.113.10", PublicKey: testRunnerEgressKey}},
		"bad key":        {{Name: "a", Index: 1, Endpoint: "203.0.113.10:51821", PublicKey: "</string>"}},
	} {
		if err := ValidateRunnerEgressGateways(gateways); err == nil {
			t.Fatalf("%s accepted", name)
		}
	}
}

func TestRenderRunnerEgressScriptWithoutGatewaysFlushesAnchor(t *testing.T) {
	script, err := renderRunnerEgressScript(Config{})
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"WANT=''",
		`sudo launchctl bootout "system/dev.tuist.runner-egress.$name"`,
		"sudo /sbin/pfctl -a com.apple/0.tuist.egress -F all",
	} {
		if !strings.Contains(script, want) {
			t.Fatalf("script missing %q:\n%s", want, script)
		}
	}
	if strings.Contains(script, "launchctl bootstrap") {
		t.Fatalf("script bootstraps a daemon without gateways:\n%s", script)
	}
}

func TestRenderRunnerEgressScriptInstallsOneDaemonPerGateway(t *testing.T) {
	cfg := Config{RunnerEgressGateways: []RunnerEgressGateway{testRunnerEgressGateway("dedicated-2", 2), testRunnerEgressGateway("dedicated-1", 1)}}
	script, err := renderRunnerEgressScript(cfg)
	if err != nil {
		t.Fatal(err)
	}
	for _, want := range []string{
		"WANT='dedicated-1 dedicated-2'",
		"PLIST=/Library/LaunchDaemons/dev.tuist.runner-egress.dedicated-1.plist",
		"PLIST=/Library/LaunchDaemons/dev.tuist.runner-egress.dedicated-2.plist",
		"<string>egress-tunnel</string>",
		"<string>--index=1</string>",
		"<string>--endpoint=203.0.113.10:51821</string>",
		"<string>--gateway-public-key=" + testRunnerEgressKey + "</string>",
		"sudo launchctl kickstart -k system/dev.tuist.runner-egress.dedicated-1",
	} {
		if !strings.Contains(script, want) {
			t.Fatalf("script missing %q:\n%s", want, script)
		}
	}
	if strings.Index(script, "dedicated-1.plist") > strings.Index(script, "dedicated-2.plist") {
		t.Fatal("gateways are not rendered in a stable order")
	}
	if strings.Contains(script, "<key>UserName</key>") || strings.Contains(script, "-F all") {
		t.Fatalf("daemon must run as root and the anchor must be left to tart-kubelet:\n%s", script)
	}

	reordered := Config{RunnerEgressGateways: []RunnerEgressGateway{testRunnerEgressGateway("dedicated-1", 1), testRunnerEgressGateway("dedicated-2", 2)}}
	if again, _ := renderRunnerEgressScript(reordered); again != script {
		t.Fatal("gateway order changes the rendered script and with it the host config hash")
	}
}

func TestRenderRunnerEgressScriptRejectsInvalidGateways(t *testing.T) {
	if _, err := renderRunnerEgressScript(Config{RunnerEgressGateways: []RunnerEgressGateway{testRunnerEgressGateway("Bad", 1)}}); err == nil {
		t.Fatal("invalid gateway rendered")
	}
}

func TestRunnerEgressKubeletArgs(t *testing.T) {
	cfg := Config{
		RunnerEgressGateways: []RunnerEgressGateway{testRunnerEgressGateway("dedicated-1", 1)},
		VMKuraEgressCIDR:     "10.128.0.0/12",
		VMClusterDNSIP:       "10.128.0.10",
		VMCachePNCIDR:        "172.16.0.0/22",
	}
	args := runnerEgressKubeletArgs(cfg, true)
	for _, want := range []string{
		"<string>--runner-egress-status-dir=/var/run/tuist-egress</string>",
		"<string>--runner-egress-state-dir=/var/db/tuist-egress</string>",
		"<string>--runner-egress-exclude-cidrs=10.128.0.0/12,10.128.0.10,172.16.0.0/22</string>",
	} {
		if !strings.Contains(args, want) {
			t.Fatalf("args missing %q: %s", want, args)
		}
	}
	if runnerEgressKubeletArgs(cfg, false) != "" {
		t.Fatal("egress enabled without a tailnet node IP")
	}
	if runnerEgressKubeletArgs(Config{}, true) != "" {
		t.Fatal("egress enabled without gateways")
	}
}

func TestLaunchdPlistCarriesRunnerEgressFlagsOnlyWhenConfigured(t *testing.T) {
	base := Config{TailscaleBinaries: []byte{1}, TailscaleAuthKey: "key"}
	if strings.Contains(renderLaunchdPlist(base), "runner-egress") {
		t.Fatal("plist enables egress without gateways")
	}
	withGateway := base
	withGateway.RunnerEgressGateways = []RunnerEgressGateway{testRunnerEgressGateway("dedicated-1", 1)}
	if !strings.Contains(renderLaunchdPlist(withGateway), "--runner-egress-status-dir=/var/run/tuist-egress") {
		t.Fatal("plist missing egress flags")
	}
}

// The SSH session runs zsh, where a glob with no match aborts the script.
func TestRenderRunnerEgressScriptRunsUnderZshWithNothingInstalled(t *testing.T) {
	if _, err := exec.LookPath("zsh"); err != nil {
		t.Skip("zsh not installed")
	}
	for _, cfg := range []Config{{}, {RunnerEgressGateways: []RunnerEgressGateway{testRunnerEgressGateway("dedicated-1", 1)}}} {
		script, err := renderRunnerEgressScript(cfg)
		if err != nil {
			t.Fatal(err)
		}
		cleanup := script[:strings.Index(script, "done\n")+len("done\n")]
		cmd := exec.Command("zsh", "-c", strings.ReplaceAll(cleanup, "/Library/LaunchDaemons", t.TempDir()))
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("cleanup loop failed under zsh: %v\n%s", err, out)
		}
	}
}
