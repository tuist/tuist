package shared

import (
	"context"
	"reflect"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

const runnerBox = "tuist-tuist-ovh-fleet-runners-linux-abc12-xyz34"

func runnerJobsScheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatalf("add scheme: %v", err)
	}
	return scheme
}

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
			cl := fake.NewClientBuilder().WithScheme(runnerJobsScheme(t)).WithObjects(objs...).Build()

			got, err := HoldReleaseForRunnerJobs(context.Background(), cl, runnerBox)
			if err != nil {
				t.Fatalf("HoldReleaseForRunnerJobs: %v", err)
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
	cl := fake.NewClientBuilder().WithScheme(runnerJobsScheme(t)).
		WithObjects(runnerPod("orphan", runnerBox, corev1.PodRunning)).Build()

	got, err := HoldReleaseForRunnerJobs(context.Background(), cl, runnerBox)
	if err != nil {
		t.Fatalf("HoldReleaseForRunnerJobs: %v", err)
	}
	if len(got) != 0 {
		t.Fatalf("running = %v, want none: a Pod bound to a Node that is gone cannot finish", got)
	}
}
