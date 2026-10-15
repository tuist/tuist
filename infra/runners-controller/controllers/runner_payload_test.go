package controllers

import (
	"context"
	"testing"

	corev1 "k8s.io/api/core/v1"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/podtemplate"
)

const (
	testImage      = "ghcr.io/tuist/tuist-runner:macos-26-5-1.0.0"
	currentPayload = "ghcr.io/tuist/tuist-runner-payload@sha256:current"
	oldPayload     = "ghcr.io/tuist/tuist-runner-payload@sha256:old"
)

func payloadPool(payload string) *tuistv1.RunnerPool {
	pool := newPool("p", testImage, 1)
	if payload != "" {
		pool.Annotations = map[string]string{podtemplate.RunnerPayloadAnnotation: payload}
	}
	return pool
}

func podOnPayload(name string, phase corev1.PodPhase, payload string) *corev1.Pod {
	pod := newRunnerPod(name, testImage, phase, "p")
	if payload != "" {
		pod.Annotations = map[string]string{podtemplate.RunnerPayloadAnnotation: payload}
	}
	return pod
}

func TestIsStalePayload(t *testing.T) {
	linux := newLinuxKataPool("p", 1, 1)
	linux.Annotations = map[string]string{podtemplate.RunnerPayloadAnnotation: currentPayload}

	cases := []struct {
		name string
		pool *tuistv1.RunnerPool
		pod  *corev1.Pod
		want bool
	}{
		{"booted the pinned payload", payloadPool(currentPayload), podOnPayload("x", corev1.PodRunning, currentPayload), false},
		{"booted an older payload", payloadPool(currentPayload), podOnPayload("x", corev1.PodRunning, oldPayload), true},
		{"booted before the pool pinned one", payloadPool(currentPayload), podOnPayload("x", corev1.PodRunning, ""), true},
		{"pool pins no payload", payloadPool(""), podOnPayload("x", corev1.PodRunning, oldPayload), false},
		{"linux pool", linux, podOnPayload("x", corev1.PodRunning, oldPayload), false},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if got := isStalePayload(tc.pod, tc.pool); got != tc.want {
				t.Fatalf("isStalePayload = %v, want %v", got, tc.want)
			}
		})
	}
}

func reconcilePayloadPool(t *testing.T, pool *tuistv1.RunnerPool, pods ...*corev1.Pod) client.Client {
	t.Helper()
	scheme := mustScheme(t)
	objects := []client.Object{pool}
	for _, p := range pods {
		objects = append(objects, p)
	}
	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(objects...).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()
	r := &RunnerPoolReconciler{Client: c, Scheme: scheme, DispatchURL: "http://dispatch"}
	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: nn(pool.Namespace, pool.Name)}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	return c
}

func TestReconcile_MarksIdlePodOnOlderPayloadDrainEligible(t *testing.T) {
	stale := podOnPayload("p-runner-stale", corev1.PodRunning, oldPayload)

	c := reconcilePayloadPool(t, payloadPool(currentPayload), stale)

	got := &corev1.Pod{}
	if err := c.Get(context.Background(), client.ObjectKeyFromObject(stale), got); err != nil {
		t.Fatalf("get pod: %v", err)
	}
	if got.Labels[drainEligibleLabel] != "true" {
		t.Fatalf("idle Pod on an older payload was not marked drain-eligible: labels %v", got.Labels)
	}
}

func TestReconcile_LeavesClaimedPodOnOlderPayloadAlone(t *testing.T) {
	claimed := podOnPayload("p-runner-claimed", corev1.PodRunning, oldPayload)
	claimed.Labels["tuist.dev/runner-pool-owner"] = "account"

	c := reconcilePayloadPool(t, payloadPool(currentPayload), claimed)

	got := &corev1.Pod{}
	if err := c.Get(context.Background(), client.ObjectKeyFromObject(claimed), got); err != nil {
		t.Fatalf("claimed Pod on an older payload was interrupted: %v", err)
	}
	if got.Labels[drainEligibleLabel] == "true" {
		t.Fatal("claimed Pod on an older payload was marked drain-eligible")
	}
}

func TestReconcile_ReplacesPendingPodOnOlderPayload(t *testing.T) {
	stale := podOnPayload("p-runner-stale", corev1.PodPending, oldPayload)

	c := reconcilePayloadPool(t, payloadPool(currentPayload), stale)

	pods := &corev1.PodList{}
	if err := c.List(context.Background(), pods); err != nil {
		t.Fatalf("list pods: %v", err)
	}
	if len(pods.Items) != 1 || pods.Items[0].Name == stale.Name {
		t.Fatalf("pods = %v, want one replacement for the stale Pending Pod", podNames(pods.Items))
	}
	if got := pods.Items[0].Annotations[podtemplate.RunnerPayloadAnnotation]; got != currentPayload {
		t.Fatalf("replacement payload = %q, want %q", got, currentPayload)
	}
}

func TestReconcile_KeepsPodOnPinnedPayload(t *testing.T) {
	current := podOnPayload("p-runner-current", corev1.PodRunning, currentPayload)

	c := reconcilePayloadPool(t, payloadPool(currentPayload), current)

	got := &corev1.Pod{}
	if err := c.Get(context.Background(), client.ObjectKeyFromObject(current), got); err != nil {
		t.Fatalf("get pod: %v", err)
	}
	if got.Labels[drainEligibleLabel] == "true" {
		t.Fatal("Pod on the pinned payload was marked drain-eligible")
	}
}
