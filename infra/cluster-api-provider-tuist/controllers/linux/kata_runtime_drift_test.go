package linux

import (
	"context"
	"crypto/ed25519"
	"crypto/rand"
	encpem "encoding/pem"
	"strings"
	"testing"

	"golang.org/x/crypto/ssh"
	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/ovh"
)

// kataHarness drives the real OVH reconcile loop against a Ready node that asked
// for kata, so the assertions are on what an operator would see on a live box.
type kataHarness struct {
	t       *testing.T
	machine *infrav1.OVHDedicatedMachine
	node    *corev1.Node
	client  client.Client
	r       *OVHDedicatedMachineReconciler
}

// newKataHarness builds a machine whose box has already joined: providerID set,
// Node Ready, kubelet config already at the current hash (so the kubelet-config
// drift loop no-ops and the kata check is what the reconcile exercises). The
// Node deliberately reports no InternalIP, which parks the repair before it
// dials SSH — the point under test is detection, not the re-push.
func newKataHarness(t *testing.T, kataRuntime bool, nodeLabels map[string]string) *kataHarness {
	t.Helper()
	const ns = "tuist-fleet"
	ca := []byte("-----BEGIN CERTIFICATE-----\nMIIBkataCAbytes\n-----END CERTIFICATE-----\n")

	scheme := runtime.NewScheme()
	for _, add := range []func(*runtime.Scheme) error{corev1.AddToScheme, rbacv1.AddToScheme, infrav1.AddToScheme} {
		if err := add(scheme); err != nil {
			t.Fatal(err)
		}
	}

	machine := &infrav1.OVHDedicatedMachine{}
	machine.Namespace = ns
	machine.Name = "ovh-runner-1"
	machine.Spec.FleetName = "runners-linux"
	machine.Spec.KataRuntime = kataRuntime
	providerID := "ovh://gra/ns1.ip-1-2-3.eu"
	machine.Spec.ProviderID = &providerID
	machine.Status.ServiceName = "ns1.ip-1-2-3.eu"

	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{
		Name:        machine.Name,
		Labels:      nodeLabels,
		Annotations: map[string]string{kubeletConfigHashAnnotation: desiredKubeletConfigHash(ca)},
	}}
	node.Status.Conditions = []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}}

	fleetKeySecret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{
			Namespace:   ns,
			Name:        machine.Spec.FleetName + "-ssh",
			Annotations: map[string]string{"scaleway.tuist.dev/ssh-key-id": "seeded"},
		},
		Data: map[string][]byte{"id_ed25519": testFleetPrivateKey(t)},
	}

	tokenSecret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Namespace: ns, Name: "tart-kubelet-" + machine.Name + "-token"},
		Type:       corev1.SecretTypeServiceAccountToken,
		Data:       map[string][]byte{"token": []byte("tok"), "ca.crt": ca},
	}

	cl := fake.NewClientBuilder().WithScheme(scheme).
		WithObjects(node, tokenSecret, fleetKeySecret).WithStatusSubresource(node).Build()

	r := &OVHDedicatedMachineReconciler{
		Client:             cl,
		APIReader:          cl,
		OVHClient:          &ovh.Client{API: &fakeOVHAPI{body: map[string]any{}}},
		Recorder:           record.NewFakeRecorder(100),
		CredentialsManager: &credentials.Manager{Client: cl, Namespace: ns, NodeIdentityClusterRole: linuxNodeIdentityClusterRole},
	}
	return &kataHarness{t: t, machine: machine, node: node, client: cl, r: r}
}

// testFleetPrivateKey mints the same shape of key the credentials manager
// persists, so EnsureFleetSSHKey reads one back instead of generating (and
// registering) a fresh one.
func testFleetPrivateKey(t *testing.T) []byte {
	t.Helper()
	_, priv, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	block, err := ssh.MarshalPrivateKey(priv, "tuist-capi-test")
	if err != nil {
		t.Fatal(err)
	}
	return encpem.EncodeToMemory(block)
}

func (h *kataHarness) reconcile() {
	h.t.Helper()
	if _, err := h.r.reconcileNormal(context.Background(), h.machine); err != nil {
		h.t.Fatalf("reconcileNormal: %v", err)
	}
}

func (h *kataHarness) liveNode() *corev1.Node {
	h.t.Helper()
	node := &corev1.Node{}
	if err := h.client.Get(context.Background(), types.NamespacedName{Name: h.machine.Name}, node); err != nil {
		h.t.Fatal(err)
	}
	return node
}

// A box bootstrapped by a provider that predates the kata support joins Ready,
// lands in the right pool, runs its DaemonSets — and never takes a job, because
// the kata-qemu RuntimeClass selects on a label the old self-join never wrote.
// Nothing in the reconcile used to notice, which is what made the production and
// canary incidents look like a scheduling bug for an hour. Reconciling such a
// machine must leave a condition that names the actual fault.
func TestKataRuntimeMissingIsSurfacedOnTheMachine(t *testing.T) {
	h := newKataHarness(t, true, nil)
	h.reconcile()

	cond := conditions.Get(h.machine, clusterv1.ConditionType("KataRuntimeReady"))
	if cond == nil {
		t.Fatalf("expected a KataRuntimeReady condition on a machine whose node asked for kata but carries no %s label; conditions=%v",
			"katacontainers.io/kata-runtime", h.machine.Status.Conditions)
	}
	if cond.Status != corev1.ConditionFalse {
		t.Fatalf("KataRuntimeReady = %s (%s), want False", cond.Status, cond.Reason)
	}
	// The node is a healthy Kubernetes node, so the Machine stays Ready: flipping
	// it would make CAPI churn a box that only needs an in-place repair.
	if !h.machine.Status.Ready {
		t.Fatalf("machine must stay Ready: the node is Ready, it is only missing a capability")
	}
	// Nothing may label the node until the box can actually run kata Pods —
	// labelling an unrepaired box just moves the failure from "never schedules"
	// to "every Pod stuck in ContainerCreating".
	if h.liveNode().Labels["katacontainers.io/kata-runtime"] != "" {
		t.Fatalf("node must not be labelled before the repair proves the shim is installed")
	}
}

// The converged case: a node that already carries the label is what every
// correctly-bootstrapped runner box looks like, and it must cost nothing.
func TestKataRuntimeReadyWhenNodeCarriesTheLabel(t *testing.T) {
	h := newKataHarness(t, true, map[string]string{"katacontainers.io/kata-runtime": "true"})
	h.reconcile()

	cond := conditions.Get(h.machine, clusterv1.ConditionType("KataRuntimeReady"))
	if cond == nil || cond.Status != corev1.ConditionTrue {
		t.Fatalf("expected KataRuntimeReady=True on a labelled node, got %v", cond)
	}
}

// A cache fleet never asks for kata, so it must carry no kata condition at all.
func TestKataRuntimeConditionAbsentWhenNotRequested(t *testing.T) {
	h := newKataHarness(t, false, nil)
	h.reconcile()

	if cond := conditions.Get(h.machine, clusterv1.ConditionType("KataRuntimeReady")); cond != nil {
		t.Fatalf("a fleet that never asked for kata must carry no KataRuntimeReady condition, got %v", cond)
	}
}

// A repair the box did not accept must leave the node unlabelled and say so.
// Labelling a box whose runtime is not really installed converts "no runner Pod
// ever schedules here" into "every runner Pod wedges in ContainerCreating",
// which is harder to diagnose and burns the job instead of queueing it.
//
// The unreachable host is loopback: nothing there will ever accept the fleet key,
// so the SSH attempt fails within milliseconds either way (connection refused, or
// a rejected publickey where the developer runs sshd).
func TestKataRuntimeRepairFailureNeverLabelsTheNode(t *testing.T) {
	h := newKataHarness(t, true, nil)
	h.node.Status.Addresses = []corev1.NodeAddress{{Type: corev1.NodeInternalIP, Address: "127.0.0.1"}}
	if err := h.client.Status().Update(context.Background(), h.node); err != nil {
		t.Fatal(err)
	}

	requeue, err := reconcileLinuxKataRuntimeDrift(context.Background(), h.client, h.r.CredentialsManager,
		h.machine, h.machine.Name, h.machine.Spec.FleetName, h.r.hostOptions(h.machine), h.liveNode())
	if err == nil {
		t.Fatalf("expected the repair to fail against an unreachable host, got requeue=%v", requeue)
	}
	if got := h.liveNode().Labels[KataRuntimeSelectorLabel]; got != "" {
		t.Fatalf("node was labelled %q despite a failed repair", got)
	}
	cond := conditions.Get(h.machine, KataRuntimeReadyCondition)
	if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != KataRuntimeRepairFailedReason {
		t.Fatalf("expected KataRuntimeReady=False/%s after a failed repair, got %v", KataRuntimeRepairFailedReason, cond)
	}
}

// The repair is an in-place, additive fix, not a re-bootstrap. That distinction
// is what makes it safe to run unattended against a box that may be holding a
// live runner: a re-bootstrap re-runs apt, regenerates the containerd config,
// and re-lays the /data mounts, any of which would disturb running work.
func TestRenderKataRuntimeRepairScript(t *testing.T) {
	script := renderKataRuntimeRepairScript(linuxCloudInitOptions{
		NodeName:      "ovh-runner-1",
		KataRuntime:   true,
		BootstrapUser: "ubuntu",
		InstanceType:  "ovh",
	})

	for _, want := range []string{
		// Installs the runtime and registers the handler.
		"kata-static-" + kataVersion + "-amd64.tar.zst",
		`runtime_path = "/opt/kata/bin/containerd-shim-kata-v2"`,
		// Re-renders the kubelet unit so a future re-registration keeps the labels.
		"tee /etc/systemd/system/kubelet.service > /dev/null <<'TUIST_EOF'",
		"--node-labels=node.cluster.x-k8s.io/instance-type=ovh,katacontainers.io/kata-runtime=true,tuist.dev/kata-runtime=true",
		"systemctl daemon-reload",
		// Proves the box can run a kata Pod before the controller advertises it.
		"test -x /opt/kata/bin/containerd-shim-kata-v2",
		"systemctl is-active --quiet containerd",
	} {
		if !strings.Contains(script, want) {
			t.Fatalf("expected the repair script to contain %q, got:\n%s", want, script)
		}
	}

	// Not a re-bootstrap: no apt sources, no kubelet reinstall, no remounting of
	// /data, no swapoff, and above all no kubelet restart — the node keeps
	// serving whatever it is already running.
	for _, banned := range []string{"pkgs.k8s.io", "install -y kubelet", "mount --bind", "swapoff", "systemctl restart kubelet", "containerd config default"} {
		if strings.Contains(script, banned) {
			t.Fatalf("repair must not run %q (that is a re-bootstrap, not an in-place repair), got:\n%s", banned, script)
		}
	}

	// The restart must be unconditional. Once the first attempt has appended the
	// handler, a restart conditioned on the handler being absent can never run
	// again: a retry after a failed or timed-out restart would skip it, and the
	// file checks would then pass against a daemon that never loaded the handler.
	if strings.Contains(script, "kata_handler_registered") {
		t.Fatalf("the containerd restart must not be conditioned on the handler already being in the config, got:\n%s", script)
	}
	if !strings.Contains(script, "systemctl restart containerd") {
		t.Fatalf("expected an unconditional containerd restart, got:\n%s", script)
	}

	// Nothing may reload into a config naming a binary that is not there, so the
	// shim is checked before the restart, not after it.
	shim := strings.Index(script, "test -x /opt/kata/bin/containerd-shim-kata-v2")
	restart := strings.Index(script, "systemctl restart containerd")
	active := strings.Index(script, "systemctl is-active --quiet containerd")
	if shim > restart {
		t.Fatalf("expected the shim check before the containerd restart (shim=%d restart=%d)", shim, restart)
	}
	if active < restart {
		t.Fatalf("expected the liveness check after the containerd restart (active=%d restart=%d)", active, restart)
	}

	// The kubelet unit carries the kata labels, so writing it before the runtime
	// is verified would let a later Node re-registration self-apply the label on
	// a box whose repair failed — jobs would schedule and wedge in
	// ContainerCreating. It goes last, so a failed repair leaves the old unit.
	unit := strings.Index(script, "tee /etc/systemd/system/kubelet.service")
	if unit < active {
		t.Fatalf("expected the labelled kubelet unit written only after verification (unit=%d verified=%d)", unit, active)
	}
}

// The repair retries against a box that keeps failing verification, so the
// install block must not re-pull the ~250 MiB kata tarball on each attempt —
// while a kataVersion bump must still reinstall.
func TestKataInstallIsGuardedByAVersionStamp(t *testing.T) {
	setup := kataSetup("sudo ", "sudo -E ", true)
	if !strings.Contains(setup, `if [ "$(cat `+kataVersionStampPath+` 2>/dev/null)" != "`+kataVersion+`" ]; then`) {
		t.Fatalf("expected the kata download to be guarded by a version stamp, got:\n%s", setup)
	}
	if !strings.Contains(setup, `printf '%s' "`+kataVersion+`" | sudo tee `+kataVersionStampPath) {
		t.Fatalf("expected the install to stamp the version it unpacked, got:\n%s", setup)
	}
	if stamp, download := strings.Index(setup, kataVersionStampPath), strings.Index(setup, "curl -fsSL -o /tmp/kata.tar.zst"); stamp > download {
		t.Fatalf("expected the stamp check before the download (stamp=%d download=%d)", stamp, download)
	}
}
