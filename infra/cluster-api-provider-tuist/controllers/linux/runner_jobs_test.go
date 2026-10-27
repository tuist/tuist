package linux

import (
	"context"
	"reflect"
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
			Namespace: runnerPodNamespace,
			Name:      name,
			Labels:    map[string]string{runnerPodLabel: "true"},
		},
		Spec:   corev1.PodSpec{NodeName: nodeName},
		Status: corev1.PodStatus{Phase: phase},
	}
}

func terminating(pod *corev1.Pod) *corev1.Pod {
	now := metav1.Now()
	pod.DeletionTimestamp = &now
	pod.Finalizers = []string{"test.tuist.dev/hold"}
	return pod
}

func TestHoldReleaseForRunnerJobs(t *testing.T) {
	cases := []struct {
		name  string
		ready corev1.ConditionStatus
		pods  []client.Object
		want  []string
	}{
		{
			name:  "a runner Pod running a job holds the release",
			ready: corev1.ConditionTrue,
			pods:  []client.Object{runnerPod("job", runnerBox, corev1.PodRunning)},
			want:  []string{"job"},
		},
		{
			name:  "a runner Pod still starting on the Node holds the release",
			ready: corev1.ConditionTrue,
			pods:  []client.Object{runnerPod("starting", runnerBox, corev1.PodPending)},
			want:  []string{"starting"},
		},
		{
			name:  "finished runner Pods do not hold the release",
			ready: corev1.ConditionTrue,
			pods: []client.Object{
				runnerPod("succeeded", runnerBox, corev1.PodSucceeded),
				runnerPod("failed", runnerBox, corev1.PodFailed),
			},
		},
		{
			name:  "runner Pods on other Nodes do not hold the release",
			ready: corev1.ConditionTrue,
			pods:  []client.Object{runnerPod("elsewhere", "another-box", corev1.PodRunning)},
		},
		{
			name:  "Pods that are not runners do not hold the release",
			ready: corev1.ConditionTrue,
			pods: func() []client.Object {
				unlabelled := runnerPod("kura", runnerBox, corev1.PodRunning)
				unlabelled.Labels = nil
				otherNamespace := runnerPod("labelled-elsewhere", runnerBox, corev1.PodRunning)
				otherNamespace.Namespace = "kura"
				return []client.Object{unlabelled, otherNamespace}
			}(),
		},
		{
			name:  "a terminating runner Pod on a reachable Node holds the release",
			ready: corev1.ConditionTrue,
			pods:  []client.Object{terminating(runnerPod("stopping", runnerBox, corev1.PodRunning))},
			want:  []string{"stopping"},
		},
		{
			name:  "a terminating runner Pod on an unreachable Node does not hold the release",
			ready: corev1.ConditionUnknown,
			pods:  []client.Object{terminating(runnerPod("lost", runnerBox, corev1.PodRunning))},
		},
		{
			name:  "a running runner Pod on an unreachable Node holds the release",
			ready: corev1.ConditionUnknown,
			pods:  []client.Object{runnerPod("not-yet-evicted", runnerBox, corev1.PodRunning)},
			want:  []string{"not-yet-evicted"},
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			objs := append([]client.Object{runnerBoxNode(tc.ready)}, tc.pods...)
			cl := fake.NewClientBuilder().WithScheme(vultrScheme(t)).WithObjects(objs...).Build()

			got, err := holdReleaseForRunnerJobs(context.Background(), cl, runnerBox)
			if err != nil {
				t.Fatalf("holdReleaseForRunnerJobs: %v", err)
			}
			if !reflect.DeepEqual(got, tc.want) {
				t.Fatalf("running = %v, want %v", got, tc.want)
			}
			node := &corev1.Node{}
			if err := cl.Get(context.Background(), types.NamespacedName{Name: runnerBox}, node); err != nil {
				t.Fatalf("get Node: %v", err)
			}
			if !node.Spec.Unschedulable {
				t.Fatal("the Node was not cordoned, so new runner Pods keep landing and idle ones are never retired")
			}
		})
	}
}

func TestHoldReleaseForRunnerJobsWithoutNode(t *testing.T) {
	cl := fake.NewClientBuilder().WithScheme(vultrScheme(t)).
		WithObjects(runnerPod("orphan", runnerBox, corev1.PodRunning)).Build()

	got, err := holdReleaseForRunnerJobs(context.Background(), cl, runnerBox)
	if err != nil {
		t.Fatalf("holdReleaseForRunnerJobs: %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("running = %v, want none: a Pod bound to a Node that is gone cannot finish", got)
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
	if requeueAfter != runnerJobsRecheckInterval {
		t.Fatalf("requeueAfter = %s, want %s", requeueAfter, runnerJobsRecheckInterval)
	}
	node := &corev1.Node{}
	if err := cl.Get(context.Background(), types.NamespacedName{Name: runnerBox}, node); err != nil {
		t.Fatalf("the Node is gone while a runner job was still running on it: %v", err)
	}
	if !node.Spec.Unschedulable {
		t.Fatal("the Node was not cordoned")
	}
}
