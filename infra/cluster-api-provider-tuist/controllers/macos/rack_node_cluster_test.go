package macos

import (
	"context"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	rbacv1 "k8s.io/api/rbac/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

const lentKubeconfigSecret = "ber1-runner-b01-staging-kubeconfig"

func lentTo(cacheVolumesURL string) *infrav1.RackHostNodeCluster {
	return &infrav1.RackHostNodeCluster{KubeconfigSecret: lentKubeconfigSecret, CacheVolumesURL: cacheVolumesURL}
}

func lentKubeconfig(data string) *corev1.Secret {
	return &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: lentKubeconfigSecret, Namespace: testNamespace},
		Data:       map[string][]byte{"kubeconfig": []byte(data)},
	}
}

// A lent host's tart-kubelet authenticates to the other cluster with the
// kubeconfig that cluster issued, and no identity is minted for it here.
func TestLentHostTakesTheOtherClustersKubeconfig(t *testing.T) {
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) { m.Spec.NodeCluster = lentTo("") })
	r := newRackReconciler(t, machine, lentKubeconfig("apiVersion: v1\nkind: Config\n# staging\n"))

	got, prepErr := r.nodeKubeconfig(context.Background(), machine)
	if prepErr != nil {
		t.Fatalf("nodeKubeconfig: %v", prepErr.err)
	}
	if got != "apiVersion: v1\nkind: Config\n# staging\n" {
		t.Fatalf("kubeconfig = %q, want the Secret's", got)
	}
	sa := &corev1.ServiceAccount{}
	err := r.Get(context.Background(), types.NamespacedName{Namespace: testNamespace, Name: "tart-kubelet-ber1-0"}, sa)
	if !apierrors.IsNotFound(err) {
		t.Fatalf("a node identity was minted here for a lent host (err %v)", err)
	}
}

// Without the Secret the host must not fall back to this cluster's identity:
// that would register its Node here again.
func TestLentHostWithoutItsKubeconfigWaits(t *testing.T) {
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) { m.Spec.NodeCluster = lentTo("") })
	r := newRackReconciler(t, machine)

	if _, prepErr := r.nodeKubeconfig(context.Background(), machine); prepErr == nil || prepErr.reason != "NodeClusterKubeconfigUnavailable" {
		t.Fatalf("prepErr = %+v, want NodeClusterKubeconfigUnavailable", prepErr)
	}

	r = newRackReconciler(t, machine, lentKubeconfig(""))
	if _, prepErr := r.nodeKubeconfig(context.Background(), machine); prepErr == nil || prepErr.reason != "NodeClusterKubeconfigUnavailable" {
		t.Fatalf("prepErr = %+v for an empty kubeconfig, want NodeClusterKubeconfigUnavailable", prepErr)
	}
}

// Lending revokes the host's identity here before deleting its Node, so a
// tart-kubelet still holding this cluster's token cannot register it again.
func TestLendingRetiresTheLocalNode(t *testing.T) {
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) { m.Spec.NodeCluster = lentTo("") })
	r := newRackReconciler(t, machine,
		&corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "ber1-0"}},
		&corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Name: "tart-kubelet-ber1-0", Namespace: testNamespace}},
		&rbacv1.ClusterRoleBinding{ObjectMeta: metav1.ObjectMeta{Name: "tart-kubelet-ber1-0"}},
	)

	if err := r.retireLocalNode(context.Background(), machine); err != nil {
		t.Fatalf("retireLocalNode: %v", err)
	}
	if err := r.Get(context.Background(), types.NamespacedName{Name: "ber1-0"}, &corev1.Node{}); !apierrors.IsNotFound(err) {
		t.Fatalf("the local Node survived (err %v)", err)
	}
	if err := r.Get(context.Background(), types.NamespacedName{Name: "tart-kubelet-ber1-0"}, &rbacv1.ClusterRoleBinding{}); !apierrors.IsNotFound(err) {
		t.Fatalf("the node identity's binding survived (err %v)", err)
	}
	if err := r.retireLocalNode(context.Background(), machine); err != nil {
		t.Fatalf("retiring again: %v", err)
	}
}

// A lent host's Node lives in the other cluster, so its absence here must not
// read as a lost Node and re-run bootstrap.
func TestLentHostIsNeverMissingItsNode(t *testing.T) {
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) { m.Spec.NodeCluster = lentTo("") })
	machine.Status.Conditions = clusterv1.Conditions{{
		Type:               BootstrappedCondition,
		Status:             corev1.ConditionTrue,
		LastTransitionTime: metav1.NewTime(time.Now().Add(-2 * nodeBootstrapGrace)),
	}}
	r := newRackReconciler(t, machine)

	missing, err := r.nodeMissingAfterBootstrap(context.Background(), machine)
	if err != nil || missing {
		t.Fatalf("missing = %v, err = %v; want a lent host never missing its Node", missing, err)
	}

	own := machine.DeepCopy()
	own.Spec.NodeCluster = nil
	if missing, err := r.nodeMissingAfterBootstrap(context.Background(), own); err != nil || !missing {
		t.Fatalf("missing = %v, err = %v; want the operator's own host missing its Node", missing, err)
	}
}

// Custom cache volumes are authorized by the server of the cluster the Node
// is in, and the change drifts the host.
func TestLentHostTakesTheOtherServersCacheVolumes(t *testing.T) {
	r := &RackAppleSiliconMachineReconciler{
		FleetConfig:          bootstrap.Config{CustomCacheURL: "https://tuist.dev/api/internal/runners/cache-volumes"},
		DefaultGuestCapacity: 1,
	}
	own := rackHost("mini-01")
	lent := rackHost("mini-01", func(h *infrav1.RackHost) { h.Spec.NodeCluster = lentTo("") })
	lentWithCache := rackHost("mini-01", func(h *infrav1.RackHost) {
		h.Spec.NodeCluster = lentTo("https://staging.tuist.dev/api/internal/runners/cache-volumes")
	})

	if got := r.rackFleetConfig(own).CustomCacheURL; got != "https://tuist.dev/api/internal/runners/cache-volumes" {
		t.Fatalf("own host cache URL = %q", got)
	}
	if got := r.rackFleetConfig(lent).CustomCacheURL; got != "" {
		t.Fatalf("lent host without a cache URL = %q, want custom cache volumes off", got)
	}
	if got := r.rackFleetConfig(lentWithCache).CustomCacheURL; got != "https://staging.tuist.dev/api/internal/runners/cache-volumes" {
		t.Fatalf("lent host cache URL = %q", got)
	}
	if r.rackFleetConfig(own).CustomCacheURL == "" {
		t.Fatal("lending one host changed the shared fleet config")
	}
}

func TestLendingDriftsTheHostOntoTheOtherCluster(t *testing.T) {
	r := &RackAppleSiliconMachineReconciler{DefaultGuestCapacity: 1}
	host := rackHost("mini-01")
	own := rackMachine("m")
	lent := rackMachine("m", func(m *infrav1.RackAppleSiliconMachine) { m.Spec.NodeCluster = lentTo("") })
	renamed := rackMachine("m", func(m *infrav1.RackAppleSiliconMachine) {
		m.Spec.NodeCluster = &infrav1.RackHostNodeCluster{KubeconfigSecret: "rotated"}
	})

	if r.desiredHostConfigHash(own, host) == r.desiredHostConfigHash(lent, host) {
		t.Fatal("lending the host does not drift it")
	}
	if r.desiredHostConfigHash(lent, host) == r.desiredHostConfigHash(renamed, host) {
		t.Fatal("pointing the host at another kubeconfig Secret does not drift it")
	}
}

// The fleet's MachineHealthCheck would find a lent host's Node missing here
// and remediate its Machine in a loop, so the Machine is kept off it, and an
// operator's own skip-remediation survives the host coming back.
func TestLentHostsMachineIsKeptOffRemediation(t *testing.T) {
	host := unmachinedHost(func(h *infrav1.RackHost) { h.Spec.NodeCluster = lentTo("") })
	r := newRackMachinesReconciler(t, host)
	reconcileHost(t, r, "mini-01")

	machine, ok := getMachine(t, r, testHostMachine)
	if !ok {
		t.Fatal("no Machine")
	}
	if _, set := machine.Annotations[clusterv1.MachineSkipRemediationAnnotation]; !set {
		t.Fatalf("annotations %v, want skip-remediation", machine.Annotations)
	}

	conditions.MarkFalse(machine, clusterv1.MachineHealthCheckSucceededCondition, clusterv1.NodeNotFoundReason, clusterv1.ConditionSeverityWarning, "")
	conditions.MarkFalse(machine, clusterv1.MachineOwnerRemediatedCondition, clusterv1.WaitingForRemediationReason, clusterv1.ConditionSeverityWarning, "")
	if err := r.Status().Update(context.Background(), machine); err != nil {
		t.Fatalf("mark unhealthy: %v", err)
	}
	reconcileHost(t, r, "mini-01")
	if _, ok := getMachine(t, r, testHostMachine); !ok {
		t.Fatal("a lent host's Machine was remediated")
	}

	returned := readHost(t, r, "mini-01")
	returned.Spec.NodeCluster = nil
	if err := r.Update(context.Background(), returned); err != nil {
		t.Fatalf("return the host: %v", err)
	}
	machine, _ = getMachine(t, r, testHostMachine)
	conditions.MarkTrue(machine, clusterv1.MachineHealthCheckSucceededCondition)
	if err := r.Status().Update(context.Background(), machine); err != nil {
		t.Fatalf("mark healthy: %v", err)
	}
	reconcileHost(t, r, "mini-01")
	machine, _ = getMachine(t, r, testHostMachine)
	if _, set := machine.Annotations[clusterv1.MachineSkipRemediationAnnotation]; set {
		t.Fatalf("annotations %v after the host came back, want the check on it again", machine.Annotations)
	}

	meta := metav1.ObjectMeta{Annotations: map[string]string{clusterv1.MachineSkipRemediationAnnotation: ""}}
	keepLentMachineOffRemediation(&meta, returned)
	if _, set := meta.Annotations[clusterv1.MachineSkipRemediationAnnotation]; !set {
		t.Fatal("an operator's own skip-remediation was removed")
	}
}
