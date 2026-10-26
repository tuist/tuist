package controllers

import (
	"crypto/ed25519"
	"crypto/rand"
	"reflect"
	"strings"
	"testing"
	"time"

	"golang.org/x/crypto/ssh"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/picos"
	"github.com/tuist/tuist/infra/rack-switch-controller/internal/picos/picostest"
)

const adminPassword = "Admin-Pass1"

func picosHarness(t *testing.T, objects ...*v1alpha1.RackSwitch) (*harness, *picostest.Switch) {
	t.Helper()
	_, private, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	signer, err := ssh.NewSignerFromKey(private)
	if err != nil {
		t.Fatal(err)
	}
	sw := picostest.New(t, signer.PublicKey())
	var objs []client.Object
	for _, o := range objects {
		o.Spec.ManagementAddress = sw.Address()
		objs = append(objs, o)
	}
	h := newHarness(t, objs...)
	h.r.Engine = nil
	h.r.PicOS = &picos.Engine{
		Dialer: picos.Dialer{User: "tuist", Signer: signer, Timeout: 5 * time.Second,
			CLIPort: sw.CLIPort(), NetconfPort: sw.NetconfPort()},
		ConfirmAfter: 5 * time.Minute,
	}
	h.r.PicOSAdminPassword = func() (string, error) { return adminPassword, nil }
	return h, sw
}

func picosSwitch(name string, cfg *v1alpha1.SwitchConfig) *v1alpha1.RackSwitch {
	return &v1alpha1.RackSwitch{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: namespace, Generation: 1},
		Spec: v1alpha1.RackSwitchSpec{
			Site:           "ber2",
			Role:           "tor",
			Model:          "s5860-24xmg",
			ApplyOrder:     1,
			ConfigRevision: "rev1",
			MAC:            "64:9d:99:d9:81:0e",
			ManagedBy:      v1alpha1.ManagedByController,
			Driver:         v1alpha1.DriverPicOS,
			Config:         cfg,
		},
	}
}

func torConfig() *v1alpha1.SwitchConfig {
	return &v1alpha1.SwitchConfig{
		Hostname: "ber2-tor-a",
		VLANs:    []v1alpha1.VLAN{{ID: 10, Name: "machines"}},
		LAGs:     []v1alpha1.LAG{{ID: 1, Name: "edge-a", Ports: []int{29, 32}}},
		Ports: []v1alpha1.PortConfig{
			{Port: 1, Description: "ber2-mini-01", NativeVLAN: 10},
			{Port: 29, TaggedVLANs: []int{10}},
			{Port: 32, TaggedVLANs: []int{10}},
		},
	}
}

func TestPicOSAdoptsAndConverges(t *testing.T) {
	h, sw := picosHarness(t, picosSwitch("ber2-tor-a", torConfig()))

	h.reconcile("ber2-tor-a")

	rs := h.get("ber2-tor-a")
	if rs.Status.HostKey != sw.HostKeyFingerprint() {
		t.Fatalf("hostKey = %q, want %q", rs.Status.HostKey, sw.HostKeyFingerprint())
	}
	if sw.Password("admin") != adminPassword {
		t.Fatalf("admin's password = %q", sw.Password("admin"))
	}
	want := []string{
		`set interface aggregate-ethernet ae1 aggregated-ether-options lacp enable true`,
		`set interface aggregate-ethernet ae1 description "edge-a"`,
		`set interface aggregate-ethernet ae1 family ethernet-switching port-mode trunk`,
		`set interface aggregate-ethernet ae1 family ethernet-switching vlan members 10`,
		`set interface gigabit-ethernet te-1/1/1 description "ber2-mini-01"`,
		`set interface gigabit-ethernet te-1/1/1 family ethernet-switching native-vlan-id 10`,
		`set interface gigabit-ethernet te-1/1/29 ether-options 802.3ad ae1`,
		`set interface gigabit-ethernet te-1/1/32 ether-options 802.3ad ae1`,
		`set protocols lacp interface te-1/1/29 rate fast`,
		`set protocols lacp interface te-1/1/32 rate fast`,
		`set system hostname "ber2-tor-a"`,
		`set vlans vlan-id 10 vlan-name "machines"`,
	}
	if got := sw.Lines(); !reflect.DeepEqual(got, want) {
		t.Fatalf("switch config:\n%s\nwant:\n%s", strings.Join(got, "\n"), strings.Join(want, "\n"))
	}
	if sw.Pending() {
		t.Fatal("the commit was left unconfirmed")
	}
	if c := condition(rs, v1alpha1.ConditionConverged); c.Status != metav1.ConditionTrue {
		t.Fatalf("Converged = %+v", c)
	}
	if c := condition(rs, v1alpha1.ConditionReady); c.Status != metav1.ConditionTrue {
		t.Fatalf("Ready = %+v", c)
	}
	if rs.Status.ObservedRevision != "rev1" || !rs.Status.Adopted || !rs.Status.Reachable || rs.Status.Drift != v1alpha1.DriftNone {
		t.Fatalf("status = %+v", rs.Status)
	}

	// Nothing differs any more, so the next pass only reads.
	writes := len(sw.Writes())
	h.reconcile("ber2-tor-a")
	if len(sw.Writes()) != writes {
		t.Fatalf("a matching switch was written to again: %v", sw.Writes()[writes:])
	}
}

func TestPicOSWaitsForZTP(t *testing.T) {
	h, sw := picosHarness(t, picosSwitch("ber2-tor-a", torConfig()))
	sw.Authorize(nil)

	result := h.reconcile("ber2-tor-a")

	rs := h.get("ber2-tor-a")
	if rs.Status.HostKey != "" || rs.Status.Adopted {
		t.Fatalf("status = %+v", rs.Status)
	}
	if c := condition(rs, v1alpha1.ConditionAdopted); c.Reason != "NotProvisioned" {
		t.Fatalf("Adopted = %+v", c)
	}
	if result.RequeueAfter != adoptionPollInterval {
		t.Fatalf("requeue after %v", result.RequeueAfter)
	}
	if len(sw.Writes()) != 0 {
		t.Fatalf("writes = %v", sw.Writes())
	}
}

func TestPicOSRefusesAnotherHostKey(t *testing.T) {
	h, sw := picosHarness(t, picosSwitch("ber2-tor-a", torConfig()))
	rs := h.get("ber2-tor-a")
	rs.Status.HostKey = "SHA256:not-this-switch"
	if err := h.client.Status().Update(t.Context(), rs); err != nil {
		t.Fatal(err)
	}

	h.reconcile("ber2-tor-a")

	rs = h.get("ber2-tor-a")
	if c := condition(rs, v1alpha1.ConditionAdopted); c.Reason != "HostKeyMismatch" {
		t.Fatalf("Adopted = %+v", c)
	}
	if len(sw.Writes()) != 0 || sw.Password("admin") != "" {
		t.Fatalf("a switch with another host key was written to: %v", sw.Writes())
	}
}

func TestPicOSRefusedLineLeavesTheSwitchAlone(t *testing.T) {
	h, sw := picosHarness(t, picosSwitch("ber2-tor-a", torConfig()))
	sw.Refuse(func(line string) bool { return strings.Contains(line, "vlan members") })

	_, err := h.r.Reconcile(t.Context(), request("ber2-tor-a"))
	if err == nil {
		t.Fatal("expected the refusal to surface as an error")
	}

	rs := h.get("ber2-tor-a")
	if c := condition(rs, v1alpha1.ConditionConverged); c.Reason != "ConvergeFailed" || !strings.Contains(c.Message, "vlan members") {
		t.Fatalf("Converged = %+v", c)
	}
	if got := sw.Lines(); len(got) != 0 {
		t.Fatalf("a refused batch changed the switch: %v", got)
	}
	if sw.Password("admin") != adminPassword {
		t.Fatal("adoption should have happened before the refused write")
	}
}

func TestPicOSReportsDriftWithoutWriting(t *testing.T) {
	h, sw := picosHarness(t, picosSwitch("ber2-tor-a", torConfig()))
	h.reconcile("ber2-tor-a")
	writes := len(sw.Writes())

	sw.Load(`set interface gigabit-ethernet te-1/1/1 family ethernet-switching native-vlan-id 4000`)
	h.reconcile("ber2-tor-a")

	rs := h.get("ber2-tor-a")
	if rs.Status.Drift != v1alpha1.DriftDrifted {
		t.Fatalf("drift = %q", rs.Status.Drift)
	}
	if c := condition(rs, v1alpha1.ConditionConverged); c.Reason != "Drifted" || !strings.Contains(c.Message, "native-vlan-id 10") {
		t.Fatalf("Converged = %+v", c)
	}
	if len(sw.Writes()) != writes {
		t.Fatalf("drift was written over: %v", sw.Writes()[writes:])
	}

	// A new revision converges it.
	h.editSpec("ber2-tor-a", func(s *v1alpha1.RackSwitchSpec) { s.ConfigRevision = "rev2" })
	h.reconcile("ber2-tor-a")
	if rs := h.get("ber2-tor-a"); rs.Status.Drift != v1alpha1.DriftNone || rs.Status.ObservedRevision != "rev2" {
		t.Fatalf("status = %+v", rs.Status)
	}
}

func request(name string) ctrl.Request {
	return ctrl.Request{NamespacedName: types.NamespacedName{Namespace: namespace, Name: name}}
}

func TestPicOSConfirmsAnEarlierWrite(t *testing.T) {
	h, sw := picosHarness(t, picosSwitch("ber2-tor-a", torConfig()))
	h.reconcile("ber2-tor-a") // adoption and the first write
	h.editSpec("ber2-tor-a", func(s *v1alpha1.RackSwitchSpec) {
		s.Config.Ports[0].Description = "ber2-mini-01b"
		s.ConfigRevision = "rev2"
	})
	refused := false
	sw.Refuse(func(line string) bool {
		if line == "commit" && !refused {
			refused = true
			return true
		}
		return false
	})

	if _, err := h.r.Reconcile(t.Context(), request("ber2-tor-a")); err == nil {
		t.Fatal("expected the refused confirmation to surface")
	}
	if !sw.Pending() {
		t.Fatal("the write should be waiting for its confirmation")
	}
	if rs := h.get("ber2-tor-a"); rs.Status.ObservedRevision == "rev2" {
		t.Fatal("an unconfirmed write was recorded as converged")
	}

	h.reconcile("ber2-tor-a")

	if sw.Pending() {
		t.Fatal("the earlier write is still unconfirmed")
	}
	rs := h.get("ber2-tor-a")
	if rs.Status.ObservedRevision != "rev2" || condition(rs, v1alpha1.ConditionConverged).Status != metav1.ConditionTrue {
		t.Fatalf("status = %+v", rs.Status)
	}
}

// slowGroup is the SFP28 group as an S5860's ZTP bootstrap leaves it, at 10G.
var slowGroup = []string{
	"set interface gigabit-ethernet te-1/1/29 speed 10000",
	"set interface gigabit-ethernet te-1/1/30 speed 10000",
	"set interface gigabit-ethernet te-1/1/31 speed 10000",
	"set interface gigabit-ethernet te-1/1/32 speed 10000",
}

// A spec that names no speeds takes the SFP28 group back to its 25G default,
// all four ports in one commit, which is the only one the switch takes.
func TestPicOSPutsTheSFP28GroupBackAtItsDefault(t *testing.T) {
	h, sw := picosHarness(t, picosSwitch("ber2-tor-a", &v1alpha1.SwitchConfig{Hostname: "ber2-tor-a"}))
	sw.Load(slowGroup...)

	h.reconcile("ber2-tor-a")

	if rs := h.get("ber2-tor-a"); rs.Status.Drift != v1alpha1.DriftNone {
		t.Fatalf("status = %+v", rs.Status)
	}
	for _, l := range sw.Lines() {
		if strings.Contains(l, " speed ") {
			t.Fatalf("a speed the spec does not name stayed: %v", sw.Lines())
		}
	}
}

func TestPicOSWritesTheSpeedsTheSpecNames(t *testing.T) {
	cfg := &v1alpha1.SwitchConfig{Hostname: "ber2-tor-a"}
	for port := 29; port <= 32; port++ {
		cfg.Ports = append(cfg.Ports, v1alpha1.PortConfig{Port: port, Speed: 10000})
	}
	h, sw := picosHarness(t, picosSwitch("ber2-tor-a", cfg))

	h.reconcile("ber2-tor-a")

	var speeds []string
	for _, l := range sw.Lines() {
		if strings.Contains(l, " speed ") {
			speeds = append(speeds, l)
		}
	}
	if !reflect.DeepEqual(speeds, slowGroup) {
		t.Fatalf("speeds %v, want %v", speeds, slowGroup)
	}
}

// The switch refuses an SFP28 group at two speeds, and the refusal surfaces.
func TestPicOSReportsASpeedTheGroupRefuses(t *testing.T) {
	cfg := &v1alpha1.SwitchConfig{Hostname: "ber2-tor-a", Ports: []v1alpha1.PortConfig{{Port: 32, Speed: 1000}}}
	h, sw := picosHarness(t, picosSwitch("ber2-tor-a", cfg))

	if _, err := h.r.Reconcile(t.Context(), request("ber2-tor-a")); err == nil {
		t.Fatal("expected the refused commit to surface as an error")
	}
	rs := h.get("ber2-tor-a")
	if c := condition(rs, v1alpha1.ConditionConverged); c.Reason != "ConvergeFailed" || !strings.Contains(c.Message, "25G or 10G/1G") {
		t.Fatalf("Converged = %+v", c)
	}
	if got := sw.Lines(); len(got) != 0 {
		t.Fatalf("a refused commit changed the switch: %v", got)
	}
}
