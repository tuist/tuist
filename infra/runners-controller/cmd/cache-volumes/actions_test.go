package main

import (
	"context"
	"errors"
	"testing"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/kubernetes/fake"
)

func runnerPod(name, uid, node, ip string, phase corev1.PodPhase) *corev1.Pod {
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "runners", UID: types.UID(uid), Labels: map[string]string{"tuist.dev/runner": "true"}},
		Spec:       corev1.PodSpec{NodeName: node},
		Status:     corev1.PodStatus{PodIP: ip, Phase: phase},
	}
}

func TestRunnerPodsResolveOnlyRunningRunnersOnThisNode(t *testing.T) {
	pods := &runnerPods{namespace: "runners", node: "node", kube: fake.NewSimpleClientset(
		runnerPod("runner", "uid-1", "node", "10.0.0.1", corev1.PodRunning),
		runnerPod("elsewhere", "uid-2", "other", "10.0.0.2", corev1.PodRunning),
		runnerPod("finished", "uid-3", "node", "10.0.0.3", corev1.PodSucceeded),
	)}

	caller, err := pods.caller(context.Background(), "10.0.0.1")
	if err != nil || caller != (cachevolumes.ActionsCaller{PodName: "runner", PodUID: "uid-1"}) {
		t.Fatalf("resolved %+v, %v", caller, err)
	}
	pods.listed = time.Time{}
	for _, ip := range []string{"10.0.0.2", "10.0.0.3", "10.0.0.9"} {
		pods.listed = time.Time{}
		if _, err := pods.caller(context.Background(), ip); !errors.Is(err, errUnknownCaller) {
			t.Fatalf("resolved %s: %v", ip, err)
		}
	}
}
