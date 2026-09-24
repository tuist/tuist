package controllers

import (
	"context"
	"reflect"
	"strings"
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

const (
	updatePauseOldImage = "ghcr.io/tuist/kura:0.54.0"
	updatePauseNewImage = "ghcr.io/tuist/kura:0.55.0"
)

func updatePauseFixture(strategy appsv1.StatefulSetUpdateStrategy, podImages ...string) (*kurav1alpha1.KuraInstance, *appsv1.StatefulSet, []corev1.Pod) {
	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-east-1", Namespace: "kura", Generation: 2},
		Spec:       kurav1alpha1.KuraInstanceSpec{Image: updatePauseNewImage, Replicas: ptr(int32(len(podImages)))},
		Status:     kurav1alpha1.KuraInstanceStatus{ObservedImage: updatePauseOldImage},
	}
	sts := &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace, Generation: 2},
		Spec: appsv1.StatefulSetSpec{
			UpdateStrategy: strategy,
			Template: corev1.PodTemplateSpec{Spec: corev1.PodSpec{Containers: []corev1.Container{
				{Name: "kura", Image: updatePauseNewImage},
			}}},
		},
		Status: appsv1.StatefulSetStatus{
			ObservedGeneration: 2,
			Replicas:           int32(len(podImages)),
			ReadyReplicas:      int32(len(podImages)),
			CurrentRevision:    "old",
			UpdateRevision:     "new",
		},
	}
	pods := make([]corev1.Pod, 0, len(podImages))
	for ordinal, image := range podImages {
		pods = append(pods, corev1.Pod{
			ObjectMeta: metav1.ObjectMeta{
				Name:      instance.Name + "-" + string(rune('0'+ordinal)),
				Namespace: instance.Namespace,
				Labels:    selectorLabels(instance),
			},
			Spec: corev1.PodSpec{Containers: []corev1.Container{{Name: "kura", Image: image}}},
		})
		if image == updatePauseNewImage {
			sts.Status.UpdatedReplicas++
		}
	}
	return instance, sts, pods
}

func partitionStrategy(partition int32) appsv1.StatefulSetUpdateStrategy {
	return appsv1.StatefulSetUpdateStrategy{
		Type:          appsv1.RollingUpdateStatefulSetStrategyType,
		RollingUpdate: &appsv1.RollingUpdateStatefulSetStrategy{Partition: ptr(partition)},
	}
}

func TestStatefulSetUpdatePause(t *testing.T) {
	onDelete := appsv1.StatefulSetUpdateStrategy{Type: appsv1.OnDeleteStatefulSetStrategyType}
	rolling := appsv1.StatefulSetUpdateStrategy{Type: appsv1.RollingUpdateStatefulSetStrategyType}

	for _, tt := range []struct {
		name        string
		strategy    appsv1.StatefulSetUpdateStrategy
		annotations map[string]string
		podImages   []string
		want        *kurav1alpha1.KuraInstanceUpdatePause
	}{
		{
			name:      "OnDelete holds every pod on the previous image",
			strategy:  onDelete,
			podImages: []string{updatePauseOldImage, updatePauseOldImage},
			want: &kurav1alpha1.KuraInstanceUpdatePause{
				Strategy:      "OnDelete",
				TemplateImage: updatePauseNewImage,
				HeldPods:      []string{"kura-tuist-eu-east-1-0", "kura-tuist-eu-east-1-1"},
			},
		},
		{
			name:      "OnDelete reports only the pods not yet replaced",
			strategy:  onDelete,
			podImages: []string{updatePauseNewImage, updatePauseOldImage},
			want: &kurav1alpha1.KuraInstanceUpdatePause{
				Strategy:      "OnDelete",
				TemplateImage: updatePauseNewImage,
				HeldPods:      []string{"kura-tuist-eu-east-1-1"},
			},
		},
		{
			name:      "OnDelete with every pod replaced is not paused",
			strategy:  onDelete,
			podImages: []string{updatePauseNewImage, updatePauseNewImage},
		},
		{
			name:      "positive partition holds the ordinals below it",
			strategy:  partitionStrategy(1),
			podImages: []string{updatePauseOldImage, updatePauseOldImage},
			want: &kurav1alpha1.KuraInstanceUpdatePause{
				Strategy:      "Partition",
				Partition:     1,
				TemplateImage: updatePauseNewImage,
				HeldPods:      []string{"kura-tuist-eu-east-1-0"},
			},
		},
		{
			name:      "positive partition does not hold ordinals Kubernetes still rolls",
			strategy:  partitionStrategy(1),
			podImages: []string{updatePauseNewImage, updatePauseOldImage},
		},
		{
			name:      "zero partition is an ordinary rolling update",
			strategy:  partitionStrategy(0),
			podImages: []string{updatePauseOldImage, updatePauseOldImage},
		},
		{
			name:        "the controller's own resize hold is not an operator pause",
			strategy:    appsv1.StatefulSetUpdateStrategy{Type: appsv1.OnDeleteStatefulSetStrategyType},
			annotations: map[string]string{resizeRolloutHoldAnnotation: "true"},
			podImages:   []string{updatePauseOldImage, updatePauseOldImage},
		},
		{
			name:      "RollingUpdate in flight is not paused",
			strategy:  rolling,
			podImages: []string{updatePauseOldImage, updatePauseOldImage},
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			instance, sts, pods := updatePauseFixture(tt.strategy, tt.podImages...)
			sts.Annotations = tt.annotations
			got := statefulSetUpdatePause(instance, sts, pods)
			if !reflect.DeepEqual(got, tt.want) {
				t.Fatalf("got %+v; want %+v", got, tt.want)
			}
		})
	}
}

func TestRolloutStatusPublishesUpdatePause(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	for _, tt := range []struct {
		name        string
		strategy    appsv1.StatefulSetUpdateStrategy
		wantPaused  bool
		wantMessage string
	}{
		{
			name:        "OnDelete",
			strategy:    appsv1.StatefulSetUpdateStrategy{Type: appsv1.OnDeleteStatefulSetStrategyType},
			wantPaused:  true,
			wantMessage: "update paused by updateStrategy OnDelete: kura-tuist-eu-east-1-0,kura-tuist-eu-east-1-1 held on a previous image, template on " + updatePauseNewImage + "; 2/2 replicas ready, 0/2 updated",
		},
		{
			name:        "positive partition",
			strategy:    partitionStrategy(2),
			wantPaused:  true,
			wantMessage: "update paused by rollingUpdate.partition=2: kura-tuist-eu-east-1-0,kura-tuist-eu-east-1-1 held on a previous image",
		},
		{
			name:        "RollingUpdate",
			strategy:    appsv1.StatefulSetUpdateStrategy{Type: appsv1.RollingUpdateStatefulSetStrategyType},
			wantMessage: "2/2 replicas ready, 0/2 updated",
		},
	} {
		t.Run(tt.name, func(t *testing.T) {
			instance, sts, pods := updatePauseFixture(tt.strategy, updatePauseOldImage, updatePauseOldImage)
			r := &KuraInstanceReconciler{
				Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, sts).Build(),
				Scheme: scheme,
			}

			state, err := r.rolloutStatus(ctx, instance, pods)
			if err != nil {
				t.Fatal(err)
			}

			if state.phase != "Pending" {
				t.Fatalf("expected Pending, got %q", state.phase)
			}
			if (state.updatePaused != nil) != tt.wantPaused {
				t.Fatalf("updatePaused = %+v; want paused=%t", state.updatePaused, tt.wantPaused)
			}
			if !strings.HasPrefix(state.message, tt.wantMessage) {
				t.Fatalf("message %q does not start with %q", state.message, tt.wantMessage)
			}
		})
	}
}

func TestRolloutStatusClearsUpdatePauseOnceReady(t *testing.T) {
	instance, sts, pods := updatePauseFixture(
		appsv1.StatefulSetUpdateStrategy{Type: appsv1.OnDeleteStatefulSetStrategyType},
		updatePauseNewImage, updatePauseNewImage,
	)
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	r := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, sts).Build(),
		Scheme: scheme,
	}

	state, err := r.rolloutStatus(context.Background(), instance, pods)
	if err != nil {
		t.Fatal(err)
	}

	if state.phase != "Ready" || state.updatePaused != nil {
		t.Fatalf("expected Ready with no pause, got phase=%q pause=%+v", state.phase, state.updatePaused)
	}
}
