package linux

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	"sigs.k8s.io/cluster-api/util/conditions"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/racknode"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const rackTestFleet = "tuist-tuist-rack-linux"

const clusterInfoKubeconfig = `apiVersion: v1
kind: Config
clusters:
- name: ""
  cluster:
    server: https://api.example:6443
    certificate-authority-data: Q0EgUEVN
contexts: []
users: []
`

type scriptRun struct {
	host   string
	script string
	pinned string
}

type fakeRunner struct {
	runs    []scriptRun
	results []error
	// reply, when set, is what a script prints on the host it runs on.
	reply func(host, script string) string
}

func (f *fakeRunner) run(_ context.Context, _, host string, _ []byte, script string, _ time.Duration, hk *bootstrap.HostKeyState) (string, error) {
	f.runs = append(f.runs, scriptRun{host: host, script: script, pinned: hk.Observed()})
	if f.reply != nil {
		return f.reply(host, script), nil
	}
	var err error
	if len(f.results) > 0 {
		err = f.results[0]
		f.results = f.results[1:]
	}
	if err != nil {
		return "", err
	}
	return "tuist-converge: changed=/var/lib/kubelet/config.yaml restarted=kubelet\n", nil
}

// nodeApply is one rack-node apply the operator ran over SSH.
type nodeApply struct {
	host   string
	req    racknode.Request
	pinned string
}

// fakeApplier answers rack-node applies: in turn with results, and otherwise
// with the configuration applied.
type fakeApplier struct {
	applies []nodeApply
	results []func(racknode.Request) (racknode.Result, error)
}

func (f *fakeApplier) apply(_ context.Context, _, host string, _ []byte, hk *bootstrap.HostKeyState, req racknode.Request) (racknode.Result, error) {
	f.applies = append(f.applies, nodeApply{host: host, req: req, pinned: hk.Observed()})
	if len(f.results) > 0 {
		next := f.results[0]
		f.results = f.results[1:]
		return next(req)
	}
	return racknode.Result{Applied: req.Config.Hash, Changed: []string{"/var/lib/kubelet/config.yaml"}, Restarted: []string{"kubelet"}}, nil
}

func needsBootstrap(racknode.Request) (racknode.Result, error) {
	return racknode.Result{NeedsBootstrap: true}, nil
}

func nodeFile(req racknode.Request, path string) string {
	for _, f := range req.Config.Files {
		if f.Path == path {
			return f.Content
		}
	}
	return ""
}

func claimedEdgeHost(device string) *infrav1.RackLinuxHost {
	h := edgeHost()
	h.Spec.Node = infrav1.RackLinuxHostNode{
		Labels: map[string]string{"tuist.dev/rack-edge": "ber1"},
		Taints: []corev1.Taint{{Key: "tuist.dev/rack-edge", Value: "ber1", Effect: corev1.TaintEffectNoSchedule}},
	}
	h.Status.Tailnet = &infrav1.RackLinuxHostTailnetStatus{
		DeviceID:  device,
		Name:      "ber1-edge.example.ts.net",
		Address:   "100.64.0.7",
		Connected: true,
	}
	return h
}

func edgeMachine() *infrav1.RackLinuxMachine {
	return &infrav1.RackLinuxMachine{
		ObjectMeta: metav1.ObjectMeta{Name: edgeUUID, Namespace: rackTestNamespace},
		Spec:       infrav1.RackLinuxMachineSpec{Host: edgeUUID},
	}
}

func ciliumDaemonSet(excludes bool) *appsv1.DaemonSet {
	var exprs []corev1.NodeSelectorRequirement
	if excludes {
		exprs = append(exprs, corev1.NodeSelectorRequirement{Key: ciliumNoScheduleLabel, Operator: corev1.NodeSelectorOpNotIn, Values: []string{"true"}})
	}
	exprs = append(exprs, corev1.NodeSelectorRequirement{Key: "kubernetes.io/os", Operator: corev1.NodeSelectorOpIn, Values: []string{"linux"}})
	return &appsv1.DaemonSet{
		ObjectMeta: metav1.ObjectMeta{Name: "cilium", Namespace: "kube-system"},
		Spec: appsv1.DaemonSetSpec{Template: corev1.PodTemplateSpec{Spec: corev1.PodSpec{Affinity: &corev1.Affinity{
			NodeAffinity: &corev1.NodeAffinity{RequiredDuringSchedulingIgnoredDuringExecution: &corev1.NodeSelector{
				NodeSelectorTerms: []corev1.NodeSelectorTerm{{MatchExpressions: exprs}},
			}},
		}}}},
	}
}

func rackClusterObjects(ciliumExcludes bool) []runtime.Object {
	return []runtime.Object{
		&corev1.Secret{
			ObjectMeta: metav1.ObjectMeta{Name: rackTestFleet + "-ssh", Namespace: rackTestNamespace},
			Data:       map[string][]byte{"id_ed25519": []byte("PRIVATE KEY")},
		},
		&corev1.Service{
			ObjectMeta: metav1.ObjectMeta{Name: "kube-dns", Namespace: "kube-system"},
			Spec:       corev1.ServiceSpec{ClusterIP: "10.128.0.10"},
		},
		&corev1.ConfigMap{
			ObjectMeta: metav1.ObjectMeta{Name: "cluster-info", Namespace: "kube-public"},
			Data:       map[string]string{"kubeconfig": clusterInfoKubeconfig},
		},
		ciliumDaemonSet(ciliumExcludes),
	}
}

type rackMachineHarness struct {
	r       *RackLinuxMachineReconciler
	c       client.Client
	runner  *fakeRunner
	applier *fakeApplier
}

func newRackMachineHarness(t *testing.T, cpVersion string, objs ...runtime.Object) *rackMachineHarness {
	t.Helper()
	scheme := rackTestScheme(t)
	if err := appsv1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithRuntimeObjects(objs...).
		WithStatusSubresource(&infrav1.RackLinuxHost{}, &infrav1.RackLinuxMachine{}, &corev1.Node{}).Build()
	runner := &fakeRunner{}
	applier := &fakeApplier{}
	r := &RackLinuxMachineReconciler{
		Client:             c,
		APIReader:          c,
		Recorder:           record.NewFakeRecorder(50),
		CredentialsManager: &credentials.Manager{Client: c, Namespace: rackTestNamespace},
		FleetName:          rackTestFleet,
		KubernetesMinor:    "v1.34",
		ControlPlaneVersion: func(context.Context) (string, error) {
			return cpVersion, nil
		},
		EgressNamespace:  "tailscale-operator",
		EgressProxyGroup: "macmini-egress",
		EgressProxyTags:  "tag:tuist-k8s-staging",
		RunScript:        runner.run,
		ApplyNode:        applier.apply,
	}
	return &rackMachineHarness{r: r, c: c, runner: runner, applier: applier}
}

func (h *rackMachineHarness) reconcile(t *testing.T) *infrav1.RackLinuxMachine {
	t.Helper()
	if _, err := h.r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Namespace: rackTestNamespace, Name: edgeUUID}}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	m := &infrav1.RackLinuxMachine{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: rackTestNamespace, Name: edgeUUID}, m); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		t.Fatal(err)
	}
	return m
}

func (h *rackMachineHarness) bootstrapTokens(t *testing.T) []corev1.Secret {
	t.Helper()
	list := &corev1.SecretList{}
	if err := h.c.List(context.Background(), list, client.InNamespace("kube-system")); err != nil {
		t.Fatal(err)
	}
	var out []corev1.Secret
	for _, s := range list.Items {
		if strings.HasPrefix(s.Name, "bootstrap-token-") {
			out = append(out, s)
		}
	}
	return out
}

func TestRackLinuxMachineJoinsAFreshHostWithAOneOffBootstrapToken(t *testing.T) {
	stale := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "ber1-edge"}}
	objs := append(rackClusterObjects(true), claimedEdgeHost("dev-1"), edgeMachine(), stale)
	h := newRackMachineHarness(t, "v1.34.8", objs...)
	h.applier.results = []func(racknode.Request) (racknode.Result, error){needsBootstrap}

	m := h.reconcile(t)

	applies := h.applier.applies
	if len(applies) != 2 {
		t.Fatalf("applied %d times, want a converge then a join", len(applies))
	}
	if applies[0].host != "rack-linux-"+edgeUUID+".tailscale-operator.svc.cluster.local" {
		t.Fatalf("dialled %q, want the egress Service", applies[0].host)
	}
	if applies[0].req.Bootstrap != "" {
		t.Fatal("the first converge carried a bootstrap token")
	}
	if !strings.Contains(applies[1].req.Bootstrap, "token: ") || !strings.Contains(applies[1].req.Bootstrap, "server: https://api.example:6443") {
		t.Fatal("the join did not carry a bootstrap kubeconfig")
	}
	if applies[1].req.Config.Kubelet.Version != "1.34.8" {
		t.Fatal("the kubelet is not pinned to the control plane release")
	}
	if tokens := h.bootstrapTokens(t); len(tokens) != 0 {
		t.Fatalf("%d bootstrap token(s) left behind", len(tokens))
	}
	if err := h.c.Get(context.Background(), types.NamespacedName{Name: "ber1-edge"}, &corev1.Node{}); !apierrors.IsNotFound(err) {
		t.Fatalf("stale Node not deleted: %v", err)
	}
	if m.Status.NodeName != "ber1-edge" || m.Spec.ProviderID == nil || *m.Spec.ProviderID != "rack-linux://ber1/"+edgeUUID {
		t.Fatalf("node %q providerID %v", m.Status.NodeName, m.Spec.ProviderID)
	}
	if m.Status.TailnetDeviceID != "dev-1" || m.Status.HostConfigHash == "" || m.Status.LastConvergeTime == nil ||
		m.Status.NodeConfig == nil || m.Status.NodeConfig.Hash != m.Status.HostConfigHash || m.Status.NodeConfigTime == nil {
		t.Fatalf("status %+v", m.Status)
	}
	if !conditions.IsTrue(m, HostConvergedCondition) {
		t.Fatal("HostConverged is not True")
	}
	svc := &corev1.Service{}
	if err := h.c.Get(context.Background(), types.NamespacedName{Namespace: "tailscale-operator", Name: "rack-linux-" + edgeUUID}, svc); err != nil {
		t.Fatalf("egress Service: %v", err)
	}
	if svc.Annotations["tailscale.com/tailnet-ip"] != "100.64.0.7" {
		t.Fatalf("egress Service fronts %q", svc.Annotations["tailscale.com/tailnet-ip"])
	}
}

// The converge keeps the port AMT shares, the host's boot MAC, up.
func TestRackLinuxMachineKeepsTheManagementPortUp(t *testing.T) {
	host := claimedEdgeHost("dev-1")
	host.Status.BootMAC = "38:05:25:38:b5:b5"
	h := newRackMachineHarness(t, "v1.34.8", append(rackClusterObjects(true), host, edgeMachine())...)

	h.reconcile(t)

	if len(h.applier.applies) == 0 || !strings.Contains(nodeFile(h.applier.applies[0].req, "/etc/systemd/network/10-tuist-management.network"), "MACAddress=38:05:25:38:b5:b5\n") {
		t.Fatal("the converge does not keep the boot MAC's port up")
	}
}

func TestRackLinuxMachineRefusesWhileCiliumWouldScheduleOntoTheNode(t *testing.T) {
	objs := append(rackClusterObjects(false), claimedEdgeHost("dev-1"), edgeMachine())
	h := newRackMachineHarness(t, "v1.34.8", objs...)

	m := h.reconcile(t)

	if len(h.applier.applies) != 0 {
		t.Fatalf("applied %d times with Cilium able to schedule onto the node", len(h.applier.applies))
	}
	c := conditions.Get(m, HostConvergedCondition)
	if c == nil || !strings.Contains(c.Message, "cilium.io/no-schedule") {
		t.Fatalf("condition %+v", c)
	}
}

func TestRackLinuxMachineReportsAKubeadmJoinedHost(t *testing.T) {
	objs := append(rackClusterObjects(true), claimedEdgeHost("dev-1"), edgeMachine())
	h := newRackMachineHarness(t, "v1.34.8", objs...)
	h.applier.results = []func(racknode.Request) (racknode.Result, error){func(racknode.Request) (racknode.Result, error) {
		return racknode.Result{ForeignJoin: true}, nil
	}}

	m := h.reconcile(t)

	if len(h.applier.applies) != 1 || len(h.bootstrapTokens(t)) != 0 {
		t.Fatalf("applied %d times; a kubeadm-joined host must not get a token", len(h.applier.applies))
	}
	if c := conditions.Get(m, HostConvergedCondition); c == nil || !strings.Contains(c.Message, "kubeadm") {
		t.Fatalf("condition %+v", c)
	}
	if m.Status.ConvergeFailures != 1 {
		t.Fatalf("failures %d", m.Status.ConvergeFailures)
	}
}

func TestRackLinuxMachineHoldsWhenTheControlPlaneIsOnAnotherMinor(t *testing.T) {
	objs := append(rackClusterObjects(true), claimedEdgeHost("dev-1"), edgeMachine())
	h := newRackMachineHarness(t, "v1.35.0", objs...)

	m := h.reconcile(t)

	if len(h.applier.applies) != 0 {
		t.Fatal("converged a kubelet onto a minor the operator does not render for")
	}
	if c := conditions.Get(m, HostConvergedCondition); c == nil || c.Reason != "ConvergeHeld" {
		t.Fatalf("condition %+v", c)
	}
}

func TestRackLinuxMachineLeavesAConvergedHostAlone(t *testing.T) {
	host := claimedEdgeHost("dev-1")
	machine := edgeMachine()
	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "ber1-edge"},
		Spec:       corev1.NodeSpec{ProviderID: "rack-linux://ber1/" + edgeUUID},
		Status:     corev1.NodeStatus{Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}},
	}
	objs := append(rackClusterObjects(true), host, machine, node)
	h := newRackMachineHarness(t, "v1.34.8", objs...)
	first := h.reconcile(t)
	if len(h.applier.applies) != 1 {
		t.Fatalf("applied %d times on the first reconcile", len(h.applier.applies))
	}

	second := h.reconcile(t)
	if len(h.applier.applies) != 1 {
		t.Fatal("converged again with nothing changed")
	}
	if !second.Status.Ready || second.Status.Phase != "Ready" || first.Status.HostConfigHash != second.Status.HostConfigHash {
		t.Fatalf("status %+v", second.Status)
	}

	h.r.ControlPlaneVersion = func(context.Context) (string, error) { return "v1.34.9", nil }
	h.reconcile(t)
	if len(h.applier.applies) != 2 || h.applier.applies[1].req.Config.Kubelet.Version != "1.34.9" {
		t.Fatal("a control plane patch release did not upgrade the kubelet")
	}
}

func TestRackLinuxMachinePinsAReinstalledHostAfresh(t *testing.T) {
	host := claimedEdgeHost("dev-2")
	machine := edgeMachine()
	machine.Status.TailnetDeviceID = "dev-1"
	objs := append(rackClusterObjects(true), host, machine)
	h := newRackMachineHarness(t, "v1.34.8", objs...)
	ctx := context.Background()
	if err := h.r.CredentialsManager.SetMachineHostFingerprint(ctx, rackLinuxPinKey(edgeUUID, "dev-1"), "SHA256:old"); err != nil {
		t.Fatal(err)
	}

	m := h.reconcile(t)

	if len(h.applier.applies) != 1 || h.applier.applies[0].pinned != "" {
		t.Fatalf("applies %+v; the reinstalled host must be trusted on first use", h.applier.applies)
	}
	if creds, err := h.r.CredentialsManager.GetMachineBootstrap(ctx, rackLinuxPinKey(edgeUUID, "dev-1")); err != nil || creds != nil {
		t.Fatalf("the previous install's pin is still there: %+v %v", creds, err)
	}
	if m.Status.TailnetDeviceID != "dev-2" {
		t.Fatalf("device %q", m.Status.TailnetDeviceID)
	}
}

func TestRackLinuxMachineKeepsAPinPerInstall(t *testing.T) {
	host := claimedEdgeHost("dev-2")
	machine := edgeMachine()
	objs := append(rackClusterObjects(true), host, machine)
	h := newRackMachineHarness(t, "v1.34.8", objs...)
	ctx := context.Background()
	for device, pin := range map[string]string{"dev-1": "SHA256:first-install", "dev-2": "SHA256:second-install"} {
		if err := h.r.CredentialsManager.SetMachineHostFingerprint(ctx, rackLinuxPinKey(edgeUUID, device), pin); err != nil {
			t.Fatal(err)
		}
	}

	h.reconcile(t)

	if len(h.applier.applies) != 1 || h.applier.applies[0].pinned != "SHA256:second-install" {
		t.Fatalf("applies %+v; want the current install's pin", h.applier.applies)
	}
}

func TestRackLinuxMachineDeleteStopsTheKubeletAndRemovesTheNode(t *testing.T) {
	host := claimedEdgeHost("dev-1")
	machine := edgeMachine()
	machine.Status.NodeName = "ber1-edge"
	machine.Finalizers = []string{RackLinuxMachineFinalizer}
	now := metav1.Now()
	machine.DeletionTimestamp = &now
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "ber1-edge"}, Spec: corev1.NodeSpec{ProviderID: "rack-linux://ber1/" + edgeUUID}}
	objs := append(rackClusterObjects(true), host, machine, node)
	h := newRackMachineHarness(t, "v1.34.8", objs...)

	if m := h.reconcile(t); m != nil {
		t.Fatalf("machine still present with finalizers %v", m.Finalizers)
	}
	if len(h.runner.runs) != 1 || !strings.Contains(h.runner.runs[0].script, "systemctl disable --now kubelet") {
		t.Fatal("the delete did not stop the host's kubelet")
	}
	if err := h.c.Get(context.Background(), types.NamespacedName{Name: "ber1-edge"}, &corev1.Node{}); !apierrors.IsNotFound(err) {
		t.Fatalf("Node not deleted: %v", err)
	}
}

// A host whose hostname changed joins again under the new name: the Node it
// joined under goes, and the converge drops the kubelet's identity and
// bootstraps it afresh.
func TestRackLinuxMachineRejoinsARenamedHost(t *testing.T) {
	host := claimedEdgeHost("dev-1")
	host.Spec.Hostname = "ber1-edge-c"
	machine := edgeMachine()
	machine.Status.NodeName = "ber1-edge"
	machine.Status.TailnetDeviceID = "dev-1"
	old := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "ber1-edge"}, Spec: corev1.NodeSpec{ProviderID: "rack-linux://ber1/" + edgeUUID}}
	objs := append(rackClusterObjects(true), host, machine, old)
	h := newRackMachineHarness(t, "v1.34.8", objs...)
	h.applier.results = []func(racknode.Request) (racknode.Result, error){needsBootstrap}

	m := h.reconcile(t)

	if err := h.c.Get(context.Background(), types.NamespacedName{Name: "ber1-edge"}, &corev1.Node{}); !apierrors.IsNotFound(err) {
		t.Fatalf("the Node the host joined under before its rename is still there: %v", err)
	}
	if len(h.applier.applies) != 2 {
		t.Fatalf("applied %d times, want a converge then a join", len(h.applier.applies))
	}
	for i, a := range h.applier.applies {
		if !a.req.Rejoin || a.req.Config.Hostname != "ber1-edge-c" || !strings.Contains(nodeFile(a.req, "/etc/systemd/system/kubelet.service"), "--hostname-override=ber1-edge-c") {
			t.Fatalf("apply %d does not rejoin the host as ber1-edge-c: %+v", i, a.req)
		}
	}
	if m.Status.NodeName != "ber1-edge-c" {
		t.Fatalf("node name %q", m.Status.NodeName)
	}

	h.reconcile(t)
	if len(h.applier.applies) != 2 {
		t.Fatal("rejoined the host again")
	}
}

func TestConvergeBackoff(t *testing.T) {
	for failures, want := range map[int32]time.Duration{1: time.Minute, 2: 2 * time.Minute, 6: 30 * time.Minute, 40: 30 * time.Minute} {
		if got := convergeBackoff(failures); got != want {
			t.Errorf("convergeBackoff(%d) = %s, want %s", failures, got, want)
		}
	}
}

func failingMachine(device string, failures int32, lastAttempt time.Duration) *infrav1.RackLinuxMachine {
	m := edgeMachine()
	m.Status.NodeName = "ber1-edge"
	m.Status.TailnetDeviceID = device
	m.Status.ConvergeFailures = failures
	at := metav1.NewTime(time.Now().Add(-lastAttempt))
	m.Status.LastConvergeAttemptTime = &at
	return m
}

func TestRackLinuxMachineConvergesANewDeviceWithoutWaitingOutTheBackoff(t *testing.T) {
	host := claimedEdgeHost("dev-2")
	objs := append(rackClusterObjects(true), host, failingMachine("dev-1", 7, time.Minute))
	h := newRackMachineHarness(t, "v1.34.8", objs...)

	m := h.reconcile(t)

	if len(h.applier.applies) != 1 {
		t.Fatalf("applied %d times; a reinstalled host must not wait out the old device's backoff", len(h.applier.applies))
	}
	if m.Status.ConvergeFailures != 0 || m.Status.TailnetDeviceID != "dev-2" {
		t.Fatalf("status %+v", m.Status)
	}
}

func TestRackLinuxMachineBacksOffOnTheSameDevice(t *testing.T) {
	host := claimedEdgeHost("dev-1")
	objs := append(rackClusterObjects(true), host, failingMachine("dev-1", 3, time.Minute))
	h := newRackMachineHarness(t, "v1.34.8", objs...)

	h.reconcile(t)

	if len(h.applier.applies) != 0 {
		t.Fatalf("applied %d times inside the backoff", len(h.applier.applies))
	}
}

// emptyNameRefused refuses a Get with no name, as the API client does, rather
// than answering NotFound as the fake client does.
type emptyNameRefused struct{ client.Client }

func (c emptyNameRefused) Get(ctx context.Context, key client.ObjectKey, obj client.Object, opts ...client.GetOption) error {
	if key.Name == "" {
		return fmt.Errorf("resource name may not be empty")
	}
	return c.Client.Get(ctx, key, obj, opts...)
}

// A RackLinuxMachine that names no host, such as one a pool of the earlier
// model created, is let go without touching any host or Node: it has nothing to
// leave.
func TestRackLinuxMachineWithNoHostIsReleasedUntouched(t *testing.T) {
	machine := edgeMachine()
	machine.Spec.Host = ""
	machine.Finalizers = []string{RackLinuxMachineFinalizer}
	now := metav1.Now()
	machine.DeletionTimestamp = &now
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "ber1-edge"}, Spec: corev1.NodeSpec{ProviderID: "rack-linux://ber1/" + edgeUUID}}
	objs := append(rackClusterObjects(true), claimedEdgeHost("dev-1"), machine, node)
	h := newRackMachineHarness(t, "v1.34.8", objs...)
	h.r.Client = emptyNameRefused{h.r.Client}

	if m := h.reconcile(t); m != nil {
		t.Fatalf("machine still present with finalizers %v", m.Finalizers)
	}
	if len(h.runner.runs) != 0 {
		t.Fatal("reached a host for a machine that names none")
	}
	if err := h.c.Get(context.Background(), types.NamespacedName{Name: "ber1-edge"}, &corev1.Node{}); err != nil {
		t.Fatalf("the Node is gone: %v", err)
	}
}

func TestRackLinuxMachineWithNoHostWaits(t *testing.T) {
	machine := edgeMachine()
	machine.Spec.Host = ""
	h := newRackMachineHarness(t, "v1.34.8", append(rackClusterObjects(true), machine)...)
	h.r.Client = emptyNameRefused{h.r.Client}

	m := h.reconcile(t)
	if m == nil || m.Status.Phase != "NoHost" || len(h.runner.runs) != 0 {
		t.Fatalf("machine %+v runs %d", m, len(h.runner.runs))
	}
}

// A host reinstalled from an install the operator published is held to the
// host key that install gave it from its first dial, before the host
// controller has pinned it, rather than trusted on first use.
func TestRackLinuxMachineHoldsANewInstallToTheHostKeyItWasGiven(t *testing.T) {
	host := claimedEdgeHost("dev-2")
	host.Status.Install = &infrav1.RackLinuxHostInstallStatus{KeyID: "kMINT1CNTRL", PreviousDeviceID: "dev-1", HostKeyFingerprint: "SHA256:given"}
	machine := edgeMachine()
	machine.Status.TailnetDeviceID = "dev-1"
	h := newRackMachineHarness(t, "v1.34.8", append(rackClusterObjects(true), host, machine)...)

	h.reconcile(t)

	if len(h.applier.applies) != 1 || h.applier.applies[0].pinned != "SHA256:given" {
		t.Fatalf("applies %+v; the new install is held to the key it was given", h.applier.applies)
	}
}
