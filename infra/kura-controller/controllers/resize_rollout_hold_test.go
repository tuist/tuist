package controllers

import (
	"context"
	"fmt"
	"testing"
	"time"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

type resizeHoldFixture struct {
	instance *kurav1alpha1.KuraInstance
}

func newResizeHoldFixture(requestMilli int32) resizeHoldFixture {
	instance := meshInstance("kura-acme-eu-east-1", "acme")
	instance.Spec.Replicas = ptr(int32(2))
	instance.Spec.StorageSize = "32Gi"
	instance.Status.CPUAutosize = &kurav1alpha1.KuraInstanceCPUAutosize{RequestMilli: requestMilli}
	return resizeHoldFixture{instance: instance}
}

func (f resizeHoldFixture) statefulSet(strategy appsv1.StatefulSetUpdateStrategy, cpu string, annotations map[string]string) *appsv1.StatefulSet {
	return &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{Name: f.instance.Name, Namespace: f.instance.Namespace, Annotations: annotations},
		Spec: appsv1.StatefulSetSpec{
			UpdateStrategy: strategy,
			Template: corev1.PodTemplateSpec{Spec: corev1.PodSpec{Containers: []corev1.Container{{
				Name:      kuraContainerName,
				Resources: corev1.ResourceRequirements{Requests: corev1.ResourceList{corev1.ResourceCPU: resource.MustParse(cpu)}},
			}}}},
			VolumeClaimTemplates: []corev1.PersistentVolumeClaim{{
				ObjectMeta: metav1.ObjectMeta{Name: "data"},
				Spec: corev1.PersistentVolumeClaimSpec{Resources: corev1.VolumeResourceRequirements{
					Requests: corev1.ResourceList{corev1.ResourceStorage: resource.MustParse("32Gi")},
				}},
			}},
		},
	}
}

func (f resizeHoldFixture) claim(ordinal int, storage string) *corev1.PersistentVolumeClaim {
	return &corev1.PersistentVolumeClaim{
		ObjectMeta: metav1.ObjectMeta{
			Name:      fmt.Sprintf("data-%s-%d", f.instance.Name, ordinal),
			Namespace: f.instance.Namespace,
			Labels:    selectorLabels(f.instance),
		},
		Spec: corev1.PersistentVolumeClaimSpec{Resources: corev1.VolumeResourceRequirements{
			Requests: corev1.ResourceList{corev1.ResourceStorage: resource.MustParse(storage)},
		}},
	}
}

func (f resizeHoldFixture) servingPod(ordinal int, cpu string) *corev1.Pod {
	pod := kuraPod(f.instance.Name, f.instance.Namespace, ordinal, true)
	pod.Spec.NodeName = "eu-east-box"
	pod.Spec.Containers = []corev1.Container{{
		Name:      kuraContainerName,
		Resources: corev1.ResourceRequirements{Requests: corev1.ResourceList{corev1.ResourceCPU: resource.MustParse(cpu)}},
	}}
	pod.Status.Phase = corev1.PodRunning
	return pod
}

func (f resizeHoldFixture) unscheduledPod(ordinal int, cpu, reason string) *corev1.Pod {
	pod := kuraPod(f.instance.Name, f.instance.Namespace, ordinal, false)
	pod.Spec.Containers = []corev1.Container{{
		Name:      kuraContainerName,
		Resources: corev1.ResourceRequirements{Requests: corev1.ResourceList{corev1.ResourceCPU: resource.MustParse(cpu)}},
	}}
	pod.Status.Phase = corev1.PodPending
	pod.Status.Conditions = append(pod.Status.Conditions, corev1.PodCondition{
		Type:    corev1.PodScheduled,
		Status:  corev1.ConditionFalse,
		Reason:  corev1.PodReasonUnschedulable,
		Message: "0/1 nodes are available: 1 " + reason + ".",
	})
	return pod
}

func rollingUpdate() appsv1.StatefulSetUpdateStrategy {
	return appsv1.StatefulSetUpdateStrategy{
		Type:          appsv1.RollingUpdateStatefulSetStrategyType,
		RollingUpdate: &appsv1.RollingUpdateStatefulSetStrategy{Partition: ptr(int32(0))},
	}
}

func onDelete() appsv1.StatefulSetUpdateStrategy {
	return appsv1.StatefulSetUpdateStrategy{Type: appsv1.OnDeleteStatefulSetStrategyType}
}

func resizeHeld() map[string]string {
	return map[string]string{resizeRolloutHoldAnnotation: "true"}
}

func objectExists(t *testing.T, c client.Client, obj client.Object) bool {
	t.Helper()
	err := c.Get(context.Background(), types.NamespacedName{Name: obj.GetName(), Namespace: obj.GetNamespace()}, obj)
	if err == nil {
		return true
	}
	if apierrors.IsNotFound(err) {
		return false
	}
	t.Fatalf("unexpected get error: %v", err)
	return false
}

func templateCPU(t *testing.T, sts *appsv1.StatefulSet) string {
	t.Helper()
	for _, container := range sts.Spec.Template.Spec.Containers {
		if container.Name == kuraContainerName {
			return container.Resources.Requests.Cpu().String()
		}
	}
	t.Fatal("template has no kura container")
	return ""
}

// The rebuilt replica of a grown claim came back at a CPU request the box can
// no longer fit, and the resize waits for it to serve before taking its
// sibling. The pass must still get the lowered request to that replica, and
// must do it without rolling the sibling, which is the only one serving.
func TestReconcileLowersTheRequestOfAResizeReplicaStrandedOnCPU(t *testing.T) {
	ctx := context.Background()
	scheme := meshTestScheme(t)
	f := newResizeHoldFixture(3000)
	instance := f.instance

	reconciler := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithStatusSubresource(instance, &corev1.Pod{}).WithObjects(
			instance,
			f.statefulSet(rollingUpdate(), "3", nil),
			f.claim(0, "32Gi"), f.claim(1, "16Gi"),
			f.unscheduledPod(0, "3", "Insufficient cpu"),
			f.servingPod(1, "3"),
		).Build(),
		Scheme: scheme,
		RuntimeStatusClient: fakeRuntimeStatusClient{statuses: map[string]runtimeStatus{
			instance.Name + "-1": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2},
		}},
	}

	result, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}})
	if err != nil {
		t.Fatal(err)
	}
	if result.RequeueAfter != 10*time.Second {
		t.Fatalf("expected the resize to keep requeuing, got %+v", result)
	}

	sts := &appsv1.StatefulSet{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		t.Fatal(err)
	}
	if sts.Spec.UpdateStrategy.Type != appsv1.OnDeleteStatefulSetStrategyType || sts.Annotations[resizeRolloutHoldAnnotation] != "true" {
		t.Fatalf("expected the resize to hold the rollout, got strategy %+v annotations %v", sts.Spec.UpdateStrategy, sts.Annotations)
	}
	if got := templateCPU(t, sts); got != "2" {
		t.Fatalf("expected the template to carry the schedule cap, got %s", got)
	}
	if objectExists(t, reconciler.Client, &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: instance.Name + "-0", Namespace: instance.Namespace}}) {
		t.Fatal("expected the stranded replica to be recreated from the lowered template")
	}
	if !objectExists(t, reconciler.Client, &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: instance.Name + "-1", Namespace: instance.Namespace}}) {
		t.Fatal("the serving sibling must not be touched")
	}
	if !objectExists(t, reconciler.Client, f.claim(1, "16Gi")) {
		t.Fatal("the serving sibling's volume must not be touched")
	}

	persisted := &kurav1alpha1.KuraInstance{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, persisted); err != nil {
		t.Fatal(err)
	}
	if persisted.Status.CPUAutosize == nil || persisted.Status.CPUAutosize.ScheduleCapMilli != 2000 {
		t.Fatalf("expected the schedule cap to be persisted, got %+v", persisted.Status.CPUAutosize)
	}
}

func TestHoldRolloutForResize(t *testing.T) {
	ctx := context.Background()
	scheme := meshTestScheme(t)

	for _, tc := range []struct {
		name           string
		sts            func(resizeHoldFixture) *appsv1.StatefulSet
		wantHeld       bool
		wantStrategy   appsv1.StatefulSetUpdateStrategyType
		wantAnnotation bool
	}{
		{
			name:           "switches a rolling update to OnDelete and marks it",
			sts:            func(f resizeHoldFixture) *appsv1.StatefulSet { return f.statefulSet(rollingUpdate(), "3", nil) },
			wantHeld:       true,
			wantStrategy:   appsv1.OnDeleteStatefulSetStrategyType,
			wantAnnotation: true,
		},
		{
			name:         "adopts an operator's OnDelete without claiming it",
			sts:          func(f resizeHoldFixture) *appsv1.StatefulSet { return f.statefulSet(onDelete(), "3", nil) },
			wantHeld:     true,
			wantStrategy: appsv1.OnDeleteStatefulSetStrategyType,
		},
		{
			name: "leaves an operator's rolling partition alone",
			sts: func(f resizeHoldFixture) *appsv1.StatefulSet {
				strategy := rollingUpdate()
				strategy.RollingUpdate.Partition = ptr(int32(1))
				return f.statefulSet(strategy, "3", nil)
			},
			wantStrategy: appsv1.RollingUpdateStatefulSetStrategyType,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := newResizeHoldFixture(3000)
			c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(f.instance, tc.sts(f)).Build()
			r := &KuraInstanceReconciler{Client: c, Scheme: scheme}

			held, err := r.holdRolloutForResize(ctx, f.instance)
			if err != nil {
				t.Fatal(err)
			}
			if held != tc.wantHeld {
				t.Fatalf("held = %v, want %v", held, tc.wantHeld)
			}
			sts := &appsv1.StatefulSet{}
			if err := c.Get(ctx, types.NamespacedName{Name: f.instance.Name, Namespace: f.instance.Namespace}, sts); err != nil {
				t.Fatal(err)
			}
			if sts.Spec.UpdateStrategy.Type != tc.wantStrategy {
				t.Fatalf("strategy = %s, want %s", sts.Spec.UpdateStrategy.Type, tc.wantStrategy)
			}
			if _, marked := sts.Annotations[resizeRolloutHoldAnnotation]; marked != tc.wantAnnotation {
				t.Fatalf("hold annotation present = %v, want %v", marked, tc.wantAnnotation)
			}
		})
	}

	t.Run("reports nothing held without a StatefulSet", func(t *testing.T) {
		f := newResizeHoldFixture(3000)
		r := &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(f.instance).Build(), Scheme: scheme}
		held, err := r.holdRolloutForResize(ctx, f.instance)
		if err != nil {
			t.Fatal(err)
		}
		if held {
			t.Fatal("a missing StatefulSet cannot be held")
		}
	})
}

func TestReleaseResizeRolloutHold(t *testing.T) {
	ctx := context.Background()
	scheme := meshTestScheme(t)

	for _, tc := range []struct {
		name           string
		annotations    map[string]string
		pods           func(resizeHoldFixture) []client.Object
		wantStrategy   appsv1.StatefulSetUpdateStrategyType
		wantAnnotation bool
	}{
		{
			name:        "restores the rolling update once every replica is ready",
			annotations: resizeHeld(),
			pods: func(f resizeHoldFixture) []client.Object {
				return []client.Object{f.servingPod(0, "600m"), f.servingPod(1, "600m")}
			},
			wantStrategy: appsv1.RollingUpdateStatefulSetStrategyType,
		},
		{
			name:        "keeps holding while a replica is not ready",
			annotations: resizeHeld(),
			pods: func(f resizeHoldFixture) []client.Object {
				return []client.Object{f.servingPod(0, "600m"), f.unscheduledPod(1, "600m", "Insufficient cpu")}
			},
			wantStrategy:   appsv1.OnDeleteStatefulSetStrategyType,
			wantAnnotation: true,
		},
		{
			name:        "keeps holding while a replica is missing",
			annotations: resizeHeld(),
			pods: func(f resizeHoldFixture) []client.Object {
				return []client.Object{f.servingPod(0, "600m")}
			},
			wantStrategy:   appsv1.OnDeleteStatefulSetStrategyType,
			wantAnnotation: true,
		},
		{
			name: "never lifts an operator's OnDelete",
			pods: func(f resizeHoldFixture) []client.Object {
				return []client.Object{f.servingPod(0, "600m"), f.servingPod(1, "600m")}
			},
			wantStrategy: appsv1.OnDeleteStatefulSetStrategyType,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := newResizeHoldFixture(600)
			objects := append([]client.Object{f.instance, f.statefulSet(onDelete(), "600m", tc.annotations)}, tc.pods(f)...)
			c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(objects...).Build()
			r := &KuraInstanceReconciler{Client: c, Scheme: scheme}

			if err := r.releaseResizeRolloutHold(ctx, f.instance); err != nil {
				t.Fatal(err)
			}
			sts := &appsv1.StatefulSet{}
			if err := c.Get(ctx, types.NamespacedName{Name: f.instance.Name, Namespace: f.instance.Namespace}, sts); err != nil {
				t.Fatal(err)
			}
			if sts.Spec.UpdateStrategy.Type != tc.wantStrategy {
				t.Fatalf("strategy = %s, want %s", sts.Spec.UpdateStrategy.Type, tc.wantStrategy)
			}
			if tc.wantStrategy == appsv1.RollingUpdateStatefulSetStrategyType {
				if rolling := sts.Spec.UpdateStrategy.RollingUpdate; rolling == nil || rolling.Partition == nil || *rolling.Partition != 0 {
					t.Fatalf("expected a rolling update from ordinal 0, got %+v", sts.Spec.UpdateStrategy.RollingUpdate)
				}
			}
			if _, marked := sts.Annotations[resizeRolloutHoldAnnotation]; marked != tc.wantAnnotation {
				t.Fatalf("hold annotation present = %v, want %v", marked, tc.wantAnnotation)
			}
		})
	}
}

// The resize's hold is released only once every replica is ready, so a replica
// that cannot become ready on the old image must still be able to reach the new
// one, or the hold would pin the fix out.
func TestImageReplacementProceedsUnderTheResizeHold(t *testing.T) {
	instance := probeTestInstance()
	sts := probeTestStatefulSet(instance, 2)
	sts.Spec.UpdateStrategy = onDelete()
	sts.Annotations = resizeHeld()
	sts.Spec.Template = podTemplate(instance, "", "", "", false, false, true)
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: instance.Name + "-0", Namespace: instance.Namespace, Labels: selectorLabels(instance)},
		Spec:       corev1.PodSpec{Containers: []corev1.Container{{Name: "kura", Image: "old"}}},
	}
	r := probeTestReconciler(t, instance, sts, pod)
	if err := r.replaceUnreadyPodsForImageChange(context.Background(), instance); err != nil {
		t.Fatal(err)
	}
	if err := getProbeTestObject(t, r, pod.Name, &corev1.Pod{}); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the unready old-image pod to be replaced, got %v", err)
	}
}

func TestReplacePodsStrandedOnCPU(t *testing.T) {
	ctx := context.Background()
	scheme := meshTestScheme(t)

	for _, tc := range []struct {
		name        string
		annotations map[string]string
		template    string
		pod         func(resizeHoldFixture) *corev1.Pod
		wantDeleted bool
	}{
		{
			name:        "recreates a replica the scheduler rejected for CPU above the template",
			annotations: resizeHeld(),
			template:    "600m",
			pod:         func(f resizeHoldFixture) *corev1.Pod { return f.unscheduledPod(0, "3", "Insufficient cpu") },
			wantDeleted: true,
		},
		{
			name:        "keeps a replica already asking for no more than the template",
			annotations: resizeHeld(),
			template:    "600m",
			pod:         func(f resizeHoldFixture) *corev1.Pod { return f.unscheduledPod(0, "600m", "Insufficient cpu") },
		},
		{
			name:        "keeps a replica blocked on something other than CPU",
			annotations: resizeHeld(),
			template:    "600m",
			pod: func(f resizeHoldFixture) *corev1.Pod {
				return f.unscheduledPod(0, "3", "node(s) didn't match Pod's node affinity/selector")
			},
		},
		{
			name:        "keeps a scheduled replica",
			annotations: resizeHeld(),
			template:    "600m",
			pod:         func(f resizeHoldFixture) *corev1.Pod { return f.servingPod(0, "3") },
		},
		{
			name:     "leaves an operator's OnDelete to the operator",
			template: "600m",
			pod:      func(f resizeHoldFixture) *corev1.Pod { return f.unscheduledPod(0, "3", "Insufficient cpu") },
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			f := newResizeHoldFixture(600)
			pod := tc.pod(f)
			c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(f.instance, f.statefulSet(onDelete(), tc.template, tc.annotations), pod).Build()
			r := &KuraInstanceReconciler{Client: c, Scheme: scheme}

			if err := r.replacePodsStrandedOnCPU(ctx, f.instance); err != nil {
				t.Fatal(err)
			}
			if deleted := !objectExists(t, c, &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: pod.Name, Namespace: pod.Namespace}}); deleted != tc.wantDeleted {
				t.Fatalf("deleted = %v, want %v", deleted, tc.wantDeleted)
			}
		})
	}
}
