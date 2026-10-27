package macos

import (
	"context"
	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
	appsv1 "k8s.io/api/apps/v1"
	coordinationv1 "k8s.io/api/coordination/v1"
	corev1 "k8s.io/api/core/v1"
	policyv1 "k8s.io/api/policy/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	"os/exec"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/client/interceptor"
	"testing"
	"time"
)

type scalewayUpdateFixture struct {
	t     *testing.T
	r     *ScalewayAppleSiliconMachineReconciler
	m     *infrav1.ScalewayAppleSiliconMachine
	host  *fakeOSUpdateHost
	creds *credentials.MachineBootstrap
}

func newScalewayUpdateFixture(t *testing.T) *scalewayUpdateFixture {
	t.Helper()
	scheme := runtime.NewScheme()
	for _, add := range []func(*runtime.Scheme) error{corev1.AddToScheme, coordinationv1.AddToScheme, appsv1.AddToScheme, clusterv1.AddToScheme, infrav1.AddToScheme} {
		if err := add(scheme); err != nil {
			t.Fatal(err)
		}
	}
	replicas := int32(2)
	dep := &appsv1.Deployment{ObjectMeta: metav1.ObjectMeta{Name: "processor", Namespace: "tuist"}, Spec: appsv1.DeploymentSpec{Replicas: &replicas, Template: corev1.PodTemplateSpec{Spec: corev1.PodSpec{NodeSelector: map[string]string{"tuist.dev/fleet": "processors"}}}}, Status: appsv1.DeploymentStatus{Replicas: 2, UpdatedReplicas: 2, AvailableReplicas: 2}}
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "mini"}, Status: corev1.NodeStatus{Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}}}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(dep, node, scalewayProcessorPod("own", "mini"), scalewayProcessorPod("peer", "other")).Build()
	host := newFakeOSUpdateHost()
	r := &ScalewayAppleSiliconMachineReconciler{Client: c, ProcessorDeploymentName: "processor", Recorder: record.NewFakeRecorder(100), FleetConfig: bootstrap.Config{TartVersion: "2.32.0"}}
	r.osUpdateDial = func(_, _ string, _ []byte, fingerprint string) (osUpdateHost, error) {
		if fingerprint != "pin" {
			t.Fatalf("lost pin %q", fingerprint)
		}
		return host, nil
	}
	m := &infrav1.ScalewayAppleSiliconMachine{ObjectMeta: metav1.ObjectMeta{Name: "mini", Namespace: "tuist", UID: "machine-uid", Annotations: map[string]string{OSUpdateAnnotation: "26.7"}}, Spec: infrav1.ScalewayAppleSiliconMachineSpec{FleetName: "processors"}}
	conditions.MarkTrue(m, BootstrappedCondition)
	m.Status.HostConfigHash = r.desiredHostConfigHash(m)
	return &scalewayUpdateFixture{t: t, r: r, m: m, host: host, creds: &credentials.MachineBootstrap{HostFingerprint: "pin", SSHUsername: host.console, SudoPassword: "password"}}
}
func scalewayProcessorPod(name, node string) *corev1.Pod {
	return &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "tuist", UID: types.UID(name), Labels: map[string]string{"app.kubernetes.io/component": "xcresult-processor"}, Annotations: map[string]string{"tuist.dev/graceful-drain": "xcresult-v1"}}, Spec: corev1.PodSpec{NodeName: node, NodeSelector: map[string]string{"tuist.dev/fleet": "processors"}}, Status: corev1.PodStatus{Phase: corev1.PodRunning, Conditions: []corev1.PodCondition{{Type: corev1.PodReady, Status: corev1.ConditionTrue}}}}
}
func (f *scalewayUpdateFixture) step() bool {
	f.t.Helper()
	handled, _, err := f.r.reconcileScalewayOSUpdate(context.Background(), f.m, []byte("key"), f.creds)
	if err != nil {
		f.t.Fatal(err)
	}
	f.m = f.m.DeepCopy() // recover the persisted status after a controller restart
	return handled
}
func (f *scalewayUpdateFixture) phase(want string) {
	f.t.Helper()
	if f.m.Status.OSUpdate.Phase != want {
		f.t.Fatalf("phase=%s want=%s: %s", f.m.Status.OSUpdate.Phase, want, f.m.Status.OSUpdate.Message)
	}
}
func (f *scalewayUpdateFixture) get(obj client.Object, name string) {
	f.t.Helper()
	ns := "tuist"
	if _, ok := obj.(*corev1.Node); ok {
		ns = ""
	}
	if err := f.r.Get(context.Background(), types.NamespacedName{Namespace: ns, Name: name}, obj); err != nil {
		f.t.Fatal(err)
	}
}

func TestScalewayOSUpdateResumesAndDoesNotInstallBeforeDrain(t *testing.T) {
	f := newScalewayUpdateFixture(t)
	f.step()
	f.phase(OSUpdatePhasePreparing)
	f.step()
	dep := &appsv1.Deployment{}
	f.get(dep, "processor")
	if !dep.Spec.Paused {
		t.Fatal("deployment was not paused")
	}
	f.step()
	f.phase(OSUpdatePhaseDraining)
	node := &corev1.Node{}
	f.get(node, "mini")
	if !node.Spec.Unschedulable {
		t.Fatal("host was not cordoned")
	}
	if len(f.host.installs) != 0 || len(f.host.downloads) != 0 {
		t.Fatal("started work before VM drain")
	}
	own := &corev1.Pod{}
	f.get(own, "own")
	if err := f.r.Delete(context.Background(), own); err != nil {
		t.Fatal(err)
	}
	f.step()
	f.phase(OSUpdatePhaseDownloading)
	f.step()
	f.step()
	if len(f.host.downloads) != 1 {
		t.Fatalf("download repeated: %v", f.host.downloads)
	}
	f.host.exit(bootstrap.OSUpdateJobDownload, 0, "")
	f.step()
	f.phase(OSUpdatePhaseInstalling)
	if len(f.host.installs) != 0 {
		t.Fatal("install started before boot-time checkpoint")
	}
	f.step()
	f.step()
	if len(f.host.installs) != 1 {
		t.Fatal("installer repeated")
	}
	f.host.version = "26.7"
	f.host.bootTime += 100
	f.step()
	f.phase(OSUpdatePhaseConverging)
	if f.step() {
		t.Fatal("maintenance did not yield to the host config drift push")
	}
	f.m.Status.HostConfigHash = f.r.desiredHostConfigHash(f.m)
	f.step()
	f.phase(osUpdatePhaseAccepting)
	f.step()
	f.phase(osUpdatePhaseAccepting)
	if err := f.r.Create(context.Background(), scalewayProcessorPod("replacement", "mini")); err != nil {
		t.Fatal(err)
	}
	f.step()
	f.phase(OSUpdatePhaseSucceeded)
	f.get(node, "mini")
	if node.Spec.Unschedulable {
		t.Fatal("owned cordon remained")
	}
	f.get(dep, "processor")
	if dep.Spec.Paused {
		t.Fatal("owned pause remained")
	}
	leases := &coordinationv1.LeaseList{}
	if err := f.r.List(context.Background(), leases); err != nil {
		t.Fatal(err)
	}
	if len(leases.Items) != 0 {
		t.Fatal("fleet lock remained")
	}
}

func TestScalewayOSUpdateSerializesHostsAndKeepsLockOnFailure(t *testing.T) {
	f := newScalewayUpdateFixture(t)
	f.step()
	f.step()
	other := f.m.DeepCopy()
	other.Name = "other"
	other.UID = "other-uid"
	other.Status.OSUpdate = nil
	for i := 0; i < 2; i++ {
		if _, _, err := f.r.reconcileScalewayOSUpdate(context.Background(), other, []byte("key"), f.creds); err != nil {
			t.Fatal(err)
		}
	}
	if other.Status.OSUpdate.Phase != OSUpdatePhasePreparing {
		t.Fatal("second host passed lock")
	}
	old := metav1.NewTime(time.Now().Add(-3 * time.Hour))
	f.m.Status.OSUpdate.PhaseStartedAt = &old
	f.step()
	f.phase(OSUpdatePhaseFailed)
	lock := &coordinationv1.Lease{}
	f.get(lock, maintenanceLeaseName("processors"))
	if *lock.Spec.HolderIdentity != string(f.m.UID) {
		t.Fatal("failed host lost lock")
	}
	if _, _, err := f.r.reconcileScalewayOSUpdate(context.Background(), f.m, []byte("key"), f.creds); err == nil {
		t.Fatal("failed maintenance silently resumed ordinary drift")
	}
}

func TestScalewayOSUpdateRequiresDrainSupportAndSpareProcessor(t *testing.T) {
	for _, scenario := range []string{"old-processor", "no-peer", "unsettled-deployment", "foreign-pause"} {
		t.Run(scenario, func(t *testing.T) {
			f := newScalewayUpdateFixture(t)
			switch scenario {
			case "old-processor":
				p := &corev1.Pod{}
				f.get(p, "own")
				delete(p.Annotations, "tuist.dev/graceful-drain")
				if err := f.r.Update(context.Background(), p); err != nil {
					t.Fatal(err)
				}
			case "no-peer":
				p := &corev1.Pod{}
				f.get(p, "peer")
				if err := f.r.Delete(context.Background(), p); err != nil {
					t.Fatal(err)
				}
			case "unsettled-deployment":
				d := &appsv1.Deployment{}
				f.get(d, "processor")
				d.Generation = 2
				if err := f.r.Update(context.Background(), d); err != nil {
					t.Fatal(err)
				}
			case "foreign-pause":
				d := &appsv1.Deployment{}
				f.get(d, "processor")
				d.Spec.Paused = true
				if err := f.r.Update(context.Background(), d); err != nil {
					t.Fatal(err)
				}
			}
			f.step()
			f.step()
			f.step()
			f.phase(OSUpdatePhasePreparing)
			n := &corev1.Node{}
			f.get(n, "mini")
			if n.Spec.Unschedulable {
				t.Fatal("cordoned before prerequisites")
			}
			if len(f.host.installs) != 0 {
				t.Fatal("installed without prerequisites")
			}
		})
	}
}

func TestScalewayOSUpdateWaitsForPDBAndTerminatingVM(t *testing.T) {
	f := newScalewayUpdateFixture(t)
	f.step()
	f.step()
	f.step()
	calls := 0
	f.r.Client = interceptor.NewClient(f.r.Client.(client.WithWatch), interceptor.Funcs{
		SubResourceCreate: func(_ context.Context, _ client.Client, resource string, pod client.Object, body client.Object, _ ...client.SubResourceCreateOption) error {
			calls++
			eviction, ok := body.(*policyv1.Eviction)
			if !ok || resource != "eviction" || pod.GetName() != "own" || *eviction.DeleteOptions.Preconditions.UID != pod.GetUID() || *eviction.DeleteOptions.GracePeriodSeconds != 600 {
				t.Fatal("eviction omitted identity or grace constraints")
			}
			return apierrors.NewTooManyRequests("disruption budget", 1)
		},
	})
	f.step()
	f.phase(OSUpdatePhaseDraining)
	if calls != 1 || len(f.host.downloads) != 0 {
		t.Fatal("PDB denial did not hold maintenance")
	}
	p := &corev1.Pod{}
	f.get(p, "own")
	p.Finalizers = []string{"tart-kubelet.tuist.dev/vm-cleanup"}
	if err := f.r.Update(context.Background(), p); err != nil {
		t.Fatal(err)
	}
	if err := f.r.Delete(context.Background(), p); err != nil {
		t.Fatal(err)
	}
	f.step()
	f.phase(OSUpdatePhaseDraining)
	if calls != 1 || len(f.host.downloads) != 0 {
		t.Fatal("terminating VM was treated as drained")
	}
}

func TestScalewayOSUpdateRefusesUnexpectedWorkloads(t *testing.T) {
	f := newScalewayUpdateFixture(t)
	p := scalewayProcessorPod("other-workload", "mini")
	p.Namespace = "another-namespace"
	if err := f.r.Create(context.Background(), p); err != nil {
		t.Fatal(err)
	}
	f.r.Client = interceptor.NewClient(f.r.Client.(client.WithWatch), interceptor.Funcs{
		SubResourceCreate: func(_ context.Context, _ client.Client, _ string, pod client.Object, _ client.Object, _ ...client.SubResourceCreateOption) error {
			if pod.GetNamespace() != "tuist" {
				t.Fatal("attempted cross-namespace eviction")
			}
			return nil
		},
	})
	empty, err := f.r.drainScalewayProcessor(context.Background(), "tuist", "mini")
	if empty || err == nil {
		t.Fatal("unexpected workload did not block drain")
	}
}

func TestScalewayMaintenanceRequestTask(t *testing.T) {
	cmd := exec.Command("bash", "../../../../.github/scripts/macos-maintenance.test.sh")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("maintenance task: %v\n%s", err, out)
	}
}
