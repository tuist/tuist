package controllers

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"hash/fnv"
	"math/big"
	"net/http"
	"strconv"
	"strings"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	policyv1 "k8s.io/api/policy/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/intstr"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"
	"sigs.k8s.io/controller-runtime/pkg/event"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

const (
	KuraInstanceFinalizer = "kurainstances.kura.tuist.dev/finalizer"

	httpPort int32 = 4000
	grpcPort int32 = 50051
	peerPort int32 = 7443

	// drainCompletionTimeoutMs and preStopDelaySeconds together set how
	// long a Kura pod is given to bleed connections off before SIGTERM.
	// preStop sends SIGUSR1 to start the runtime drain and then sleeps
	// for preStopDelaySeconds so endpoint propagation removes the pod
	// from the Service before it stops accepting new work.
	drainCompletionTimeoutMs int64 = 240_000
	preStopDelaySeconds      int64 = 20
	terminationGraceExtra    int64 = 15

	// podNameLabel is the per-pod label the StatefulSet controller stamps
	// on every pod (<statefulset>-<ordinal>). The public backend Service
	// selects a single pod through it so steady-state cache traffic for a
	// region lands on one node, giving read-after-write consistency
	// without fanning the read path across the eventually-consistent mesh.
	podNameLabel = "statefulset.kubernetes.io/pod-name"

	// minPrimaryPodAge gives a restarted pod time to bootstrap from peers
	// before the public Services can route cache reads to it.
	minPrimaryPodAge = 10 * time.Minute

	sharedSecretsName         = "kura-shared-secrets"
	otlpTracesEndpointEnvVar  = "KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"
	environmentEnvVar         = "KURA_OTEL_DEPLOYMENT_ENVIRONMENT"
	sharedSecretsRVAnnotation = "kura.tuist.dev/shared-secrets-resource-version"

	peerTLSVolumeName = "peer-tls"
	peerTLSMountPath  = "/etc/kura/peer-tls"
	peerTLSCAFile     = "ca.pem"
	peerTLSCertFile   = "tls.crt"
	peerTLSKeyFile    = "tls.key"
	peerCACertFile    = "ca.pem"
	peerCAKeyFile     = "ca-key.pem"
)

type KuraInstanceReconciler struct {
	client.Client
	Scheme *runtime.Scheme

	// GRPCClusterIssuer, when non-empty, makes the controller request
	// cert-manager Certificates per instance with this ClusterIssuer for
	// both the public HTTPS host and the gRPC host. The issued Secrets
	// are referenced by the regional Kura ingress layer that terminates
	// TLS for customer-facing traffic.
	// The name is historical; the controller uses the same issuer for
	// every cert it asks cert-manager to mint.
	GRPCClusterIssuer   string
	OTLPTracesEndpoint  string
	Environment         string
	RuntimeStatusClient RuntimeStatusClient
}

type RuntimeStatusClient interface {
	Status(ctx context.Context, pod corev1.Pod) (runtimeStatus, error)
}

type runtimeStatus struct {
	Ready           bool   `json:"ready"`
	State           string `json:"state"`
	RingMembers     int    `json:"ring_members"`
	WriterLockOwned bool   `json:"writer_lock_owned"`
}

type httpRuntimeStatusClient struct {
	client *http.Client
}

func certificateGVK() schema.GroupVersionKind {
	return schema.GroupVersionKind{Group: "cert-manager.io", Version: "v1", Kind: "Certificate"}
}

func grpcTLSSecretName(instance *kurav1alpha1.KuraInstance) string {
	return instance.Name + "-grpc-tls"
}

func publicTLSSecretName(instance *kurav1alpha1.KuraInstance) string {
	return instance.Name + "-public-tls"
}

func peerTLSSecretName(instance *kurav1alpha1.KuraInstance) string {
	if instance.Spec.PeerTLSSecretName != "" {
		return instance.Spec.PeerTLSSecretName
	}
	return instance.Name + "-peer-tls"
}

func grpcServiceName(instance *kurav1alpha1.KuraInstance) string {
	return instance.Name + "-grpc"
}

func peerServiceName(instance *kurav1alpha1.KuraInstance) string {
	return instance.Name + "-peer"
}

func externalServiceName(instance *kurav1alpha1.KuraInstance) string {
	return instance.Name + "-external"
}

func crossRegionRuntimeEnabled(instance *kurav1alpha1.KuraInstance) bool {
	return instance.Spec.Mesh || instance.Spec.PeerTLSSecretName != ""
}

// meshManagedPeerTLS is true when the controller owns peer TLS for this
// instance: Mesh is on and no external secret was supplied. In that mode
// the controller maintains the per-account CA and signs the instance leaf.
func meshManagedPeerTLS(instance *kurav1alpha1.KuraInstance) bool {
	return instance.Spec.Mesh && instance.Spec.PeerTLSSecretName == ""
}

func accountPeerCASecretName(instance *kurav1alpha1.KuraInstance) string {
	name := "kura-" + instance.Spec.AccountHandle + "-peer-ca"
	if len(name) <= 63 {
		return name
	}

	hash := fnv.New32a()
	_, _ = hash.Write([]byte(instance.Spec.AccountHandle))
	suffix := fmt.Sprintf("-%x", hash.Sum32())
	return strings.TrimRight(name[:63-len(suffix)], "-") + suffix
}

func terminationGracePeriodSeconds() int64 {
	return preStopDelaySeconds + drainCompletionTimeoutMs/1000 + terminationGraceExtra
}

// +kubebuilder:rbac:groups=kura.tuist.dev,resources=kurainstances,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=kura.tuist.dev,resources=kurainstances/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=kura.tuist.dev,resources=kurainstances/finalizers,verbs=update
// +kubebuilder:rbac:groups=apps,resources=statefulsets,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=services;configmaps,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=secrets,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups="",resources=pods,verbs=get;list;watch
// +kubebuilder:rbac:groups="",resources=nodes,verbs=get;list;watch
// +kubebuilder:rbac:groups="",resources=persistentvolumeclaims,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=networking.k8s.io,resources=ingresses;networkpolicies,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=policy,resources=poddisruptionbudgets,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=cert-manager.io,resources=certificates,verbs=get;list;watch;create;update;patch;delete

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
	if err := r.reconcileAccountPeerService(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}
	primaryPod, err := r.selectPrimaryPod(ctx, instance)
	if err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileService(ctx, instance, primaryPod); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileGRPCService(ctx, instance, primaryPod); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcilePeerService(ctx, instance, primaryPod); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileExternalService(ctx, instance, primaryPod); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcilePublicIngress(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileGRPCIngress(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcilePublicCertificate(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileGRPCCertificate(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcilePeerTLSSecret(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileNetworkPolicy(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcilePodDisruptionBudget(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileStatefulSet(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}

	rollout, err := r.rolloutStatus(ctx, instance)
	if err != nil {
		return ctrl.Result{}, err
	}
	external, err := r.externalEndpoint(ctx, instance, primaryPod)
	if err != nil {
		return ctrl.Result{}, err
	}
	now := metav1.NewTime(time.Now().UTC())
	instance.Status.Phase = rollout.phase
	instance.Status.PublicURL = publicURL(instance)
	instance.Status.GRPCPublicURL = grpcPublicURL(instance)
	instance.Status.ObservedImage = rollout.observedImage
	instance.Status.ReadyReplicas = rollout.readyReplicas
	instance.Status.Message = rollout.message
	instance.Status.NodeAddress = external.nodeAddress
	instance.Status.NodePortHTTP = external.nodePortHTTP
	instance.Status.NodePortGRPC = external.nodePortGRPC
	instance.Status.LastReconciledAt = &now

	if err := r.Status().Update(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}

	logger.Info("reconciled Kura instance", "phase", rollout.phase, "readyReplicas", rollout.readyReplicas)
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

func (r *KuraInstanceReconciler) reconcileAccountPeerService(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	if !crossRegionRuntimeEnabled(instance) {
		return nil
	}

	service := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: accountPeerServiceName(instance), Namespace: instance.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, service, func() error {
		service.Labels = map[string]string{
			"app.kubernetes.io/name":       "kura",
			"app.kubernetes.io/managed-by": "kura-controller",
			"tuist.dev/account":            instance.Spec.AccountHandle,
		}
		service.Spec.ClusterIP = corev1.ClusterIPNone
		service.Spec.PublishNotReadyAddresses = true
		service.Spec.Selector = map[string]string{
			"app.kubernetes.io/name": "kura",
			"tuist.dev/account":      instance.Spec.AccountHandle,
		}
		service.Spec.Ports = []corev1.ServicePort{
			{Name: "peer", Port: peerPort, TargetPort: intstr.FromString("peer")},
		}
		return nil
	})
	return err
}

func (r *KuraInstanceReconciler) reconcileService(ctx context.Context, instance *kurav1alpha1.KuraInstance, primaryPod string) error {
	service := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, service, func() error {
		if err := controllerutil.SetControllerReference(instance, service, r.Scheme); err != nil {
			return err
		}
		service.Labels = labels(instance)
		service.Spec.Selector = primaryServiceSelector(instance, primaryPod)
		service.Annotations = nil
		service.Spec.Type = corev1.ServiceTypeClusterIP
		service.Spec.ExternalTrafficPolicy = ""
		service.Spec.Ports = ports()
		return nil
	})
	return err
}

// reconcileExternalService publishes http/grpc on a NodePort Service
// for clients that share a network with the node pool but not the pod
// network (see KuraInstanceSpec.ExposeNodePort). externalTrafficPolicy
// Local both preserves the client source IP (so ClientCIDRs NetworkPolicy
// rules can match it) and refuses traffic on nodes not hosting the
// primary pod — dispatch always pairs the port with status.NodeAddress.
func (r *KuraInstanceReconciler) reconcileExternalService(ctx context.Context, instance *kurav1alpha1.KuraInstance, primaryPod string) error {
	if !instance.Spec.ExposeNodePort {
		return r.deleteLegacyServiceIfExists(ctx, externalServiceName(instance), instance.Namespace)
	}
	service := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: externalServiceName(instance), Namespace: instance.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, service, func() error {
		if err := controllerutil.SetControllerReference(instance, service, r.Scheme); err != nil {
			return err
		}
		// Keep the NodePorts the API server already allocated:
		// rewriting ports with nodePort 0 re-allocates them, which
		// would invalidate every endpoint dispatch handed out.
		allocated := map[string]int32{}
		for _, port := range service.Spec.Ports {
			allocated[port.Name] = port.NodePort
		}
		ports := externalPorts()
		for i := range ports {
			ports[i].NodePort = allocated[ports[i].Name]
		}
		service.Labels = labels(instance)
		service.Spec.Selector = primaryServiceSelector(instance, primaryPod)
		service.Spec.Type = corev1.ServiceTypeNodePort
		service.Spec.ExternalTrafficPolicy = corev1.ServiceExternalTrafficPolicyLocal
		service.Spec.Ports = ports
		return nil
	})
	return err
}

type externalEndpoint struct {
	nodeAddress  string
	nodePortHTTP int32
	nodePortGRPC int32
}

// externalEndpoint resolves what NodePort clients dial: the allocated
// ports plus the Private-Network address (`tuist.dev/pn-ipv4` node
// label) of the node hosting the primary pod. Any missing link —
// unplaced pod, unlabeled node, unallocated Service — yields empty
// fields rather than an error: dispatch withholds the endpoint until
// the whole chain is up, the same contract as an unprovisioned
// instance.
func (r *KuraInstanceReconciler) externalEndpoint(ctx context.Context, instance *kurav1alpha1.KuraInstance, primaryPod string) (externalEndpoint, error) {
	if !instance.Spec.ExposeNodePort {
		return externalEndpoint{}, nil
	}

	endpoint := externalEndpoint{}
	service := &corev1.Service{}
	switch err := r.Get(ctx, types.NamespacedName{Name: externalServiceName(instance), Namespace: instance.Namespace}, service); {
	case err == nil:
		for _, port := range service.Spec.Ports {
			switch port.Name {
			case "http":
				endpoint.nodePortHTTP = port.NodePort
			case "grpc":
				endpoint.nodePortGRPC = port.NodePort
			}
		}
	case apierrors.IsNotFound(err):
		return externalEndpoint{}, nil
	default:
		return externalEndpoint{}, err
	}

	if primaryPod == "" {
		return endpoint, nil
	}
	pod := &corev1.Pod{}
	switch err := r.Get(ctx, types.NamespacedName{Name: primaryPod, Namespace: instance.Namespace}, pod); {
	case err == nil:
	case apierrors.IsNotFound(err):
		return endpoint, nil
	default:
		return externalEndpoint{}, err
	}
	if pod.Spec.NodeName == "" {
		return endpoint, nil
	}
	node := &corev1.Node{}
	switch err := r.Get(ctx, types.NamespacedName{Name: pod.Spec.NodeName}, node); {
	case err == nil:
		endpoint.nodeAddress = node.Labels["tuist.dev/pn-ipv4"]
	case apierrors.IsNotFound(err):
	default:
		return externalEndpoint{}, err
	}
	return endpoint, nil
}

func (r *KuraInstanceReconciler) reconcileGRPCService(ctx context.Context, instance *kurav1alpha1.KuraInstance, primaryPod string) error {
	return r.deleteLegacyServiceIfExists(ctx, grpcServiceName(instance), instance.Namespace)
}

func (r *KuraInstanceReconciler) reconcilePeerService(ctx context.Context, instance *kurav1alpha1.KuraInstance, primaryPod string) error {
	return r.deleteLegacyServiceIfExists(ctx, peerServiceName(instance), instance.Namespace)
}

func (r *KuraInstanceReconciler) deleteLegacyServiceIfExists(ctx context.Context, name string, namespace string) error {
	service := &corev1.Service{}
	if err := r.Get(ctx, types.NamespacedName{Name: name, Namespace: namespace}, service); err != nil {
		if apierrors.IsNotFound(err) {
			return nil
		}
		return err
	}
	return r.Delete(ctx, service)
}

func (r *KuraInstanceReconciler) reconcilePublicIngress(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	ingress := &networkingv1.Ingress{ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace}}
	if instance.Spec.PublicHost == "" {
		if err := r.Delete(ctx, ingress); err != nil && !apierrors.IsNotFound(err) {
			return err
		}
		return nil
	}

	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, ingress, func() error {
		if err := controllerutil.SetControllerReference(instance, ingress, r.Scheme); err != nil {
			return err
		}
		ingress.Labels = labels(instance)
		ingress.Annotations = publicIngressAnnotations()
		ingress.Spec.IngressClassName = ptr(ingressClassName(instance))
		ingress.Spec.TLS = []networkingv1.IngressTLS{{
			Hosts:      []string{instance.Spec.PublicHost},
			SecretName: publicTLSSecretName(instance),
		}}
		ingress.Spec.Rules = []networkingv1.IngressRule{{
			Host: instance.Spec.PublicHost,
			IngressRuleValue: networkingv1.IngressRuleValue{HTTP: &networkingv1.HTTPIngressRuleValue{
				Paths: []networkingv1.HTTPIngressPath{{
					Path:     "/",
					PathType: ptr(networkingv1.PathTypePrefix),
					Backend:  ingressBackend(instance.Name, "http"),
				}},
			}},
		}}
		return nil
	})
	return err
}

func (r *KuraInstanceReconciler) reconcileGRPCIngress(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	ingress := &networkingv1.Ingress{ObjectMeta: metav1.ObjectMeta{Name: grpcServiceName(instance), Namespace: instance.Namespace}}
	if instance.Spec.GRPCPublicHost == "" {
		if err := r.Delete(ctx, ingress); err != nil && !apierrors.IsNotFound(err) {
			return err
		}
		return nil
	}

	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, ingress, func() error {
		if err := controllerutil.SetControllerReference(instance, ingress, r.Scheme); err != nil {
			return err
		}
		ingress.Labels = labels(instance)
		ingress.Annotations = grpcIngressAnnotations()
		ingress.Spec.IngressClassName = ptr(ingressClassName(instance))
		ingress.Spec.TLS = []networkingv1.IngressTLS{{
			Hosts:      []string{instance.Spec.GRPCPublicHost},
			SecretName: grpcTLSSecretName(instance),
		}}
		ingress.Spec.Rules = []networkingv1.IngressRule{{
			Host: instance.Spec.GRPCPublicHost,
			IngressRuleValue: networkingv1.IngressRuleValue{HTTP: &networkingv1.HTTPIngressRuleValue{
				Paths: []networkingv1.HTTPIngressPath{{
					Path:     "/",
					PathType: ptr(networkingv1.PathTypePrefix),
					Backend:  ingressBackend(instance.Name, "grpc"),
				}},
			}},
		}}
		return nil
	})
	return err
}

func ingressBackend(serviceName string, servicePortName string) networkingv1.IngressBackend {
	return networkingv1.IngressBackend{Service: &networkingv1.IngressServiceBackend{
		Name: serviceName,
		Port: networkingv1.ServiceBackendPort{Name: servicePortName},
	}}
}

func ingressClassName(instance *kurav1alpha1.KuraInstance) string {
	if strings.TrimSpace(instance.Spec.IngressClassName) != "" {
		return strings.TrimSpace(instance.Spec.IngressClassName)
	}
	return "nginx"
}

// primaryServiceSelector pins a public Service to a single pod by adding
// the StatefulSet per-pod label to the instance selector. The headless
// Service keeps the broad selector so peer replication still reaches
// every pod.
func primaryServiceSelector(instance *kurav1alpha1.KuraInstance, primaryPod string) map[string]string {
	selector := selectorLabels(instance)
	selector[podNameLabel] = primaryPod
	return selector
}

// selectPrimaryPod resolves which pod the public Services should route
// to. The currently routed pod is read back from the existing Service
// selector so the choice is sticky across reconciles and survives a
// controller restart without a dedicated status field.
func (r *KuraInstanceReconciler) selectPrimaryPod(ctx context.Context, instance *kurav1alpha1.KuraInstance) (string, error) {
	current := ""
	service := &corev1.Service{}
	switch err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, service); {
	case err == nil:
		current = service.Spec.Selector[podNameLabel]
	case apierrors.IsNotFound(err):
	default:
		return "", err
	}

	pods := &corev1.PodList{}
	if err := r.List(ctx, pods, client.InNamespace(instance.Namespace), client.MatchingLabels(selectorLabels(instance))); err != nil {
		return "", err
	}
	return choosePrimaryPod(current, instance.Name, pods.Items, r.primaryPodHealth(ctx, instance, pods.Items)), nil
}

func (r *KuraInstanceReconciler) primaryPodHealth(ctx context.Context, instance *kurav1alpha1.KuraInstance, pods []corev1.Pod) map[string]bool {
	kubernetesReady := map[string]bool{}
	now := time.Now()
	for i := range pods {
		if podReady(&pods[i]) && podOldEnoughForPrimary(&pods[i], now, replicas(instance)) {
			kubernetesReady[pods[i].Name] = true
		}
	}

	statusClient := r.RuntimeStatusClient
	if statusClient == nil {
		statusClient = defaultRuntimeStatusClient()
	}

	runtimeHealthy := map[string]bool{}
	runtimeStatuses := 0
	for i := range pods {
		if !kubernetesReady[pods[i].Name] {
			continue
		}
		status, err := statusClient.Status(ctx, pods[i])
		if err != nil {
			log.FromContext(ctx).V(1).Info("failed to read Kura pod rollout status", "pod", pods[i].Name, "error", err)
			continue
		}
		runtimeStatuses++
		runtimeHealthy[pods[i].Name] = runtimeStatusRoutable(status, replicas(instance))
	}

	if runtimeStatuses == 0 {
		return kubernetesReady
	}
	return runtimeHealthy
}

func defaultRuntimeStatusClient() RuntimeStatusClient {
	return &httpRuntimeStatusClient{client: &http.Client{Timeout: 2 * time.Second}}
}

func (c *httpRuntimeStatusClient) Status(ctx context.Context, pod corev1.Pod) (runtimeStatus, error) {
	if pod.Status.PodIP == "" {
		return runtimeStatus{}, fmt.Errorf("pod has no IP")
	}
	request, err := http.NewRequestWithContext(ctx, http.MethodGet, fmt.Sprintf("http://%s:%d/status/rollout", pod.Status.PodIP, httpPort), nil)
	if err != nil {
		return runtimeStatus{}, err
	}
	response, err := c.client.Do(request)
	if err != nil {
		return runtimeStatus{}, err
	}
	defer response.Body.Close()

	if response.StatusCode != http.StatusOK {
		return runtimeStatus{}, fmt.Errorf("unexpected status %d", response.StatusCode)
	}
	var status runtimeStatus
	if err := json.NewDecoder(response.Body).Decode(&status); err != nil {
		return runtimeStatus{}, err
	}
	return status, nil
}

func runtimeStatusRoutable(status runtimeStatus, replicas int32) bool {
	if !status.Ready || status.State != "serving" || !status.WriterLockOwned {
		return false
	}
	return status.RingMembers >= requiredPrimaryRingMembers(replicas)
}

func requiredPrimaryRingMembers(replicas int32) int {
	if replicas <= 1 {
		return 1
	}
	return 2
}

// choosePrimaryPod picks the pod the public Services route to. It is
// sticky: the current primary is kept while it stays routable so a
// recovered lower-ordinal pod does not steal traffic back, because every
// handoff costs a brief read-after-write inconsistency window during
// async replication catch-up and we want to minimise them. Otherwise it
// falls to the lowest-ordinal routable pod, and before any pod is
// routable it defaults to ordinal 0 so the Service has a stable selector.
func choosePrimaryPod(current, instanceName string, pods []corev1.Pod, routable map[string]bool) string {
	if routable == nil {
		routable = map[string]bool{}
		for i := range pods {
			if podReady(&pods[i]) {
				routable[pods[i].Name] = true
			}
		}
	}

	if current != "" && routable[current] {
		return current
	}

	best := ""
	bestOrdinal := -1
	for name, ok := range routable {
		if !ok {
			continue
		}
		ordinal, ok := podOrdinal(name, instanceName)
		if !ok {
			continue
		}
		if best == "" || ordinal < bestOrdinal {
			best = name
			bestOrdinal = ordinal
		}
	}
	if best != "" {
		return best
	}

	if current != "" {
		return current
	}
	return fmt.Sprintf("%s-0", instanceName)
}

func podReady(pod *corev1.Pod) bool {
	if pod.DeletionTimestamp != nil {
		return false
	}
	for _, condition := range pod.Status.Conditions {
		if condition.Type == corev1.PodReady {
			return condition.Status == corev1.ConditionTrue
		}
	}
	return false
}

func podOldEnoughForPrimary(pod *corev1.Pod, now time.Time, replicas int32) bool {
	if replicas <= 1 || pod.CreationTimestamp.IsZero() {
		return true
	}
	return now.Sub(pod.CreationTimestamp.Time) >= minPrimaryPodAge
}

func podOrdinal(podName, instanceName string) (int, bool) {
	prefix := instanceName + "-"
	if !strings.HasPrefix(podName, prefix) {
		return 0, false
	}
	ordinal, err := strconv.Atoi(strings.TrimPrefix(podName, prefix))
	if err != nil {
		return 0, false
	}
	return ordinal, true
}

// reconcilePublicCertificate provisions a cert-manager Certificate for
// the regional Kura ingress that terminates public HTTPS. No-ops when either
// GRPCClusterIssuer or spec.publicHost is unset. cert-manager must be
// installed in the cluster before --grpc-cluster-issuer is set.
func (r *KuraInstanceReconciler) reconcilePublicCertificate(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	cert := &unstructured.Unstructured{}
	cert.SetGroupVersionKind(certificateGVK())
	cert.SetName(publicTLSSecretName(instance))
	cert.SetNamespace(instance.Namespace)

	if r.GRPCClusterIssuer == "" || instance.Spec.PublicHost == "" {
		if err := r.Delete(ctx, cert); err != nil && !apierrors.IsNotFound(err) {
			return client.IgnoreNotFound(err)
		}
		return nil
	}

	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, cert, func() error {
		if err := controllerutil.SetControllerReference(instance, cert, r.Scheme); err != nil {
			return err
		}
		cert.SetLabels(labels(instance))
		spec := map[string]any{
			"secretName": publicTLSSecretName(instance),
			"dnsNames":   dnsNames(instance.Spec.PublicHost),
			"issuerRef": map[string]any{
				"name": r.GRPCClusterIssuer,
				"kind": "ClusterIssuer",
			},
			"privateKey": map[string]any{
				"algorithm":      "ECDSA",
				"size":           int64(256),
				"rotationPolicy": "Always",
			},
		}
		return unstructured.SetNestedField(cert.Object, spec, "spec")
	})
	return err
}

// reconcileGRPCCertificate provisions a cert-manager Certificate for
// the regional Kura ingress that terminates public gRPC. No-ops when either
// GRPCClusterIssuer or spec.grpcPublicHost is unset. cert-manager must
// be installed in the cluster before --grpc-cluster-issuer is set.
func (r *KuraInstanceReconciler) reconcileGRPCCertificate(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	cert := &unstructured.Unstructured{}
	cert.SetGroupVersionKind(certificateGVK())
	cert.SetName(grpcTLSSecretName(instance))
	cert.SetNamespace(instance.Namespace)

	if r.GRPCClusterIssuer == "" || instance.Spec.GRPCPublicHost == "" {
		if err := r.Delete(ctx, cert); err != nil && !apierrors.IsNotFound(err) {
			return client.IgnoreNotFound(err)
		}
		return nil
	}

	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, cert, func() error {
		if err := controllerutil.SetControllerReference(instance, cert, r.Scheme); err != nil {
			return err
		}
		cert.SetLabels(labels(instance))
		spec := map[string]any{
			"secretName": grpcTLSSecretName(instance),
			"dnsNames":   dnsNames(instance.Spec.GRPCPublicHost),
			"issuerRef": map[string]any{
				"name": r.GRPCClusterIssuer,
				"kind": "ClusterIssuer",
			},
			"privateKey": map[string]any{
				"algorithm":      "ECDSA",
				"size":           int64(256),
				"rotationPolicy": "Always",
			},
		}
		return unstructured.SetNestedField(cert.Object, spec, "spec")
	})
	return err
}

func (r *KuraInstanceReconciler) reconcilePeerTLSSecret(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	// An externally supplied secret is owned outside the controller.
	if instance.Spec.PeerTLSSecretName != "" {
		return nil
	}

	// The pod always mounts a peer TLS secret for the internal mTLS port.
	// Mesh instances are signed by the shared per-account CA so the
	// account's pods authenticate each other across regions; non-mesh
	// instances keep a self-signed per-instance CA that only secures
	// peering among their own replicas.
	var caCert *x509.Certificate
	var caKey *ecdsa.PrivateKey
	var caCertPEM []byte
	if meshManagedPeerTLS(instance) {
		var err error
		caCert, caKey, caCertPEM, err = r.reconcileAccountPeerCA(ctx, instance)
		if err != nil {
			return err
		}
	}

	secret := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: peerTLSSecretName(instance), Namespace: instance.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, secret, func() error {
		if err := controllerutil.SetControllerReference(instance, secret, r.Scheme); err != nil {
			return err
		}
		secret.Labels = labels(instance)
		secret.Type = corev1.SecretTypeOpaque
		if peerTLSSecretDataValid(secret.Data, instance, caCertPEM) {
			return nil
		}
		var data map[string][]byte
		var genErr error
		if caCertPEM != nil {
			data, genErr = generatePeerLeafSecretData(instance, caCert, caKey, caCertPEM)
		} else {
			data, genErr = generateSelfSignedPeerTLSSecretData(instance)
		}
		if genErr != nil {
			return genErr
		}
		secret.Data = data
		return nil
	})
	return err
}

// reconcileAccountPeerCA ensures the per-account peer CA secret exists and
// returns the parsed CA. The CA is shared by every instance of the account,
// so an account's pods can mutually authenticate while a leaf signed by a
// different account's CA fails the handshake. It carries no owner reference:
// deleting one instance must never revoke the CA the account's other
// instances depend on.
func (r *KuraInstanceReconciler) reconcileAccountPeerCA(ctx context.Context, instance *kurav1alpha1.KuraInstance) (*x509.Certificate, *ecdsa.PrivateKey, []byte, error) {
	secret := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: accountPeerCASecretName(instance), Namespace: instance.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, secret, func() error {
		secret.Labels = map[string]string{
			"app.kubernetes.io/name":       "kura",
			"app.kubernetes.io/managed-by": "kura-controller",
			"tuist.dev/account":            instance.Spec.AccountHandle,
		}
		secret.Type = corev1.SecretTypeOpaque
		if accountPeerCADataValid(secret.Data) {
			return nil
		}
		data, err := generateAccountPeerCAData(instance)
		if err != nil {
			return err
		}
		secret.Data = data
		return nil
	})
	if err != nil {
		return nil, nil, nil, err
	}
	return parseAccountPeerCA(secret.Data)
}

func accountPeerCADataValid(data map[string][]byte) bool {
	if len(data[peerCACertFile]) == 0 || len(data[peerCAKeyFile]) == 0 {
		return false
	}
	cert, key, _, err := parseAccountPeerCA(data)
	if err != nil {
		return false
	}
	return cert.IsCA && key != nil && time.Now().UTC().Before(cert.NotAfter)
}

func parseAccountPeerCA(data map[string][]byte) (*x509.Certificate, *ecdsa.PrivateKey, []byte, error) {
	caCertPEM := data[peerCACertFile]
	certBlock, _ := pem.Decode(caCertPEM)
	if certBlock == nil || certBlock.Type != "CERTIFICATE" {
		return nil, nil, nil, fmt.Errorf("account peer CA certificate is not valid PEM")
	}
	caCert, err := x509.ParseCertificate(certBlock.Bytes)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("parse account peer CA certificate: %w", err)
	}
	keyBlock, _ := pem.Decode(data[peerCAKeyFile])
	if keyBlock == nil {
		return nil, nil, nil, fmt.Errorf("account peer CA key is not valid PEM")
	}
	parsedKey, err := x509.ParsePKCS8PrivateKey(keyBlock.Bytes)
	if err != nil {
		return nil, nil, nil, fmt.Errorf("parse account peer CA key: %w", err)
	}
	caKey, ok := parsedKey.(*ecdsa.PrivateKey)
	if !ok {
		return nil, nil, nil, fmt.Errorf("account peer CA key is not an ECDSA key")
	}
	return caCert, caKey, caCertPEM, nil
}

func generateAccountPeerCAData(instance *kurav1alpha1.KuraInstance) (map[string][]byte, error) {
	caKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("generate account peer CA key: %w", err)
	}
	now := time.Now().UTC()
	caTemplate := &x509.Certificate{
		SerialNumber:          randomSerialNumber(),
		Subject:               pkix.Name{CommonName: "kura " + instance.Spec.AccountHandle + " peer CA"},
		NotBefore:             now.Add(-time.Hour),
		NotAfter:              now.AddDate(10, 0, 0),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
		BasicConstraintsValid: true,
		IsCA:                  true,
	}
	caDER, err := x509.CreateCertificate(rand.Reader, caTemplate, caTemplate, &caKey.PublicKey, caKey)
	if err != nil {
		return nil, fmt.Errorf("generate account peer CA certificate: %w", err)
	}
	caKeyPKCS8, err := x509.MarshalPKCS8PrivateKey(caKey)
	if err != nil {
		return nil, fmt.Errorf("marshal account peer CA key: %w", err)
	}
	return map[string][]byte{
		peerCACertFile: pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: caDER}),
		peerCAKeyFile:  pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: caKeyPKCS8}),
	}, nil
}

// peerTLSSecretDataValid checks the stored leaf is usable. When caCertPEM is
// non-nil (mesh mode) the embedded CA must be the live account CA, so rotating
// it reissues every instance leaf, and the leaf must cover the account peer
// Service (the SNI replication clients verify against). When caCertPEM is nil
// (self-signed mode) the leaf only needs to cover the instance's own pods.
func peerTLSSecretDataValid(data map[string][]byte, instance *kurav1alpha1.KuraInstance, caCertPEM []byte) bool {
	if len(data[peerTLSCAFile]) == 0 || len(data[peerTLSCertFile]) == 0 || len(data[peerTLSKeyFile]) == 0 {
		return false
	}
	if caCertPEM != nil && !bytes.Equal(data[peerTLSCAFile], caCertPEM) {
		return false
	}

	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(data[peerTLSCAFile]) {
		return false
	}
	if _, err := tls.X509KeyPair(data[peerTLSCertFile], data[peerTLSKeyFile]); err != nil {
		return false
	}
	block, _ := pem.Decode(data[peerTLSCertFile])
	if block == nil || block.Type != "CERTIFICATE" {
		return false
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		return false
	}
	dnsName := firstPodDNSName(instance)
	if caCertPEM != nil {
		dnsName = accountPeerServiceDNSName(instance)
	}
	_, err = cert.Verify(x509.VerifyOptions{
		DNSName:   dnsName,
		Roots:     roots,
		KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	})
	return err == nil && hasExtKeyUsage(cert, x509.ExtKeyUsageClientAuth)
}

func generateSelfSignedPeerTLSSecretData(instance *kurav1alpha1.KuraInstance) (map[string][]byte, error) {
	caKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("generate peer CA key: %w", err)
	}
	now := time.Now().UTC()
	caTemplate := &x509.Certificate{
		SerialNumber:          randomSerialNumber(),
		Subject:               pkix.Name{CommonName: instance.Name + " peer CA"},
		NotBefore:             now.Add(-time.Hour),
		NotAfter:              now.AddDate(10, 0, 0),
		KeyUsage:              x509.KeyUsageCertSign | x509.KeyUsageCRLSign,
		BasicConstraintsValid: true,
		IsCA:                  true,
	}
	caDER, err := x509.CreateCertificate(rand.Reader, caTemplate, caTemplate, &caKey.PublicKey, caKey)
	if err != nil {
		return nil, fmt.Errorf("generate peer CA certificate: %w", err)
	}
	caCertPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: caDER})

	caCert, err := x509.ParseCertificate(caDER)
	if err != nil {
		return nil, fmt.Errorf("parse generated peer CA certificate: %w", err)
	}
	return generatePeerLeafSecretData(instance, caCert, caKey, caCertPEM)
}

func generatePeerLeafSecretData(instance *kurav1alpha1.KuraInstance, caCert *x509.Certificate, caKey *ecdsa.PrivateKey, caCertPEM []byte) (map[string][]byte, error) {
	leafKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("generate peer certificate key: %w", err)
	}

	now := time.Now().UTC()
	leafTemplate := &x509.Certificate{
		SerialNumber: randomSerialNumber(),
		Subject:      pkix.Name{CommonName: instance.Name + " peer"},
		DNSNames:     peerTLSDNSNames(instance),
		NotBefore:    now.Add(-time.Hour),
		NotAfter:     now.AddDate(2, 0, 0),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth},
	}
	leafDER, err := x509.CreateCertificate(rand.Reader, leafTemplate, caCert, &leafKey.PublicKey, caKey)
	if err != nil {
		return nil, fmt.Errorf("generate peer certificate: %w", err)
	}

	leafPKCS8, err := x509.MarshalPKCS8PrivateKey(leafKey)
	if err != nil {
		return nil, fmt.Errorf("marshal peer private key: %w", err)
	}

	return map[string][]byte{
		peerTLSCAFile:   caCertPEM,
		peerTLSCertFile: pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: leafDER}),
		peerTLSKeyFile:  pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: leafPKCS8}),
	}, nil
}

func randomSerialNumber() *big.Int {
	serial, err := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 128))
	if err != nil {
		return big.NewInt(time.Now().UnixNano())
	}
	return serial
}

func hasExtKeyUsage(cert *x509.Certificate, usage x509.ExtKeyUsage) bool {
	for _, certUsage := range cert.ExtKeyUsage {
		if certUsage == usage {
			return true
		}
	}
	return false
}

func peerTLSDNSNames(instance *kurav1alpha1.KuraInstance) []string {
	headless := headlessServiceName(instance)
	account := accountPeerServiceName(instance)
	namespace := instance.Namespace
	return []string{
		fmt.Sprintf("*.%s.%s.svc.cluster.local", headless, namespace),
		fmt.Sprintf("*.%s.%s.svc", headless, namespace),
		fmt.Sprintf("*.%s.%s", headless, namespace),
		headless,
		fmt.Sprintf("%s.%s", headless, namespace),
		fmt.Sprintf("%s.%s.svc", headless, namespace),
		fmt.Sprintf("%s.%s.svc.cluster.local", headless, namespace),
		// The account peer Service is the SNI the replication client
		// verifies the server cert against: KURA_GLOBAL_DISCOVERY_DNS_NAME
		// resolves here, and reqwest keeps that host as the TLS name while
		// dialing the resolved pod address.
		account,
		fmt.Sprintf("%s.%s", account, namespace),
		fmt.Sprintf("%s.%s.svc", account, namespace),
		fmt.Sprintf("%s.%s.svc.cluster.local", account, namespace),
		fmt.Sprintf("*.%s.%s.svc.cluster.local", account, namespace),
	}
}

func firstPodDNSName(instance *kurav1alpha1.KuraInstance) string {
	return fmt.Sprintf("%s-0.%s.%s.svc.cluster.local", instance.Name, headlessServiceName(instance), instance.Namespace)
}

func dnsNames(names ...string) []any {
	seen := map[string]bool{}
	result := make([]any, 0, len(names))
	for _, name := range names {
		if name == "" || seen[name] {
			continue
		}
		seen[name] = true
		result = append(result, name)
	}
	return result
}

func (r *KuraInstanceReconciler) reconcilePodDisruptionBudget(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	pdb := &policyv1.PodDisruptionBudget{ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace}}
	if replicas(instance) <= 1 {
		if err := r.Delete(ctx, pdb); err != nil && !apierrors.IsNotFound(err) {
			return err
		}
		return nil
	}

	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, pdb, func() error {
		if err := controllerutil.SetControllerReference(instance, pdb, r.Scheme); err != nil {
			return err
		}
		pdb.Labels = labels(instance)
		pdb.Spec.MinAvailable = ptr(intstr.FromInt32(replicas(instance) - 1))
		pdb.Spec.Selector = &metav1.LabelSelector{MatchLabels: selectorLabels(instance)}
		return nil
	})
	return err
}

func (r *KuraInstanceReconciler) reconcileStatefulSet(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	sts := &appsv1.StatefulSet{ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace}}
	sharedSecretsResourceVersion, err := r.sharedSecretsResourceVersion(ctx, instance.Namespace)
	if err != nil {
		return err
	}
	_, err = controllerutil.CreateOrUpdate(ctx, r.Client, sts, func() error {
		existingVolumeClaimTemplates := sts.Spec.VolumeClaimTemplates
		if err := controllerutil.SetControllerReference(instance, sts, r.Scheme); err != nil {
			return err
		}
		sts.Labels = labels(instance)
		sts.Spec.ServiceName = headlessServiceName(instance)
		sts.Spec.Replicas = ptr(replicas(instance))
		sts.Spec.PodManagementPolicy = appsv1.ParallelPodManagement
		sts.Spec.Selector = &metav1.LabelSelector{MatchLabels: selectorLabels(instance)}
		sts.Spec.Template = podTemplate(instance, r.OTLPTracesEndpoint, r.Environment, sharedSecretsResourceVersion)
		if len(existingVolumeClaimTemplates) > 0 {
			sts.Spec.VolumeClaimTemplates = existingVolumeClaimTemplates
		} else {
			sts.Spec.VolumeClaimTemplates = []corev1.PersistentVolumeClaim{dataVolumeClaim(instance)}
		}
		// Drop the PVC when the StatefulSet itself is deleted (server
		// destroy), but keep it around when scaling down so a replica
		// can rejoin with its existing cache.
		sts.Spec.PersistentVolumeClaimRetentionPolicy = &appsv1.StatefulSetPersistentVolumeClaimRetentionPolicy{
			WhenDeleted: appsv1.DeletePersistentVolumeClaimRetentionPolicyType,
			WhenScaled:  appsv1.RetainPersistentVolumeClaimRetentionPolicyType,
		}
		return nil
	})
	if err != nil {
		return err
	}
	return r.reconcileDataPersistentVolumeClaims(ctx, instance)
}

func (r *KuraInstanceReconciler) reconcileDataPersistentVolumeClaims(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	desiredStorage := storageQuantity(instance)
	for ordinal := int32(0); ordinal < replicas(instance); ordinal++ {
		pvc := &corev1.PersistentVolumeClaim{}
		name := fmt.Sprintf("data-%s-%d", instance.Name, ordinal)
		if err := r.Get(ctx, types.NamespacedName{Name: name, Namespace: instance.Namespace}, pvc); err != nil {
			if apierrors.IsNotFound(err) {
				continue
			}
			return err
		}

		currentStorage := pvc.Spec.Resources.Requests[corev1.ResourceStorage]
		if desiredStorage.Cmp(currentStorage) <= 0 {
			continue
		}

		before := pvc.DeepCopy()
		if pvc.Spec.Resources.Requests == nil {
			pvc.Spec.Resources.Requests = corev1.ResourceList{}
		}
		pvc.Spec.Resources.Requests[corev1.ResourceStorage] = desiredStorage.DeepCopy()
		if err := r.Patch(ctx, pvc, client.MergeFrom(before)); err != nil {
			return err
		}
	}
	return nil
}

func (r *KuraInstanceReconciler) sharedSecretsResourceVersion(ctx context.Context, namespace string) (string, error) {
	secret := &corev1.Secret{}
	if err := r.Get(ctx, types.NamespacedName{Name: sharedSecretsName, Namespace: namespace}, secret); err != nil {
		if apierrors.IsNotFound(err) {
			return "", nil
		}
		return "", err
	}
	return secret.ResourceVersion, nil
}

type rolloutState struct {
	phase         string
	observedImage string
	readyReplicas int32
	message       string
}

func (r *KuraInstanceReconciler) rolloutStatus(ctx context.Context, instance *kurav1alpha1.KuraInstance) (rolloutState, error) {
	sts := &appsv1.StatefulSet{}
	err := r.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts)
	if apierrors.IsNotFound(err) {
		return rolloutState{
			phase:         "Pending",
			observedImage: instance.Status.ObservedImage,
			readyReplicas: 0,
			message:       fmt.Sprintf("StatefulSet %s has not been created yet", instance.Name),
		}, nil
	}
	if err != nil {
		return rolloutState{}, err
	}
	return rolloutStatusFromStatefulSet(instance, sts), nil
}

func rolloutStatusFromStatefulSet(instance *kurav1alpha1.KuraInstance, sts *appsv1.StatefulSet) rolloutState {
	replicas := replicas(instance)
	readyReplicas := sts.Status.ReadyReplicas
	updatedReplicas := sts.Status.UpdatedReplicas
	observedImage := instance.Status.ObservedImage
	observedGeneration := sts.Status.ObservedGeneration >= sts.Generation
	revisionsMatch := sts.Status.UpdateRevision != "" && sts.Status.CurrentRevision == sts.Status.UpdateRevision

	if observedGeneration && revisionsMatch && readyReplicas >= replicas && updatedReplicas >= replicas {
		observedImage = instance.Spec.Image

		return rolloutState{
			phase:         "Ready",
			observedImage: observedImage,
			readyReplicas: readyReplicas,
			message:       fmt.Sprintf("%d/%d replicas ready on revision %s", readyReplicas, replicas, sts.Status.CurrentRevision),
		}
	}

	return rolloutState{
		phase:         "Pending",
		observedImage: observedImage,
		readyReplicas: readyReplicas,
		message: fmt.Sprintf(
			"%d/%d replicas ready, %d/%d updated, observedGeneration=%t, revisionsMatch=%t",
			readyReplicas,
			replicas,
			updatedReplicas,
			replicas,
			observedGeneration,
			revisionsMatch,
		),
	}
}

func podTemplate(instance *kurav1alpha1.KuraInstance, otlpTracesEndpoint string, environment string, sharedSecretsResourceVersion string) corev1.PodTemplateSpec {
	return corev1.PodTemplateSpec{
		ObjectMeta: metav1.ObjectMeta{
			Labels:      labels(instance),
			Annotations: podAnnotations(instance, sharedSecretsResourceVersion),
		},
		Spec: corev1.PodSpec{
			TerminationGracePeriodSeconds: ptr(terminationGracePeriodSeconds()),
			NodeSelector:                  nodeSelector(instance),
			Tolerations:                   instance.Spec.Tolerations,
			TopologySpreadConstraints:     topologySpreadConstraints(instance),
			Containers: []corev1.Container{{
				Name:            "kura",
				Image:           instance.Spec.Image,
				ImagePullPolicy: corev1.PullIfNotPresent,
				Ports:           containerPorts(instance),
				Env:             append(baseEnv(instance, otlpTracesEndpoint, environment), instance.Spec.ExtraEnv...),
				EnvFrom:         sharedSecretsEnvFrom(),
				Resources:       defaultResources(),
				VolumeMounts:    volumeMounts(instance),
				Lifecycle:       preStopLifecycle(),
				ReadinessProbe:  httpProbe("/ready", 5, 10),
				LivenessProbe:   httpProbe("/up", 20, 20),
				StartupProbe:    httpProbe("/up", 0, 10),
			}},
			Volumes: volumes(instance),
		},
	}
}

// podAnnotations exposes Kura's Prometheus metrics to the managed
// clusters' Alloy annotation autodiscovery pipeline. Keep this aligned
// with kura/ops/helm/kura/values.yaml so controller-managed Kura pods
// publish the same telemetry surface as chart-managed ones.
func podAnnotations(instance *kurav1alpha1.KuraInstance, sharedSecretsResourceVersion string) map[string]string {
	annotations := map[string]string{}
	for key, value := range instance.Spec.PodAnnotations {
		annotations[key] = value
	}
	annotations["prometheus.io/scrape"] = "true"
	annotations["prometheus.io/port-name"] = "http"
	annotations["prometheus.io/path"] = "/metrics"
	if sharedSecretsResourceVersion != "" {
		annotations[sharedSecretsRVAnnotation] = sharedSecretsResourceVersion
	}
	return annotations
}

// preStopLifecycle sends SIGUSR1 to the kura process so it begins
// draining, then sleeps so endpoint propagation removes the pod from
// the Service before SIGTERM lands. Mirrors the in-tree Helm chart
// behaviour at kura/ops/helm/kura/templates/statefulset.yaml.
func preStopLifecycle() *corev1.Lifecycle {
	return &corev1.Lifecycle{
		PreStop: &corev1.LifecycleHandler{
			Exec: &corev1.ExecAction{
				Command: []string{
					"/bin/sh",
					"-c",
					"KURA_PID=\"$(tr ' ' '\\n' </proc/1/task/1/children | head -n1)\" && " +
						"if [ -n \"$KURA_PID\" ]; then kill -USR1 \"$KURA_PID\"; fi && " +
						"sleep " + strconv.FormatInt(preStopDelaySeconds, 10),
				},
			},
		},
	}
}

// sharedSecretsEnvFrom mounts the kura-shared-secrets Secret if it
// exists. The Tuist control plane and operator drop credentials such as
// KURA_EXTENSION_JWT_VERIFIER_TUIST_SECRET into this Secret so they
// stay out of the KuraInstance spec (which is readable by anyone with
// list/watch on the CR).
func sharedSecretsEnvFrom() []corev1.EnvFromSource {
	return []corev1.EnvFromSource{{
		SecretRef: &corev1.SecretEnvSource{
			LocalObjectReference: corev1.LocalObjectReference{Name: sharedSecretsName},
			Optional:             ptr(true),
		},
	}}
}

// The memory request matches the limit because Kura sizes its memory
// budget from the cgroup limit (soft limit 70%, hard limit 85% of it)
// and routinely operates above 1Gi, so the full 2Gi must be reserved
// at scheduling time to avoid node overcommit.
func defaultResources() corev1.ResourceRequirements {
	return corev1.ResourceRequirements{
		Requests: corev1.ResourceList{
			corev1.ResourceCPU:    resource.MustParse("500m"),
			corev1.ResourceMemory: resource.MustParse("2Gi"),
		},
		Limits: corev1.ResourceList{
			corev1.ResourceMemory: resource.MustParse("2Gi"),
		},
	}
}

func publicIngressAnnotations() map[string]string {
	return streamingIngressAnnotations("HTTP")
}

func grpcIngressAnnotations() map[string]string {
	return streamingIngressAnnotations("GRPC")
}

func streamingIngressAnnotations(backendProtocol string) map[string]string {
	return map[string]string{
		"nginx.ingress.kubernetes.io/backend-protocol":        backendProtocol,
		"nginx.ingress.kubernetes.io/proxy-body-size":         "0",
		"nginx.ingress.kubernetes.io/proxy-buffering":         "off",
		"nginx.ingress.kubernetes.io/proxy-request-buffering": "off",
		"nginx.ingress.kubernetes.io/proxy-read-timeout":      "3600",
		"nginx.ingress.kubernetes.io/proxy-send-timeout":      "3600",
	}
}

// reconcileNetworkPolicy keeps inter-tenant traffic off the Kura pods on
// the shared kura node pool. Selector traffic is allowed only between
// pods of the same KuraInstance, from same-account Kura peers, and from
// in-cluster Services such as the regional Kura ingress. Egress is left
// default-allow because the runtime needs to reach the Tuist API for
// license/JWT validation and the OTLP collector.
func (r *KuraInstanceReconciler) reconcileNetworkPolicy(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	policy := &networkingv1.NetworkPolicy{ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, policy, func() error {
		if err := controllerutil.SetControllerReference(instance, policy, r.Scheme); err != nil {
			return err
		}
		policy.Labels = labels(instance)
		policy.Spec.PodSelector = metav1.LabelSelector{MatchLabels: selectorLabels(instance)}
		policy.Spec.PolicyTypes = []networkingv1.PolicyType{networkingv1.PolicyTypeIngress}
		ingress := []networkingv1.NetworkPolicyIngressRule{
			{
				// Ingress from this instance's own pods (peer
				// replication, headless DNS bootstrap).
				From: []networkingv1.NetworkPolicyPeer{
					{PodSelector: &metav1.LabelSelector{MatchLabels: selectorLabels(instance)}},
				},
			},
			{
				// Same-account Kura peers in other regions share
				// artifacts through the internal mTLS peer port.
				From: []networkingv1.NetworkPolicyPeer{
					{PodSelector: &metav1.LabelSelector{MatchLabels: accountPeerSelectorLabels(instance)}},
				},
				Ports: []networkingv1.NetworkPolicyPort{
					{Port: ptr(intstr.FromString("peer")), Protocol: ptr(corev1.ProtocolTCP)},
				},
			},
			{
				// Tuist server pod-list calls and internal health
				// checks. Limit plain HTTP and plaintext gRPC to
				// in-cluster peers; the JWT layer in the runtime is
				// the auth boundary.
				From: []networkingv1.NetworkPolicyPeer{
					{NamespaceSelector: &metav1.LabelSelector{}},
				},
				Ports: []networkingv1.NetworkPolicyPort{
					{Port: ptr(intstr.FromString("http")), Protocol: ptr(corev1.ProtocolTCP)},
					{Port: ptr(intstr.FromString("grpc")), Protocol: ptr(corev1.ProtocolTCP)},
				},
			},
		}
		if len(instance.Spec.ClientCIDRs) > 0 {
			// NodePort clients keep their original source address
			// (externalTrafficPolicy: Local), which no
			// namespaceSelector can match.
			peers := make([]networkingv1.NetworkPolicyPeer, 0, len(instance.Spec.ClientCIDRs))
			for _, cidr := range instance.Spec.ClientCIDRs {
				peers = append(peers, networkingv1.NetworkPolicyPeer{IPBlock: &networkingv1.IPBlock{CIDR: cidr}})
			}
			ingress = append(ingress, networkingv1.NetworkPolicyIngressRule{
				From: peers,
				Ports: []networkingv1.NetworkPolicyPort{
					{Port: ptr(intstr.FromString("http")), Protocol: ptr(corev1.ProtocolTCP)},
					{Port: ptr(intstr.FromString("grpc")), Protocol: ptr(corev1.ProtocolTCP)},
				},
			})
		}
		policy.Spec.Ingress = ingress
		return nil
	})
	return err
}

func defaultNodeSelector() map[string]string {
	return map[string]string{"node.cluster.x-k8s.io/pool": "kura"}
}

func nodeSelector(instance *kurav1alpha1.KuraInstance) map[string]string {
	if len(instance.Spec.NodeSelector) == 0 {
		return defaultNodeSelector()
	}
	selector := make(map[string]string, len(instance.Spec.NodeSelector))
	for key, value := range instance.Spec.NodeSelector {
		selector[key] = value
	}
	return selector
}

func topologySpreadConstraints(instance *kurav1alpha1.KuraInstance) []corev1.TopologySpreadConstraint {
	return []corev1.TopologySpreadConstraint{{
		MaxSkew:           1,
		TopologyKey:       "kubernetes.io/hostname",
		WhenUnsatisfiable: corev1.DoNotSchedule,
		LabelSelector:     &metav1.LabelSelector{MatchLabels: selectorLabels(instance)},
	}}
}

// baseEnv carries only the values the controller must set: identity,
// per-pod paths, peer wiring, and the drain timeout that has to stay in
// sync with the pod's terminationGracePeriodSeconds. Resource-shaped
// knobs (FD pool, memory soft/hard limits, manifest cache, RocksDB)
// are derived from the pod's cgroup and rlimit at runtime startup, so
// the controller deliberately doesn't override them. See
// kura/src/config.rs::DerivedRuntimeDefaults.
func baseEnv(instance *kurav1alpha1.KuraInstance, otlpTracesEndpoint string, environment string) []corev1.EnvVar {
	if environment == "" {
		environment = "production"
	}
	env := []corev1.EnvVar{
		{Name: "POD_NAME", ValueFrom: &corev1.EnvVarSource{FieldRef: &corev1.ObjectFieldSelector{FieldPath: "metadata.name"}}},
		{Name: "POD_NAMESPACE", ValueFrom: &corev1.EnvVarSource{FieldRef: &corev1.ObjectFieldSelector{FieldPath: "metadata.namespace"}}},
		{Name: "KURA_PORT", Value: fmt.Sprintf("%d", httpPort)},
		{Name: "KURA_GRPC_PORT", Value: fmt.Sprintf("%d", grpcPort)},
		{Name: "KURA_TENANT_ID", Value: instance.Spec.TenantID},
		{Name: "KURA_REGION", Value: instance.Spec.Region},
		{Name: "KURA_TMP_DIR", Value: "/var/cache/kura/tmp"},
		{Name: "KURA_DATA_DIR", Value: "/var/cache/kura"},
		{Name: "KURA_NODE_URL", Value: fmt.Sprintf("https://$(POD_NAME).%s.$(POD_NAMESPACE).svc.cluster.local:%d", headlessServiceName(instance), peerPort)},
		{Name: "KURA_DISCOVERY_DNS_NAME", Value: fmt.Sprintf("%s.$(POD_NAMESPACE).svc.cluster.local", headlessServiceName(instance))},
		{Name: "KURA_INTERNAL_PORT", Value: fmt.Sprintf("%d", peerPort)},
		{Name: "KURA_INTERNAL_TLS_CA_CERT_PATH", Value: peerTLSMountPath + "/" + peerTLSCAFile},
		{Name: "KURA_INTERNAL_TLS_CERT_PATH", Value: peerTLSMountPath + "/" + peerTLSCertFile},
		{Name: "KURA_INTERNAL_TLS_KEY_PATH", Value: peerTLSMountPath + "/" + peerTLSKeyFile},
		{Name: "KURA_DRAIN_COMPLETION_TIMEOUT_MS", Value: strconv.FormatInt(drainCompletionTimeoutMs, 10)},
		{Name: "KURA_OTEL_SERVICE_NAME", Value: "$(POD_NAME)"},
	}
	if !hasEnvVar(instance.Spec.ExtraEnv, environmentEnvVar) {
		env = append(env, corev1.EnvVar{Name: environmentEnvVar, Value: environment})
	}
	if otlpTracesEndpoint != "" && !hasEnvVar(instance.Spec.ExtraEnv, otlpTracesEndpointEnvVar) {
		env = append(env, corev1.EnvVar{Name: otlpTracesEndpointEnvVar, Value: otlpTracesEndpoint})
	}
	if instance.Spec.ExtensionScript != "" {
		env = append(env,
			corev1.EnvVar{Name: "KURA_EXTENSION_ENABLED", Value: "true"},
			corev1.EnvVar{Name: "KURA_EXTENSION_SCRIPT_PATH", Value: "/etc/kura/extensions/hooks.lua"},
		)
	}
	if crossRegionRuntimeEnabled(instance) {
		env = append(env, corev1.EnvVar{Name: "KURA_GLOBAL_DISCOVERY_DNS_NAME", Value: accountPeerServiceDNSName(instance)})
	}
	return env
}

func hasEnvVar(env []corev1.EnvVar, name string) bool {
	for _, envVar := range env {
		if envVar.Name == name {
			return true
		}
	}
	return false
}

// containerPorts exposes only the plain HTTP, gRPC, and internal mTLS
// peer ports. Customer-facing TLS terminates at the regional Kura ingress, not
// inside each Kura runtime pod.
func containerPorts(instance *kurav1alpha1.KuraInstance) []corev1.ContainerPort {
	return []corev1.ContainerPort{
		{Name: "http", ContainerPort: httpPort},
		{Name: "grpc", ContainerPort: grpcPort},
		{Name: "peer", ContainerPort: peerPort},
	}
}

func volumeMounts(instance *kurav1alpha1.KuraInstance) []corev1.VolumeMount {
	mounts := []corev1.VolumeMount{
		{Name: "data", MountPath: "/var/cache/kura"},
		{Name: peerTLSVolumeName, MountPath: peerTLSMountPath, ReadOnly: true},
	}
	if instance.Spec.ExtensionScript != "" {
		mounts = append(mounts, corev1.VolumeMount{Name: "extension-script", MountPath: "/etc/kura/extensions", ReadOnly: true})
	}
	return mounts
}

func volumes(instance *kurav1alpha1.KuraInstance) []corev1.Volume {
	volumes := []corev1.Volume{{
		Name: peerTLSVolumeName,
		VolumeSource: corev1.VolumeSource{Secret: &corev1.SecretVolumeSource{
			SecretName: peerTLSSecretName(instance),
		}},
	}}
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
	storage := storageQuantity(instance)
	pvc := corev1.PersistentVolumeClaim{
		ObjectMeta: metav1.ObjectMeta{Name: "data", Labels: labels(instance)},
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

func storageQuantity(instance *kurav1alpha1.KuraInstance) resource.Quantity {
	if instance.Spec.StorageSize != "" {
		if storage, err := resource.ParseQuantity(instance.Spec.StorageSize); err == nil {
			return storage
		}
	}
	return resource.MustParse("200Gi")
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

// externalPorts deliberately omits peer: replication stays mTLS-only
// between cluster pods, never exposed at the node boundary.
func externalPorts() []corev1.ServicePort {
	return []corev1.ServicePort{
		{Name: "http", Port: httpPort, TargetPort: intstr.FromString("http")},
		{Name: "grpc", Port: grpcPort, TargetPort: intstr.FromString("grpc")},
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

func grpcPublicURL(instance *kurav1alpha1.KuraInstance) string {
	if instance.Spec.GRPCPublicHost == "" {
		return ""
	}
	return "grpcs://" + instance.Spec.GRPCPublicHost
}

func labels(instance *kurav1alpha1.KuraInstance) map[string]string {
	labels := selectorLabels(instance)
	labels["app.kubernetes.io/managed-by"] = "kura-controller"
	labels["tuist.dev/account"] = instance.Spec.AccountHandle
	labels["tuist.dev/region"] = instance.Spec.Region
	return labels
}

func accountPeerSelectorLabels(instance *kurav1alpha1.KuraInstance) map[string]string {
	return map[string]string{
		"app.kubernetes.io/name": "kura",
		"tuist.dev/account":      instance.Spec.AccountHandle,
	}
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

func accountPeerServiceDNSName(instance *kurav1alpha1.KuraInstance) string {
	return fmt.Sprintf("%s.%s.svc.cluster.local", accountPeerServiceName(instance), instance.Namespace)
}

func accountPeerServiceName(instance *kurav1alpha1.KuraInstance) string {
	name := "kura-" + instance.Spec.AccountHandle + "-peers"
	if len(name) <= 63 {
		return name
	}

	hash := fnv.New32a()
	_, _ = hash.Write([]byte(instance.Spec.AccountHandle))
	suffix := fmt.Sprintf("-%x", hash.Sum32())
	return strings.TrimRight(name[:63-len(suffix)], "-") + suffix
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
		Watches(
			&corev1.Secret{},
			handler.EnqueueRequestsFromMapFunc(r.kuraInstancesForSharedSecret),
			builder.WithPredicates(predicate.NewPredicateFuncs(func(object client.Object) bool {
				return object.GetName() == sharedSecretsName
			})),
		).
		Watches(
			&corev1.Pod{},
			handler.EnqueueRequestsFromMapFunc(r.kuraInstanceForPod),
			builder.WithPredicates(predicate.And(kuraPodPredicate(), podRoutabilityChangedPredicate())),
		).
		Owns(&appsv1.StatefulSet{}).
		Owns(&corev1.Service{}).
		Owns(&corev1.ConfigMap{}).
		Owns(&corev1.Secret{}).
		Owns(&networkingv1.Ingress{}).
		Owns(&networkingv1.NetworkPolicy{}).
		Owns(&policyv1.PodDisruptionBudget{}).
		Complete(r)
}

// kuraInstanceForPod maps a Kura pod back to its owning KuraInstance so a
// pod readiness change re-runs primary selection and fails the public
// Services over to a healthy pod.
func (r *KuraInstanceReconciler) kuraInstanceForPod(_ context.Context, object client.Object) []reconcile.Request {
	labels := object.GetLabels()
	instanceName := labels["app.kubernetes.io/instance"]
	if labels["app.kubernetes.io/name"] != "kura" || instanceName == "" {
		return nil
	}
	return []reconcile.Request{{
		NamespacedName: types.NamespacedName{Name: instanceName, Namespace: object.GetNamespace()},
	}}
}

func kuraPodPredicate() predicate.Predicate {
	return predicate.NewPredicateFuncs(func(object client.Object) bool {
		return object.GetLabels()["app.kubernetes.io/name"] == "kura"
	})
}

// podRoutabilityChangedPredicate keeps the controller from re-running on
// every pod heartbeat: it only enqueues when a pod appears, disappears,
// or crosses the Ready/terminating boundary that primary selection cares
// about.
func podRoutabilityChangedPredicate() predicate.Predicate {
	return predicate.Funcs{
		CreateFunc:  func(event.CreateEvent) bool { return true },
		DeleteFunc:  func(event.DeleteEvent) bool { return true },
		GenericFunc: func(event.GenericEvent) bool { return false },
		UpdateFunc: func(e event.UpdateEvent) bool {
			oldPod, ok := e.ObjectOld.(*corev1.Pod)
			newPod, okNew := e.ObjectNew.(*corev1.Pod)
			if !ok || !okNew {
				return false
			}
			return podReady(oldPod) != podReady(newPod)
		},
	}
}

func (r *KuraInstanceReconciler) kuraInstancesForSharedSecret(ctx context.Context, object client.Object) []reconcile.Request {
	instances := &kurav1alpha1.KuraInstanceList{}
	if err := r.List(ctx, instances, client.InNamespace(object.GetNamespace())); err != nil {
		log.FromContext(ctx).Error(err, "list Kura instances for shared secret update", "namespace", object.GetNamespace())
		return nil
	}

	requests := make([]reconcile.Request, 0, len(instances.Items))
	for _, instance := range instances.Items {
		requests = append(requests, reconcile.Request{
			NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace},
		})
	}
	return requests
}
