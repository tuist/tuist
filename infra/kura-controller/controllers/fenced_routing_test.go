package controllers

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
)

func acknowledgedRoute(t *testing.T) (*ServingAuthorityReconciler, servingGrant, map[string]runtimeStatus) {
	t.Helper()
	r, _, statuses := authorityFixture(t)
	grant := authorityStep(t, r)
	pod := &corev1.Pod{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: grant.PodName, Namespace: "test"}, pod); err != nil {
		t.Fatal(err)
	}
	pod.Status.ContainerStatuses = []corev1.ContainerStatus{{Name: "kura", State: corev1.ContainerState{Running: &corev1.ContainerStateRunning{StartedAt: metav1.NewTime(time.Now().Add(-time.Minute))}}}}
	if err := r.Status().Update(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
	sample := statuses[grant.PodName]
	sample.ServingAuthority.Valid = true
	sample.ServingAuthority.Epoch = grant.Epoch
	sample.ServingAuthority.Observed = &grant
	statuses[grant.PodName] = sample
	authorityStep(t, r)
	assertRoute(t, r, grant.PodName)
	return r, grant, statuses
}

func assertRoute(t *testing.T, r *ServingAuthorityReconciler, want string) {
	t.Helper()
	service := &corev1.Service{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: "test", Namespace: "test"}, service); err != nil {
		t.Fatal(err)
	}
	if got := service.Spec.Selector[podNameLabel]; got != want {
		t.Fatalf("route = %q, want %q", got, want)
	}
}

func TestFencedRoutingRejectsHTTPFailuresAndMalformedStatus(t *testing.T) {
	for _, responseCase := range []struct {
		name   string
		status int
		body   string
	}{
		{"HTTP 503", http.StatusServiceUnavailable, "unavailable"},
		{"malformed JSON", http.StatusOK, "not a runtime status"},
		{"wrong field type", http.StatusOK, `{"ready":"wrong"}`},
		{"null", http.StatusOK, "null"},
	} {
		t.Run(responseCase.name, func(t *testing.T) {
			r, _, _ := acknowledgedRoute(t)
			response := httptest.NewRecorder()
			response.WriteHeader(responseCase.status)
			_, _ = response.WriteString(responseCase.body)
			_, err := decodeRuntimeStatus(response.Result())
			if err == nil {
				t.Fatal("invalid response accepted")
			}
			r.RuntimeStatusClient = fakeRuntimeStatusClient{err: err}
			authorityStep(t, r)
			assertRoute(t, r, "fenced-unavailable")
		})
	}
}

func TestFencedRoutingPreservesPublishedHolderDuringProbeGap(t *testing.T) {
	for _, phase := range []string{"Serving", "Quiescing"} {
		t.Run(phase, func(t *testing.T) {
			r, grant, statuses := acknowledgedRoute(t)
			grant.Phase = phase
			grant.ExpiresMS = time.Now().UnixMilli() + 9000
			if phase == "Quiescing" {
				grant.Handover = &handoverIntent{ID: "pending", DeadlineMS: time.Now().UnixMilli() + 300000}
			}
			writeAuthorityGrant(t, r, grant)
			delete(statuses, grant.PodName)
			next := authorityStep(t, r)
			assertRoute(t, r, grant.PodName)
			if next.Epoch != grant.Epoch || next.ExpiresMS != grant.ExpiresMS || next.Holder != grant.Holder {
				t.Fatal("routing fallback changed authority", next)
			}
		})
	}
}

func TestFencedRoutingDoesNotHideRefusalOrIdentityChanges(t *testing.T) {
	for _, fault := range []string{"refusal", "epoch", "incarnation", "pod-replaced", "host-changed", "restarted", "terminating", "unready", "expired", "overlong", "unpublished", "fencing", "revoking"} {
		t.Run(fault, func(t *testing.T) {
			r, grant, statuses := acknowledgedRoute(t)
			sample := statuses[grant.PodName]
			switch fault {
			case "refusal":
				sample.ServingAuthority.Valid = false
			case "epoch":
				sample.ServingAuthority.Epoch++
			case "incarnation":
				sample.ServingAuthority.Identity.Incarnation = "new-process"
			case "fencing", "revoking":
				if fault == "fencing" {
					grant.Phase = "Fencing"
				} else {
					grant.Phase = "Revoking"
				}
				writeAuthorityGrant(t, r, grant)
			case "expired", "overlong":
				grant.ExpiresMS = time.Now().UnixMilli() + 1000
				if fault == "overlong" {
					grant.ExpiresMS = time.Now().UnixMilli() + 20000
				}
				writeAuthorityGrant(t, r, grant)
			case "unpublished":
				service := &corev1.Service{}
				key := types.NamespacedName{Name: "test", Namespace: "test"}
				if err := r.Get(context.Background(), key, service); err != nil {
					t.Fatal(err)
				}
				service.Spec.Selector[podNameLabel] = "fenced-unavailable"
				if err := r.Update(context.Background(), service); err != nil {
					t.Fatal(err)
				}
			default:
				pod := &corev1.Pod{}
				key := types.NamespacedName{Name: grant.PodName, Namespace: "test"}
				if err := r.Get(context.Background(), key, pod); err != nil {
					t.Fatal(err)
				}
				if fault == "pod-replaced" {
					pod.UID = "replacement"
				}
				if fault == "host-changed" {
					pod.Spec.NodeName = "different-host"
				}
				if fault == "restarted" {
					pod.Status.ContainerStatuses[0].State.Running.StartedAt = metav1.Now()
					if err := r.Status().Update(context.Background(), pod); err != nil {
						t.Fatal(err)
					}
				}
				if fault == "unready" {
					pod.Status.Conditions[0].Status = corev1.ConditionFalse
					if err := r.Status().Update(context.Background(), pod); err != nil {
						t.Fatal(err)
					}
				}
				if fault == "terminating" {
					pod.Finalizers = []string{"test/hold"}
					if err := r.Update(context.Background(), pod); err != nil {
						t.Fatal(err)
					}
					if err := r.Delete(context.Background(), pod); err != nil {
						t.Fatal(err)
					}
				} else if err := r.Update(context.Background(), pod); err != nil {
					t.Fatal(err)
				}
			}
			statuses[grant.PodName] = sample
			if fault != "refusal" && fault != "epoch" && fault != "incarnation" {
				delete(statuses, grant.PodName)
			}
			authorityStep(t, r)
			assertRoute(t, r, "fenced-unavailable")
		})
	}
}
