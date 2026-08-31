package podagent

import (
	"context"
	"os"
	"path/filepath"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

func writeHeartbeat(t *testing.T, dir, state string, at time.Time) {
	t.Helper()
	path := filepath.Join(dir, runnerHeartbeatFile)
	if err := os.WriteFile(path, []byte(state), 0o644); err != nil {
		t.Fatalf("write heartbeat: %v", err)
	}
	if err := os.Chtimes(path, at, at); err != nil {
		t.Fatalf("chtimes: %v", err)
	}
}

func TestReadRunnerHeartbeat(t *testing.T) {
	beat := time.Now().Add(-90 * time.Second).Truncate(time.Second)

	t.Run("reports the state and the mtime of the beat", func(t *testing.T) {
		dir := t.TempDir()
		writeHeartbeat(t, dir, heartbeatStatePolling+"\n", beat)

		state, at, ok := readRunnerHeartbeat(dir)
		if !ok || state != heartbeatStatePolling {
			t.Fatalf("readRunnerHeartbeat = (%q, %v, %v), want polling", state, at, ok)
		}
		if !at.Equal(beat) {
			t.Fatalf("beat time = %v, want %v", at, beat)
		}
	})

	t.Run("reads claimed", func(t *testing.T) {
		dir := t.TempDir()
		writeHeartbeat(t, dir, heartbeatStateClaimed, beat)
		if state, _, ok := readRunnerHeartbeat(dir); !ok || state != heartbeatStateClaimed {
			t.Fatalf("state = %q ok = %v, want claimed", state, ok)
		}
	})

	// The states drive whether the controller counts a Pod as capacity,
	// and the file is written by untrusted customer CI, so the set is
	// closed: anything else is no signal rather than a state to act on.
	t.Run("rejects a state it does not model", func(t *testing.T) {
		dir := t.TempDir()
		writeHeartbeat(t, dir, "definitely-warm", beat)
		if _, _, ok := readRunnerHeartbeat(dir); ok {
			t.Error("accepted a state outside the modelled set")
		}
	})

	t.Run("absent file is no signal", func(t *testing.T) {
		if _, _, ok := readRunnerHeartbeat(t.TempDir()); ok {
			t.Error("reported a beat with no file present")
		}
	})

	t.Run("no status share is no signal", func(t *testing.T) {
		if _, _, ok := readRunnerHeartbeat(""); ok {
			t.Error("reported a beat with no status share")
		}
	})
}

func heartbeatPod(name string, annotations map[string]string) *corev1.Pod {
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Namespace:   "tuist-runners",
			Name:        name,
			Annotations: annotations,
		},
		Spec: corev1.PodSpec{
			Containers: []corev1.Container{{Name: "runner", Image: "ghcr.io/tuist/tuist-runner:test"}},
		},
		Status: corev1.PodStatus{Phase: corev1.PodRunning},
	}
}

func podAnnotations(t *testing.T, c client.Client, name string) map[string]string {
	t.Helper()
	got := &corev1.Pod{}
	if err := c.Get(context.Background(), types.NamespacedName{Namespace: "tuist-runners", Name: name}, got); err != nil {
		t.Fatalf("get pod: %v", err)
	}
	return got.Annotations
}

func heartbeatReconciler(t *testing.T, pod *corev1.Pod, statusDir string) (*Reconciler, client.Client) {
	t.Helper()
	kubeClient := newPodTestClient(t, pod)
	store := NewStore()
	store.Put(pod.Namespace, pod.Name, &Entry{VMName: "vm-" + pod.Name, VolumeStatusDir: statusDir})
	return &Reconciler{CachedClient: kubeClient, Store: store}, kubeClient
}

func TestPublishRunnerHeartbeat(t *testing.T) {
	ctx := context.Background()

	t.Run("publishes the guest's state and beat", func(t *testing.T) {
		dir := t.TempDir()
		beat := time.Now().Add(-10 * time.Second).Truncate(time.Second)
		writeHeartbeat(t, dir, heartbeatStatePolling, beat)

		pod := heartbeatPod("runner-a", nil)
		r, c := heartbeatReconciler(t, pod, dir)
		if err := r.publishRunnerHeartbeat(ctx, pod); err != nil {
			t.Fatalf("publishRunnerHeartbeat: %v", err)
		}

		got := podAnnotations(t, c, "runner-a")
		if got[runnerHeartbeatStateAnnotation] != heartbeatStatePolling {
			t.Fatalf("state annotation = %q, want polling", got[runnerHeartbeatStateAnnotation])
		}
		if got[runnerHeartbeatAtAnnotation] != beat.UTC().Format(time.RFC3339) {
			t.Fatalf("beat annotation = %q, want %q", got[runnerHeartbeatAtAnnotation], beat.UTC().Format(time.RFC3339))
		}
	})

	// The guest beats every couple of seconds and this reconciler runs
	// every 30. Writing the Pod each time would be a write per Pod per
	// reconcile just to move a timestamp nothing reads at that resolution.
	t.Run("does not republish a beat that barely moved", func(t *testing.T) {
		dir := t.TempDir()
		published := time.Now().Add(-40 * time.Second).UTC().Truncate(time.Second)
		writeHeartbeat(t, dir, heartbeatStatePolling, published.Add(20*time.Second))

		pod := heartbeatPod("runner-b", map[string]string{
			runnerHeartbeatStateAnnotation: heartbeatStatePolling,
			runnerHeartbeatAtAnnotation:    published.Format(time.RFC3339),
		})
		r, c := heartbeatReconciler(t, pod, dir)
		if err := r.publishRunnerHeartbeat(ctx, pod); err != nil {
			t.Fatalf("publishRunnerHeartbeat: %v", err)
		}

		if got := podAnnotations(t, c, "runner-b")[runnerHeartbeatAtAnnotation]; got != published.Format(time.RFC3339) {
			t.Fatalf("beat annotation = %q, want it left at %q", got, published.Format(time.RFC3339))
		}
	})

	t.Run("republishes once the beat has moved past the interval", func(t *testing.T) {
		dir := t.TempDir()
		published := time.Now().Add(-5 * time.Minute).UTC().Truncate(time.Second)
		beat := published.Add(heartbeatRepublishInterval + time.Second)
		writeHeartbeat(t, dir, heartbeatStatePolling, beat)

		pod := heartbeatPod("runner-c", map[string]string{
			runnerHeartbeatStateAnnotation: heartbeatStatePolling,
			runnerHeartbeatAtAnnotation:    published.Format(time.RFC3339),
		})
		r, c := heartbeatReconciler(t, pod, dir)
		if err := r.publishRunnerHeartbeat(ctx, pod); err != nil {
			t.Fatalf("publishRunnerHeartbeat: %v", err)
		}

		if got := podAnnotations(t, c, "runner-c")[runnerHeartbeatAtAnnotation]; got != beat.Format(time.RFC3339) {
			t.Fatalf("beat annotation = %q, want %q", got, beat.Format(time.RFC3339))
		}
	})

	// A state change is what tells the controller the Pod stopped being
	// warm, so it must never wait on the timestamp throttle.
	t.Run("publishes a state change immediately", func(t *testing.T) {
		dir := t.TempDir()
		published := time.Now().Add(-10 * time.Second).UTC().Truncate(time.Second)
		writeHeartbeat(t, dir, heartbeatStateClaimed, published.Add(time.Second))

		pod := heartbeatPod("runner-d", map[string]string{
			runnerHeartbeatStateAnnotation: heartbeatStatePolling,
			runnerHeartbeatAtAnnotation:    published.Format(time.RFC3339),
		})
		r, c := heartbeatReconciler(t, pod, dir)
		if err := r.publishRunnerHeartbeat(ctx, pod); err != nil {
			t.Fatalf("publishRunnerHeartbeat: %v", err)
		}

		if got := podAnnotations(t, c, "runner-d")[runnerHeartbeatStateAnnotation]; got != heartbeatStateClaimed {
			t.Fatalf("state annotation = %q, want claimed", got)
		}
	})

	// A guest that stopped beating is exactly the state worth reporting.
	// Clearing the annotations here would turn it back into "no signal",
	// which is the reading that fails open.
	t.Run("leaves a previous beat in place when the file goes away", func(t *testing.T) {
		published := time.Now().Add(-2 * time.Hour).UTC().Truncate(time.Second)
		pod := heartbeatPod("runner-e", map[string]string{
			runnerHeartbeatStateAnnotation: heartbeatStatePolling,
			runnerHeartbeatAtAnnotation:    published.Format(time.RFC3339),
		})
		r, c := heartbeatReconciler(t, pod, t.TempDir())
		if err := r.publishRunnerHeartbeat(ctx, pod); err != nil {
			t.Fatalf("publishRunnerHeartbeat: %v", err)
		}

		got := podAnnotations(t, c, "runner-e")
		if got[runnerHeartbeatAtAnnotation] != published.Format(time.RFC3339) {
			t.Fatalf("beat annotation = %q, want the stale beat preserved", got[runnerHeartbeatAtAnnotation])
		}
	})

	// A Pod with no status share must stay unannotated: the controller
	// reads absence as "this host cannot speak for the guest" and keeps
	// counting the Pod as capacity.
	t.Run("publishes nothing without a status share", func(t *testing.T) {
		pod := heartbeatPod("runner-f", nil)
		r, c := heartbeatReconciler(t, pod, "")
		if err := r.publishRunnerHeartbeat(ctx, pod); err != nil {
			t.Fatalf("publishRunnerHeartbeat: %v", err)
		}
		if got := podAnnotations(t, c, "runner-f"); got[runnerHeartbeatStateAnnotation] != "" {
			t.Fatalf("annotations = %v, want none", got)
		}
	})

	// A host clock stepped backwards leaves a beat dated ahead of now.
	// Publishing it would make the Pod read fresh for as long as the skew
	// lasts, which is the one direction this signal must not fail.
	t.Run("clamps a beat dated ahead of the host", func(t *testing.T) {
		dir := t.TempDir()
		writeHeartbeat(t, dir, heartbeatStatePolling, time.Now().Add(time.Hour))

		pod := heartbeatPod("runner-g", nil)
		r, c := heartbeatReconciler(t, pod, dir)
		if err := r.publishRunnerHeartbeat(ctx, pod); err != nil {
			t.Fatalf("publishRunnerHeartbeat: %v", err)
		}

		raw := podAnnotations(t, c, "runner-g")[runnerHeartbeatAtAnnotation]
		at, err := time.Parse(time.RFC3339, raw)
		if err != nil {
			t.Fatalf("parse published beat %q: %v", raw, err)
		}
		if at.After(time.Now().Add(time.Minute)) {
			t.Fatalf("published beat %v is in the future; want it clamped to now", at)
		}
	})
}
