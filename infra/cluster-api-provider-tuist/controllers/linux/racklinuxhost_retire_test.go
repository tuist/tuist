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
	"k8s.io/utils/ptr"
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

func retiringHost(name string, connected bool) *infrav1.RackLinuxHost {
	host := svcHost()
	host.Name = name
	host.Finalizers = []string{RackLinuxHostFinalizer}
	host.Status.Tailnet = &infrav1.RackLinuxHostTailnetStatus{DeviceID: name + "-device", Name: name + ".example.ts.net", Address: "100.64.0.9", Connected: connected}
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
	got := h.reconcile(t, "ber1-svc")
	if !controllerutil.ContainsFinalizer(got, RackLinuxHostFinalizer) {
		t.Fatalf("finalizers %v", got.Finalizers)
	}
}

func TestRackLinuxHostDeleteRetiresAnUnclaimedHost(t *testing.T) {
	host := withInstall(retiringHost("ber1-svc", false), "kMINT1CNTRL", "ber1-svc-device", installEpoch.Add(-time.Minute), nil)
	h := newInstallHarness(t, host, publishedBoot("kMINT1CNTRL"),
		consoleSecret(map[string]string{"ber1-svc": "retired", "ber1-edge-a": "kept"}),
		egressService("ber1-svc"))
	stale := svcDevice("ber1-svc-device-0", "2026-08-01T00:00:00Z", false)
	h.api.devices = []tailnet.Device{
		svcDevice("ber1-svc-device", "2026-09-01T00:00:00Z", false),
		stale,
		edgeDevice("edge", "ber1-edge-a", "2026-09-01T00:00:00Z", true, "100.64.0.7"),
	}
	ctx := context.Background()
	if err := h.r.CredentialsManager.SetMachineHostFingerprint(ctx, rackLinuxPinKey("ber1-svc", "ber1-svc-device"), "SHA256:pin"); err != nil {
		t.Fatal(err)
	}

	h.deleteHost(t, "ber1-svc")
	if got, _ := h.reconcileOrGone(t, "ber1-svc"); got != nil {
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
	if _, ok := console.Data["ber1-svc"]; ok || string(console.Data["ber1-edge-a"]) != "kept" {
		t.Fatalf("console keys %v", console.Data)
	}
	if h.exists(t, &corev1.Service{}, "tailscale-operator", rackLinuxEgressName("ber1-svc")) {
		t.Error("the egress Service is still there")
	}
	if creds, err := h.r.CredentialsManager.GetMachineBootstrap(ctx, rackLinuxPinKey("ber1-svc", "ber1-svc-device")); err != nil || creds != nil {
		t.Errorf("host key pin %+v %v", creds, err)
	}
}

func TestRackLinuxHostDeleteKeepsTheFinalizerWhileTheTailnetFails(t *testing.T) {
	h := newInstallHarness(t, retiringHost("ber1-svc", false), consoleSecret(map[string]string{"ber1-svc": "pw"}))
	h.api.devices = []tailnet.Device{svcDevice("ber1-svc-device", "2026-09-01T00:00:00Z", false)}
	h.api.deleteErr = errors.New("tailnet API down")
	h.deleteHost(t, "ber1-svc")

	if _, err := h.r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Namespace: rackTestNamespace, Name: "ber1-svc"}}); err == nil {
		t.Fatal("Reconcile succeeded while the device could not be removed")
	}
	host := &infrav1.RackLinuxHost{}
	if !h.exists(t, host, rackTestNamespace, "ber1-svc") || !controllerutil.ContainsFinalizer(host, RackLinuxHostFinalizer) {
		t.Fatal("the finalizer was dropped")
	}

	h.api.deleteErr = nil
	if got, _ := h.reconcileOrGone(t, "ber1-svc"); got != nil {
		t.Fatalf("host still present with finalizers %v", got.Finalizers)
	}
}

func rackLinuxMachineOf(name, machine string) *infrav1.RackLinuxMachine {
	return &infrav1.RackLinuxMachine{ObjectMeta: metav1.ObjectMeta{
		Name:      name,
		Namespace: rackTestNamespace,
		OwnerReferences: []metav1.OwnerReference{{
			APIVersion: clusterv1.GroupVersion.String(),
			Kind:       "Machine",
			Name:       machine,
			UID:        types.UID(machine + "-uid"),
		}},
	}}
}

func capiMachine(name, deployment string) *clusterv1.Machine {
	return &clusterv1.Machine{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: rackTestNamespace, Labels: map[string]string{clusterv1.MachineDeploymentNameLabel: deployment}},
		Spec:       clusterv1.MachineSpec{ClusterName: "tuist-capi"},
	}
}

func poolHost(name string, connected bool, claimedBy string) *infrav1.RackLinuxHost {
	host := svcHost()
	host.Name = name
	host.Spec.BootMAC = ""
	host.Status.ClaimedBy = claimedBy
	host.Status.Tailnet = &infrav1.RackLinuxHostTailnetStatus{DeviceID: name + "-device", Address: "100.64.0.30", Connected: connected}
	return host
}

func (h *installHarness) releaseClaim(t *testing.T, name string) {
	t.Helper()
	host := &infrav1.RackLinuxHost{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: name}, host); err != nil {
		t.Fatal(err)
	}
	host.Status.ClaimedBy = ""
	host.Status.ClaimedAt = nil
	if err := h.c.Status().Update(context.Background(), host); err != nil {
		t.Fatal(err)
	}
}

func TestRackLinuxHostDeleteScalesItsPoolDownAroundItsMachine(t *testing.T) {
	host := retiringHost("ber1-svc", true)
	host.Status.ClaimedBy = "svc-0"
	h := newInstallHarness(t, host,
		poolHost("ber1-svc-2", false, "svc-1"),
		poolHost("ber1-svc-3", false, ""),
		rackLinuxMachineOf("svc-0", "svc-m0"), capiMachine("svc-m0", "svc"),
		rackLinuxMachineOf("svc-1", "svc-m1"), capiMachine("svc-m1", "svc"),
		poolDeployment("svc", "ber1-staging-services", 2))
	h.api.devices = []tailnet.Device{svcDevice("ber1-svc-device", "2026-09-01T00:00:00Z", true)}
	h.deleteHost(t, "ber1-svc")

	got, res := h.reconcileOrGone(t, "ber1-svc")
	if got == nil || !controllerutil.ContainsFinalizer(got, RackLinuxHostFinalizer) || res.RequeueAfter == 0 {
		t.Fatalf("host %v result %+v, want it kept, and looked at again, while its machine holds it", got, res)
	}
	machine := &clusterv1.Machine{}
	if !h.exists(t, machine, rackTestNamespace, "svc-m0") || machine.Annotations[clusterv1.DeleteMachineAnnotation] != "true" {
		t.Fatalf("machine annotations %v, want it marked for the MachineSet to delete", machine.Annotations)
	}
	other := &clusterv1.Machine{}
	if !h.exists(t, other, rackTestNamespace, "svc-m1") || other.Annotations[clusterv1.DeleteMachineAnnotation] != "" {
		t.Fatal("another host's machine was touched")
	}
	md := &clusterv1.MachineDeployment{}
	if !h.exists(t, md, rackTestNamespace, "svc") || *md.Spec.Replicas != 1 {
		t.Fatalf("replicas %d, want 1: the host off the tailnet that holds a machine keeps it", *md.Spec.Replicas)
	}
	if len(h.api.deleted) != 0 {
		t.Fatalf("deleted %v while the host's machine still needs to reach it", h.api.deleted)
	}

	got, _ = h.reconcileOrGone(t, "ber1-svc")
	if got == nil {
		t.Fatal("host gone while still claimed")
	}

	h.releaseClaim(t, "ber1-svc")
	if got, _ := h.reconcileOrGone(t, "ber1-svc"); got != nil {
		t.Fatalf("host still present with finalizers %v", got.Finalizers)
	}
	if strings.Join(h.api.deleted, ",") != "ber1-svc-device" {
		t.Fatalf("deleted %v", h.api.deleted)
	}
}

func TestRackLinuxHostDeleteReplacesTheMachineOfAHostItsPoolKeeps(t *testing.T) {
	host := retiringHost("ber1-svc", true)
	host.Status.ClaimedBy = "svc-0"
	h := newInstallHarness(t, host,
		poolHost("ber1-svc-2", true, ""),
		rackLinuxMachineOf("svc-0", "svc-m0"), capiMachine("svc-m0", "svc"),
		poolDeployment("svc", "ber1-staging-services", 1))
	h.deleteHost(t, "ber1-svc")

	got, res := h.reconcileOrGone(t, "ber1-svc")
	if got == nil || !controllerutil.ContainsFinalizer(got, RackLinuxHostFinalizer) || res.RequeueAfter == 0 {
		t.Fatalf("host %v result %+v", got, res)
	}
	if h.exists(t, &clusterv1.Machine{}, rackTestNamespace, "svc-m0") {
		t.Fatal("the machine was not deleted")
	}
	md := &clusterv1.MachineDeployment{}
	if !h.exists(t, md, rackTestNamespace, "svc") || *md.Spec.Replicas != 1 {
		t.Fatalf("replicas %d, want 1 so the replacement claims ber1-svc-2", *md.Spec.Replicas)
	}
}

func TestRackPoolScaleUpIgnoresADeletingHost(t *testing.T) {
	deleting := poolHost("ber1-svc-2", true, "svc-1")
	deleting.Finalizers = []string{RackLinuxHostFinalizer}
	now := metav1.NewTime(installEpoch)
	deleting.DeletionTimestamp = &now
	h := newInstallHarness(t, svcHost(), deleting, poolDeployment("svc", "ber1-staging-services", 1))
	h.api.devices = []tailnet.Device{svcDevice("new", "2026-09-24T07:50:00Z", true)}
	h.reconcile(t, "ber1-svc")
	md := &clusterv1.MachineDeployment{}
	if !h.exists(t, md, rackTestNamespace, "svc") || *md.Spec.Replicas != 1 {
		t.Fatalf("replicas %d, want 1: a host being retired is not one to join", *md.Spec.Replicas)
	}
}

func rackPoolMD(name, pool, template string, replicas, observed int32, created time.Time) *clusterv1.MachineDeployment {
	md := poolDeployment(name, pool, replicas)
	md.CreationTimestamp = metav1.NewTime(created)
	md.Status.Replicas = observed
	md.Spec.Template.Spec.InfrastructureRef = corev1.ObjectReference{
		APIVersion: infrav1.GroupVersion.String(),
		Kind:       "RackLinuxMachineTemplate",
		Name:       template,
	}
	return md
}

func rackTemplate(name string) *infrav1.RackLinuxMachineTemplate {
	return &infrav1.RackLinuxMachineTemplate{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: rackTestNamespace}}
}

func TestRackPoolCleanupDeletesAnEmptyPool(t *testing.T) {
	old := installEpoch.Add(-time.Hour)
	h := newInstallHarness(t, edgeHost(),
		rackPoolMD("tuist-tuist-rack-linux-services", "ber1-staging-services", "services-aaaa1111", 0, 0, old), rackTemplate("services-aaaa1111"),
		rackPoolMD("tuist-tuist-rack-linux-edge", "ber1-staging-edge", "edge-bbbb2222", 0, 0, old), rackTemplate("edge-bbbb2222"),
		rackPoolMD("retired-edge", "ber1-retired-edge", "edge-bbbb2222", 0, 0, old),
		rackPoolMD("storage", "ber1-staging-storage", "storage-cccc3333", 0, 0, old), rackTemplate("storage-cccc3333"), capiMachine("storage-m0", "storage"),
		rackPoolMD("draining", "ber1-staging-draining", "draining-dddd4444", 0, 1, old), rackTemplate("draining-dddd4444"),
		rackPoolMD("scaled", "ber1-staging-scaled", "scaled-eeee5555", 1, 1, old), rackTemplate("scaled-eeee5555"),
		rackPoolMD("fresh", "ber1-staging-fresh", "fresh-ffff6666", 0, 0, installEpoch.Add(-time.Minute)), rackTemplate("fresh-ffff6666"),
		&clusterv1.MachineDeployment{ObjectMeta: metav1.ObjectMeta{Name: "not-a-rack-pool", Namespace: rackTestNamespace, CreationTimestamp: metav1.NewTime(old)},
			Spec: clusterv1.MachineDeploymentSpec{ClusterName: "tuist-capi", Replicas: ptr.To(int32(0))}},
		func() *clusterv1.MachineDeployment {
			md := rackPoolMD("rack-minis", "ber1-staging-minis", "minis-gggg7777", 0, 0, old)
			md.Spec.Template.Spec.InfrastructureRef.Kind = "RackAppleSiliconMachineTemplate"
			return md
		}(),
	)
	h.reconcile(t, "ber1-edge")

	for name, want := range map[string]bool{
		"tuist-tuist-rack-linux-services": false,
		"retired-edge":                    false,
		"tuist-tuist-rack-linux-edge":     true,
		"storage":                         true,
		"draining":                        true,
		"scaled":                          true,
		"fresh":                           true,
		"not-a-rack-pool":                 true,
		"rack-minis":                      true,
	} {
		if got := h.exists(t, &clusterv1.MachineDeployment{}, rackTestNamespace, name); got != want {
			t.Errorf("MachineDeployment %s exists=%v, want %v", name, got, want)
		}
	}
	for name, want := range map[string]bool{
		"services-aaaa1111": false,
		"edge-bbbb2222":     true,
		"storage-cccc3333":  true,
		"draining-dddd4444": true,
		"scaled-eeee5555":   true,
		"fresh-ffff6666":    true,
	} {
		if got := h.exists(t, &infrav1.RackLinuxMachineTemplate{}, rackTestNamespace, name); got != want {
			t.Errorf("RackLinuxMachineTemplate %s exists=%v, want %v", name, got, want)
		}
	}
}

func TestRackPoolCleanupRunsWhenAHostIsGone(t *testing.T) {
	h := newInstallHarness(t,
		rackPoolMD("tuist-tuist-rack-linux-services", "ber1-staging-services", "services-aaaa1111", 0, 0, installEpoch.Add(-time.Hour)),
		rackTemplate("services-aaaa1111"))
	if _, err := h.r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Namespace: rackTestNamespace, Name: "ber1-svc"}}); err != nil {
		t.Fatal(err)
	}
	if h.exists(t, &clusterv1.MachineDeployment{}, rackTestNamespace, "tuist-tuist-rack-linux-services") {
		t.Fatal("the empty pool's MachineDeployment is still there")
	}
	if h.exists(t, &infrav1.RackLinuxMachineTemplate{}, rackTestNamespace, "services-aaaa1111") {
		t.Fatal("its template is still there")
	}
}
