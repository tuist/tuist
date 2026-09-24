package controllers

import (
	"reflect"
	"testing"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

const (
	rolloutOldImage = "ghcr.io/tuist/kura:0.5.2"
	rolloutNewImage = "ghcr.io/tuist/kura:0.5.3"
)

func rolloutInstance(image, observed string) *kurav1alpha1.KuraInstance {
	return &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-west-1", Namespace: "kura"},
		Spec:       kurav1alpha1.KuraInstanceSpec{Image: image, Replicas: ptr(int32(2))},
		Status:     kurav1alpha1.KuraInstanceStatus{ObservedImage: observed},
	}
}

// rolloutStatefulSet is a StatefulSet whose status is fully converged on its
// own template.
func rolloutStatefulSet(generation int64, templateImage, revision string) *appsv1.StatefulSet {
	return &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-west-1", Namespace: "kura", Generation: generation},
		Spec: appsv1.StatefulSetSpec{
			Template: corev1.PodTemplateSpec{Spec: corev1.PodSpec{Containers: []corev1.Container{{Name: kuraContainerName, Image: templateImage}}}},
		},
		Status: appsv1.StatefulSetStatus{
			ObservedGeneration: generation,
			Replicas:           2,
			ReadyReplicas:      2,
			UpdatedReplicas:    2,
			CurrentRevision:    revision,
			UpdateRevision:     revision,
		},
	}
}

func rolloutPod(ordinal int, image, revision string, ready bool) corev1.Pod {
	pod := kuraPod("kura-tuist-eu-west-1", "kura", ordinal, ready)
	pod.Labels[appsv1.StatefulSetRevisionLabel] = revision
	pod.Spec.Containers = []corev1.Container{{Name: kuraContainerName, Image: image}}
	return *pod
}

func assertRollout(t *testing.T, got rolloutState, wantPhase, wantImage string) {
	t.Helper()
	if got.phase != wantPhase || got.observedImage != wantImage {
		t.Fatalf("got phase=%q observedImage=%q (%s); want phase=%q observedImage=%q", got.phase, got.observedImage, got.message, wantPhase, wantImage)
	}
}

func TestRolloutStatusConvergedReportsNewImage(t *testing.T) {
	instance := rolloutInstance(rolloutNewImage, rolloutOldImage)
	sts := rolloutStatefulSet(3, rolloutNewImage, "rev-new")
	pods := []corev1.Pod{rolloutPod(0, rolloutNewImage, "rev-new", true), rolloutPod(1, rolloutNewImage, "rev-new", true)}

	got := rolloutStatusFromStatefulSet(instance, sts, pods)

	assertRollout(t, got, "Ready", rolloutNewImage)
	if got.message != "2/2 replicas ready on revision rev-new" {
		t.Fatalf("unexpected message %q", got.message)
	}
}

// The reconcile writes the new template and then reads the StatefulSet back
// through the informer cache, which can still hold the previous object: its
// generation, revisions and counters all agree with each other.
func TestRolloutStatusStaleReadAfterTemplateChangeKeepsPodImage(t *testing.T) {
	for _, strategy := range []appsv1.StatefulSetUpdateStrategyType{appsv1.RollingUpdateStatefulSetStrategyType, appsv1.OnDeleteStatefulSetStrategyType} {
		t.Run(string(strategy), func(t *testing.T) {
			instance := rolloutInstance(rolloutNewImage, rolloutOldImage)
			sts := rolloutStatefulSet(2, rolloutOldImage, "rev-old")
			sts.Spec.UpdateStrategy.Type = strategy
			if strategy == appsv1.OnDeleteStatefulSetStrategyType {
				sts.Status.CurrentRevision = "rev-original"
			}
			pods := []corev1.Pod{rolloutPod(0, rolloutOldImage, "rev-old", true), rolloutPod(1, rolloutOldImage, "rev-old", true)}

			assertRollout(t, rolloutStatusFromStatefulSet(instance, sts, pods), "Pending", rolloutOldImage)
		})
	}
}

func TestRolloutStatusMidRollWithMixedPodImages(t *testing.T) {
	sts := rolloutStatefulSet(3, rolloutNewImage, "rev-new")
	sts.Status.CurrentRevision = "rev-old"
	sts.Status.UpdatedReplicas = 1
	pods := []corev1.Pod{rolloutPod(0, rolloutOldImage, "rev-old", true), rolloutPod(1, rolloutNewImage, "rev-new", true)}

	t.Run("keeps the last converged image", func(t *testing.T) {
		assertRollout(t, rolloutStatusFromStatefulSet(rolloutInstance(rolloutNewImage, rolloutOldImage), sts, pods), "Pending", rolloutOldImage)
	})
	// An observedImage already latched to the target by an earlier stale read
	// must let go while a pod still runs the previous image.
	t.Run("drops a latched target image", func(t *testing.T) {
		assertRollout(t, rolloutStatusFromStatefulSet(rolloutInstance(rolloutNewImage, rolloutNewImage), sts, pods), "Pending", rolloutOldImage)
	})
	t.Run("counters converged ahead of the pods", func(t *testing.T) {
		converged := rolloutStatefulSet(3, rolloutNewImage, "rev-new")
		assertRollout(t, rolloutStatusFromStatefulSet(rolloutInstance(rolloutNewImage, rolloutOldImage), converged, pods), "Pending", rolloutOldImage)
	})
}

func TestRolloutStatusNewPodsNotReady(t *testing.T) {
	sts := rolloutStatefulSet(3, rolloutNewImage, "rev-new")
	sts.Status.ReadyReplicas = 1
	pods := []corev1.Pod{rolloutPod(0, rolloutNewImage, "rev-new", true), rolloutPod(1, rolloutNewImage, "rev-new", false)}

	assertRollout(t, rolloutStatusFromStatefulSet(rolloutInstance(rolloutNewImage, rolloutOldImage), sts, pods), "Pending", rolloutOldImage)
	assertRollout(t, rolloutStatusFromStatefulSet(rolloutInstance(rolloutNewImage, ""), sts, pods), "Pending", "")
}

func TestRolloutStatusOnDeleteTemplateUpdatedPodsHeld(t *testing.T) {
	const heldImage = "ghcr.io/tuist/kura:0.6.0-canary.5"
	sts := rolloutStatefulSet(5, rolloutNewImage, "rev-new")
	sts.Spec.UpdateStrategy.Type = appsv1.OnDeleteStatefulSetStrategyType
	sts.Status.CurrentRevision = "rev-original"
	sts.Status.UpdatedReplicas = 0
	pods := []corev1.Pod{rolloutPod(0, heldImage, "rev-canary", true), rolloutPod(1, heldImage, "rev-canary", true)}

	for _, observed := range []string{heldImage, rolloutNewImage} {
		t.Run("previously observed "+observed, func(t *testing.T) {
			assertRollout(t, rolloutStatusFromStatefulSet(rolloutInstance(rolloutNewImage, observed), sts, pods), "Pending", heldImage)
		})
	}
}

func TestRolloutStatusPartitionedRollingUpdate(t *testing.T) {
	sts := rolloutStatefulSet(3, rolloutNewImage, "rev-new")
	sts.Spec.UpdateStrategy = appsv1.StatefulSetUpdateStrategy{
		Type:          appsv1.RollingUpdateStatefulSetStrategyType,
		RollingUpdate: &appsv1.RollingUpdateStatefulSetStrategy{Partition: ptr(int32(1))},
	}
	sts.Status.CurrentRevision = "rev-old"
	sts.Status.UpdatedReplicas = 1
	pods := []corev1.Pod{rolloutPod(0, rolloutOldImage, "rev-old", true), rolloutPod(1, rolloutNewImage, "rev-new", true)}

	for _, observed := range []string{rolloutOldImage, rolloutNewImage} {
		t.Run("previously observed "+observed, func(t *testing.T) {
			assertRollout(t, rolloutStatusFromStatefulSet(rolloutInstance(rolloutNewImage, observed), sts, pods), "Pending", rolloutOldImage)
		})
	}
}

func TestRolloutStatusRollbackToOlderImage(t *testing.T) {
	instance := rolloutInstance(rolloutOldImage, rolloutNewImage)

	stale := rolloutStatefulSet(4, rolloutNewImage, "rev-new")
	onNew := []corev1.Pod{rolloutPod(0, rolloutNewImage, "rev-new", true), rolloutPod(1, rolloutNewImage, "rev-new", true)}
	assertRollout(t, rolloutStatusFromStatefulSet(instance, stale, onNew), "Pending", rolloutNewImage)

	rolling := rolloutStatefulSet(5, rolloutOldImage, "rev-old")
	rolling.Status.CurrentRevision = "rev-new"
	rolling.Status.UpdatedReplicas = 1
	mixed := []corev1.Pod{rolloutPod(0, rolloutNewImage, "rev-new", true), rolloutPod(1, rolloutOldImage, "rev-old", true)}
	assertRollout(t, rolloutStatusFromStatefulSet(instance, rolling, mixed), "Pending", rolloutNewImage)

	rolledBack := rolloutStatefulSet(5, rolloutOldImage, "rev-old")
	onOld := []corev1.Pod{rolloutPod(0, rolloutOldImage, "rev-old", true), rolloutPod(1, rolloutOldImage, "rev-old", true)}
	assertRollout(t, rolloutStatusFromStatefulSet(instance, rolledBack, onOld), "Ready", rolloutOldImage)
}

func TestRolloutStatusIgnoresTerminatingPods(t *testing.T) {
	sts := rolloutStatefulSet(3, rolloutNewImage, "rev-new")
	terminating := rolloutPod(2, rolloutOldImage, "rev-old", false)
	terminating.DeletionTimestamp = ptr(metav1.Now())
	pods := []corev1.Pod{rolloutPod(0, rolloutNewImage, "rev-new", true), rolloutPod(1, rolloutNewImage, "rev-new", true), terminating}

	assertRollout(t, rolloutStatusFromStatefulSet(rolloutInstance(rolloutNewImage, rolloutOldImage), sts, pods), "Ready", rolloutNewImage)
}

func TestRolloutStatusOnDelete(t *testing.T) {
	newPods := func() []corev1.Pod {
		return []corev1.Pod{rolloutPod(0, rolloutNewImage, "new", true), rolloutPod(1, rolloutNewImage, "new", true)}
	}
	for _, tt := range []struct {
		name      string
		mutate    func(*appsv1.StatefulSet, []corev1.Pod) []corev1.Pod
		wantReady bool
		wantImage string
	}{
		{name: "all pods manually replaced", wantReady: true},
		{name: "matching revisions", mutate: func(s *appsv1.StatefulSet, p []corev1.Pod) []corev1.Pod { s.Status.CurrentRevision = "new"; return p }, wantReady: true},
		{name: "matching revisions with extra old pod", mutate: func(s *appsv1.StatefulSet, p []corev1.Pod) []corev1.Pod {
			s.Status.CurrentRevision = "new"
			s.Status.Replicas = 3
			return append(p, rolloutPod(2, rolloutOldImage, "old", true))
		}},
		{name: "one old pod remains", mutate: func(s *appsv1.StatefulSet, p []corev1.Pod) []corev1.Pod {
			s.Status.UpdatedReplicas = 1
			p[1] = rolloutPod(1, rolloutOldImage, "old", true)
			return p
		}},
		{name: "updated pod not ready", mutate: func(s *appsv1.StatefulSet, p []corev1.Pod) []corev1.Pod {
			s.Status.ReadyReplicas = 1
			p[1] = rolloutPod(1, rolloutNewImage, "new", false)
			return p
		}},
		{name: "stale generation", mutate: func(s *appsv1.StatefulSet, p []corev1.Pod) []corev1.Pod { s.Status.ObservedGeneration = 1; return p }, wantImage: rolloutNewImage},
		{name: "missing update revision", mutate: func(s *appsv1.StatefulSet, p []corev1.Pod) []corev1.Pod { s.Status.UpdateRevision = ""; return p }, wantImage: rolloutNewImage},
		{name: "extra old pod", mutate: func(s *appsv1.StatefulSet, p []corev1.Pod) []corev1.Pod {
			s.Status.Replicas = 3
			return append(p, rolloutPod(2, rolloutOldImage, "old", true))
		}},
		{name: "rolling update still requires matching revisions", mutate: func(s *appsv1.StatefulSet, p []corev1.Pod) []corev1.Pod {
			s.Spec.UpdateStrategy.Type = appsv1.RollingUpdateStatefulSetStrategyType
			return p
		}, wantImage: rolloutNewImage},
	} {
		t.Run(tt.name, func(t *testing.T) {
			instance := rolloutInstance(rolloutNewImage, rolloutOldImage)
			sts := rolloutStatefulSet(2, rolloutNewImage, "new")
			sts.Spec.UpdateStrategy.Type = appsv1.OnDeleteStatefulSetStrategyType
			sts.Status.CurrentRevision = "old"
			pods := newPods()
			if tt.mutate != nil {
				pods = tt.mutate(sts, pods)
			}
			before := sts.DeepCopy()
			got := rolloutStatusFromStatefulSet(instance, sts, pods)
			wantPhase, wantImage := "Pending", rolloutOldImage
			if tt.wantImage != "" {
				wantImage = tt.wantImage
			}
			if tt.wantReady {
				wantPhase, wantImage = "Ready", rolloutNewImage
			}
			assertRollout(t, got, wantPhase, wantImage)
			if tt.wantReady && got.message != "2/2 replicas ready on revision new" {
				t.Fatalf("expected the updated revision in readiness message, got %q", got.message)
			}
			if !reflect.DeepEqual(sts, before) {
				t.Fatal("rollout observation changed StatefulSet")
			}
		})
	}
}
