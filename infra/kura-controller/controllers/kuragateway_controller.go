package controllers

import (
	"context"
	"fmt"
	"strings"
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
	KuraGatewayFinalizer = "kuragateways.kura.tuist.dev/finalizer"

	defaultGatewayControllerImage = "registry.k8s.io/ingress-nginx/controller:v1.11.3"
	defaultGatewayServiceAccount  = "kura-gateway-ingress-nginx"
)

type KuraGatewayReconciler struct {
	client.Client
	Scheme *runtime.Scheme

	GatewayServiceAccountName string
}

// +kubebuilder:rbac:groups=kura.tuist.dev,resources=kuragateways,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=kura.tuist.dev,resources=kuragateways/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=kura.tuist.dev,resources=kuragateways/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=deployments,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=services;configmaps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=networking.k8s.io,resources=ingressclasses,verbs=get;list;watch;create;update;patch;delete

func (r *KuraGatewayReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("kuragateway", req.NamespacedName)

	gateway := &kurav1alpha1.KuraGateway{}
	if err := r.Get(ctx, req.NamespacedName, gateway); err != nil {
		if apierrors.IsNotFound(err) {
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, err
	}

	if !gateway.DeletionTimestamp.IsZero() {
		if err := r.deleteIngressClass(ctx, gateway); err != nil {
			return ctrl.Result{}, err
		}
		controllerutil.RemoveFinalizer(gateway, KuraGatewayFinalizer)
		return ctrl.Result{}, r.Update(ctx, gateway)
	}

	if !controllerutil.ContainsFinalizer(gateway, KuraGatewayFinalizer) {
		controllerutil.AddFinalizer(gateway, KuraGatewayFinalizer)
		if err := r.Update(ctx, gateway); err != nil {
			return ctrl.Result{}, err
		}
	}

	if err := r.deleteRenamedIngressClass(ctx, gateway); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileGatewayConfigMap(ctx, gateway); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileGatewayService(ctx, gateway); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileGatewayIngressClass(ctx, gateway); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.rememberGatewayIngressClassName(ctx, gateway); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.Get(ctx, req.NamespacedName, gateway); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileGatewayDeployment(ctx, gateway); err != nil {
		return ctrl.Result{}, err
	}

	status, err := r.gatewayStatus(ctx, gateway)
	if err != nil {
		return ctrl.Result{}, err
	}
	now := metav1.NewTime(time.Now().UTC())
	gateway.Status.Phase = status.phase
	gateway.Status.IngressClassName = gatewayIngressClassName(gateway)
	gateway.Status.ServiceName = gatewayWorkloadName(gateway)
	gateway.Status.ReadyReplicas = status.readyReplicas
	gateway.Status.LoadBalancer = status.loadBalancer
	gateway.Status.Message = status.message
	gateway.Status.LastReconciledAt = &now

	if err := r.Status().Update(ctx, gateway); err != nil {
		return ctrl.Result{}, err
	}

	logger.Info("reconciled Kura gateway", "phase", status.phase, "readyReplicas", status.readyReplicas)
	return ctrl.Result{RequeueAfter: 30 * time.Second}, nil
}

func (r *KuraGatewayReconciler) deleteIngressClass(ctx context.Context, gateway *kurav1alpha1.KuraGateway) error {
	names := []string{gatewayIngressClassName(gateway)}
	if gateway.Status.IngressClassName != "" && gateway.Status.IngressClassName != names[0] {
		names = append(names, gateway.Status.IngressClassName)
	}
	for _, name := range names {
		ingressClass := &networkingv1.IngressClass{ObjectMeta: metav1.ObjectMeta{Name: name}}
		if err := r.Delete(ctx, ingressClass); err != nil && !apierrors.IsNotFound(err) {
			return err
		}
	}
	return nil
}

func (r *KuraGatewayReconciler) deleteRenamedIngressClass(ctx context.Context, gateway *kurav1alpha1.KuraGateway) error {
	if gateway.Status.IngressClassName == "" || gateway.Status.IngressClassName == gatewayIngressClassName(gateway) {
		return nil
	}
	ingressClass := &networkingv1.IngressClass{ObjectMeta: metav1.ObjectMeta{Name: gateway.Status.IngressClassName}}
	if err := r.Delete(ctx, ingressClass); err != nil && !apierrors.IsNotFound(err) {
		return err
	}
	return nil
}

// gatewayNginxConfigData is the ingress-nginx ConfigMap for dedicated Kura
// gateways. The keys it shares with the regional gateway config in
// infra/helm/platform/values.yaml must stay equal; TestGatewayNginxConfigMatchesChart
// asserts that (required keys present and matching, any other shared key
// matching where a region sets it) so the two render paths cannot drift.
//
// hostNetwork gateways (bare-metal regions) sit directly on the box NIC with no
// LoadBalancer to prepend a PROXY header, so proxy-protocol must be off there or
// it mangles every connection — the same override the platform chart applies to
// its host-network regional gateways. The LB-fronted path keeps it on.
func gatewayNginxConfigData(hostNetwork bool) map[string]string {
	useProxyProtocol := "true"
	if hostNetwork {
		useProxyProtocol = "false"
	}
	return map[string]string{
		"use-forwarded-headers":       "true",
		"use-proxy-protocol":          useProxyProtocol,
		"compute-full-forwarded-for":  "true",
		"upstream-keepalive-timeout":  "10",
		"allow-snippet-annotations":   "false",
		"enable-real-ip":              "true",
		"proxy-real-ip-cidr":          "0.0.0.0/0",
		"proxy-body-size":             "0",
		"proxy-request-buffering":     "off",
		"proxy-buffering":             "off",
		"proxy-max-temp-file-size":    "0",
		"keep-alive-requests":         "10000",
		"upstream-keepalive-requests": "10000",
		// HTTP/2 request-body flow control. nginx's 64KB default window caps
		// every upload stream (gRPC ByteStream writes and HTTP/2 CLI uploads
		// alike) at ~window/RTT — ~310KB/s from a 193ms client. Both knobs must
		// move together: http2_body_preread_size is the window advertised before
		// the body is consumed, client-body-buffer-size paces WINDOW_UPDATEs
		// while streaming to the upstream. The stream cap bounds worst-case nginx
		// memory at 32 x 4m = 128MB per client connection; excess RPCs queue
		// client-side.
		"client-body-buffer-size":      "4m",
		"http2-max-concurrent-streams": "32",
		"http-snippet":                 "http2_body_preread_size 4m;",
	}
}

func (r *KuraGatewayReconciler) reconcileGatewayConfigMap(ctx context.Context, gateway *kurav1alpha1.KuraGateway) error {
	configMap := &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: gatewayWorkloadName(gateway), Namespace: gateway.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, configMap, func() error {
		if err := controllerutil.SetControllerReference(gateway, configMap, r.Scheme); err != nil {
			return err
		}
		configMap.Labels = gatewayLabels(gateway)
		configMap.Data = gatewayNginxConfigData(gateway.Spec.HostNetwork)
		return nil
	})
	return err
}

func (r *KuraGatewayReconciler) reconcileGatewayService(ctx context.Context, gateway *kurav1alpha1.KuraGateway) error {
	service := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: gatewayWorkloadName(gateway), Namespace: gateway.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, service, func() error {
		if err := controllerutil.SetControllerReference(gateway, service, r.Scheme); err != nil {
			return err
		}
		service.Labels = gatewayLabels(gateway)
		if gateway.Spec.HostNetwork {
			service.Annotations = nil
			service.Spec.Type = corev1.ServiceTypeClusterIP
			service.Spec.ExternalTrafficPolicy = ""
		} else {
			service.Annotations = gateway.Spec.ServiceAnnotations()
			service.Spec.Type = corev1.ServiceTypeLoadBalancer
			service.Spec.ExternalTrafficPolicy = corev1.ServiceExternalTrafficPolicyLocal
		}
		service.Spec.Selector = gatewaySelectorLabels(gateway)
		service.Spec.Ports = []corev1.ServicePort{
			{Name: "http", Port: 80, TargetPort: intstr.FromString("http"), Protocol: corev1.ProtocolTCP},
			{Name: "https", Port: 443, TargetPort: intstr.FromString("https"), Protocol: corev1.ProtocolTCP},
		}
		return nil
	})
	return err
}

func (r *KuraGatewayReconciler) reconcileGatewayIngressClass(ctx context.Context, gateway *kurav1alpha1.KuraGateway) error {
	ingressClass := &networkingv1.IngressClass{ObjectMeta: metav1.ObjectMeta{Name: gatewayIngressClassName(gateway)}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, ingressClass, func() error {
		ingressClass.Labels = gatewayLabels(gateway)
		ingressClass.Spec.Controller = gatewayControllerClassName(gateway)
		return nil
	})
	return err
}

func (r *KuraGatewayReconciler) rememberGatewayIngressClassName(ctx context.Context, gateway *kurav1alpha1.KuraGateway) error {
	ingressClassName := gatewayIngressClassName(gateway)
	if gateway.Status.IngressClassName == ingressClassName {
		return nil
	}
	gateway.Status.IngressClassName = ingressClassName
	return r.Status().Update(ctx, gateway)
}

func (r *KuraGatewayReconciler) reconcileGatewayDeployment(ctx context.Context, gateway *kurav1alpha1.KuraGateway) error {
	deployment := &appsv1.Deployment{ObjectMeta: metav1.ObjectMeta{Name: gatewayWorkloadName(gateway), Namespace: gateway.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, deployment, func() error {
		if err := controllerutil.SetControllerReference(gateway, deployment, r.Scheme); err != nil {
			return err
		}
		deployment.Labels = gatewayLabels(gateway)
		deployment.Spec.Replicas = ptr(gatewayReplicas(gateway))
		deployment.Spec.Selector = &metav1.LabelSelector{MatchLabels: gatewaySelectorLabels(gateway)}
		deployment.Spec.Template = gatewayPodTemplate(gateway, r.gatewayServiceAccountName())
		return nil
	})
	return err
}

// gatewayControllerArgs builds the ingress-nginx controller flags. A
// LoadBalancer-fronted gateway publishes its Service's external IP into Ingress
// status via --publish-service. A host-network gateway has no LoadBalancer, so it
// must report the node's own InternalIP (the box's public IP) instead —
// otherwise external-dns would resolve the per-account host to the unreachable
// ClusterIP. Mirrors the platform chart's reportNodeInternalIp for its
// host-network regional gateways.
func gatewayControllerArgs(gateway *kurav1alpha1.KuraGateway) []string {
	args := []string{
		"/nginx-ingress-controller",
		"--election-id=" + gateway.Name + "-leader",
		"--controller-class=" + gatewayControllerClassName(gateway),
		"--ingress-class=" + gatewayIngressClassName(gateway),
		"--configmap=$(POD_NAMESPACE)/" + gatewayWorkloadName(gateway),
		"--watch-namespace=$(POD_NAMESPACE)",
	}
	if gateway.Spec.HostNetwork {
		args = append(args, "--report-node-internal-ip-address=true")
	} else {
		args = append(args, "--publish-service=$(POD_NAMESPACE)/"+gatewayWorkloadName(gateway))
	}
	return args
}

func gatewayPodTemplate(gateway *kurav1alpha1.KuraGateway, serviceAccountName string) corev1.PodTemplateSpec {
	return corev1.PodTemplateSpec{
		ObjectMeta: metav1.ObjectMeta{Labels: gatewaySelectorLabels(gateway)},
		Spec: corev1.PodSpec{
			HostNetwork:        gateway.Spec.HostNetwork,
			DNSPolicy:          gatewayDNSPolicy(gateway),
			ServiceAccountName: serviceAccountName,
			NodeSelector:       gateway.Spec.PodNodeSelector(),
			Containers: []corev1.Container{{
				Name:            "controller",
				Image:           gatewayControllerImage(gateway),
				ImagePullPolicy: corev1.PullIfNotPresent,
				Args: gatewayControllerArgs(gateway),
				Env: gateway.Spec.Environment(),
				Ports: []corev1.ContainerPort{
					{Name: "http", ContainerPort: 80, Protocol: corev1.ProtocolTCP},
					{Name: "https", ContainerPort: 443, Protocol: corev1.ProtocolTCP},
					{Name: "metrics", ContainerPort: 10254, Protocol: corev1.ProtocolTCP},
				},
				ReadinessProbe: gatewayHealthProbe(),
				LivenessProbe:  gatewayHealthProbe(),
				Resources: corev1.ResourceRequirements{
					Requests: corev1.ResourceList{
						corev1.ResourceCPU:    resource.MustParse("100m"),
						corev1.ResourceMemory: resource.MustParse("128Mi"),
					},
					Limits: corev1.ResourceList{
						corev1.ResourceMemory: resource.MustParse("512Mi"),
					},
				},
			}},
		},
	}
}

func gatewayDNSPolicy(gateway *kurav1alpha1.KuraGateway) corev1.DNSPolicy {
	if gateway.Spec.HostNetwork {
		return corev1.DNSClusterFirstWithHostNet
	}
	return corev1.DNSClusterFirst
}

func gatewayHealthProbe() *corev1.Probe {
	return &corev1.Probe{
		ProbeHandler: corev1.ProbeHandler{HTTPGet: &corev1.HTTPGetAction{
			Path: "/healthz",
			Port: intstr.FromString("metrics"),
		}},
		InitialDelaySeconds: 10,
		PeriodSeconds:       10,
		TimeoutSeconds:      1,
	}
}

type gatewayStatusState struct {
	phase         string
	readyReplicas int32
	loadBalancer  string
	message       string
}

func (r *KuraGatewayReconciler) gatewayStatus(ctx context.Context, gateway *kurav1alpha1.KuraGateway) (gatewayStatusState, error) {
	deployment := &appsv1.Deployment{}
	if err := r.Get(ctx, types.NamespacedName{Name: gatewayWorkloadName(gateway), Namespace: gateway.Namespace}, deployment); err != nil {
		if apierrors.IsNotFound(err) {
			return gatewayStatusState{phase: "Pending", message: "Deployment has not been created yet"}, nil
		}
		return gatewayStatusState{}, err
	}
	ready := deployment.Status.ReadyReplicas
	replicas := gatewayReplicas(gateway)

	// Host-network gateways bind the node's public IP directly and have no
	// cloud LoadBalancer to wait on, so readiness gates on replicas alone.
	if gateway.Spec.HostNetwork {
		if ready >= replicas {
			return gatewayStatusState{
				phase:         "Ready",
				readyReplicas: ready,
				loadBalancer:  "host-network",
				message:       fmt.Sprintf("%d/%d gateway replicas ready (hostNetwork)", ready, replicas),
			}, nil
		}
		return gatewayStatusState{
			phase:         "Pending",
			readyReplicas: ready,
			message:       fmt.Sprintf("%d/%d gateway replicas ready (hostNetwork)", ready, replicas),
		}, nil
	}

	loadBalancer, err := r.gatewayLoadBalancer(ctx, gateway)
	if err != nil {
		return gatewayStatusState{}, err
	}
	if ready >= replicas && loadBalancer != "" {
		return gatewayStatusState{
			phase:         "Ready",
			readyReplicas: ready,
			loadBalancer:  loadBalancer,
			message:       fmt.Sprintf("%d/%d gateway replicas ready", ready, replicas),
		}, nil
	}
	return gatewayStatusState{
		phase:         "Pending",
		readyReplicas: ready,
		loadBalancer:  loadBalancer,
		message:       fmt.Sprintf("%d/%d gateway replicas ready, loadBalancer=%t", ready, replicas, loadBalancer != ""),
	}, nil
}

func (r *KuraGatewayReconciler) gatewayLoadBalancer(ctx context.Context, gateway *kurav1alpha1.KuraGateway) (string, error) {
	service := &corev1.Service{}
	if err := r.Get(ctx, types.NamespacedName{Name: gatewayWorkloadName(gateway), Namespace: gateway.Namespace}, service); err != nil {
		if apierrors.IsNotFound(err) {
			return "", nil
		}
		return "", err
	}
	for _, ingress := range service.Status.LoadBalancer.Ingress {
		if ingress.Hostname != "" {
			return ingress.Hostname, nil
		}
		if ingress.IP != "" {
			return ingress.IP, nil
		}
	}
	return "", nil
}

func gatewayReplicas(gateway *kurav1alpha1.KuraGateway) int32 {
	if gateway.Spec.Replicas != nil && *gateway.Spec.Replicas > 0 {
		return *gateway.Spec.Replicas
	}
	return 2
}

func gatewayControllerImage(gateway *kurav1alpha1.KuraGateway) string {
	if strings.TrimSpace(gateway.Spec.ControllerImage) != "" {
		return strings.TrimSpace(gateway.Spec.ControllerImage)
	}
	return defaultGatewayControllerImage
}

func gatewayIngressClassName(gateway *kurav1alpha1.KuraGateway) string {
	return strings.TrimSpace(gateway.Spec.IngressClassName)
}

func gatewayControllerClassName(gateway *kurav1alpha1.KuraGateway) string {
	if strings.TrimSpace(gateway.Spec.ControllerClassName) != "" {
		return strings.TrimSpace(gateway.Spec.ControllerClassName)
	}
	return "k8s.io/" + gatewayIngressClassName(gateway) + "-ingress-nginx"
}

func gatewayWorkloadName(gateway *kurav1alpha1.KuraGateway) string {
	return gateway.Name + "-controller"
}

func gatewayLabels(gateway *kurav1alpha1.KuraGateway) map[string]string {
	labels := gatewaySelectorLabels(gateway)
	labels["app.kubernetes.io/managed-by"] = "kura-controller"
	labels["tuist.dev/region"] = gateway.Spec.Region
	labels["tuist.dev/kura-gateway"] = gateway.Name
	return labels
}

func gatewaySelectorLabels(gateway *kurav1alpha1.KuraGateway) map[string]string {
	return map[string]string{
		"app.kubernetes.io/name":      "ingress-nginx",
		"app.kubernetes.io/instance":  gateway.Name,
		"app.kubernetes.io/component": "controller",
	}
}

func (r *KuraGatewayReconciler) gatewayServiceAccountName() string {
	if strings.TrimSpace(r.GatewayServiceAccountName) != "" {
		return strings.TrimSpace(r.GatewayServiceAccountName)
	}
	return defaultGatewayServiceAccount
}

func (r *KuraGatewayReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&kurav1alpha1.KuraGateway{}).
		Owns(&appsv1.Deployment{}).
		Owns(&corev1.Service{}).
		Owns(&corev1.ConfigMap{}).
		Complete(r)
}
