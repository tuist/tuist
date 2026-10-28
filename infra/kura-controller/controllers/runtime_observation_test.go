package controllers

import (
	"context"
	"errors"
	"io"
	"net/http"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
)

func TestInvalidRuntimeObservationDoesNotResetCounters(t *testing.T) {
	r, instance, statuses := authorityFixture(t)
	pod := &corev1.Pod{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: "test-0", Namespace: "test"}, pod); err != nil {
		t.Fatal(err)
	}
	status := statuses[pod.Name]
	status.FDTimeoutCount, status.PeerConnectionFailureCount = 7, 11
	statuses[pod.Name] = status
	workload := &KuraInstanceReconciler{Client: r.Client, Scheme: r.Scheme(), RuntimeStatusClient: fakeRuntimeStatusClient{statuses: statuses}}
	workload.sampleRuntimeStatuses(context.Background(), instance, []corev1.Pod{*pod})
	key := types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}
	sample := workload.podSamples[key][pod.Name]
	sampledAt := sample.sampledAt
	workload.RuntimeStatusClient = fakeRuntimeStatusClient{err: &runtimeStatusResponseError{cause: errors.New("HTTP 503")}}
	workload.sampleRuntimeStatuses(context.Background(), instance, []corev1.Pod{*pod})
	if !sample.sampledAt.Equal(sampledAt) {
		t.Fatal("invalid response refreshed last successful sample")
	}
	workload.RuntimeStatusClient = fakeRuntimeStatusClient{statuses: statuses}
	workload.sampleRuntimeStatuses(context.Background(), instance, []corev1.Pod{*pod})
	if sample.clampedFDTimeouts() != 7 || sample.clampedPeerFailures() != 11 {
		t.Fatalf("inflated counters: %+v", sample)
	}
}

func TestInvalidRuntimeObservationPreservesLegacyReadinessFallback(t *testing.T) {
	r, instance, _ := authorityFixture(t)
	pod := &corev1.Pod{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: "test-0", Namespace: "test"}, pod); err != nil {
		t.Fatal(err)
	}
	pod.CreationTimestamp = metav1.NewTime(time.Now().Add(-time.Hour))
	workload := &KuraInstanceReconciler{Client: r.Client, RuntimeStatusClient: fakeRuntimeStatusClient{err: &runtimeStatusResponseError{cause: errors.New("HTTP 503")}}}
	pods := []corev1.Pod{*pod}
	fresh := workload.sampleRuntimeStatuses(context.Background(), instance, pods)
	healthy, caughtUp := primaryPodHealthFromSamples(instance, pods, fresh, time.Now())
	if !healthy[pod.Name] || caughtUp[pod.Name] {
		t.Fatal("invalid response changed legacy readiness fallback", healthy, caughtUp)
	}
}

type interruptedStatusBody struct{ err error }

func (b interruptedStatusBody) Read([]byte) (int, error) { return 0, b.err }
func (b interruptedStatusBody) Close() error             { return nil }

func TestRuntimeBodyTransportFailureKeepsPublishedRoute(t *testing.T) {
	for _, failure := range []error{context.DeadlineExceeded, io.ErrUnexpectedEOF} {
		t.Run(failure.Error(), func(t *testing.T) {
			r, grant, _ := acknowledgedRoute(t)
			response := &http.Response{StatusCode: http.StatusOK, Body: interruptedStatusBody{err: failure}}
			_, err := decodeRuntimeStatus(response)
			if err == nil {
				t.Fatal("failed read accepted")
			}
			r.RuntimeStatusClient = fakeRuntimeStatusClient{err: err}
			authorityStep(t, r)
			assertRoute(t, r, grant.PodName)
		})
	}
}
