package linux

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/tailnet"
)

// reconcileOrGone reconciles the host and returns it, or nil once it is gone.
func (h *installHarness) reconcileOrGone(t *testing.T, name string) (*infrav1.RackLinuxHost, ctrl.Result) {
	t.Helper()
	res, err := h.r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Namespace: rackTestNamespace, Name: name}})
	if err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	host := &infrav1.RackLinuxHost{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: name}, host); err != nil {
		if apierrors.IsNotFound(err) {
			return nil, res
		}
		t.Fatal(err)
	}
	return host, res
}

func (h *installHarness) deleteHost(t *testing.T, name string) {
	t.Helper()
	host := &infrav1.RackLinuxHost{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: name}, host); err != nil {
		t.Fatal(err)
	}
	if err := h.c.Delete(context.Background(), host); err != nil {
		t.Fatal(err)
	}
}

func (h *installHarness) exists(t *testing.T, obj client.Object, namespace, name string) bool {
	t.Helper()
	err := h.c.Get(context.Background(), types.NamespacedName{Namespace: namespace, Name: name}, obj)
	if apierrors.IsNotFound(err) {
		return false
	}
	if err != nil {
		t.Fatal(err)
	}
	return true
}

func retiringHost(connected bool) *infrav1.RackLinuxHost {
	host := svcHost()
	host.Finalizers = []string{RackLinuxHostFinalizer}
	host.Status.Tailnet = &infrav1.RackLinuxHostTailnetStatus{DeviceID: "ber1-svc-device", Name: "ber1-svc.example.ts.net", Address: "100.64.0.9", Connected: connected}
	return host
}

func consoleSecret(passwords map[string]string) *corev1.Secret {
	data := map[string][]byte{}
	for host, password := range passwords {
		data[host] = []byte(password)
	}
	return &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: rackTestFleet + "-console", Namespace: rackTestNamespace}, Data: data}
}

func egressService(host string) *corev1.Service {
	return &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: rackLinuxEgressName(host), Namespace: "tailscale-operator"}}
}

func TestRackLinuxHostGetsAFinalizer(t *testing.T) {
	h := newInstallHarness(t, svcHost())
	got := h.reconcile(t, svcUUID)
	if !controllerutil.ContainsFinalizer(got, RackLinuxHostFinalizer) {
		t.Fatalf("finalizers %v", got.Finalizers)
	}
}

func TestRackLinuxHostDeleteRetiresAHost(t *testing.T) {
	host := withInstall(retiringHost(false), "kMINT1CNTRL", "ber1-svc-device", installEpoch.Add(-time.Minute), nil)
	h := newInstallHarness(t, host, publishedBoot("kMINT1CNTRL"),
		consoleSecret(map[string]string{svcUUID: "retired", edgeUUID: "kept"}),
		egressService(svcUUID))
	stale := svcDevice("ber1-svc-device-0", "2026-08-01T00:00:00Z", false)
	h.api.devices = []tailnet.Device{
		svcDevice("ber1-svc-device", "2026-09-01T00:00:00Z", false),
		stale,
		edgeDevice("edge", "ber1-edge-a", "2026-09-01T00:00:00Z", true, "100.64.0.7"),
	}
	ctx := context.Background()
	if err := h.r.CredentialsManager.SetMachineHostFingerprint(ctx, rackLinuxPinKey(svcUUID, "ber1-svc-device"), "SHA256:pin"); err != nil {
		t.Fatal(err)
	}

	h.deleteHost(t, svcUUID)
	if got, _ := h.reconcileOrGone(t, svcUUID); got != nil {
		t.Fatalf("host still present with finalizers %v", got.Finalizers)
	}

	if strings.Join(h.api.deleted, ",") != "ber1-svc-device,ber1-svc-device-0" {
		t.Fatalf("deleted devices %v, want the host's own", h.api.deleted)
	}
	boot := h.boot(t)
	if _, ok := boot[svcMACPath+".ipxe"]; ok {
		t.Error("the host's install is still published")
	}
	if _, ok := boot["aa-bb-cc-dd-ee-ff.ipxe"]; !ok {
		t.Error("another host's install was withdrawn")
	}
	console := &corev1.Secret{}
	if !h.exists(t, console, rackTestNamespace, rackTestFleet+"-console") {
		t.Fatal("the console Secret is gone")
	}
	if _, ok := console.Data[svcUUID]; ok || string(console.Data[edgeUUID]) != "kept" {
		t.Fatalf("console keys %v", console.Data)
	}
	if h.exists(t, &corev1.Service{}, "tailscale-operator", rackLinuxEgressName(svcUUID)) {
		t.Error("the egress Service is still there")
	}
	if creds, err := h.r.CredentialsManager.GetMachineBootstrap(ctx, rackLinuxPinKey(svcUUID, "ber1-svc-device")); err != nil || creds != nil {
		t.Errorf("host key pin %+v %v", creds, err)
	}
}

func TestRackLinuxHostDeleteKeepsTheFinalizerWhileTheTailnetFails(t *testing.T) {
	h := newInstallHarness(t, retiringHost(false), consoleSecret(map[string]string{svcUUID: "pw"}))
	h.api.devices = []tailnet.Device{svcDevice("ber1-svc-device", "2026-09-01T00:00:00Z", false)}
	h.api.deleteErr = errors.New("tailnet API down")
	h.deleteHost(t, svcUUID)

	if _, err := h.r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Namespace: rackTestNamespace, Name: svcUUID}}); err == nil {
		t.Fatal("Reconcile succeeded while the device could not be removed")
	}
	host := &infrav1.RackLinuxHost{}
	if !h.exists(t, host, rackTestNamespace, svcUUID) || !controllerutil.ContainsFinalizer(host, RackLinuxHostFinalizer) {
		t.Fatal("the finalizer was dropped")
	}

	h.api.deleteErr = nil
	if got, _ := h.reconcileOrGone(t, svcUUID); got != nil {
		t.Fatalf("host still present with finalizers %v", got.Finalizers)
	}
}

// A deleted host's Machine goes first: its RackLinuxMachine stops the kubelet
// over the tailnet and deletes the Node, so the host's devices stay until the
// Machine is gone.
func TestRackLinuxHostDeleteRemovesItsMachineFirst(t *testing.T) {
	machine := &clusterv1.Machine{ObjectMeta: metav1.ObjectMeta{
		Name: svcUUID, Namespace: rackTestNamespace,
		Finalizers: []string{"machine.cluster.x-k8s.io"},
	}}
	h := newInstallHarness(t, retiringHost(true), machine)
	h.api.devices = []tailnet.Device{svcDevice("ber1-svc-device", "2026-09-01T00:00:00Z", true)}
	h.deleteHost(t, svcUUID)

	got, res := h.reconcileOrGone(t, svcUUID)
	if got == nil || res.RequeueAfter == 0 {
		t.Fatalf("host %v requeue %v; it waits for its Machine", got, res.RequeueAfter)
	}
	if got.Status.Provisioning.State != infrav1.RackLinuxHostDeprovisioning {
		t.Fatalf("provisioning %+v", got.Status.Provisioning)
	}
	deleting := &clusterv1.Machine{}
	if !h.exists(t, deleting, rackTestNamespace, svcUUID) || deleting.DeletionTimestamp.IsZero() {
		t.Fatal("the Machine was not deleted")
	}
	if len(h.api.deleted) != 0 {
		t.Fatalf("deleted devices %v while the Machine still stops the kubelet over the tailnet", h.api.deleted)
	}

	deleting.Finalizers = nil
	if err := h.c.Update(context.Background(), deleting); err != nil {
		t.Fatal(err)
	}
	if got, _ := h.reconcileOrGone(t, svcUUID); got != nil {
		t.Fatalf("host still present with finalizers %v", got.Finalizers)
	}
	if strings.Join(h.api.deleted, ",") != "ber1-svc-device" {
		t.Fatalf("deleted devices %v", h.api.deleted)
	}
}
