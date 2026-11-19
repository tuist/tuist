package linux

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// Execute the installed host script with isolated files and fake Linux commands.
// No network, systemd, sudo or host filesystem mutation is performed.
func TestRunnerEgressHostApplyRepairAndRemoval(t *testing.T) {
	root := t.TempDir()
	for _, dir := range []string{"bin", "sys/private0", "proc/private0", "lock"} {
		if err := os.MkdirAll(filepath.Join(root, dir), 0755); err != nil {
			t.Fatal(err)
		}
	}
	write := func(name, body string) {
		t.Helper()
		if err := os.WriteFile(filepath.Join(root, name), []byte(body), 0755); err != nil {
			t.Fatal(err)
		}
	}
	write("sys/private0/address", "aa:bb:cc:dd:ee:01\n")
	write("proc/private0/rp_filter", "1\n")
	write("bin/sudo", "#!/usr/bin/env bash\nexec \"$@\"\n")
	write("bin/flock", "#!/usr/bin/env bash\nexit 0\n")
	write("bin/systemctl", `#!/usr/bin/env bash
set -euo pipefail
if [ "$*" = 'daemon-reload' ]; then
 if [ -f "$EGRESS_TEST_ROOT/etc/systemd/system/kubelet.service.d/35-runner-egress.conf" ]; then
  touch "$EGRESS_TEST_ROOT/kubelet-requires-egress"
 else
  rm -f "$EGRESS_TEST_ROOT/kubelet-requires-egress"
 fi
fi
if [ "$*" = 'stop tuist-runner-egress.service' ] && [ -f "$EGRESS_TEST_ROOT/kubelet-requires-egress" ]; then
 touch "$EGRESS_TEST_ROOT/kubelet-stopped"
fi
if [ "$*" = 'start tuist-runner-egress.service' ]; then
 "$EGRESS_TEST_ROOT/sbin/tuist-runner-egress"
fi
`)
	write("bin/ip", `#!/usr/bin/env bash
set -euo pipefail
root=$EGRESS_TEST_ROOT
case "$*" in
 '-4 route show default') echo 'default via 192.0.2.1 dev public0' ;;
 '-4 route show table 243') if [ -f "$root/routes" ]; then cat "$root/routes"; fi ;;
 '-4 rule show priority 10430') if [ -f "$root/rule" ]; then cat "$root/rule"; fi ;;
 '-o -4 address show dev private0') if [ -f "$root/address" ]; then cat "$root/address"; fi ;;
 'link set dev private0 up') ;;
 'address replace 198.51.100.1/32 dev private0 noprefixroute') echo '2: private0 inet 198.51.100.1/32 scope global private0' > "$root/address" ;;
 '-4 route replace 198.51.100.6/32 dev private0 scope link table 243 proto 243') echo '198.51.100.6 dev private0 proto 243 scope link' > "$root/routes" ;;
 '-4 route replace default via 198.51.100.6 dev private0 src 198.51.100.1 table 243 proto 243') echo 'default via 198.51.100.6 dev private0 proto 243 src 198.51.100.1' >> "$root/routes" ;;
 '-4 rule add priority 10430 from 198.51.100.1/32 table 243') printf '10430:\tfrom 198.51.100.1 lookup 243\n' > "$root/rule" ;;
 '-4 route get 1.1.1.1 from 198.51.100.1') echo '1.1.1.1 from 198.51.100.1 via 198.51.100.6 dev private0 table 243' ;;
 '-4 rule del priority 10430 from 198.51.100.1/32 table 243') rm "$root/rule" ;;
 '-4 route flush table 243 proto 243') rm -f "$root/routes" ;;
 'address del 198.51.100.1/32 dev private0')
  if [ -f "$root/deny-delete" ]; then echo 'simulated deletion failure' >&2; exit 1; fi
  rm "$root/address"
  ;;
 *) echo "unexpected ip command: $*" >&2; exit 1 ;;
esac
`)
	render := func(remove bool) string {
		t.Helper()
		script, err := renderRunnerEgressScript(runnerEgressReservation{MAC: "aa:bb:cc:dd:ee:01", Address: "198.51.100.1"}, "pn-123", "198.51.100.0/29", remove)
		if err != nil {
			t.Fatal(err)
		}
		return strings.NewReplacer("/etc/", root+"/etc/", "/usr/local/sbin", root+"/sbin", "/sys/class/net", root+"/sys", "/proc/sys/net/ipv4/conf", root+"/proc", "/run/lock", root+"/lock").Replace(script)
	}
	run := func(script string, wantFailure bool) {
		t.Helper()
		cmd := exec.Command("bash", "-s")
		cmd.Stdin = strings.NewReader(script)
		cmd.Env = append(os.Environ(), "PATH="+filepath.Join(root, "bin")+":"+os.Getenv("PATH"), "EGRESS_TEST_ROOT="+root)
		out, err := cmd.CombinedOutput()
		if (err != nil) != wantFailure {
			t.Fatalf("failure=%v want=%v: %s", err, wantFailure, out)
		}
	}
	run(render(false), false)
	run(render(false), false)
	for _, file := range []string{"routes", "rule", "address", "etc/tuist/runner-egress", "etc/systemd/system/kubelet.service.d/35-runner-egress.conf"} {
		if _, err := os.Stat(filepath.Join(root, file)); err != nil {
			t.Fatal("missing configured state", file, err)
		}
	}
	if err := os.Remove(filepath.Join(root, "routes")); err != nil {
		t.Fatal(err)
	}
	run("\""+filepath.Join(root, "sbin/tuist-runner-egress")+"\"", false)
	if _, err := os.Stat(filepath.Join(root, "routes")); err != nil {
		t.Fatal("timer did not repair routes", err)
	}
	write("deny-delete", "")
	run(render(true), true)
	if _, err := os.Stat(filepath.Join(root, "kubelet-stopped")); !os.IsNotExist(err) {
		t.Fatal("egress cleanup stopped kubelet through its loaded Requires dependency")
	}
	if _, err := os.Stat(filepath.Join(root, "etc/tuist/runner-egress")); err != nil {
		t.Fatal("failed cleanup lost ownership", err)
	}
	if err := os.Remove(filepath.Join(root, "deny-delete")); err != nil {
		t.Fatal(err)
	}
	run(render(true), false)
	run(render(true), false)
	for _, file := range []string{"routes", "rule", "address", "etc/tuist/runner-egress", "sbin/tuist-runner-egress", "etc/systemd/system/kubelet.service.d/35-runner-egress.conf"} {
		if _, err := os.Stat(filepath.Join(root, file)); !os.IsNotExist(err) {
			t.Fatal("cleanup left state", file, err)
		}
	}
	write("address", "2: private0 inet 198.51.100.1/32 scope global private0\n")
	run(render(false), true)
	run(render(true), true)
	if _, err := os.Stat(filepath.Join(root, "address")); err != nil {
		t.Fatal("touched unowned address")
	}
}
