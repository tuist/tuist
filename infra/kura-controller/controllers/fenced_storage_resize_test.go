package controllers

import (
	"context"
	"encoding/json"
	"fmt"
	"testing"
	"time"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func TestReconcileFencedDataStorageResize(t *testing.T) {
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	const (
		instanceName = "kura-acme-eu-west"
		namespace    = "kura"
		instanceUID  = "instance-uid"
	)

	instance := func(mutate ...func(*kurav1alpha1.KuraInstance)) *kurav1alpha1.KuraInstance {
		instance := &kurav1alpha1.KuraInstance{
			ObjectMeta: metav1.ObjectMeta{Name: instanceName, Namespace: namespace, UID: instanceUID},
			Spec: kurav1alpha1.KuraInstanceSpec{
				Replicas:    ptr(int32(2)),
				StorageSize: "256Gi",
				ServingMode: servingMode,
			},
		}
		for _, apply := range mutate {
			apply(instance)
		}
		return instance
	}
	sts := func(storage string) *appsv1.StatefulSet {
		return &appsv1.StatefulSet{
			ObjectMeta: metav1.ObjectMeta{Name: instanceName, Namespace: namespace},
			Spec: appsv1.StatefulSetSpec{
				UpdateStrategy: appsv1.StatefulSetUpdateStrategy{Type: appsv1.OnDeleteStatefulSetStrategyType},
				VolumeClaimTemplates: []corev1.PersistentVolumeClaim{{
					ObjectMeta: metav1.ObjectMeta{Name: "data"},
					Spec: corev1.PersistentVolumeClaimSpec{Resources: corev1.VolumeResourceRequirements{
						Requests: corev1.ResourceList{corev1.ResourceStorage: resource.MustParse(storage)},
					}},
				}},
			},
		}
	}
	claim := func(ordinal int, storage string) *corev1.PersistentVolumeClaim {
		return &corev1.PersistentVolumeClaim{
			ObjectMeta: metav1.ObjectMeta{
				Name:      fmt.Sprintf("data-%s-%d", instanceName, ordinal),
				Namespace: namespace,
				Labels:    selectorLabels(instance()),
			},
			Spec: corev1.PersistentVolumeClaimSpec{Resources: corev1.VolumeResourceRequirements{
				Requests: corev1.ResourceList{corev1.ResourceStorage: resource.MustParse(storage)},
			}},
		}
	}
	pod := func(ordinal int, ready bool) *corev1.Pod {
		status := corev1.ConditionFalse
		if ready {
			status = corev1.ConditionTrue
		}
		return &corev1.Pod{
			ObjectMeta: metav1.ObjectMeta{
				Name:      fmt.Sprintf("%s-%d", instanceName, ordinal),
				Namespace: namespace,
				UID:       types.UID(fmt.Sprintf("pod-uid-%d", ordinal)),
				Labels:    selectorLabels(instance()),
			},
			Spec:   corev1.PodSpec{NodeName: fmt.Sprintf("host-%d", ordinal)},
			Status: corev1.PodStatus{Conditions: []corev1.PodCondition{{Type: corev1.PodReady, Status: status}}},
		}
	}
	grant := func(holder int, mutate ...func(*servingGrant)) *corev1.ConfigMap {
		value := servingGrant{
			Epoch:     11,
			Phase:     "Serving",
			PodName:   fmt.Sprintf("%s-%d", instanceName, holder),
			ExpiresMS: time.Now().Add(10 * time.Second).UnixMilli(),
			Holder: servingHolder{
				InstanceUID: instanceUID,
				PodUID:      fmt.Sprintf("pod-uid-%d", holder),
				Host:        fmt.Sprintf("host-%d", holder),
			},
		}
		for _, apply := range mutate {
			apply(&value)
		}
		data, err := json.Marshal(value)
		if err != nil {
			t.Fatal(err)
		}
		return &corev1.ConfigMap{
			ObjectMeta: metav1.ObjectMeta{Name: instanceName + "-serving", Namespace: namespace},
			Data:       map[string]string{"grant": string(data)},
		}
	}
	exists := func(t *testing.T, c client.Client, obj client.Object) bool {
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
	run := func(t *testing.T, subject *kurav1alpha1.KuraInstance, objects ...client.Object) (client.Client, bool) {
		t.Helper()
		c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(append([]client.Object{subject}, objects...)...).Build()
		r := &KuraInstanceReconciler{Client: c, Scheme: scheme}
		inProgress, err := r.reconcileDataStorageResize(context.Background(), subject)
		if err != nil {
			t.Fatal(err)
		}
		return c, inProgress
	}

	t.Run("re-templates without disturbing either replica", func(t *testing.T) {
		c, inProgress := run(t, instance(), sts("64Gi"), claim(0, "64Gi"), claim(1, "64Gi"), pod(0, true), pod(1, true), grant(1))
		if !inProgress {
			t.Fatal("expected the re-template to report in flight")
		}
		if exists(t, c, &appsv1.StatefulSet{ObjectMeta: metav1.ObjectMeta{Name: instanceName, Namespace: namespace}}) {
			t.Fatal("expected the StatefulSet to be replaced")
		}
		for ordinal := 0; ordinal < 2; ordinal++ {
			if !exists(t, c, pod(ordinal, true)) || !exists(t, c, claim(ordinal, "64Gi")) {
				t.Fatalf("ordinal %d must keep its pod and claim through the re-template", ordinal)
			}
		}
	})

	t.Run("rebuilds only the standby and keeps the recovery hold", func(t *testing.T) {
		c, inProgress := run(t, instance(), sts("256Gi"), claim(0, "64Gi"), claim(1, "64Gi"), pod(0, true), pod(1, true), grant(1))
		if !inProgress {
			t.Fatal("expected the standby rebuild to report in flight")
		}
		if exists(t, c, claim(0, "64Gi")) || exists(t, c, pod(0, true)) {
			t.Fatal("expected the standby to be taken for rebuild")
		}
		if !exists(t, c, claim(1, "64Gi")) || !exists(t, c, pod(1, true)) {
			t.Fatal("the serving holder's pod and claim must never be touched")
		}
		live := &appsv1.StatefulSet{ObjectMeta: metav1.ObjectMeta{Name: instanceName, Namespace: namespace}}
		if !exists(t, c, live) || live.Annotations[recoveryRolloutHold] != "true" {
			t.Fatalf("expected the recovery hold on the StatefulSet, got %v", live.Annotations)
		}
	})

	t.Run("leaves the holder's claim for after a handover", func(t *testing.T) {
		c, inProgress := run(t, instance(), sts("256Gi"), claim(0, "256Gi"), claim(1, "64Gi"), pod(0, true), pod(1, true), grant(1))
		if inProgress {
			t.Fatal("a claim only a handover can free must not hold the rest of the reconcile")
		}
		if !exists(t, c, claim(1, "64Gi")) || !exists(t, c, pod(1, true)) {
			t.Fatal("the serving holder's pod and claim must never be touched")
		}
	})

	for name, subject := range map[string]*kurav1alpha1.KuraInstance{
		"a planned handover": instance(func(instance *kurav1alpha1.KuraInstance) {
			instance.Spec.PlannedHandover = &kurav1alpha1.PlannedHandoverRequest{ID: "handover", PodName: instanceName + "-0"}
		}),
		"a replica recovery in progress": instance(func(instance *kurav1alpha1.KuraInstance) {
			instance.Spec.ReplicaRecovery = &kurav1alpha1.ReplicaRecoveryRequest{ID: "recovery"}
		}),
	} {
		t.Run("waits out "+name, func(t *testing.T) {
			c, inProgress := run(t, subject, sts("64Gi"), claim(0, "64Gi"), claim(1, "64Gi"), pod(0, true), pod(1, true), grant(1))
			if inProgress {
				t.Fatal("expected no resize work during an authority transition")
			}
			if !exists(t, c, &appsv1.StatefulSet{ObjectMeta: metav1.ObjectMeta{Name: instanceName, Namespace: namespace}}) {
				t.Fatal("the StatefulSet must not be replaced during an authority transition")
			}
		})
	}

	t.Run("proceeds past a recovery that already verified", func(t *testing.T) {
		subject := instance(func(instance *kurav1alpha1.KuraInstance) {
			instance.Spec.ReplicaRecovery = &kurav1alpha1.ReplicaRecoveryRequest{ID: "recovery"}
			instance.Status.ReplicaRecovery = &kurav1alpha1.ReplicaRecoveryStatus{
				Phase:   "Verified",
				Request: kurav1alpha1.ReplicaRecoveryRequest{ID: "recovery"},
			}
		})
		c, inProgress := run(t, subject, sts("256Gi"), claim(0, "64Gi"), claim(1, "64Gi"), pod(0, true), pod(1, true), grant(1))
		if !inProgress || exists(t, c, claim(0, "64Gi")) {
			t.Fatal("expected a finished recovery not to block the standby rebuild")
		}
	})

	for name, objects := range map[string][]client.Object{
		"a quiescing grant": {grant(1, func(g *servingGrant) { g.Phase = "Quiescing" })},
		"a grant with a handover": {grant(1, func(g *servingGrant) {
			g.Handover = &handoverIntent{ID: "handover"}
		})},
		"an expired grant":   {grant(1, func(g *servingGrant) { g.ExpiresMS = time.Now().Add(-time.Second).UnixMilli() })},
		"a holder not ready": {grant(1)},
		"a missing grant":    {},
		"a foreign holder":   {grant(1, func(g *servingGrant) { g.Holder.PodUID = "elsewhere" })},
	} {
		t.Run("never rebuilds under "+name, func(t *testing.T) {
			holderReady := name != "a holder not ready"
			c, inProgress := run(t, instance(), append([]client.Object{sts("256Gi"), claim(0, "64Gi"), claim(1, "64Gi"), pod(0, true), pod(1, holderReady)}, objects...)...)
			if inProgress {
				t.Fatal("expected no resize work without a settled serving holder")
			}
			if !exists(t, c, claim(0, "64Gi")) || !exists(t, c, pod(0, true)) {
				t.Fatal("expected the standby to be left alone")
			}
		})
	}
}
