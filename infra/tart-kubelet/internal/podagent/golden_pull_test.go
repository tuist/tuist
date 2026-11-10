package podagent

import (
	"context"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/event"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/envresolver"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

const pulledImage = "ghcr.io/tuist/tuist-runner@sha256:" + "1111111111111111111111111111111111111111111111111111111111111111"

// fakeTartWithSlowPull is a tart whose `pull` blocks until release is
// created (or fails when failPull is set) and whose VMs exist once cloned.
func fakeTartWithSlowPull(t *testing.T, failPull bool) (bin, release string) {
	t.Helper()
	dir := t.TempDir()
	release = filepath.Join(dir, "release")
	pull := `while [ ! -f '` + release + `' ]; do sleep 0.05; done`
	if failPull {
		pull = `echo 'connection reset' >&2; exit 1`
	}
	script := "#!/bin/sh\n" +
		"case \"$1\" in\n" +
		"get) if [ -f '" + dir + "/vm-'\"$2\" ]; then echo '{}'; exit 0; fi; echo 'the specified VM \"x\" does not exist' >&2; exit 1;;\n" +
		"pull) " + pull + ";;\n" +
		"clone) eval last=\\${$#}; touch '" + dir + "/vm-'\"$last\";;\n" +
		"esac\n" +
		"exit 0\n"
	bin = filepath.Join(dir, "faketart")
	if err := os.WriteFile(bin, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = os.WriteFile(release, nil, 0o600) })
	return bin, release
}

func runnerPod(name string) *corev1.Pod {
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Namespace:  "tuist-runners",
			Name:       name,
			Finalizers: []string{PodFinalizer},
		},
		Spec: corev1.PodSpec{
			NodeName:   "mini-1",
			Containers: []corev1.Container{{Name: "runner", Image: pulledImage}},
		},
	}
}

func awaitPodEvent(t *testing.T, events <-chan event.GenericEvent, name string) {
	t.Helper()
	deadline := time.After(10 * time.Second)
	for {
		select {
		case ev := <-events:
			if ev.Object.GetName() == name {
				return
			}
		case <-deadline:
			t.Fatalf("pod %s was not re-enqueued when its golden finished", name)
		}
	}
}

// On 2026-10-21 the first Pod of a new runner image on two rack hosts pulled
// its golden for 532 s and 562 s inside its reconcile. The single reconcile
// worker could not tear down the hosts' finished Pods meanwhile, so their VM
// slots stayed taken and a job queued for eight minutes on an idle account.
func TestGoldenPullDoesNotBlockAnotherPodsDeletion(t *testing.T) {
	ctx := context.Background()
	bin, release := fakeTartWithSlowPull(t, false)

	pulling := runnerPod("runner-first-of-new-image")
	deletedAt := metav1.Now()
	finished := runnerPod("runner-finished")
	finished.DeletionTimestamp = &deletedAt
	finished.Status.Phase = corev1.PodSucceeded

	kubeClient := newPodTestClient(t, pulling, finished)
	events := make(chan event.GenericEvent, 8)
	r := &Reconciler{
		CachedClient:  kubeClient,
		NodeName:      "mini-1",
		Tart:          &tart.Client{Binary: bin, UserDataDir: t.TempDir()},
		Resolver:      &envresolver.Resolver{K8s: kubeClient},
		Store:         NewStore(),
		requeueEvents: events,
	}

	done := make(chan ctrl.Result, 1)
	go func() {
		result, err := r.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Namespace: "tuist-runners", Name: pulling.Name}})
		if err != nil {
			t.Errorf("Reconcile: %v", err)
		}
		done <- result
	}()
	select {
	case result := <-done:
		if result.RequeueAfter <= 0 {
			t.Fatalf("result = %+v, want a requeue while the golden pulls", result)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("the reconcile of a Pod waiting on its golden held the worker for the whole pull")
	}

	if _, err := r.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Namespace: "tuist-runners", Name: finished.Name}}); err != nil {
		t.Fatalf("Reconcile: %v", err)
	}
	assertPodDeleted(t, ctx, kubeClient, types.NamespacedName{Namespace: "tuist-runners", Name: finished.Name})

	if _, _, err := r.readyGolden(ctx, pulling, pulledImage); !errors.Is(err, errGoldenPulling) {
		t.Fatalf("err = %v while the pull runs, want errGoldenPulling", err)
	}

	if err := os.WriteFile(release, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	awaitPodEvent(t, events, pulling.Name)

	name, pulledAt, err := r.readyGolden(ctx, pulling, pulledImage)
	if err != nil {
		t.Fatalf("readyGolden after the pull: %v", err)
	}
	if name != goldenVMName(pulledImage) || pulledAt.IsZero() {
		t.Fatalf("golden = %q pulledAt = %v, want %q pulled by this Pod's request", name, pulledAt, goldenVMName(pulledImage))
	}
	if _, pulledAt, err := r.readyGolden(ctx, pulling, pulledImage); err != nil || !pulledAt.IsZero() {
		t.Fatalf("second readyGolden: pulledAt = %v err = %v, want a reused golden", pulledAt, err)
	}
}

// A failed pull is reported to every Pod that waited on it until the retry
// interval passes, and only then pulled again.
func TestGoldenPullFailureIsReportedThenRetried(t *testing.T) {
	ctx := context.Background()
	bin, _ := fakeTartWithSlowPull(t, true)
	events := make(chan event.GenericEvent, 8)
	now := time.Date(2026, 10, 21, 10, 25, 0, 0, time.UTC)
	r := &Reconciler{
		Tart:          &tart.Client{Binary: bin},
		requeueEvents: events,
		now:           func() time.Time { return now },
	}
	first, second := runnerPod("runner-a"), runnerPod("runner-b")

	if _, _, err := r.readyGolden(ctx, first, pulledImage); !errors.Is(err, errGoldenPulling) {
		t.Fatalf("err = %v, want errGoldenPulling", err)
	}
	if _, _, err := r.readyGolden(ctx, second, pulledImage); !errors.Is(err, errGoldenPulling) {
		t.Fatalf("err = %v, want errGoldenPulling", err)
	}
	awaitPodEvent(t, events, first.Name)

	for _, pod := range []*corev1.Pod{first, second} {
		_, _, err := r.readyGolden(ctx, pod, pulledImage)
		if err == nil || errors.Is(err, errGoldenPulling) || !strings.Contains(err.Error(), "tart pull") {
			t.Fatalf("%s: err = %v, want the pull's failure", pod.Name, err)
		}
	}

	now = now.Add(goldenRetryInterval)
	if _, _, err := r.readyGolden(ctx, first, pulledImage); !errors.Is(err, errGoldenPulling) {
		t.Fatalf("err = %v after the retry interval, want a new pull", err)
	}
}
