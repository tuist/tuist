package controllers

import (
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/pem"
	"fmt"
	"math/big"
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

	httpPort        int32 = 4000
	httpsPort       int32 = 443
	httpsTargetPort int32 = 4443
	grpcPort        int32 = 50051
	peerPort        int32 = 7443

	// drainCompletionTimeoutMs and preStopDelaySeconds together set how
	// long a Kura pod is given to bleed connections off before SIGTERM.
	// preStop sends SIGUSR1 to start the runtime drain and then sleeps
	// for preStopDelaySeconds so endpoint propagation removes the pod
	// from the Service before it stops accepting new work.
	drainCompletionTimeoutMs int64 = 240_000
	preStopDelaySeconds      int64 = 20
	terminationGraceExtra    int64 = 15

	// podNameLabel is the per-pod label the StatefulSet controller stamps
	// on every pod (<statefulset>-<ordinal>). The public Services select a
	// single pod through it so steady-state cache traffic for a region
	// lands on one node, giving read-after-write consistency without
	// fanning the read path across the eventually-consistent mesh.
	podNameLabel = "statefulset.kubernetes.io/pod-name"

	sharedSecretsName         = "kura-shared-secrets"
	otlpTracesEndpointEnvVar  = "KURA_OTEL_EXPORTER_OTLP_TRACES_ENDPOINT"
	environmentEnvVar         = "KURA_OTEL_DEPLOYMENT_ENVIRONMENT"
	sharedSecretsRVAnnotation = "kura.tuist.dev/shared-secrets-resource-version"

	grpcTLSVolumeName = "grpc-tls"
	grpcTLSMountPath  = "/etc/kura/grpc-tls"
	grpcTLSCertFile   = "tls.crt"
	grpcTLSKeyFile    = "tls.key"

	publicTLSVolumeName = "public-tls"
	publicTLSMountPath  = "/etc/kura/public-tls"
	publicTLSCertFile   = "tls.crt"
	publicTLSKeyFile    = "tls.key"

	peerTLSVolumeName = "peer-tls"
	peerTLSMountPath  = "/etc/kura/peer-tls"
	peerTLSCAFile     = "ca.pem"
	peerTLSCertFile   = "tls.crt"
	peerTLSKeyFile    = "tls.key"
)

type KuraInstanceReconciler struct {
	client.Client
	Scheme *runtime.Scheme

	// GRPCClusterIssuer, when non-empty, makes the controller request
	// cert-manager Certificates per instance with this ClusterIssuer for
	// both the public HTTPS host and the gRPC host. The issued Secrets
	// are mounted into the Kura pod so the runtime can terminate TLS
	// for both the public HTTPS LoadBalancer and the gRPC LoadBalancer.
	// The name is historical; the controller uses the same issuer for
	// every cert it asks cert-manager to mint.
	GRPCClusterIssuer  string
	OTLPTracesEndpoint string
	Environment        string
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
	return instance.Name + "-peer-tls"
}

func grpcServiceName(instance *kurav1alpha1.KuraInstance) string {
	return instance.Name + "-grpc"
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
	if err := r.reconcilePublicCertificate(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcileGRPCCertificate(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.reconcilePeerTLSSecret(ctx, instance); err != nil {
		return ctrl.Result{}, err
	}
	if err := r.deleteLegacyIngress(ctx, instance); err != nil {
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
	now := metav1.NewTime(time.Now().UTC())
	instance.Status.Phase = rollout.phase
	instance.Status.PublicURL = publicURL(instance)
	instance.Status.GRPCPublicURL = grpcPublicURL(instance)
	instance.Status.ObservedImage = rollout.observedImage
	instance.Status.ReadyReplicas = rollout.readyReplicas
	instance.Status.Message = rollout.message
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

func (r *KuraInstanceReconciler) reconcileService(ctx context.Context, instance *kurav1alpha1.KuraInstance, primaryPod string) error {
	service := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, service, func() error {
		if err := controllerutil.SetControllerReference(instance, service, r.Scheme); err != nil {
			return err
		}
		service.Labels = labels(instance)
		service.Spec.Selector = primaryServiceSelector(instance, primaryPod)
		service.Annotations = publicServiceAnnotations(instance)

		if instance.Spec.PublicHost == "" {
			service.Spec.Type = corev1.ServiceTypeClusterIP
			service.Spec.ExternalTrafficPolicy = ""
			service.Spec.Ports = []corev1.ServicePort{
				{Name: "http", Port: httpPort, TargetPort: intstr.FromString("http")},
				{Name: "grpc", Port: grpcPort, TargetPort: intstr.FromString("grpc")},
			}
			return nil
		}

		service.Spec.Type = corev1.ServiceTypeLoadBalancer
		service.Spec.ExternalTrafficPolicy = corev1.ServiceExternalTrafficPolicyLocal
		service.Spec.Ports = []corev1.ServicePort{
			{Name: "https", Port: httpsPort, TargetPort: intstr.FromString("https"), Protocol: corev1.ProtocolTCP},
		}
		return nil
	})
	return err
}

// reconcileGRPCService exposes the runtime's gRPC port via a separate
// Hetzner Cloud LoadBalancer in tcp-passthrough mode. Hetzner managed
// certificates only work with the http/https LB protocol (HTTP/1.1
// downstream), so gRPC is incompatible with them — Kura terminates TLS
// itself using the cert-manager Certificate produced by
// reconcileGRPCCertificate.
func (r *KuraInstanceReconciler) reconcileGRPCService(ctx context.Context, instance *kurav1alpha1.KuraInstance, primaryPod string) error {
	service := &corev1.Service{ObjectMeta: metav1.ObjectMeta{Name: grpcServiceName(instance), Namespace: instance.Namespace}}

	if instance.Spec.GRPCPublicHost == "" {
		if err := r.Delete(ctx, service); err != nil && !apierrors.IsNotFound(err) {
			return err
		}
		return nil
	}

	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, service, func() error {
		if err := controllerutil.SetControllerReference(instance, service, r.Scheme); err != nil {
			return err
		}
		service.Labels = labels(instance)
		service.Annotations = grpcServiceAnnotations(instance)
		service.Spec.Type = corev1.ServiceTypeLoadBalancer
		service.Spec.ExternalTrafficPolicy = corev1.ServiceExternalTrafficPolicyLocal
		service.Spec.Selector = primaryServiceSelector(instance, primaryPod)
		service.Spec.Ports = []corev1.ServicePort{
			{Name: "grpcs", Port: httpsPort, TargetPort: intstr.FromString("grpc"), Protocol: corev1.ProtocolTCP},
		}
		return nil
	})
	return err
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
	return choosePrimaryPod(current, instance.Name, pods.Items), nil
}

// choosePrimaryPod picks the pod the public Services route to. It is
// sticky: the current primary is kept while it stays Ready so a recovered
// lower-ordinal pod does not steal traffic back, because every handoff
// costs a brief read-after-write inconsistency window during async
// replication catch-up and we want to minimise them. Otherwise it falls
// to the lowest-ordinal Ready pod, and before any pod is Ready it
// defaults to ordinal 0 so the Service has a stable selector.
func choosePrimaryPod(current, instanceName string, pods []corev1.Pod) string {
	ready := map[string]bool{}
	for i := range pods {
		if podReady(&pods[i]) {
			ready[pods[i].Name] = true
		}
	}

	if current != "" && ready[current] {
		return current
	}

	best := ""
	bestOrdinal := -1
	for name := range ready {
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

// reconcilePublicCertificate provisions a cert-manager Certificate so
// the runtime can terminate TLS for the public HTTPS LoadBalancer. The
// LB is configured as TCP-passthrough; TLS termination happens in the
// Kura pod from a cert-manager-issued Secret. No-ops when either
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

// reconcileGRPCCertificate provisions a cert-manager Certificate so the
// runtime can terminate TLS for the gRPC LoadBalancer. No-ops when
// either GRPCClusterIssuer or spec.grpcPublicHost is unset. cert-manager
// must be installed in the cluster before --grpc-cluster-issuer is set.
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
	secret := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: peerTLSSecretName(instance), Namespace: instance.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, secret, func() error {
		if err := controllerutil.SetControllerReference(instance, secret, r.Scheme); err != nil {
			return err
		}
		secret.Labels = labels(instance)
		secret.Type = corev1.SecretTypeOpaque
		if peerTLSSecretDataValid(secret.Data, instance) {
			return nil
		}
		data, err := generatePeerTLSSecretData(instance)
		if err != nil {
			return err
		}
		secret.Data = data
		return nil
	})
	return err
}

func peerTLSSecretDataValid(data map[string][]byte, instance *kurav1alpha1.KuraInstance) bool {
	if len(data[peerTLSCAFile]) == 0 || len(data[peerTLSCertFile]) == 0 || len(data[peerTLSKeyFile]) == 0 {
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
	_, err = cert.Verify(x509.VerifyOptions{
		DNSName:   firstPodDNSName(instance),
		Roots:     roots,
		KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
	})
	return err == nil && hasExtKeyUsage(cert, x509.ExtKeyUsageClientAuth)
}

func generatePeerTLSSecretData(instance *kurav1alpha1.KuraInstance) (map[string][]byte, error) {
	caKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("generate peer CA key: %w", err)
	}
	leafKey, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil {
		return nil, fmt.Errorf("generate peer certificate key: %w", err)
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

	leafTemplate := &x509.Certificate{
		SerialNumber: randomSerialNumber(),
		Subject:      pkix.Name{CommonName: instance.Name + " peer"},
		DNSNames:     peerTLSDNSNames(instance),
		NotBefore:    now.Add(-time.Hour),
		NotAfter:     now.AddDate(2, 0, 0),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth},
	}
	leafDER, err := x509.CreateCertificate(rand.Reader, leafTemplate, caTemplate, &leafKey.PublicKey, caKey)
	if err != nil {
		return nil, fmt.Errorf("generate peer certificate: %w", err)
	}

	leafPKCS8, err := x509.MarshalPKCS8PrivateKey(leafKey)
	if err != nil {
		return nil, fmt.Errorf("marshal peer private key: %w", err)
	}

	return map[string][]byte{
		peerTLSCAFile:   pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: caDER}),
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
	namespace := instance.Namespace
	return []string{
		fmt.Sprintf("*.%s.%s.svc.cluster.local", headless, namespace),
		fmt.Sprintf("*.%s.%s.svc", headless, namespace),
		fmt.Sprintf("*.%s.%s", headless, namespace),
		headless,
		fmt.Sprintf("%s.%s", headless, namespace),
		fmt.Sprintf("%s.%s.svc", headless, namespace),
		fmt.Sprintf("%s.%s.svc.cluster.local", headless, namespace),
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

func (r *KuraInstanceReconciler) deleteLegacyIngress(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	ingress := &networkingv1.Ingress{ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace}}
	if err := r.Delete(ctx, ingress); err != nil && !apierrors.IsNotFound(err) {
		return err
	}
	return nil
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
		if err := controllerutil.SetControllerReference(instance, sts, r.Scheme); err != nil {
			return err
		}
		sts.Labels = labels(instance)
		sts.Spec.ServiceName = headlessServiceName(instance)
		sts.Spec.Replicas = ptr(replicas(instance))
		sts.Spec.PodManagementPolicy = appsv1.ParallelPodManagement
		sts.Spec.Selector = &metav1.LabelSelector{MatchLabels: selectorLabels(instance)}
		sts.Spec.Template = podTemplate(instance, r.OTLPTracesEndpoint, r.Environment, sharedSecretsResourceVersion)
		sts.Spec.VolumeClaimTemplates = []corev1.PersistentVolumeClaim{dataVolumeClaim(instance)}
		// Drop the PVC when the StatefulSet itself is deleted (server
		// destroy), but keep it around when scaling down so a replica
		// can rejoin with its existing cache.
		sts.Spec.PersistentVolumeClaimRetentionPolicy = &appsv1.StatefulSetPersistentVolumeClaimRetentionPolicy{
			WhenDeleted: appsv1.DeletePersistentVolumeClaimRetentionPolicyType,
			WhenScaled:  appsv1.RetainPersistentVolumeClaimRetentionPolicyType,
		}
		return nil
	})
	return err
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
			Annotations: podAnnotations(sharedSecretsResourceVersion),
		},
		Spec: corev1.PodSpec{
			TerminationGracePeriodSeconds: ptr(terminationGracePeriodSeconds()),
			NodeSelector:                  nodeSelector(instance),
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
func podAnnotations(sharedSecretsResourceVersion string) map[string]string {
	annotations := map[string]string{
		"prometheus.io/scrape":    "true",
		"prometheus.io/port-name": "http",
		"prometheus.io/path":      "/metrics",
	}
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

// publicServiceAnnotations returns the Hetzner Cloud LoadBalancer
// annotations for the public Service. The LB runs in tcp-passthrough
// mode and TLS is terminated inside the Kura pod from a cert-manager-
// issued Secret. Health checks use TCP against the Service NodePort
// because Hetzner targets nodes, not pods; HTTP health checks would
// speak cleartext to the TLS passthrough port.
func publicServiceAnnotations(instance *kurav1alpha1.KuraInstance) map[string]string {
	if instance.Spec.PublicHost == "" {
		return nil
	}

	return map[string]string{
		"external-dns.alpha.kubernetes.io/hostname":         instance.Spec.PublicHost,
		"load-balancer.hetzner.cloud/name":                  instance.Name,
		"load-balancer.hetzner.cloud/protocol":              "tcp",
		"load-balancer.hetzner.cloud/algorithm-type":        "least_connections",
		"load-balancer.hetzner.cloud/node-selector":         "node.cluster.x-k8s.io/pool=kura",
		"load-balancer.hetzner.cloud/health-check-protocol": "tcp",
	}
}

func grpcServiceAnnotations(instance *kurav1alpha1.KuraInstance) map[string]string {
	if instance.Spec.GRPCPublicHost == "" {
		return nil
	}

	return map[string]string{
		"external-dns.alpha.kubernetes.io/hostname":         instance.Spec.GRPCPublicHost,
		"load-balancer.hetzner.cloud/name":                  grpcServiceName(instance),
		"load-balancer.hetzner.cloud/protocol":              "tcp",
		"load-balancer.hetzner.cloud/algorithm-type":        "least_connections",
		"load-balancer.hetzner.cloud/node-selector":         "node.cluster.x-k8s.io/pool=kura",
		"load-balancer.hetzner.cloud/health-check-protocol": "tcp",
	}
}

// reconcileNetworkPolicy keeps inter-tenant traffic off the Kura pods on
// the shared kura node pool. Selector traffic is allowed only between
// pods of the same KuraInstance (peer replication, internal status) and
// from Services in the same namespace (ingress LoadBalancer health
// probes). Egress is left default-allow because the runtime needs to
// reach the Tuist API for license/JWT validation and the OTLP collector.
func (r *KuraInstanceReconciler) reconcileNetworkPolicy(ctx context.Context, instance *kurav1alpha1.KuraInstance) error {
	policy := &networkingv1.NetworkPolicy{ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace}}
	_, err := controllerutil.CreateOrUpdate(ctx, r.Client, policy, func() error {
		if err := controllerutil.SetControllerReference(instance, policy, r.Scheme); err != nil {
			return err
		}
		policy.Labels = labels(instance)
		policy.Spec.PodSelector = metav1.LabelSelector{MatchLabels: selectorLabels(instance)}
		policy.Spec.PolicyTypes = []networkingv1.PolicyType{networkingv1.PolicyTypeIngress}
		policy.Spec.Ingress = []networkingv1.NetworkPolicyIngressRule{
			{
				// Ingress from this instance's own pods (peer
				// replication, headless DNS bootstrap).
				From: []networkingv1.NetworkPolicyPeer{
					{PodSelector: &metav1.LabelSelector{MatchLabels: selectorLabels(instance)}},
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
			{
				// Public LoadBalancer traffic. With externalTrafficPolicy=Local
				// the original client/LB source IP is preserved, so these ports
				// need an explicit all-sources rule.
				Ports: []networkingv1.NetworkPolicyPort{
					{Port: ptr(intstr.FromString("https")), Protocol: ptr(corev1.ProtocolTCP)},
					{Port: ptr(intstr.FromString("grpc")), Protocol: ptr(corev1.ProtocolTCP)},
				},
			},
		}
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
		{Name: "KURA_TMP_DIR", Value: "/tmp/kura"},
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
	if instance.Spec.GRPCPublicHost != "" {
		env = append(env,
			corev1.EnvVar{Name: "KURA_GRPC_TLS_CERT_PATH", Value: grpcTLSMountPath + "/" + grpcTLSCertFile},
			corev1.EnvVar{Name: "KURA_GRPC_TLS_KEY_PATH", Value: grpcTLSMountPath + "/" + grpcTLSKeyFile},
		)
	}
	if instance.Spec.PublicHost != "" {
		env = append(env,
			corev1.EnvVar{Name: "KURA_HTTPS_PORT", Value: fmt.Sprintf("%d", httpsTargetPort)},
			corev1.EnvVar{Name: "KURA_PUBLIC_TLS_CERT_PATH", Value: publicTLSMountPath + "/" + publicTLSCertFile},
			corev1.EnvVar{Name: "KURA_PUBLIC_TLS_KEY_PATH", Value: publicTLSMountPath + "/" + publicTLSKeyFile},
		)
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

// containerPorts always exposes the plain HTTP, gRPC, and peer ports;
// it additionally exposes the TLS-terminating HTTPS port whenever the
// instance has a public host, so the Hetzner LoadBalancer in tcp-
// passthrough mode can target it.
func containerPorts(instance *kurav1alpha1.KuraInstance) []corev1.ContainerPort {
	ports := []corev1.ContainerPort{
		{Name: "http", ContainerPort: httpPort},
		{Name: "grpc", ContainerPort: grpcPort},
		{Name: "peer", ContainerPort: peerPort},
	}
	if instance.Spec.PublicHost != "" {
		ports = append(ports, corev1.ContainerPort{Name: "https", ContainerPort: httpsTargetPort})
	}
	return ports
}

func volumeMounts(instance *kurav1alpha1.KuraInstance) []corev1.VolumeMount {
	mounts := []corev1.VolumeMount{
		{Name: "tmp", MountPath: "/tmp/kura"},
		{Name: "data", MountPath: "/var/cache/kura"},
		{Name: peerTLSVolumeName, MountPath: peerTLSMountPath, ReadOnly: true},
	}
	if instance.Spec.ExtensionScript != "" {
		mounts = append(mounts, corev1.VolumeMount{Name: "extension-script", MountPath: "/etc/kura/extensions", ReadOnly: true})
	}
	if instance.Spec.GRPCPublicHost != "" {
		mounts = append(mounts, corev1.VolumeMount{Name: grpcTLSVolumeName, MountPath: grpcTLSMountPath, ReadOnly: true})
	}
	if instance.Spec.PublicHost != "" {
		mounts = append(mounts, corev1.VolumeMount{Name: publicTLSVolumeName, MountPath: publicTLSMountPath, ReadOnly: true})
	}
	return mounts
}

func volumes(instance *kurav1alpha1.KuraInstance) []corev1.Volume {
	tmpSize := resource.MustParse("4Gi")
	volumes := []corev1.Volume{{
		Name: "tmp",
		VolumeSource: corev1.VolumeSource{
			EmptyDir: &corev1.EmptyDirVolumeSource{SizeLimit: &tmpSize},
		},
	}, {
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
	if instance.Spec.GRPCPublicHost != "" {
		volumes = append(volumes, corev1.Volume{
			Name: grpcTLSVolumeName,
			VolumeSource: corev1.VolumeSource{Secret: &corev1.SecretVolumeSource{
				SecretName: grpcTLSSecretName(instance),
				Optional:   ptr(true),
			}},
		})
	}
	if instance.Spec.PublicHost != "" {
		volumes = append(volumes, corev1.Volume{
			Name: publicTLSVolumeName,
			VolumeSource: corev1.VolumeSource{Secret: &corev1.SecretVolumeSource{
				SecretName: publicTLSSecretName(instance),
				Optional:   ptr(true),
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
