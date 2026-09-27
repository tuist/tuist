package macos

import (
	"context"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
)

func withHostEgress(r *RackHostReconciler) *RackHostReconciler {
	r.EgressNamespace = "tailscale-operator"
	r.EgressProxyGroup = "macmini-egress"
	return r
}

func eatonRegistry(d power.Driver) *power.Registry {
	return power.NewRegistryWith(map[string]power.Driver{power.DriverEaton: d})
}

// pduHost is a host on outlet 3 of the RackPDU ber1-pdu-b.
func pduHost(name string) *infrav1.RackHost {
	return rackHost(name, func(h *infrav1.RackHost) {
		h.Spec.Power = &infrav1.PowerOutletRef{PDU: "ber1-pdu-b", Outlet: "3"}
	})
}

func readyPDU(ready bool) *infrav1.RackPDU {
	pdu := &infrav1.RackPDU{
		ObjectMeta: metav1.ObjectMeta{Name: "ber1-pdu-b", Namespace: testNamespace},
		Spec: infrav1.RackPDUSpec{Site: "ber1", Model: "evmafc20a", Address: "192.168.0.16",
			ManagedBy: infrav1.RackPDUManagedByController, OutletStateOnStartup: "on"},
	}
	if ready {
		conditions.MarkTrue(pdu, clusterv1.ReadyCondition)
	} else {
		conditions.MarkFalse(pdu, clusterv1.ReadyCondition, "Unreachable", clusterv1.ConditionSeverityWarning, "dial tcp 192.168.0.16:443: i/o timeout")
	}
	return pdu
}

func pduCredentials() *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: "ber1-pdu-b-credentials", Namespace: testNamespace},
		Data: map[string][]byte{
			"username":         []byte("tuist-controller"),
			"password":         []byte("Hunter2-hunter2"),
			"initial-password": []byte("Initial-pass1"),
			"tlsFingerprint":   []byte("AB:CD"),
		},
	}
}

func TestAnEndpointOfTheHostsOwnIsDialledDirectly(t *testing.T) {
	host := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Spec.Power.CredentialsSecretRef = &corev1.LocalObjectReference{Name: "pdu"}
	})
	secret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: "pdu", Namespace: testNamespace},
		Data:       map[string][]byte{"username": []byte("u"), "password": []byte("p")},
	}
	driver := &credentialRecordingDriver{}
	r := withHostEgress(newRackHostReconciler(t, nil, host, secret))
	r.Power = registryWithShelly(driver)

	reconcileHost(t, r, "mini-01")

	if driver.outlet.Username != "u" || driver.outlet.Host != "192.168.0.50" {
		t.Fatalf("driver saw %+v, want the Secret's username on the host's own endpoint", driver.outlet)
	}
	if driver.outlet.Dial != "" {
		t.Fatalf("Dial = %q; an endpoint of the host's own is dialled directly", driver.outlet.Dial)
	}
}

// An outlet of a RackPDU goes through the PDU's egress Service, with the
// credentials and pin its controller owns.
func TestPDUOutletUsesTheRackPDUsCredentialsAndEgressService(t *testing.T) {
	driver := &credentialRecordingDriver{}
	r := withHostEgress(newRackHostReconciler(t, nil, pduHost("mini-01"), readyPDU(true), pduCredentials()))
	r.Power = eatonRegistry(driver)

	reconcileHost(t, r, "mini-01")

	o := driver.outlet
	if o.Dial != "rackpdu-ber1-pdu-b.tailscale-operator.svc.cluster.local" || o.Host != "https://192.168.0.16" || o.Outlet != "3" {
		t.Fatalf("driver saw %+v, want outlet 3 of https://192.168.0.16 through its egress Service", o)
	}
	if o.Username != "tuist-controller" || o.Password != "Hunter2-hunter2" || o.InitialPassword != "Initial-pass1" || o.TLSFingerprint != "AB:CD" {
		t.Fatalf("driver saw %+v, want the RackPDU's Secret", o)
	}
	if cond := conditionOf(readHost(t, r, "mini-01"), PowerReachableCondition); cond == nil || cond.Status != corev1.ConditionTrue {
		t.Fatalf("PowerReachable = %+v, want True", cond)
	}
}

func TestPowerIsRefusedWhileTheRackPDUIsNotReady(t *testing.T) {
	driver := &stubPowerDriver{on: true}
	host := pduHost("mini-01")
	host.Annotations = map[string]string{PowerActionAnnotation: "on"}
	r := newRackHostReconciler(t, nil, host, readyPDU(false), pduCredentials())
	r.Power = eatonRegistry(driver)

	reconcileHost(t, r, "mini-01")

	got := readHost(t, r, "mini-01")
	cond := conditionOf(got, PowerReachableCondition)
	if cond == nil || cond.Reason != "PDUNotReady" || !strings.Contains(cond.Message, "i/o timeout") {
		t.Fatalf("PowerReachable = %+v, want PDUNotReady naming the RackPDU's own reason", cond)
	}
	if calls := driver.recorded(); len(calls) != 0 {
		t.Fatalf("switched an outlet of a PDU that is not Ready: %v", calls)
	}
	if _, still := got.Annotations[PowerActionAnnotation]; still {
		t.Fatal("the refused action stayed annotated")
	}
}

func TestPowerThroughAMissingRackPDUIsNotReady(t *testing.T) {
	r := newRackHostReconciler(t, nil, pduHost("mini-01"))
	r.Power = eatonRegistry(&stubPowerDriver{on: true})

	reconcileHost(t, r, "mini-01")

	cond := conditionOf(readHost(t, r, "mini-01"), PowerReachableCondition)
	if cond == nil || cond.Reason != "PDUNotReady" || !strings.Contains(cond.Message, "no such RackPDU") {
		t.Fatalf("PowerReachable = %+v", cond)
	}
}

// The bootstrap-recovery reboot reaches a RackPDU's outlet the same way.
func TestBootstrapRecoveryCycleGoesThroughTheRackPDU(t *testing.T) {
	host := pduHost("mini-01")
	r := withEgress(newRackReconciler(t, host, readyPDU(true), pduCredentials()))
	stub := &stubPowerDriver{on: true}
	r.Power = eatonRegistry(stub)

	if err := r.cycleHostPower(context.Background(), host); err != nil {
		t.Fatalf("cycleHostPower: %v", err)
	}
	if got := stub.recorded(); len(got) != 2 {
		t.Fatalf("outlet calls = %v, want off then on", got)
	}

	r = withEgress(newRackReconciler(t, host, readyPDU(false), pduCredentials()))
	r.Power = eatonRegistry(stub)
	if err := r.cycleHostPower(context.Background(), host); err == nil || !strings.Contains(err.Error(), "not Ready") {
		t.Fatalf("cycleHostPower through a PDU that is not Ready = %v", err)
	}
}
