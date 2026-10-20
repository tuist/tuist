package controllers

import (
	"context"
	"errors"
	"github.com/go-logr/logr/funcr"
	"strings"
	"testing"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/client/interceptor"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

func TestReplacePendingPodsForStorageDecrease(t *testing.T) {
	for _, tc := range []struct {
		name, request, template, node                    string
		phase                                            corev1.PodPhase
		strategy                                         appsv1.StatefulSetUpdateStrategy
		deleted                                          bool
		missingSTS, missingContainer, duplicateContainer bool
		deleteError                                      error
		expectError                                      bool
	}{
		{name: "StatefulSet absent during recreation", request: "50Gi", template: "8Gi", phase: corev1.PodPending, missingSTS: true},
		{name: "template missing Kura container", request: "50Gi", template: "8Gi", phase: corev1.PodPending, missingContainer: true},
		{name: "template duplicates Kura container", request: "50Gi", template: "8Gi", phase: corev1.PodPending, duplicateContainer: true},
		{name: "delete races with pod update", request: "50Gi", template: "8Gi", phase: corev1.PodPending, deleteError: apierrors.NewConflict(schema.GroupResource{Resource: "pods"}, "runner-1", errors.New("resource version changed"))},
		{name: "delete races with disappearance", request: "50Gi", template: "8Gi", phase: corev1.PodPending, deleteError: apierrors.NewNotFound(schema.GroupResource{Resource: "pods"}, "runner-1")},
		{name: "delete authorization failure remains visible", request: "50Gi", template: "8Gi", phase: corev1.PodPending, deleteError: apierrors.NewForbidden(schema.GroupResource{Resource: "pods"}, "runner-1", errors.New("denied")), expectError: true},
		{name: "old unscheduled reservation", request: "50Gi", template: "8Gi", phase: corev1.PodPending, deleted: true},
		{name: "replacement remains during startup", request: "8Gi", template: "8Gi", phase: corev1.PodPending},
		{name: "scheduled pod retains its volume", request: "50Gi", template: "8Gi", node: "runner", phase: corev1.PodPending},
		{name: "running replica rolls normally", request: "50Gi", template: "8Gi", node: "runner", phase: corev1.PodRunning},
		{name: "growth stays on normal path", request: "4Gi", template: "8Gi", phase: corev1.PodPending},
		{name: "stale template cannot recreate smaller pod", request: "50Gi", template: "50Gi", phase: corev1.PodPending},
		{name: "operator OnDelete pause", request: "50Gi", template: "8Gi", phase: corev1.PodPending, strategy: appsv1.StatefulSetUpdateStrategy{Type: appsv1.OnDeleteStatefulSetStrategyType}},
		{name: "operator partition pause", request: "50Gi", template: "8Gi", phase: corev1.PodPending, strategy: appsv1.StatefulSetUpdateStrategy{Type: appsv1.RollingUpdateStatefulSetStrategyType, RollingUpdate: &appsv1.RollingUpdateStatefulSetStrategy{Partition: ptr(int32(1))}}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			var messages []string
			logger := funcr.New(func(prefix, args string) { messages = append(messages, prefix+args) }, funcr.Options{})
			ctx := log.IntoContext(context.Background(), logger)
			scheme := runtime.NewScheme()
			if err := clientgoscheme.AddToScheme(scheme); err != nil {
				t.Fatal(err)
			}
			instance := &kurav1alpha1.KuraInstance{ObjectMeta: metav1.ObjectMeta{Name: "runner", Namespace: "kura"}, Spec: kurav1alpha1.KuraInstanceSpec{StorageSize: "8Gi"}}
			container := func(size string) corev1.Container {
				return corev1.Container{Name: "kura", Resources: corev1.ResourceRequirements{Requests: corev1.ResourceList{corev1.ResourceEphemeralStorage: resource.MustParse(size)}}}
			}
			pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: "runner-1", Namespace: "kura", Labels: selectorLabels(instance)}, Spec: corev1.PodSpec{NodeName: tc.node, Containers: []corev1.Container{container(tc.request)}}, Status: corev1.PodStatus{Phase: tc.phase}}
			sts := &appsv1.StatefulSet{ObjectMeta: metav1.ObjectMeta{Name: "runner", Namespace: "kura"}, Spec: appsv1.StatefulSetSpec{UpdateStrategy: tc.strategy, Template: corev1.PodTemplateSpec{Spec: corev1.PodSpec{Containers: []corev1.Container{container(tc.template)}}}}}
			pvc := &corev1.PersistentVolumeClaim{ObjectMeta: metav1.ObjectMeta{Name: "data-runner-1", Namespace: "kura"}}
			if tc.missingContainer {
				sts.Spec.Template.Spec.Containers = nil
			}
			if tc.duplicateContainer {
				sts.Spec.Template.Spec.Containers = append(sts.Spec.Template.Spec.Containers, container(tc.template))
			}
			objects := []client.Object{pod, pvc}
			if !tc.missingSTS {
				objects = append(objects, sts)
			}
			interceptors := interceptor.Funcs{Delete: func(ctx context.Context, c client.WithWatch, obj client.Object, opts ...client.DeleteOption) error {
				if tc.deleteError != nil {
					return tc.deleteError
				}
				return c.Delete(ctx, obj, opts...)
			}}
			r := &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(objects...).WithInterceptorFuncs(interceptors).Build()}
			for range 2 {
				err := r.replacePendingPodsForStorageDecrease(ctx, instance)
				if tc.expectError {
					if !apierrors.IsForbidden(err) {
						t.Fatalf("expected forbidden error, got %v", err)
					}
				} else if err != nil {
					t.Fatal(err)
				}
			}
			if tc.deleteError != nil && strings.Contains(strings.Join(messages, "\n"), "replacing unscheduled Kura pod") {
				t.Fatal("failed or raced deletions must not be logged as replacements")
			}
			err := r.Get(ctx, client.ObjectKeyFromObject(pod), &corev1.Pod{})
			if tc.deleted {
				if !apierrors.IsNotFound(err) {
					t.Fatalf("expected deletion, got %v", err)
				}
			} else if err != nil {
				t.Fatalf("expected retained pod: %v", err)
			}
			if err := r.Get(ctx, types.NamespacedName{Name: pvc.Name, Namespace: pvc.Namespace}, &corev1.PersistentVolumeClaim{}); err != nil {
				t.Fatalf("PVC must remain: %v", err)
			}
		})
	}
}
