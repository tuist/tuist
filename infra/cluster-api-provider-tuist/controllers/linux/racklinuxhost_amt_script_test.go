package linux

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// amtHost runs the AMT script against a fake rpc that behaves as the MS-01's
// AMT did: it learns the DHCP domain only from a lease of its own, which it
// takes once activated, so admin control mode needs client control mode
// first.
type amtHost struct {
	dir, rpc, calls, state string
}

func newAMTHost(t *testing.T, mode int, address string) amtHost {
	t.Helper()
	if _, err := exec.LookPath("jq"); err != nil {
		t.Skip("no jq")
	}
	dir := t.TempDir()
	h := amtHost{dir: dir, rpc: filepath.Join(dir, "rpc"), calls: filepath.Join(dir, "calls"), state: filepath.Join(dir, "state")}
	if err := os.WriteFile(h.state, []byte(fmt.Sprintf("%d %s\n", mode, address)), 0o600); err != nil {
		t.Fatal(err)
	}
	rpc := fmt.Sprintf(`#!/usr/bin/env bash
state=%[1]q
read -r mode address < "$state"
echo "$* password=${AMT_PASSWORD:+set} cert=${PROVISIONING_CERT:+set} mebx=${MEBX_PASSWORD:+set}" >> %[2]q
case "$1" in
amtinfo)
  names=("not activated" "client control mode" "admin control mode")
  printf '{"amt":"16.1.25","controlMode":"%%s","wiredAdapter":{"linkStatus":"up","ipAddress":"%%s"}}\n' "${names[$mode]}" "$address"
  ;;
activate)
  [ -n "${AMT_PASSWORD:-}" ] || { echo '{"error":"no password"}'; exit 3; }
  case " $* " in
  *" --ccm "*)
    [ "$mode" = 0 ] || exit 11
    echo "1 192.168.50.112" > "$state"
    echo '{"message":"Device activated in Client Control Mode","status":"success"}'
    ;;
  *" --acm "*)
    if [ "$mode" != 1 ] || [ "$address" = 0.0.0.0 ] || [ -z "${PROVISIONING_CERT:-}" ]; then
      echo '{"error":"adminsetup failed: returned 5"}'
      exit 10
    fi
    echo "2 $address" > "$state"
    echo '{"message":"Device activated in Admin Control Mode","status":"success"}'
    ;;
  esac
  ;;
configure)
  [ "$mode" = 2 ] && [ -n "${AMT_PASSWORD:-}" ] || exit 12
  case "$2" in
  mebx) [ -n "${MEBX_PASSWORD:-}" ] || exit 13 ;;
  wired) echo "2 $4" > "$state" ;;
  esac
  echo '{"status":"success"}'
  ;;
esac
`, h.state, h.calls)
	bin := filepath.Join(dir, "bin")
	if err := os.MkdirAll(bin, 0o755); err != nil {
		t.Fatal(err)
	}
	for path, body := range map[string]string{
		h.rpc:                         rpc,
		filepath.Join(bin, "timeout"): "#!/bin/sh\nwhile [ \"${1#-}\" != \"$1\" ]; do shift; done\nshift\nexec \"$@\"\n",
		filepath.Join(bin, "sleep"):   "#!/bin/sh\n:\n",
	} {
		if err := os.WriteFile(path, []byte(body), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	return h
}

func (h amtHost) run(t *testing.T, a *amtRun) (amtScriptResult, string) {
	t.Helper()
	bash, err := exec.LookPath("bash")
	if err != nil {
		t.Skip("no bash")
	}
	cmd := exec.Command(bash, "-s")
	cmd.Stdin = strings.NewReader(strings.ReplaceAll(renderAMTScript(a), amtRPCPath, h.rpc))
	cmd.Env = append(os.Environ(), "PATH="+filepath.Join(h.dir, "bin")+":"+os.Getenv("PATH"))
	out, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("%v\n%s", err, out)
	}
	result, err := parseAMTScriptOutput(string(out))
	if err != nil {
		t.Fatalf("%v\n%s", err, out)
	}
	calls, _ := os.ReadFile(h.calls)
	return result, string(calls)
}

var testActivation = &amtRun{Password: "Aa1!secret-password-xx", PFX: "UEZY", PFXPassword: "pfx-pass"}

func TestAMTScriptActivatesThroughClientControlMode(t *testing.T) {
	h := newAMTHost(t, 0, "0.0.0.0")

	result, calls := h.run(t, testActivation)

	if step, ok := result.steps["activate"]; !ok || step.exit != 0 || result.info.ControlMode != "admin control mode" || result.info.Wired.Address != "192.168.50.112" {
		t.Fatalf("result %+v\ncalls:\n%s", result, calls)
	}
	ccm := strings.Index(calls, "activate --ccm --skipIPRenew --json password=set")
	acm := strings.Index(calls, "activate --acm --skipIPRenew --json password=set cert=set")
	if ccm < 0 || acm < ccm {
		t.Fatalf("want client control mode, then the upgrade:\n%s", calls)
	}
	if strings.Contains(calls, "secret-password") || strings.Contains(calls, "UEZY") {
		t.Fatalf("a secret reached rpc's command line:\n%s", calls)
	}
	if strings.Contains(calls, "amtinfo --json --ver --mode --lan --uuid password=set") {
		t.Fatalf("amtinfo ran with the secrets in its environment:\n%s", calls)
	}
}

func TestAMTScriptUpgradesClientControlMode(t *testing.T) {
	h := newAMTHost(t, 1, "192.168.50.112")

	result, calls := h.run(t, testActivation)

	if step, ok := result.steps["activate"]; !ok || step.exit != 0 || result.info.ControlMode != "admin control mode" {
		t.Fatalf("result %+v\ncalls:\n%s", result, calls)
	}
	if strings.Contains(calls, "--ccm") {
		t.Fatalf("activated client control mode again:\n%s", calls)
	}
}

func TestAMTScriptReportsAFailedUpgrade(t *testing.T) {
	h := newAMTHost(t, 1, "0.0.0.0")

	result, _ := h.run(t, testActivation)

	if step := result.steps["activate"]; step.exit != 10 || !strings.Contains(step.output, "returned 5") ||
		result.info.ControlMode != "client control mode" {
		t.Fatalf("result %+v", result)
	}
}

func TestAMTScriptOnlyReadsAnActivatedAMT(t *testing.T) {
	h := newAMTHost(t, 2, "192.168.50.112")

	result, calls := h.run(t, testActivation)

	if len(result.steps) != 0 || strings.Contains(calls, "activate") || strings.Contains(calls, "configure") {
		t.Fatalf("acted on an activated AMT with nothing to configure:\n%s", calls)
	}
}

var testConfiguration = &amtRun{Password: "Aa1!secret-password-xx", MEBxPassword: "Bb2!secret-mebx-xxxxxx",
	Address: "192.168.50.21", Mask: "255.255.255.0", Gateway: "192.168.50.1"}

// Activated AMT gets the MEBx password and the static address, with the
// secrets in the environment of those runs only.
func TestAMTScriptConfiguresActivatedAMT(t *testing.T) {
	h := newAMTHost(t, 2, "192.168.50.112")

	result, calls := h.run(t, testConfiguration)

	if result.steps["mebx"].exit != 0 || result.steps["wired"].exit != 0 || result.info.Wired.Address != "192.168.50.21" {
		t.Fatalf("result %+v\ncalls:\n%s", result, calls)
	}
	for _, want := range []string{
		"configure mebx --json password=set cert= mebx=set",
		"configure wired --ipaddress 192.168.50.21 --subnetmask 255.255.255.0 --gateway 192.168.50.1 --primarydns 192.168.50.1 --json password=set",
	} {
		if !strings.Contains(calls, want) {
			t.Fatalf("calls lack %q:\n%s", want, calls)
		}
	}
	if strings.Contains(calls, "secret") || strings.Contains(calls, "activate") {
		t.Fatalf("calls:\n%s", calls)
	}
}

func TestAMTScriptLeavesAnAddressThatIsAlreadyAMTs(t *testing.T) {
	h := newAMTHost(t, 2, "192.168.50.21")

	result, calls := h.run(t, &amtRun{Password: testConfiguration.Password, Address: "192.168.50.21", Mask: "255.255.255.0", Gateway: "192.168.50.1"})

	if _, ok := result.steps["wired"]; ok || strings.Contains(calls, "configure") {
		t.Fatalf("configured AMT's address again:\n%s", calls)
	}
}

// Activation and configuration run together: a pre-provisioned AMT ends the
// run activated, with its MEBx password and address.
func TestAMTScriptActivatesAndConfigures(t *testing.T) {
	h := newAMTHost(t, 0, "0.0.0.0")
	run := *testConfiguration
	run.PFX, run.PFXPassword = "UEZY", "pfx-pass"

	result, calls := h.run(t, &run)

	if result.steps["activate"].exit != 0 || result.steps["mebx"].exit != 0 || result.steps["wired"].exit != 0 ||
		result.info.ControlMode != "admin control mode" || result.info.Wired.Address != "192.168.50.21" {
		t.Fatalf("result %+v\ncalls:\n%s", result, calls)
	}
}

// Client control mode has no MEBx password to set.
func TestAMTScriptConfiguresOnlyAdminControlMode(t *testing.T) {
	h := newAMTHost(t, 1, "0.0.0.0")

	result, calls := h.run(t, testConfiguration)

	if len(result.steps) != 0 || strings.Contains(calls, "configure") {
		t.Fatalf("configured client control mode:\n%s", calls)
	}
}
