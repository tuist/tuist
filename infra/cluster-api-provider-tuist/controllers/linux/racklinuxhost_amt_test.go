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
			amtInfoJSON("activated in admin control mode", "up", "192.168.50.112")
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
		"export AMT_PASSWORD=" + shellSingleQuote(password),
		"export PROVISIONING_CERT='UEZYQkFTRTY0'",
		"export PROVISIONING_CERT_PASSWORD='pfx-pass'",
		`"$rpc" activate -local -acm -skipIPRenew -json`,
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
			amtInfoJSON("pre-provisioning state", "up", "0.0.0.0")
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
	if !strings.Contains(runs[1].script, "export AMT_PASSWORD="+shellSingleQuote(password)) {
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
	host.Status.AMT = &infrav1.RackLinuxHostAMTStatus{ControlMode: "admin", Address: "192.168.50.112", ObservedAt: &observed}
	h := newAMTHarness(t, host, provisioningSecret())
	h.runner.reply = func(_, _ string) string {
		return "--- amtinfo\n" + amtInfoJSON("activated in admin control mode", "up", "192.168.50.112")
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
	for name, activation := range map[string]*amtActivation{
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
		return "--- amtinfo\n" + amtInfoJSON("activated in admin control mode", "up", "192.168.50.112")
	}

	got := h.reconcile(t, "ber1-edge")

	if len(h.amtRuns()) != 1 || got.Status.AMT.Address != "192.168.50.112" {
		t.Fatalf("runs %d status %+v, want AMT's address read again", len(h.amtRuns()), got.Status.AMT)
	}
}
