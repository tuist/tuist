package linux

import (
	"context"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/controllers/shared"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
)

const runnerBox = "tuist-tuist-ovh-fleet-runners-linux-abc12-xyz34"

func runnerBoxNode(ready corev1.ConditionStatus) *corev1.Node {
	return &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: runnerBox},
		Status: corev1.NodeStatus{
			Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: ready}},
		},
	}
}

func runnerPod(name, nodeName string, phase corev1.PodPhase) *corev1.Pod {
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Namespace: "tuist-runners",
			Name:      name,
			Labels:    map[string]string{"tuist.dev/runner": "true"},
		},
		Spec:   corev1.PodSpec{NodeName: nodeName},
		Status: corev1.PodStatus{Phase: phase},
	}
}

func TestOVHDedicatedReconcileDeleteWaitsForRunnerJobs(t *testing.T) {
	ctx := context.Background()
	machine := &infrav1.OVHDedicatedMachine{
		ObjectMeta: metav1.ObjectMeta{Name: runnerBox, Namespace: "tuist", Finalizers: []string{OVHDedicatedMachineFinalizer}},
	}
	job := runnerPod("job", runnerBox, corev1.PodRunning)
	cl := fake.NewClientBuilder().WithScheme(vultrScheme(t)).
		WithObjects(machine, runnerBoxNode(corev1.ConditionTrue), job).Build()
	r := &OVHDedicatedMachineReconciler{
		Client:             cl,
		CredentialsManager: &credentials.Manager{Client: cl, Namespace: "tuist"},
	}

	res, err := r.reconcileDelete(ctx, machine)
	if err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}
	assertReleaseHeld(t, cl, res.RequeueAfter, controllerutil.ContainsFinalizer(machine, OVHDedicatedMachineFinalizer))

	job.Status.Phase = corev1.PodSucceeded
	if err := cl.Status().Update(ctx, job); err != nil {
		t.Fatalf("finish the job: %v", err)
	}
	if _, err := r.reconcileDelete(ctx, machine); err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}
	if controllerutil.ContainsFinalizer(machine, OVHDedicatedMachineFinalizer) {
		t.Fatal("the release is still held after the job finished")
	}
	if err := cl.Get(ctx, types.NamespacedName{Name: runnerBox}, &corev1.Node{}); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the Node to be deleted once the job finished, got err=%v", err)
	}
}

func TestElasticMetalReconcileDeleteWaitsForRunnerJobs(t *testing.T) {
	machine := &infrav1.ScalewayElasticMetalMachine{
		ObjectMeta: metav1.ObjectMeta{Name: runnerBox, Namespace: "tuist", Finalizers: []string{ElasticMetalMachineFinalizer}},
	}
	cl := fake.NewClientBuilder().WithScheme(vultrScheme(t)).
		WithObjects(machine, runnerBoxNode(corev1.ConditionTrue), runnerPod("job", runnerBox, corev1.PodRunning)).Build()
	r := &ScalewayElasticMetalMachineReconciler{
		Client:             cl,
		CredentialsManager: &credentials.Manager{Client: cl, Namespace: "tuist"},
	}

	res, err := r.reconcileDelete(context.Background(), machine)
	if err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}
	assertReleaseHeld(t, cl, res.RequeueAfter, controllerutil.ContainsFinalizer(machine, ElasticMetalMachineFinalizer))
}

func TestVultrReconcileDeleteWaitsForRunnerJobs(t *testing.T) {
	machine := vultrMachine("tuist", runnerBox, "box-1")
	machine.Finalizers = []string{VultrMachineFinalizer}
	reinstalled := ""
	cl := fake.NewClientBuilder().WithScheme(vultrScheme(t)).
		WithObjects(machine, runnerBoxNode(corev1.ConditionTrue), runnerPod("job", runnerBox, corev1.PodRunning)).Build()
	r := &VultrMachineReconciler{
		Client:             cl,
		CredentialsManager: &credentials.Manager{Client: cl, Namespace: "tuist"},
		VultrClient:        newFakeVultrAPI(func(id string) { reinstalled = id }),
	}

	res, err := r.reconcileDelete(context.Background(), machine)
	if err != nil {
		t.Fatalf("reconcileDelete: %v", err)
	}
	if reinstalled != "" {
		t.Fatalf("reinstalled %q while a runner job was still running on it", reinstalled)
	}
	assertReleaseHeld(t, cl, res.RequeueAfter, controllerutil.ContainsFinalizer(machine, VultrMachineFinalizer))
}

func assertReleaseHeld(t *testing.T, cl client.Client, requeueAfter time.Duration, finalizerKept bool) {
	t.Helper()
	if !finalizerKept {
		t.Fatal("the box was released while a runner job was still running on it")
	}
	if requeueAfter != shared.RunnerJobsRecheckInterval {
		t.Fatalf("requeueAfter = %s, want %s", requeueAfter, shared.RunnerJobsRecheckInterval)
	}
	node := &corev1.Node{}
	if err := cl.Get(context.Background(), types.NamespacedName{Name: runnerBox}, node); err != nil {
		t.Fatalf("the Node is gone while a runner job was still running on it: %v", err)
	}
	if !node.Spec.Unschedulable {
		t.Fatal("the Node was not cordoned")
	}
}
