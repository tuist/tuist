package controllers

import (
	"context"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/kura-controller/internal/runnerrelay"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
)

func (r *KuraInstanceReconciler) reconcileRunnerCacheRelay(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	// Never expose the private macOS regions through the ordinary Linux path.
	// Disabling preparation retains existing aliases for jobs already holding
	// their URLs; instance ownership removes aliases when the instance retires.
	if !r.RunnerCacheRelay || instance.Spec.Private {
		return nil
	}
	service := &corev1.Service{ObjectMeta: metav1.ObjectMeta{
		Name: runnerrelay.ServiceName(instance.Name), Namespace: instance.Namespace,
	}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, service, func() error {
		if err := controllerutil.SetControllerReference(instance, service, r.Scheme); err != nil {
			return err
		}
		service.Labels = map[string]string{runnerrelay.Label: "true"}
		service.Annotations = map[string]string{runnerrelay.BackendAnnotation: instance.Name}
		service.Spec.Selector = map[string]string{"app.kubernetes.io/name": runnerrelay.App}
		service.Spec.Type = corev1.ServiceTypeClusterIP
		service.Spec.Ports = []corev1.ServicePort{{Name: "http", Port: httpPort, TargetPort: intstr.FromInt32(8080)}}
		return nil
	})
	return err
}
