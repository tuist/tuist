package controllers

import (
	"context"
	"fmt"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/log"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

const (
	KuraInstanceFinalizer = "kurainstances.kura.tuist.dev/finalizer"

	httpPort int32 = 4000
	grpcPort int32 = 50051
	peerPort int32 = 7443
)

type KuraInstanceReconciler struct {
	client.Client
	Scheme *runtime.Scheme
}

// +kubebuilder:rbac:groups=kura.tuist.dev,resources=kurainstances,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=kura.tuist.dev,resources=kurainstances/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=kura.tuist.dev,resources=kurainstances/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=statefulsets,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=services;configmaps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=networking.k8s.io,resources=ingresses,verbs=get;list;watch;create;update;patch;delete

func (r *KuraInstanceReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("kurainstance", req.NamespacedName)

	instance := &kurav1alpha1.KuraInstance{}
	if err := r.Get(ctx, req.NamespacedName, instance); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	if !instance.DeletionTimestamp.IsZero() {
		controllerutil.RemoveFinalizer(instance, KuraInstanceFinalizer)
		return ctrl.Result{}, r.Update(ctx, instance)
	}

	if !controllerutil.ContainsFinalizer(instance, KuraInstanceFinalizer) {
		controllerutil.AddFinalizer(instance, KuraInstanceFinalizer)
		if err := r.Update(ctx, instance); err != nil {
			return ctrl.Result{}, err
		}
	}

	if err := r.reconcileConfigMap(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileHeadlessService(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileService(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileIngress(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileStatefulSet(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}

	readyReplicas, err := r.readyReplicas(ctx, instance)
	if err != nil {
		return ctrl.Result{}, err
	}
	now := metav1.NewTime(time.Now().UTC())
	phase := "Pending"
	replicas := replicas(instance)
	if readyReplicas >= replicas {
		phase = "Ready"
	}
	instance.Status.Phase = phase
	instance.Status.PublicURL = publicURL(instance)
	instance.Status.ObservedImage = instance.Spec.Image
	instance.Status.ReadyReplicas = readyReplicas
	instance.Status.Message = fmt.Sprintf("%d/%d replicas ready", readyReplicas, replicas)
	instance.Status.LastReconciledAt = &now

	if err := r.Status().Update(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}

	logger.Info("reconciled Kura instance", "phase", phase, "readyReplicas", readyReplicas)
	return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
}

func (r *KuraInstanceReconciler) reconcileConfigMap(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	if instance.Spec.ExtensionScript == "" {
		return nil
	}
	configMap := &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: extensionConfigMapName(instance), Namespace: instance.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, configMap, func() error {
		if err := controllerutil.SetControllerReference(instance, configMap, r.Scheme); err != nil {
			return err
		}
		configMap.Labels = labels(instance)
		configMap.Data = map[string]string{"hooks.lua": instance.Spec.ExtensionScript}
		return nil
	})
	return err
}

func (r *KuraInstanceReconciler) reconcileHeadlessService(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	service := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: headlessServiceName(instance), Namespace: instance.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, service, func() error {
		if err := controllerutil.SetControllerReference(instance, service, r.Scheme); err != nil {
			return err
		}
		service.Labels = labels(instance)
		service.Spec.ClusterIP = corev1.ClusterIPNone
		service.Spec.PublishNotReadyAddresses = true
		service.Spec.Selector = selectorLabels(instance)
		service.Spec.Ports = ports()
		return nil
	})
	return err
}

func (r *KuraInstanceReconciler) reconcileService(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	service := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, service, func() error {
		if err := controllerutil.SetControllerReference(instance, service, r.Scheme); err != nil {
			return err
		}
		service.Labels = labels(instance)
		service.Spec.Type = corev1.ServiceTypeClusterIP
		service.Spec.Selector = selectorLabels(instance)
		service.Spec.Ports = []corev1.ServicePort{
			{Name: "http", Port: httpPort, TargetPort: intstr.FromString("http")},
			{Name: "grpc", Port: grpcPort, TargetPort: intstr.FromString("grpc")},
		}
		return nil
	})
	return err
}

func (r *KuraInstanceReconciler) reconcileIngress(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	if instance.Spec.PublicHost == "" {
		return nil
	}
	pathType := networkingv1.PathTypePrefix
	ingress := &networkingv1.Ingress{ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, ingress, func() error {
		if err := controllerutil.SetControllerReference(instance, ingress, r.Scheme); err != nil {
			return err
		}
		ingress.Labels = labels(instance)
		ingress.Annotations = map[string]string{"nginx.ingress.kubernetes.io/backend-protocol": "HTTP"}
		ingress.Spec.Rules = []networkingv1.IngressRule{{
			Host: instance.Spec.PublicHost,
			IngressRuleValue: networkingv1.IngressRuleValue{HTTP: &networkingv1.HTTPIngressRuleValue{
				Paths: []networkingv1.HTTPIngressPath{{
					Path:     "/",
					PathType: &pathType,
					Backend: networkingv1.IngressBackend{Service: &networkingv1.IngressServiceBackend{
						Name: instance.Name,
						Port: networkingv1.ServiceBackendPort{Name: "http"},
					}},
				}},
			}},
		}}
		if instance.Spec.TLSSecretName != "" {
			ingress.Spec.TLS = []networkingv1.IngressTLS{{SecretName: instance.Spec.TLSSecretName, Hosts: []string{instance.Spec.PublicHost}}}
		}
		return nil
	})
	return err
}

func (r *KuraInstanceReconciler) reconcileStatefulSet(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	sts := &appsv1.StatefulSet{ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, sts, func() error {
		if err := controllerutil.SetControllerReference(instance, sts, r.Scheme); err != nil {
			return err
		}
		sts.Labels = labels(instance)
		sts.Spec.ServiceName = headlessServiceName(instance)
		sts.Spec.Replicas = ptr(replicas(instance))
		sts.Spec.PodManagementPolicy = appsv1.ParallelPodManagement
		sts.Spec.Selector = &metav1.LabelSelector{MatchLabels: selectorLabels(instance)}
		sts.Spec.Template = podTemplate(instance)
		sts.Spec.VolumeClaimTemplates = []corev1.PersistentVolumeClaim{dataVolumeClaim(instance)}
		return nil
	})
	return err
}

func (r *KuraInstanceReconciler) readyReplicas(ctx context.Context, instance *kurav1alpha1.KuraInstance) (int32, error) {
	sts := &appsv1.StatefulSet{}
	err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts)
	if apierrors.IsNotFound(err) {
		return 0, nil
	}
	if err != nil {
		return 0, err
	}
	return sts.Status.ReadyReplicas, nil
}

func podTemplate(instance *kurav1alpha1.KuraInstance) corev1.PodTemplateSpec {
	return corev1.PodTemplateSpec{
		ObjectMeta: metav1.ObjectMeta{Labels: selectorLabels(instance), Annotations: defaultPodAnnotations()},
		Spec: corev1.PodSpec{
			TerminationGracePeriodSeconds: ptr(int64(255)),
			NodeSelector:                  defaultNodeSelector(),
			Containers: []corev1.Container{{
				Name:            "kura",
				Image:           instance.Spec.Image,
				ImagePullPolicy: corev1.PullIfNotPresent,
				Ports: []corev1.ContainerPort{
					{Name: "http", ContainerPort: httpPort},
					{Name: "grpc", ContainerPort: grpcPort},
					{Name: "peer", ContainerPort: peerPort},
				},
				Env:            append(baseEnv(instance), instance.Spec.ExtraEnv...),
				Resources:      defaultResources(),
				VolumeMounts:   volumeMounts(instance),
				ReadinessProbe: httpProbe("/ready", 5, 10),
				LivenessProbe:  httpProbe("/up", 20, 20),
				StartupProbe:   httpProbe("/up", 0, 10),
			}},
			Volumes: volumes(instance),
		},
	}
}

func defaultResources() corev1.ResourceRequirements {
	return corev1.ResourceRequirements{
		Requests: corev1.ResourceList{
			corev1.ResourceCPU:    resource.MustParse("500m"),
			corev1.ResourceMemory: resource.MustParse("1Gi"),
		},
		Limits: corev1.ResourceList{
			corev1.ResourceMemory: resource.MustParse("2Gi"),
		},
	}
}

func defaultPodAnnotations() map[string]string {
	return map[string]string{
		"kubernetes.io/ingress-bandwidth": "250M",
		"kubernetes.io/egress-bandwidth":  "250M",
	}
}

func defaultNodeSelector() map[string]string {
	return map[string]string{"node.cluster.x-k8s.io/pool": "kura"}
}

func baseEnv(instance *kurav1alpha1.KuraInstance) []corev1.EnvVar {
	env := []corev1.EnvVar{
		{Name: "POD_NAME", ValueFrom: &corev1.EnvVarSource{FieldRef: &corev1.ObjectFieldSelector{FieldPath: "metadata.name"}}},
		{Name: "POD_NAMESPACE", ValueFrom: &corev1.EnvVarSource{FieldRef: &corev1.ObjectFieldSelector{FieldPath: "metadata.namespace"}}},
		{Name: "KURA_PORT", Value: fmt.Sprintf("%d", httpPort)},
		{Name: "KURA_GRPC_PORT", Value: fmt.Sprintf("%d", grpcPort)},
		{Name: "KURA_TENANT_ID", Value: instance.Spec.TenantID},
		{Name: "KURA_REGION", Value: instance.Spec.Region},
		{Name: "KURA_TMP_DIR", Value: "/tmp/kura"},
		{Name: "KURA_DATA_DIR", Value: "/var/cache/kura"},
		{Name: "KURA_NODE_URL", Value: fmt.Sprintf("http://$(POD_NAME).%s.$(POD_NAMESPACE).svc.cluster.local:%d", headlessServiceName(instance), peerPort)},
		{Name: "KURA_DISCOVERY_DNS_NAME", Value: fmt.Sprintf("%s.$(POD_NAMESPACE).svc.cluster.local", headlessServiceName(instance))},
		{Name: "KURA_INTERNAL_PORT", Value: fmt.Sprintf("%d", peerPort)},
		{Name: "KURA_FILE_DESCRIPTOR_POOL_SIZE", Value: "128"},
		{Name: "KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS", Value: "5000"},
		{Name: "KURA_DRAIN_COMPLETION_TIMEOUT_MS", Value: "240000"},
		{Name: "KURA_SEGMENT_HANDLE_CACHE_SIZE", Value: "32"},
		{Name: "KURA_MEMORY_SOFT_LIMIT_BYTES", Value: "536870912"},
		{Name: "KURA_MEMORY_HARD_LIMIT_BYTES", Value: "805306368"},
		{Name: "KURA_MANIFEST_CACHE_MAX_BYTES", Value: "67108864"},
		{Name: "KURA_MAX_KEYVALUE_BYTES", Value: "1048576"},
		{Name: "KURA_METADATA_STORE_MAX_OPEN_FILES", Value: "1024"},
		{Name: "KURA_METADATA_STORE_MAX_BACKGROUND_JOBS", Value: "4"},
		{Name: "KURA_OTEL_SERVICE_NAME", Value: "$(POD_NAME)"},
		{Name: "KURA_OTEL_DEPLOYMENT_ENVIRONMENT", Value: "production"},
	}
	if instance.Spec.ExtensionScript != "" {
		env = append(env,
			corev1.EnvVar{Name: "KURA_EXTENSION_ENABLED", Value: "true"},
			corev1.EnvVar{Name: "KURA_EXTENSION_SCRIPT_PATH", Value: "/etc/kura/extensions/hooks.lua"},
		)
	}
	return env
}

func volumeMounts(instance *kurav1alpha1.KuraInstance) []corev1.VolumeMount {
	mounts := []corev1.VolumeMount{{Name: "tmp", MountPath: "/tmp/kura"}, {Name: "data", MountPath: "/var/cache/kura"}}
	if instance.Spec.ExtensionScript != "" {
		mounts = append(mounts, corev1.VolumeMount{Name: "extension-script", MountPath: "/etc/kura/extensions", ReadOnly: true})
	}
	return mounts
}

func volumes(instance *kurav1alpha1.KuraInstance) []corev1.Volume {
	volumes := []corev1.Volume{{Name: "tmp", VolumeSource: corev1.VolumeSource{EmptyDir: &corev1.EmptyDirVolumeSource{}}}}
	if instance.Spec.ExtensionScript != "" {
		volumes = append(volumes, corev1.Volume{
			Name: "extension-script",
			VolumeSource: corev1.VolumeSource{ConfigMap: &corev1.ConfigMapVolumeSource{
				LocalObjectReference: corev1.LocalObjectReference{Name: extensionConfigMapName(instance)},
			}},
		})
	}
	return volumes
}

func dataVolumeClaim(instance *kurav1alpha1.KuraInstance) corev1.PersistentVolumeClaim {
	storage := resource.MustParse("20Gi")
	if instance.Spec.VolumeSizeGi > 0 {
		storage = resource.MustParse(fmt.Sprintf("%dGi", instance.Spec.VolumeSizeGi))
	}
	pvc := corev1.PersistentVolumeClaim{
		ObjectMeta: metav1.ObjectMeta{Name: "data"},
		Spec: corev1.PersistentVolumeClaimSpec{
			AccessModes: []corev1.PersistentVolumeAccessMode{corev1.ReadWriteOncePod},
			Resources:   corev1.VolumeResourceRequirements{Requests: corev1.ResourceList{corev1.ResourceStorage: storage}},
		},
	}
	if instance.Spec.StorageClassName != "" {
		pvc.Spec.StorageClassName = &instance.Spec.StorageClassName
	}
	return pvc
}

func httpProbe(path string, initialDelay, period int32) *corev1.Probe {
	return &corev1.Probe{
		ProbeHandler:        corev1.ProbeHandler{HTTPGet: &corev1.HTTPGetAction{Path: path, Port: intstr.FromString("http")}},
		InitialDelaySeconds: initialDelay,
		PeriodSeconds:       period,
		TimeoutSeconds:      5,
	}
}

func ports() []corev1.ServicePort {
	return []corev1.ServicePort{
		{Name: "http", Port: httpPort, TargetPort: intstr.FromString("http")},
		{Name: "grpc", Port: grpcPort, TargetPort: intstr.FromString("grpc")},
		{Name: "peer", Port: peerPort, TargetPort: intstr.FromString("peer")},
	}
}

func replicas(instance *kurav1alpha1.KuraInstance) int32 {
	if instance.Spec.Replicas != nil && *instance.Spec.Replicas > 0 {
		return *instance.Spec.Replicas
	}
	return 3
}

func publicURL(instance *kurav1alpha1.KuraInstance) string {
	if instance.Spec.PublicHost == "" {
		return ""
	}
	return "https://" + instance.Spec.PublicHost
}

func labels(instance *kurav1alpha1.KuraInstance) map[string]string {
	labels := selectorLabels(instance)
	labels["app.kubernetes.io/managed-by"] = "kura-controller"
	labels["tuist.dev/account"] = instance.Spec.AccountHandle
	labels["tuist.dev/region"] = instance.Spec.Region
	return labels
}

func selectorLabels(instance *kurav1alpha1.KuraInstance) map[string]string {
	return map[string]string{
		"app.kubernetes.io/name":     "kura",
		"app.kubernetes.io/instance": instance.Name,
	}
}

func headlessServiceName(instance *kurav1alpha1.KuraInstance) string {
	return instance.Name + "-headless"
}

func extensionConfigMapName(instance *kurav1alpha1.KuraInstance) string {
	return instance.Name + "-extension"
}

func ptr[T any](v T) *T {
	return &v
}

func (r *KuraInstanceReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&kurav1alpha1.KuraInstance{}).
		Owns(&appsv1.StatefulSet{}).
		Owns(&corev1.Service{}).
		Owns(&corev1.ConfigMap{}).
		Owns(&networkingv1.Ingress{}).
		Complete(r)
}
