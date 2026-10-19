package macos

import (
	"context"
	"strings"
	"testing"
	"time"

	applesilicon "github.com/scaleway/scaleway-sdk-go/api/applesilicon/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	"k8s.io/utils/ptr"
	"sigs.k8s.io/controller-runtime/pkg/client"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/controllers/shared"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/scaleway"
)

func tartNode(name string) *corev1.Node {
	return &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: name},
		Status: corev1.NodeStatus{
			Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}},
		},
	}
}

func tartRunnerPod(name, nodeName string) *corev1.Pod {
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Namespace: "tuist-runners",
			Name:      name,
			Labels:    map[string]string{"tuist.dev/runner": "true"},
		},
		Spec:   corev1.PodSpec{NodeName: nodeName},
		Status: corev1.PodStatus{Phase: corev1.PodRunning},
	}
}

func nodeIdentity(machineName string) *corev1.ServiceAccount {
	return &corev1.ServiceAccount{ObjectMeta: metav1.ObjectMeta{Name: "tart-kubelet-" + machineName, Namespace: testNamespace}}
}

func finishJob(t *testing.T, c client.Client, job *corev1.Pod) {
	t.Helper()
	job.Status.Phase = corev1.PodSucceeded
	if err := c.Status().Update(context.Background(), job); err != nil {
		t.Fatalf("finish the job: %v", err)
	}
}

func assertMacOSReleaseHeld(t *testing.T, c client.Client, recorder record.EventRecorder, nodeName string, requeueAfter time.Duration, finalizerKept bool) {
	t.Helper()
	ctx := context.Background()
	if !finalizerKept {
		t.Fatal("the machine was released while a runner job was still running on it")
	}
	if requeueAfter != shared.RunnerJobsRecheckInterval {
		t.Fatalf("requeueAfter = %s, want %s", requeueAfter, shared.RunnerJobsRecheckInterval)
	}
	node := &corev1.Node{}
	if err := c.Get(ctx, types.NamespacedName{Name: nodeName}, node); err != nil {
		t.Fatalf("the Node is gone while a runner job was still running on it: %v", err)
	}
	if !node.Spec.Unschedulable {
		t.Fatal("the Node was not cordoned, so new runner Pods keep landing and idle ones are never retired")
	}
	if err := c.Get(ctx, types.NamespacedName{Namespace: testNamespace, Name: "tart-kubelet-" + nodeName}, &corev1.ServiceAccount{}); err != nil {
		t.Fatalf("the node identity was revoked while a runner job was still running, so tart-kubelet can no longer report it: %v", err)
	}
	events := recorder.(*record.FakeRecorder).Events
	for {
		select {
		case event := <-events:
			if strings.Contains(event, "WaitingForRunnerJobs") {
				return
			}
		default:
			t.Fatal("no WaitingForRunnerJobs event says what the release is waiting for")
		}
	}
}

func TestScalewayAppleSiliconReconcileDeleteWaitsForRunnerJobs(t *testing.T) {
	ctx := context.Background()
	const name = "macos-fleet-0"
	api := &scalewayAPIStub{
		servers: []*applesilicon.Server{{ID: "srv-1", Name: "tuist-tuist-macos-fleet-0"}},
	}
	machine := &infrav1.ScalewayAppleSiliconMachine{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: testNamespace, Finalizers: []string{MachineFinalizer}},
		Spec:       infrav1.ScalewayAppleSiliconMachineSpec{AdoptPoolPrefix: "tuist-pool-", Zone: "fr-par-1"},
		Status:     infrav1.ScalewayAppleSiliconMachineStatus{ServerID: "srv-1"},
	}
	job := tartRunnerPod("job", name)
	r := newReconciler(t, tartNode(name), job, nodeIdentity(name))
	r.ScalewayClient = &scaleway.Client{API: api}

	res, err := r.reconcileDelete(ctx, machine)
	if err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}
	if len(api.reinstalledIDs) != 0 {
		t.Fatalf("reinstalled %v while a runner job was still running on it", api.reinstalledIDs)
	}
	assertMacOSReleaseHeld(t, r.Client, r.Recorder, name, res.RequeueAfter, containsString(machine.Finalizers, MachineFinalizer))

	finishJob(t, r.Client, job)
	if _, err := r.reconcileDelete(ctx, machine); err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}
	if got := api.reinstalledIDs; len(got) != 1 || got[0] != "srv-1" {
		t.Fatalf("expected srv-1 to be returned to the pool once the job finished, got %v", got)
	}
	if containsString(machine.Finalizers, MachineFinalizer) {
		t.Fatal("the release is still held after the job finished")
	}
	if err := r.Get(ctx, types.NamespacedName{Name: name}, &corev1.Node{}); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the Node to be deleted once the job finished, got err=%v", err)
	}
}

func TestRackAppleSiliconReconcileDeleteWaitsForRunnerJobs(t *testing.T) {
	ctx := context.Background()
	const name = "ber1-0"
	machine := rackMachine(name, func(m *infrav1.RackAppleSiliconMachine) {
		m.Finalizers = []string{RackMachineFinalizer}
		m.DeletionTimestamp = ptr.To(metav1.Now())
	})
	job := tartRunnerPod("job", name)
	r := newRackReconciler(t, rackHost("mini-01"), machine, tartNode(name), job, nodeIdentity(name))

	res, err := r.reconcileDelete(ctx, machine)
	if err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}
	assertMacOSReleaseHeld(t, r.Client, r.Recorder, name, res.RequeueAfter, containsString(machine.Finalizers, RackMachineFinalizer))

	finishJob(t, r.Client, job)
	if _, err := r.reconcileDelete(ctx, machine); err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}
	if containsString(machine.Finalizers, RackMachineFinalizer) {
		t.Fatal("the release is still held after the job finished")
	}
	if err := r.Get(ctx, types.NamespacedName{Name: name}, &corev1.Node{}); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the Node to be deleted once the job finished, got err=%v", err)
	}
}

// A host lent to another cluster has no Node here: its runner Pods are the
// other cluster's, and this cluster's delete never stops them.
func TestRackAppleSiliconReconcileDeleteOfALentHostDoesNotWait(t *testing.T) {
	machine := rackMachine("ber1-0", func(m *infrav1.RackAppleSiliconMachine) {
		m.Finalizers = []string{RackMachineFinalizer}
		m.DeletionTimestamp = ptr.To(metav1.Now())
		m.Spec.NodeCluster = &infrav1.RackHostNodeCluster{KubeconfigSecret: "staging-node-kubeconfig"}
	})
	r := newRackReconciler(t, rackHost("mini-01"), machine)

	res, err := r.reconcileDelete(context.Background(), machine)
	if err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}
	if res.RequeueAfter != 0 || containsString(machine.Finalizers, RackMachineFinalizer) {
		t.Fatalf("a lent host's delete was held (requeueAfter=%s, finalizers=%v)", res.RequeueAfter, machine.Finalizers)
	}
}
