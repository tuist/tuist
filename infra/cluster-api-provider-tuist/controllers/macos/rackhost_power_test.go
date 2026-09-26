package macos

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
)

func withHostEgress(r *RackHostReconciler) *RackHostReconciler {
	r.EgressNamespace = "tailscale-operator"
	r.EgressProxyGroup = "macmini-egress"
	return r
}

func eatonHost(name string) *infrav1.RackHost {
	return rackHost(name, func(h *infrav1.RackHost) {
		h.Spec.Power = &infrav1.PowerOutletRef{
			Driver:               power.DriverEaton,
			Host:                 "https://192.168.0.16",
			Outlet:               "1",
			CredentialsSecretRef: &corev1.LocalObjectReference{Name: "pdu"},
		}
	})
}

func pduSecret() *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: "pdu", Namespace: testNamespace},
		Data: map[string][]byte{
			"username":       []byte("tuist-controller"),
			"password":       []byte("hunter2"),
			"tlsFingerprint": []byte("AB:CD"),
		},
	}
}

func eatonRegistry(d power.Driver) *power.Registry {
	return power.NewRegistryWith(map[string]power.Driver{power.DriverEaton: d})
}

func getEgressService(t *testing.T, r *RackHostReconciler, name string) (*corev1.Service, bool) {
	t.Helper()
	svc := &corev1.Service{}
	err := r.Get(context.Background(), types.NamespacedName{Namespace: "tailscale-operator", Name: name}, svc)
	if apierrors.IsNotFound(err) {
		return nil, false
	}
	if err != nil {
		t.Fatalf("get Service %s: %v", name, err)
	}
	return svc, true
}

func TestPowerTLSFingerprintIsReadFromTheSecret(t *testing.T) {
	driver := &credentialRecordingDriver{}
	r := newRackHostReconciler(t, nil, eatonHost("mini-01"), pduSecret())
	r.Power = eatonRegistry(driver)

	reconcileHost(t, r, "mini-01")

	if driver.outlet.TLSFingerprint != "AB:CD" || driver.outlet.Username != "tuist-controller" {
		t.Fatalf("driver saw %+v, want the Secret's username and tlsFingerprint", driver.outlet)
	}
	if driver.outlet.Dial != "" {
		t.Fatalf("Dial = %q without an egress; the PDU is dialled directly", driver.outlet.Dial)
	}
}

// A Pod has no route to the rack's management LAN, so the PDU is dialled
// through an egress Service fronting its address, as a host's SSH is.
func TestPDUIsDialledThroughItsEgressService(t *testing.T) {
	driver := &credentialRecordingDriver{}
	r := withHostEgress(newRackHostReconciler(t, nil, eatonHost("mini-01"), pduSecret()))
	r.Power = eatonRegistry(driver)

	reconcileHost(t, r, "mini-01")

	if want := "pdu-192-168-0-16.tailscale-operator.svc.cluster.local"; driver.outlet.Dial != want {
		t.Fatalf("Dial = %q, want %q", driver.outlet.Dial, want)
	}
	if driver.outlet.Host != "https://192.168.0.16" {
		t.Fatalf("Host = %q; the PDU keeps its own address, which keys its session", driver.outlet.Host)
	}
	svc, ok := getEgressService(t, r, "pdu-192-168-0-16")
	if !ok {
		t.Fatal("no egress Service for the PDU")
	}
	if svc.Annotations["tailscale.com/tailnet-ip"] != "192.168.0.16" || svc.Annotations["tailscale.com/proxy-group"] != "macmini-egress" {
		t.Fatalf("annotations = %v", svc.Annotations)
	}
	if svc.Spec.Type != corev1.ServiceTypeExternalName {
		t.Fatalf("type = %q", svc.Spec.Type)
	}
	if len(svc.Spec.Ports) != 1 || svc.Spec.Ports[0].Port != 443 {
		t.Fatalf("ports = %+v, want only :443 for an HTTPS PDU", svc.Spec.Ports)
	}
	if _, scraped := svc.Labels["tuist.dev/macmini-egress"]; scraped {
		t.Fatal("labelled for alloy discovery; a PDU serves no metrics there")
	}
}

func TestPlainHTTPPowerEndpointGetsPort80(t *testing.T) {
	driver := &credentialRecordingDriver{}
	r := withHostEgress(newRackHostReconciler(t, nil, rackHost("mini-01")))
	r.Power = registryWithShelly(driver)

	reconcileHost(t, r, "mini-01")

	svc, ok := getEgressService(t, r, "pdu-192-168-0-50")
	if !ok {
		t.Fatal("no egress Service for the plug")
	}
	if len(svc.Spec.Ports) != 1 || svc.Spec.Ports[0].Port != 80 {
		t.Fatalf("ports = %+v, want only :80", svc.Spec.Ports)
	}
	if driver.outlet.Dial != "pdu-192-168-0-50.tailscale-operator.svc.cluster.local" {
		t.Fatalf("Dial = %q", driver.outlet.Dial)
	}
}

// An endpoint named by a hostname has no address to front, so it is dialled
// as it is.
func TestPowerEndpointNamedByHostnameIsDialledDirectly(t *testing.T) {
	driver := &credentialRecordingDriver{}
	host := rackHost("mini-01", func(h *infrav1.RackHost) { h.Spec.Power.Host = "plug.rack.lan" })
	r := withHostEgress(newRackHostReconciler(t, nil, host))
	r.Power = registryWithShelly(driver)

	reconcileHost(t, r, "mini-01")

	if driver.outlet.Dial != "" {
		t.Fatalf("Dial = %q, want none", driver.outlet.Dial)
	}
	services := &corev1.ServiceList{}
	if err := r.List(context.Background(), services); err != nil {
		t.Fatal(err)
	}
	if len(services.Items) != 0 {
		t.Fatalf("made %d Services for an endpoint with no address", len(services.Items))
	}
}

// Several hosts share one PDU, so its Service is only unused once the last of
// them is gone.
func TestPDUEgressServiceOutlivesAnyOneHostOnIt(t *testing.T) {
	unrelated := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: "rack-mini-01", Namespace: "tailscale-operator"}}
	r := withHostEgress(newRackHostReconciler(t, nil, eatonHost("mini-01"), eatonHost("mini-02"), pduSecret(), unrelated))
	r.Power = eatonRegistry(&credentialRecordingDriver{})

	reconcileHost(t, r, "mini-01")
	reconcileHost(t, r, "mini-02")

	if err := r.Delete(context.Background(), readHost(t, r, "mini-01")); err != nil {
		t.Fatalf("delete mini-01: %v", err)
	}
	reconcileHost(t, r, "mini-01")
	if _, ok := getEgressService(t, r, "pdu-192-168-0-16"); !ok {
		t.Fatal("deleted the PDU's Service while mini-02 is still plugged into it")
	}

	if err := r.Delete(context.Background(), readHost(t, r, "mini-02")); err != nil {
		t.Fatalf("delete mini-02: %v", err)
	}
	reconcileHost(t, r, "mini-02")
	if _, ok := getEgressService(t, r, "pdu-192-168-0-16"); ok {
		t.Fatal("kept the PDU's Service after the last host on it was deleted")
	}
	if _, ok := getEgressService(t, r, "rack-mini-01"); !ok {
		t.Fatal("deleted a Service that is not a PDU's")
	}
}

func TestPDUEgressServiceFollowsTheHostsOutlet(t *testing.T) {
	r := withHostEgress(newRackHostReconciler(t, nil, eatonHost("mini-01"), pduSecret()))
	r.Power = eatonRegistry(&credentialRecordingDriver{})
	reconcileHost(t, r, "mini-01")

	host := readHost(t, r, "mini-01")
	host.Spec.Power.Host = "192.168.0.17"
	if err := r.Update(context.Background(), host); err != nil {
		t.Fatalf("update: %v", err)
	}
	reconcileHost(t, r, "mini-01")

	if _, ok := getEgressService(t, r, "pdu-192-168-0-16"); ok {
		t.Fatal("kept the Service of a PDU no host names")
	}
	if _, ok := getEgressService(t, r, "pdu-192-168-0-17"); !ok {
		t.Fatal("no Service for the PDU the host moved to")
	}
}

// The bootstrap-recovery reboot reaches the PDU the same way the RackHost
// controller does.
func TestBootstrapRecoveryCycleDialsThePDUEgressService(t *testing.T) {
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) {
		m.Status.BootstrapAttempts = 2
	})
	host := eatonHost("mini-01")
	r := withEgress(newRackReconciler(t, host, machine, pduSecret()))
	driver := &credentialRecordingDriver{}
	r.Power = eatonRegistry(driver)

	if err := r.cycleHostPower(context.Background(), host); err == nil {
		t.Fatal("a cycle against an outlet that never reads Off reported success")
	}
	if driver.outlet.Dial != "pdu-192-168-0-16.tailscale-operator.svc.cluster.local" || driver.outlet.TLSFingerprint != "AB:CD" {
		t.Fatalf("driver saw %+v, want the PDU's egress Service and the Secret's fingerprint", driver.outlet)
	}

	stub := &stubPowerDriver{on: true}
	r.Power = eatonRegistry(stub)
	if err := r.cycleHostPower(context.Background(), host); err != nil {
		t.Fatalf("cycleHostPower: %v", err)
	}
	if got := stub.recorded(); len(got) != 2 {
		t.Fatalf("outlet calls = %v, want off then on", got)
	}
}

func TestPDUEndpoint(t *testing.T) {
	for _, tc := range []struct {
		ref     infrav1.PowerOutletRef
		address string
		port    int32
		ok      bool
	}{
		{infrav1.PowerOutletRef{Driver: power.DriverEaton, Host: "192.168.0.16"}, "192.168.0.16", 443, true},
		{infrav1.PowerOutletRef{Driver: power.DriverEaton, Host: "https://192.168.0.16"}, "192.168.0.16", 443, true},
		{infrav1.PowerOutletRef{Driver: power.DriverEaton, Host: "http://192.168.0.16"}, "192.168.0.16", 80, true},
		{infrav1.PowerOutletRef{Driver: power.DriverShelly, Host: "192.168.0.50"}, "192.168.0.50", 80, true},
		{infrav1.PowerOutletRef{Driver: power.DriverShelly, Host: "192.168.0.50:8080"}, "192.168.0.50", 8080, true},
		{infrav1.PowerOutletRef{Driver: power.DriverEaton, Host: "pdu.rack.lan"}, "", 0, false},
		{infrav1.PowerOutletRef{Driver: power.DriverEaton}, "", 0, false},
	} {
		address, port, ok := pduEndpoint(&tc.ref)
		if address != tc.address || port != tc.port || ok != tc.ok {
			t.Errorf("pduEndpoint(%+v) = %q, %d, %t; want %q, %d, %t", tc.ref, address, port, ok, tc.address, tc.port, tc.ok)
		}
	}
	if _, _, ok := pduEndpoint(nil); ok {
		t.Error("pduEndpoint(nil) reported an endpoint")
	}
}
