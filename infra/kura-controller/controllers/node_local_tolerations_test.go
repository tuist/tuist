package controllers

import (
	"context"
	"reflect"
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/equality"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"
)

func TestNodeLocalTolerationsAdoption(t *testing.T) {
	for _, tc := range []struct {
		name          string
		storage       string
		existingImage string
		retained      bool
		wantProtected bool
	}{
		{name: "new local replica", storage: "scw-local-nvme", wantProtected: true},
		{name: "existing replica does not roll", storage: "scw-local-nvme", existingImage: "ghcr.io/tuist/kura:0.9.0"},
		{name: "next image adopts protection", storage: "scw-local-nvme", existingImage: "ghcr.io/tuist/kura:0.8.0", wantProtected: true},
		{name: "protection survives reconciliation", storage: "scw-local-nvme", existingImage: "ghcr.io/tuist/kura:0.9.0", retained: true, wantProtected: true},
		{name: "network volume keeps eviction", storage: "hcloud-volumes"},
		{name: "unspecified storage keeps eviction"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			instance := probeTestInstance()
			instance.Spec.StorageClassName = tc.storage
			objects := []client.Object{instance}
			if tc.existingImage != "" {
				sts := probeTestStatefulSet(instance, 2)
				sts.Spec.Template = podTemplate(instance, "", "", "", false, false, true)
				sts.Spec.Template.Spec.Containers[0].Image = tc.existingImage
				if tc.retained {
					sts.Spec.Template.Spec.Tolerations = nodeLocalTolerations(instance, &appsv1.StatefulSet{})
				}
				objects = append(objects, sts)
			}
			r := probeTestReconciler(t, objects...)
			before := instance.DeepCopy()
			for range 2 {
				if err := r.reconcileStatefulSet(context.Background(), instance); err != nil {
					t.Fatal(err)
				}
				sts := &appsv1.StatefulSet{}
				if err := getProbeTestObject(t, r, instance.Name, sts); err != nil {
					t.Fatal(err)
				}
				for _, key := range []string{corev1.TaintNodeNotReady, corev1.TaintNodeUnreachable} {
					protected := false
					for _, tol := range sts.Spec.Template.Spec.Tolerations {
						if tol.ToleratesTaint(&corev1.Taint{Key: key, Effect: corev1.TaintEffectNoSchedule}) {
							t.Fatal("allowed scheduling on an unavailable node")
						}
						if tol.ToleratesTaint(&corev1.Taint{Key: key, Effect: corev1.TaintEffectNoExecute}) {
							// Kubernetes uses the first matching toleration.
							protected = tol.TolerationSeconds == nil
							break
						}
					}
					if protected != tc.wantProtected {
						t.Fatalf("%s protected = %v, want %v", key, protected, tc.wantProtected)
					}
				}
			}
			if !reflect.DeepEqual(before.Spec.Tolerations, instance.Spec.Tolerations) {
				t.Fatal("mutated instance tolerations")
			}
		})
	}
}

func TestImageReplacementRespectsRecoveryPause(t *testing.T) {
	for _, tc := range []struct {
		name     string
		strategy appsv1.StatefulSetUpdateStrategy
		stale    bool
	}{
		{name: "OnDelete", strategy: appsv1.StatefulSetUpdateStrategy{Type: appsv1.OnDeleteStatefulSetStrategyType}},
		{name: "partition", strategy: appsv1.StatefulSetUpdateStrategy{
			Type:          appsv1.RollingUpdateStatefulSetStrategyType,
			RollingUpdate: &appsv1.RollingUpdateStatefulSetStrategy{Partition: ptr(int32(1))},
		}},
		{name: "stale template", stale: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			instance := probeTestInstance()
			sts := probeTestStatefulSet(instance, 2)
			sts.Spec.UpdateStrategy = tc.strategy
			sts.Spec.Template = podTemplate(instance, "", "", "", false, false, true)
			if tc.stale {
				sts.Spec.Template.Spec.Containers[0].Image = "old"
			}
			pod := &corev1.Pod{
				ObjectMeta: metav1.ObjectMeta{Name: instance.Name + "-0", Namespace: instance.Namespace, Labels: selectorLabels(instance)},
				Spec:       corev1.PodSpec{Containers: []corev1.Container{{Name: "kura", Image: "old"}}},
			}
			r := probeTestReconciler(t, instance, sts, pod)
			if err := r.replaceUnreadyPodsForImageChange(context.Background(), instance); err != nil {
				t.Fatal(err)
			}
			if err := getProbeTestObject(t, r, pod.Name, &corev1.Pod{}); err != nil {
				t.Fatalf("deleted paused pod: %v", err)
			}
			if instance.Annotations[unreadyPodsReplacedForImageAnnotation] == instance.Spec.Image {
				t.Fatal("marked a paused replacement complete")
			}
		})
	}
}

func TestNodeLocalTolerationsDoNotChangeExistingTemplateOrResumeRollout(t *testing.T) {
	instance := probeTestInstance()
	sts := probeTestStatefulSet(instance, 2)
	sts.Spec.Template = podTemplate(instance, "", "", "", false, false, true)
	sts.Spec.UpdateStrategy.Type = appsv1.OnDeleteStatefulSetStrategyType
	wantTemplate := sts.Spec.Template.DeepCopy()
	r := probeTestReconciler(t, instance, sts)
	if err := r.reconcileStatefulSet(context.Background(), instance); err != nil {
		t.Fatal(err)
	}
	if err := getProbeTestObject(t, r, instance.Name, sts); err != nil {
		t.Fatal(err)
	}
	if !equality.Semantic.DeepEqual(wantTemplate, &sts.Spec.Template) {
		t.Fatal("controller-only update changed the existing pod template")
	}
	if sts.Spec.UpdateStrategy.Type != appsv1.OnDeleteStatefulSetStrategyType {
		t.Fatal("resumed an operator-paused rollout")
	}
}

func TestNodeLocalTolerationsExplicitDeadlineReplacesRetainedDefault(t *testing.T) {
	instance := probeTestInstance()
	sts := &appsv1.StatefulSet{}
	sts.Spec.Template.Spec.Tolerations = nodeLocalTolerations(instance, sts)
	instance.Spec.Tolerations = append(instance.Spec.Tolerations, corev1.Toleration{
		Key: corev1.TaintNodeUnreachable, Operator: corev1.TolerationOpExists,
		Effect: corev1.TaintEffectNoExecute, TolerationSeconds: ptr(int64(120)),
	})
	got := nodeLocalTolerations(instance, sts)
	matches := 0
	for _, tol := range got {
		if !tol.ToleratesTaint(&corev1.Taint{Key: corev1.TaintNodeUnreachable, Effect: corev1.TaintEffectNoExecute}) {
			continue
		}
		matches++
		if tol.TolerationSeconds == nil || *tol.TolerationSeconds != 120 {
			t.Fatal("retained an indefinite default over the explicit deadline")
		}
	}
	if matches != 1 {
		t.Fatalf("matching tolerations = %d, want exactly the explicit policy", matches)
	}
}

func TestNodeLocalTolerationsRespectExplicitPolicy(t *testing.T) {
	for _, explicit := range []corev1.Toleration{
		{Key: corev1.TaintNodeUnreachable, Operator: corev1.TolerationOpExists, Effect: corev1.TaintEffectNoExecute, TolerationSeconds: ptr(int64(60))},
		{Operator: corev1.TolerationOpExists, Effect: corev1.TaintEffectNoExecute, TolerationSeconds: ptr(int64(60))},
	} {
		instance := probeTestInstance()
		instance.Spec.Tolerations = []corev1.Toleration{explicit}
		got := nodeLocalTolerations(instance, &appsv1.StatefulSet{})
		count := 0
		for _, tol := range got {
			if tol.ToleratesTaint(&corev1.Taint{Key: corev1.TaintNodeUnreachable, Effect: corev1.TaintEffectNoExecute}) {
				count++
				if !reflect.DeepEqual(tol, explicit) {
					t.Fatalf("overrode explicit eviction policy: %#v", tol)
				}
			}
			if tol.ToleratesTaint(&corev1.Taint{Key: corev1.TaintNodeUnreachable, Effect: corev1.TaintEffectNoSchedule}) {
				t.Fatal("allowed scheduling on an unreachable node")
			}
		}
		if count != 1 {
			t.Fatalf("matching tolerations = %d, want 1", count)
		}
	}
}
