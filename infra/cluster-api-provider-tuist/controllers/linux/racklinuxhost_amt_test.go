package linux

import (
	"context"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/cluster-api/util/conditions"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/tailnet"
)

const amtTestProvisioningSecret = "tuist-rack-amt-provisioning"

func amtInfoJSON(mode, link, address string) string {
	return `{
  "amt": "16.1.25",
  "controlMode": "` + mode + `",
  "wiredAdapter": {"linkStatus": "` + link + `", "ipAddress": "` + address + `", "macAddress": "38:05:25:38:b5:b5"}
}
`
}

func amtEdge() *infrav1.RackLinuxHost {
	h := edgeHost()
	h.Spec.AMT = &infrav1.RackLinuxHostAMT{Activate: true}
	return h
}

func provisioningSecret() *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: amtTestProvisioningSecret, Namespace: rackTestNamespace},
		Data:       map[string][]byte{"pfx": []byte("UEZYQkFTRTY0"), "password": []byte("pfx-pass")},
	}
}

func newAMTHarness(t *testing.T, objs ...runtime.Object) *installHarness {
	t.Helper()
	h := newInstallHarness(t, objs...)
	h.api.devices = []tailnet.Device{edgeDevice("dev-1", "ber1-edge", "2026-09-24T08:00:00Z", true, "100.64.0.7")}
	h.r.AMT = &RackAMT{FleetName: rackTestFleet, ProvisioningSecret: amtTestProvisioningSecret}
	return h
}

func (h *installHarness) amtRuns() []scriptRun {
	var out []scriptRun
	for _, run := range h.runner.runs {
		if strings.Contains(run.script, amtRPCSHA256) {
			out = append(out, run)
		}
	}
	return out
}

func (h *installHarness) amtPassword(t *testing.T) string {
	t.Helper()
	secret := &corev1.Secret{}
	err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: "ber1-edge-amt"}, secret)
	if apierrors.IsNotFound(err) {
		return ""
	}
	if err != nil {
		t.Fatal(err)
	}
	return string(secret.Data["password"])
}

func TestRackAMTActivatesAPreProvisionedHostWhenAsked(t *testing.T) {
	h := newAMTHarness(t, amtEdge(), provisioningSecret())
	h.runner.reply = func(_, script string) string {
		return "--- activate\n{\"status\":\"success\"}\n--- activate exit 0\n--- amtinfo\n" +
			amtInfoJSON("admin control mode", "up", "192.168.50.112")
	}

	got := h.reconcile(t, "ber1-edge")

	runs := h.amtRuns()
	if len(runs) != 1 {
		t.Fatalf("ran %d AMT scripts, want 1", len(runs))
	}
	password := h.amtPassword(t)
	if !validAMTPassword(password) {
		t.Fatalf("stored AMT password %q breaks AMT's rules", password)
	}
	script := runs[0].script
	for _, want := range []string{
		"amt_password=" + shellSingleQuote(password),
		"provisioning_cert='UEZYQkFTRTY0'",
		"provisioning_cert_password='pfx-pass'",
		`timeout --kill-after=10 300 "$rpc" activate "$@" --skipIPRenew --json`,
	} {
		if !strings.Contains(script, want) {
			t.Fatalf("the script lacks %q:\n%s", want, script)
		}
	}
	if strings.Contains(script, "-amtPassword") || strings.Contains(script, "-provisioningCert") {
		t.Fatal("a secret is passed on rpc's command line")
	}
	amt := got.Status.AMT
	if amt == nil || amt.ControlMode != "admin" || amt.Version != "16.1.25" || amt.Link != "up" || amt.Address != "192.168.50.112" {
		t.Fatalf("status %+v", amt)
	}
	if amt.LastActivation == nil || amt.ActivationError != "" || amt.ObservedAt == nil {
		t.Fatalf("activation record %+v", amt)
	}
	if !conditions.IsTrue(got, AMTActivatedCondition) {
		t.Fatal("AMTActivated is not True")
	}
}

func TestRackAMTRecordsAFailedActivationAndBacksOff(t *testing.T) {
	h := newAMTHarness(t, amtEdge(), provisioningSecret())
	h.runner.reply = func(_, _ string) string {
		return "--- activate\n{\"status\":\"failed\",\"error\":\"ActivationFailed\"}\n--- activate exit 102\n--- amtinfo\n" +
			amtInfoJSON("not activated", "up", "0.0.0.0")
	}

	got := h.reconcile(t, "ber1-edge")

	amt := got.Status.AMT
	if amt == nil || amt.ControlMode != "pre-provisioning" || !strings.Contains(amt.ActivationError, "exit 102") ||
		!strings.Contains(amt.ActivationError, "ActivationFailed") {
		t.Fatalf("status %+v", amt)
	}
	if c := conditions.Get(got, AMTActivatedCondition); c == nil || c.Status != corev1.ConditionFalse || c.Reason != "ActivationFailed" {
		t.Fatalf("condition %+v", c)
	}
	password := h.amtPassword(t)

	h.now = h.now.Add(30 * time.Minute)
	h.reconcile(t, "ber1-edge")
	if n := len(h.amtRuns()); n != 1 {
		t.Fatalf("tried again after 30 minutes (%d runs)", n)
	}

	h.now = h.now.Add(31 * time.Minute)
	h.reconcile(t, "ber1-edge")
	runs := h.amtRuns()
	if len(runs) != 2 {
		t.Fatalf("did not try again after the backoff (%d runs)", len(runs))
	}
	if !strings.Contains(runs[1].script, "amt_password="+shellSingleQuote(password)) {
		t.Fatal("the retry did not reuse the stored password")
	}
}

func TestRackAMTLeavesAHostThatDoesNotAskForIt(t *testing.T) {
	h := newAMTHarness(t, edgeHost(), provisioningSecret())

	got := h.reconcile(t, "ber1-edge")

	if len(h.amtRuns()) != 0 || h.amtPassword(t) != "" || got.Status.AMT != nil || conditions.Get(got, AMTActivatedCondition) != nil {
		t.Fatalf("touched AMT on a host that did not ask: status %+v", got.Status.AMT)
	}
}

func TestRackAMTWaitsForTheProvisioningCertificate(t *testing.T) {
	h := newAMTHarness(t, amtEdge())

	got := h.reconcile(t, "ber1-edge")

	if len(h.amtRuns()) != 0 || h.amtPassword(t) != "" {
		t.Fatal("tried to activate without a provisioning certificate")
	}
	if c := conditions.Get(got, AMTActivatedCondition); c == nil || c.Reason != "NoProvisioningCertificate" {
		t.Fatalf("condition %+v", c)
	}
}

func TestRackAMTWaitsForTheHostToBeOnline(t *testing.T) {
	h := newAMTHarness(t, amtEdge(), provisioningSecret())
	h.api.devices[0].ConnectedToControl = false

	h.reconcile(t, "ber1-edge")

	if len(h.amtRuns()) != 0 {
		t.Fatal("dialled a host that is not on the tailnet")
	}
}

func TestRackAMTLooksAtAnActivatedHostOnlyNowAndThen(t *testing.T) {
	host := amtEdge()
	observed := metav1.NewTime(installEpoch.Add(-10 * time.Minute))
	host.Status.AMT = &infrav1.RackLinuxHostAMTStatus{ControlMode: "admin", Address: "192.168.50.112", MEBxPasswordSet: true, ObservedAt: &observed}
	h := newAMTHarness(t, host, provisioningSecret())
	h.runner.reply = func(_, _ string) string {
		return "--- amtinfo\n" + amtInfoJSON("admin control mode", "up", "192.168.50.112")
	}

	h.reconcile(t, "ber1-edge")
	if len(h.amtRuns()) != 0 {
		t.Fatal("looked again 10 minutes after the last look")
	}

	h.now = h.now.Add(time.Hour)
	got := h.reconcile(t, "ber1-edge")
	runs := h.amtRuns()
	if len(runs) != 1 {
		t.Fatalf("ran %d AMT scripts after an hour, want 1", len(runs))
	}
	if strings.Contains(runs[0].script, "AMT_PASSWORD") || strings.Contains(runs[0].script, " activate ") {
		t.Fatal("an activated host was sent the activation")
	}
	if got.Status.AMT.Address != "192.168.50.112" || !conditions.IsTrue(got, AMTActivatedCondition) {
		t.Fatalf("status %+v", got.Status.AMT)
	}
}

func TestAMTScriptParses(t *testing.T) {
	bash, err := exec.LookPath("bash")
	if err != nil {
		t.Skip("no bash")
	}
	for name, activation := range map[string]*amtRun{
		"observe":  nil,
		"activate": {Password: "Aa1!" + strings.Repeat("x", 20), PFX: "UEZY", PFXPassword: "it's"},
	} {
		t.Run(name, func(t *testing.T) {
			path := filepath.Join(t.TempDir(), "amt.sh")
			if err := os.WriteFile(path, []byte(renderAMTScript(activation)), 0o600); err != nil {
				t.Fatal(err)
			}
			if out, err := exec.Command(bash, "-n", path).CombinedOutput(); err != nil {
				t.Fatalf("bash -n: %v\n%s", err, out)
			}
		})
	}
}

func TestAMTPasswordsFollowAMTsRules(t *testing.T) {
	for range 200 {
		p, err := generateAMTPassword()
		if err != nil {
			t.Fatal(err)
		}
		if !validAMTPassword(p) {
			t.Fatalf("%q breaks AMT's rules", p)
		}
	}
	for _, bad := range []string{"Sh1!a", "alllowercase1!xxxxxxxx", "NoDigits!xxxxxxxxxxxx", "NoSpecial1xxxxxxxxxxx", `Has"Quote1xxxxxxxxxxx`, "Aa1!" + strings.Repeat("x", 29)} {
		if validAMTPassword(bad) {
			t.Fatalf("accepted %q", bad)
		}
	}
}

// AMT takes its address by DHCP after the activation, so an activated AMT
// without one is looked at again soon rather than in an hour.
func TestRackAMTLooksAgainSoonForTheAddressOfAFreshlyActivatedAMT(t *testing.T) {
	host := amtEdge()
	observed := metav1.NewTime(installEpoch.Add(-3 * time.Minute))
	host.Status.AMT = &infrav1.RackLinuxHostAMTStatus{ControlMode: "admin", Address: "0.0.0.0", ObservedAt: &observed}
	h := newAMTHarness(t, host, provisioningSecret())
	h.runner.reply = func(_, _ string) string {
		return "--- amtinfo\n" + amtInfoJSON("admin control mode", "up", "192.168.50.112")
	}

	got := h.reconcile(t, "ber1-edge")

	if len(h.amtRuns()) != 1 || got.Status.AMT.Address != "192.168.50.112" {
		t.Fatalf("runs %d status %+v, want AMT's address read again", len(h.amtRuns()), got.Status.AMT)
	}
}

// rpc's own transport to AMT has hung for good before, so the script bounds it
// and reports the timeout as the activation's failure.
func TestAMTScriptBoundsRPC(t *testing.T) {
	script := renderAMTScript(&amtRun{Password: "Aa1!xxxxxxxxxxxxxxxxxxxx", PFX: "UEZY", PFXPassword: "pw"})
	for _, want := range []string{
		`timeout 120 "$rpc" amtinfo --json --ver --mode --lan`,
		`timeout --kill-after=10 300 "$rpc" activate "$@" --skipIPRenew --json`,
		`= 'not activated'`,
	} {
		if !strings.Contains(script, want) {
			t.Fatalf("the script lacks %q:\n%s", want, script)
		}
	}
}

// A host that went to client control mode and failed its upgrade is upgraded
// on the next attempt, after the backoff.
func TestRackAMTUpgradesAHostInClientControlMode(t *testing.T) {
	host := amtEdge()
	tried := metav1.NewTime(installEpoch.Add(-2 * time.Hour))
	host.Status.AMT = &infrav1.RackLinuxHostAMTStatus{ControlMode: "client", Address: "192.168.50.112", ObservedAt: &tried,
		LastActivation: &tried, ActivationError: "rpc activate exit 10: adminsetup failed: returned 5"}
	h := newAMTHarness(t, host, provisioningSecret(), amtSecret("Stored-Pa55!"))
	h.runner.reply = func(_, _ string) string {
		return "--- activate\n{\"status\":\"success\"}\n--- activate exit 0\n--- amtinfo\n" +
			amtInfoJSON("admin control mode", "up", "192.168.50.112")
	}

	got := h.reconcile(t, "ber1-edge")

	runs := h.amtRuns()
	if len(runs) != 1 || !strings.Contains(runs[0].script, "amt_password='Stored-Pa55!'") {
		t.Fatalf("runs %d, want the upgrade with the stored password", len(runs))
	}
	if got.Status.AMT.ControlMode != "admin" || got.Status.AMT.ActivationError != "" || !conditions.IsTrue(got, AMTActivatedCondition) {
		t.Fatalf("status %+v", got.Status.AMT)
	}
}

func adminEdge(address string, mebxSet bool) *infrav1.RackLinuxHost {
	host := amtEdge()
	observed := metav1.NewTime(installEpoch.Add(-10 * time.Minute))
	host.Status.AMT = &infrav1.RackLinuxHostAMTStatus{ControlMode: "admin", Address: address, MEBxPasswordSet: mebxSet, ObservedAt: &observed}
	return host
}

func (h *installHarness) amtSecretData(t *testing.T) map[string][]byte {
	t.Helper()
	secret := &corev1.Secret{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: "ber1-edge-amt"}, secret); err != nil {
		t.Fatal(err)
	}
	return secret.Data
}

// MEBx still has its factory password after the activation; the operator
// replaces it with one it generates and keeps beside AMT's.
func TestRackAMTSetsTheMEBxPasswordOfAnActivatedHost(t *testing.T) {
	h := newAMTHarness(t, adminEdge("192.168.50.112", false), provisioningSecret(), amtSecret("Stored-Pa55!"))
	h.runner.reply = func(_, _ string) string {
		return "--- mebx\n{\"status\":\"success\"}\n--- mebx exit 0\n--- amtinfo\n" + amtInfoJSON("admin control mode", "up", "192.168.50.112")
	}

	got := h.reconcile(t, "ber1-edge")

	data := h.amtSecretData(t)
	mebx := string(data["mebx-password"])
	if !validAMTPassword(mebx) || string(data["password"]) != "Stored-Pa55!" {
		t.Fatalf("secret %v, want a MEBx password beside the kept AMT password", data)
	}
	runs := h.amtRuns()
	if len(runs) != 1 || !strings.Contains(runs[0].script, "mebx_password="+shellSingleQuote(mebx)) ||
		!strings.Contains(runs[0].script, "provisioning_cert=''") {
		t.Fatalf("runs %d, want one carrying the MEBx password and no certificate", len(runs))
	}
	amt := got.Status.AMT
	if !amt.MEBxPasswordSet || amt.LastConfiguration == nil || amt.ConfigurationError != "" {
		t.Fatalf("status %+v", amt)
	}

	h.now = h.now.Add(10 * time.Minute)
	h.reconcile(t, "ber1-edge")
	if n := len(h.amtRuns()); n != 1 {
		t.Fatalf("configured again (%d runs)", n)
	}
}

// A host declaring a static AMT address has AMT moved to it.
func TestRackAMTGivesAMTItsStaticAddress(t *testing.T) {
	host := adminEdge("192.168.50.112", true)
	host.Spec.AMT.Address, host.Spec.AMT.Gateway = "192.168.50.21/24", "192.168.50.1"
	h := newAMTHarness(t, host, provisioningSecret(), amtSecret("Stored-Pa55!"))
	h.runner.reply = func(_, _ string) string {
		return "--- wired\n{\"status\":\"success\"}\n--- wired exit 0\n--- amtinfo\n" + amtInfoJSON("admin control mode", "up", "192.168.50.21")
	}

	got := h.reconcile(t, "ber1-edge")

	runs := h.amtRuns()
	if len(runs) != 1 {
		t.Fatalf("runs %d", len(runs))
	}
	for _, want := range []string{"static_address='192.168.50.21'", "static_mask='255.255.255.0'", "static_gateway='192.168.50.1'", "mebx_password=''"} {
		if !strings.Contains(runs[0].script, want) {
			t.Fatalf("the run lacks %q", want)
		}
	}
	if got.Status.AMT.Address != "192.168.50.21" || got.Status.AMT.ConfigurationError != "" {
		t.Fatalf("status %+v", got.Status.AMT)
	}
}

func TestRackAMTBacksOffAFailedConfiguration(t *testing.T) {
	h := newAMTHarness(t, adminEdge("192.168.50.112", false), provisioningSecret(), amtSecret("Stored-Pa55!"))
	h.runner.reply = func(_, _ string) string {
		return "--- mebx\n{\"error\":\"SetMEBXPasswordFailed\"}\n--- mebx exit 1\n--- amtinfo\n" + amtInfoJSON("admin control mode", "up", "192.168.50.112")
	}

	got := h.reconcile(t, "ber1-edge")
	if got.Status.AMT.MEBxPasswordSet || !strings.Contains(got.Status.AMT.ConfigurationError, "SetMEBXPasswordFailed") {
		t.Fatalf("status %+v", got.Status.AMT)
	}
	if !conditions.IsTrue(got, AMTActivatedCondition) {
		t.Fatal("a failed configuration took AMTActivated down")
	}

	h.now = h.now.Add(30 * time.Minute)
	h.reconcile(t, "ber1-edge")
	if n := len(h.amtRuns()); n != 1 {
		t.Fatalf("tried again after 30 minutes (%d runs)", n)
	}
	h.now = h.now.Add(31 * time.Minute)
	h.reconcile(t, "ber1-edge")
	if n := len(h.amtRuns()); n != 2 {
		t.Fatalf("did not try again after the backoff (%d runs)", n)
	}
}

// Reading AMT's state keeps what the operator recorded of it.
func TestRackAMTKeepsTheLastPowerActionAcrossReads(t *testing.T) {
	host := adminEdge("192.168.50.112", true)
	host.Status.AMT.ObservedAt = &metav1.Time{Time: installEpoch.Add(-2 * time.Hour)}
	host.Status.AMT.LastPowerAction = &infrav1.RackLinuxHostAMTPowerAction{Action: "cycle", At: metav1.NewTime(installEpoch.Add(-time.Hour)), Via: "ber1-edge-b"}
	h := newAMTHarness(t, host, provisioningSecret(), amtSecret("Stored-Pa55!"))
	h.runner.reply = func(_, _ string) string {
		return "--- amtinfo\n" + amtInfoJSON("admin control mode", "up", "192.168.50.112")
	}

	got := h.reconcile(t, "ber1-edge")

	if len(h.amtRuns()) != 1 || got.Status.AMT.LastPowerAction == nil || got.Status.AMT.LastPowerAction.Via != "ber1-edge-b" {
		t.Fatalf("status %+v", got.Status.AMT)
	}
}

// AMT activated by hand after the operator's attempt failed is activated.
func TestRackAMTDropsTheErrorOfAnActivationAMTNoLongerNeeds(t *testing.T) {
	host := adminEdge("192.168.50.112", true)
	host.Status.AMT.ObservedAt = &metav1.Time{Time: installEpoch.Add(-2 * time.Hour)}
	host.Status.AMT.LastActivation = &metav1.Time{Time: installEpoch.Add(-3 * time.Hour)}
	host.Status.AMT.ActivationError = "rpc activate exit 10: adminsetup failed: returned 5"
	h := newAMTHarness(t, host, provisioningSecret(), amtSecret("Stored-Pa55!"))
	h.runner.reply = func(_, _ string) string {
		return "--- amtinfo\n" + amtInfoJSON("admin control mode", "up", "192.168.50.112")
	}

	got := h.reconcile(t, "ber1-edge")

	if got.Status.AMT.ActivationError != "" || got.Status.AMT.LastActivation == nil {
		t.Fatalf("status %+v", got.Status.AMT)
	}
}

func TestRackAMTRefusesAGatewayOutsideTheAddress(t *testing.T) {
	host := adminEdge("192.168.50.112", true)
	host.Spec.AMT.Address, host.Spec.AMT.Gateway = "192.168.50.21/24", "192.168.0.1"
	h := newAMTHarness(t, host, provisioningSecret(), amtSecret("Stored-Pa55!"))

	got := h.reconcile(t, "ber1-edge")

	if c := conditions.Get(got, AMTActivatedCondition); len(h.amtRuns()) != 0 || c == nil || c.Reason != "InvalidAddress" {
		t.Fatalf("runs %d condition %+v", len(h.amtRuns()), c)
	}
}
