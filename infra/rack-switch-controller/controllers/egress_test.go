package controllers

import (
	"context"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	"github.com/tuist/tuist/infra/rack-switch-controller/api/v1alpha1"
)

var testEgress = Egress{Namespace: "tailscale-operator", ProxyGroup: "macmini-egress"}

// withEgress dials through testEgress, whose Service names resolve nowhere
// outside a cluster, so a dial gives up quickly.
func (h *harness) withEgress() {
	h.r.Egress = testEgress
	h.r.PicOS.Dialer.Timeout = 200 * time.Millisecond
}

func (h *harness) egressService(name string) (*corev1.Service, error) {
	var svc corev1.Service
	err := h.client.Get(context.Background(), types.NamespacedName{Namespace: testEgress.Namespace, Name: "rackswitch-" + name}, &svc)
	return &svc, err
}

func TestPicOSSwitchIsDialledThroughItsEgressService(t *testing.T) {
	h, sw := picosHarness(t, picosSwitch("ber2-tor-a", torConfig()))
	h.withEgress()

	h.reconcile("ber2-tor-a")

	svc, err := h.egressService("ber2-tor-a")
	if err != nil {
		t.Fatal(err)
	}
	if svc.Annotations["tailscale.com/tailnet-ip"] != sw.Address() || svc.Annotations["tailscale.com/proxy-group"] != "macmini-egress" {
		t.Fatalf("annotations = %v", svc.Annotations)
	}
	if svc.Spec.Type != corev1.ServiceTypeExternalName || len(svc.Spec.Ports) != 2 ||
		svc.Spec.Ports[0].Port != 22 || svc.Spec.Ports[1].Port != 830 {
		t.Fatalf("spec = %+v", svc.Spec)
	}
	rs := h.get("ber2-tor-a")
	if !controllerutil.ContainsFinalizer(rs, EgressFinalizer) {
		t.Fatalf("finalizers = %v", rs.Finalizers)
	}
	// The Service's name is what was dialled, not the address: nothing
	// resolves it outside a cluster, so the switch was never reached.
	c := condition(rs, v1alpha1.ConditionAdopted)
	if c.Reason != "NotProvisioned" || !strings.Contains(c.Message, "rackswitch-ber2-tor-a.tailscale-operator.svc.cluster.local") {
		t.Fatalf("Adopted = %+v", c)
	}
	if len(sw.Writes()) != 0 {
		t.Fatalf("the switch was written to at its address: %v", sw.Writes())
	}
}

func TestAnEgressServiceFollowsTheManagementAddress(t *testing.T) {
	h, _ := picosHarness(t, picosSwitch("ber2-tor-a", torConfig()))
	h.withEgress()
	h.reconcile("ber2-tor-a")

	h.editSpec("ber2-tor-a", func(s *v1alpha1.RackSwitchSpec) { s.ManagementAddress = "192.168.61.2" })
	h.reconcile("ber2-tor-a")

	svc, err := h.egressService("ber2-tor-a")
	if err != nil {
		t.Fatal(err)
	}
	if svc.Annotations["tailscale.com/tailnet-ip"] != "192.168.61.2" {
		t.Fatalf("tailnet-ip = %q", svc.Annotations["tailscale.com/tailnet-ip"])
	}
}

func TestDeletingAPicOSSwitchDeletesItsEgressService(t *testing.T) {
	h, _ := picosHarness(t, picosSwitch("ber2-tor-a", torConfig()))
	h.withEgress()
	h.reconcile("ber2-tor-a")
	if _, err := h.egressService("ber2-tor-a"); err != nil {
		t.Fatal(err)
	}

	if err := h.client.Delete(context.Background(), h.get("ber2-tor-a")); err != nil {
		t.Fatal(err)
	}
	h.reconcile("ber2-tor-a")

	if _, err := h.egressService("ber2-tor-a"); !apierrors.IsNotFound(err) {
		t.Fatalf("egress Service still there: %v", err)
	}
	var rs v1alpha1.RackSwitch
	if err := h.client.Get(context.Background(), types.NamespacedName{Namespace: namespace, Name: "ber2-tor-a"}, &rs); !apierrors.IsNotFound(err) {
		t.Fatalf("RackSwitch still there: %v, finalizers %v", err, rs.Finalizers)
	}
}

func TestWithoutAnEgressAPicOSSwitchIsDialledAtItsAddress(t *testing.T) {
	h, sw := picosHarness(t, picosSwitch("ber2-tor-a", torConfig()))

	h.reconcile("ber2-tor-a")

	if rs := h.get("ber2-tor-a"); rs.Status.HostKey != sw.HostKeyFingerprint() || len(rs.Finalizers) != 0 {
		t.Fatalf("hostKey %q, finalizers %v", rs.Status.HostKey, rs.Finalizers)
	}
	var services corev1.ServiceList
	if err := h.client.List(context.Background(), &services); err != nil || len(services.Items) != 0 {
		t.Fatalf("services = %v, %v", services.Items, err)
	}
}
