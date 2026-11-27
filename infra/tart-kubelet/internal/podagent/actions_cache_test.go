package podagent

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func TestVMPodsResolvesOnlyThisHostsRunningRunnerVMs(t *testing.T) {
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	pod := func(name, node, ip string, phase corev1.PodPhase, runner bool) *corev1.Pod {
		labels := map[string]string{}
		if runner {
			labels[runnerPodLabel] = "true"
		}
		return &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "tuist-runners", UID: types.UID("uid-" + name), Labels: labels},
			Spec: corev1.PodSpec{NodeName: node}, Status: corev1.PodStatus{PodIP: ip, Phase: phase}}
	}
	reader := fake.NewClientBuilder().WithScheme(scheme).WithObjects(
		pod("runner", "mini-1", "192.168.64.5", corev1.PodRunning, true),
		pod("elsewhere", "mini-2", "192.168.64.6", corev1.PodRunning, true),
		pod("pending", "mini-1", "192.168.64.7", corev1.PodPending, true),
		pod("service", "mini-1", "192.168.64.8", corev1.PodRunning, false),
	).Build()
	pods := &vmPods{reader: reader, node: "mini-1"}

	caller, err := pods.caller(context.Background(), "192.168.64.5")
	if err != nil || caller.PodName != "runner" || caller.PodUID != "uid-runner" {
		t.Fatalf("caller = %+v, %v; want the runner Pod", caller, err)
	}
	for _, ip := range []string{"192.168.64.6", "192.168.64.7", "192.168.64.8", "10.10.0.20"} {
		if caller, err := pods.caller(context.Background(), ip); err == nil {
			t.Fatalf("%s resolved to %+v; only this host's running runner VMs may use the cache", ip, caller)
		}
	}
}

func TestGuestsOnlyRefusesTheHostsSegment(t *testing.T) {
	handler := guestsOnly(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) { w.WriteHeader(http.StatusNoContent) }))
	for addr, want := range map[string]int{
		"192.168.64.5:50000": http.StatusNoContent,
		"192.168.67.9:50000": http.StatusNoContent,
		"192.168.68.1:50000": http.StatusForbidden,
		"10.20.0.14:50000":   http.StatusForbidden,
		"[fe80::1]:50000":    http.StatusForbidden,
	} {
		request := httptest.NewRequest(http.MethodGet, "/actions-cache/healthz", nil)
		request.RemoteAddr = addr
		recorder := httptest.NewRecorder()
		handler.ServeHTTP(recorder, request)
		if recorder.Code != want {
			t.Errorf("%s: status %d, want %d", addr, recorder.Code, want)
		}
	}
}
