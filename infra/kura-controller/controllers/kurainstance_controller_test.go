package controllers

import (
	"bytes"
	"context"
	"crypto/x509"
	"encoding/pem"
	"fmt"
	"testing"
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
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

func TestKuraInstanceReconcileCreatesWorkloadResources(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-1", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle:    "tuist",
			TenantID:         "tuist",
			Region:           "eu",
			Image:            "ghcr.io/tuist/kura:0.5.2",
			PublicHost:       "tuist-eu-1.kura.tuist.dev",
			IngressClassName: "kura-eu-central",
			StorageClassName: "hcloud-volumes",
			ExtensionScript:  "return true",
		},
	}
	legacyIngress := &networkingv1.Ingress{ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace}}
	sharedSecret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: sharedSecretsName, Namespace: instance.Namespace, ResourceVersion: "12345"},
	}

	reconciler := &KuraInstanceReconciler{
		Client:             fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, legacyIngress, sharedSecret).WithStatusSubresource(instance).Build(),
		Scheme:             scheme,
		GRPCClusterIssuer:  "letsencrypt-prod",
		OTLPTracesEndpoint: "http://k8s-monitoring-alloy-receiver.observability.svc.cluster.local:4318/v1/traces",
		Environment:        "canary",
	}

	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}); err != nil {
		t.Fatal(err)
	}

	service := &corev1.Service{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, service); err != nil {
		t.Fatal(err)
	}
	if service.Spec.Type != corev1.ServiceTypeClusterIP {
		t.Fatalf("expected public service to be a ClusterIP backend for regional Kura ingress, got %q", service.Spec.Type)
	}
	if service.Spec.ExternalTrafficPolicy != "" {
		t.Fatalf("expected no external traffic policy on ClusterIP backend, got %q", service.Spec.ExternalTrafficPolicy)
	}
	if got := len(service.Spec.Ports); got != 3 {
		t.Fatalf("expected backend service to expose http, grpc, and peer ports, got %d", got)
	}
	if got := service.Spec.Ports[0].TargetPort.StrVal; got != "http" {
		t.Fatalf("expected public ingress backend service to target the plain http port, got %q", got)
	}
	if got := service.Spec.Ports[1].TargetPort.StrVal; got != "grpc" {
		t.Fatalf("expected backend service to expose grpc, got %q", got)
	}
	if got := service.Spec.Ports[2].TargetPort.StrVal; got != "peer" {
		t.Fatalf("expected backend service to expose peer, got %q", got)
	}
	if len(service.Annotations) != 0 {
		t.Fatalf("expected no per-customer LoadBalancer annotations on backend service, got %v", service.Annotations)
	}

	publicCert := &unstructured.Unstructured{}
	publicCert.SetGroupVersionKind(certificateGVK())
	if err := reconciler.Get(ctx, types.NamespacedName{Name: publicTLSSecretName(instance), Namespace: instance.Namespace}, publicCert); err != nil {
		t.Fatalf("expected cert-manager Certificate for the public host to be created: %v", err)
	}
	if got, _, _ := unstructured.NestedString(publicCert.Object, "spec", "issuerRef", "name"); got != "letsencrypt-prod" {
		t.Fatalf("expected public Certificate ClusterIssuer ref, got %q", got)
	}
	if got, _, _ := unstructured.NestedStringSlice(publicCert.Object, "spec", "dnsNames"); len(got) != 1 || got[0] != "tuist-eu-1.kura.tuist.dev" {
		t.Fatalf("expected public Certificate dnsNames to include the regional public host, got %v", got)
	}

	ingress := &networkingv1.Ingress{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, ingress); err != nil {
		t.Fatalf("expected public regional Kura ingress to be created: %v", err)
	}
	if ingress.Spec.IngressClassName == nil || *ingress.Spec.IngressClassName != "kura-eu-central" {
		t.Fatalf("expected public ingress class kura-eu-central, got %v", ingress.Spec.IngressClassName)
	}
	if got := ingress.Spec.TLS[0].SecretName; got != publicTLSSecretName(instance) {
		t.Fatalf("expected public ingress to terminate with cert-manager Secret, got %q", got)
	}
	if got := ingress.Spec.Rules[0].Host; got != "tuist-eu-1.kura.tuist.dev" {
		t.Fatalf("expected public ingress host, got %q", got)
	}
	backend := ingress.Spec.Rules[0].HTTP.Paths[0].Backend.Service
	if backend == nil || backend.Name != instance.Name || backend.Port.Name != "http" {
		t.Fatalf("expected public ingress to route to %s:http, got %#v", instance.Name, backend)
	}
	if got := ingress.Annotations["nginx.ingress.kubernetes.io/proxy-request-buffering"]; got != "off" {
		t.Fatalf("expected request buffering disabled for streaming uploads, got %q", got)
	}
	if got := ingress.Annotations["nginx.ingress.kubernetes.io/proxy-body-size"]; got != "0" {
		t.Fatalf("expected unlimited public ingress body size, got %q", got)
	}

	pdb := &policyv1.PodDisruptionBudget{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, pdb); err != nil {
		t.Fatal(err)
	}
	if got := pdb.Spec.MinAvailable.IntVal; got != 2 {
		t.Fatalf("expected PDB minAvailable 2, got %d", got)
	}
	if got := pdb.Spec.Selector.MatchLabels["app.kubernetes.io/instance"]; got != instance.Name {
		t.Fatalf("expected PDB selector to match instance, got %q", got)
	}

	configMap := &corev1.ConfigMap{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: "kura-tuist-eu-1-extension", Namespace: instance.Namespace}, configMap); err != nil {
		t.Fatal(err)
	}
	if got := configMap.Data["hooks.lua"]; got != "return true" {
		t.Fatalf("expected extension script, got %q", got)
	}

	sts := &appsv1.StatefulSet{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		t.Fatal(err)
	}
	if got := *sts.Spec.Replicas; got != 3 {
		t.Fatalf("expected default replicas, got %d", got)
	}
	container := sts.Spec.Template.Spec.Containers[0]
	env := map[string]string{}
	for _, envVar := range container.Env {
		env[envVar.Name] = envVar.Value
	}
	if got := env["KURA_EXTENSION_ENABLED"]; got != "true" {
		t.Fatalf("expected controller to enable the extension, got %q", got)
	}
	if _, ok := env["KURA_PUBLIC_TLS_CERT_PATH"]; ok {
		t.Fatal("expected public TLS cert env to be absent because regional Kura ingress terminates TLS")
	}
	if _, ok := env["KURA_PUBLIC_TLS_KEY_PATH"]; ok {
		t.Fatal("expected public TLS key env to be absent because regional Kura ingress terminates TLS")
	}
	if _, ok := env["KURA_HTTPS_PORT"]; ok {
		t.Fatal("expected KURA_HTTPS_PORT to be absent because Kura no longer exposes a public TLS port")
	}
	if got := env["KURA_NODE_URL"]; got != "https://$(POD_NAME).kura-tuist-eu-1-headless.$(POD_NAMESPACE).svc.cluster.local:7443" {
		t.Fatalf("expected peer node URL to use mTLS, got %q", got)
	}
	if env["KURA_INTERNAL_TLS_CA_CERT_PATH"] == "" ||
		env["KURA_INTERNAL_TLS_CERT_PATH"] == "" ||
		env["KURA_INTERNAL_TLS_KEY_PATH"] == "" {
		t.Fatal("expected internal peer mTLS env paths to be configured")
	}
	if got := env[otlpTracesEndpointEnvVar]; got != "http://k8s-monitoring-alloy-receiver.observability.svc.cluster.local:4318/v1/traces" {
		t.Fatalf("expected default OTLP traces endpoint, got %q", got)
	}
	if got := env[environmentEnvVar]; got != "canary" {
		t.Fatalf("expected deployment environment, got %q", got)
	}
	peerMountFound := false
	for _, mount := range container.VolumeMounts {
		if mount.Name == "public-tls" {
			t.Fatal("expected public TLS secret not to be mounted into the kura container")
		}
		if mount.Name == peerTLSVolumeName && mount.ReadOnly {
			peerMountFound = true
		}
	}
	if !peerMountFound {
		t.Fatal("expected peer mTLS secret to be mounted into the kura container")
	}
	peerSecret := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: peerTLSSecretName(instance), Namespace: instance.Namespace}, peerSecret); err != nil {
		t.Fatalf("expected per-instance peer mTLS Secret to be created: %v", err)
	}
	if !peerTLSSecretDataValid(peerSecret.Data, instance, nil) {
		t.Fatal("expected generated peer mTLS Secret to contain a valid CA, certificate, and key")
	}
	block, _ := pem.Decode(peerSecret.Data[peerTLSCertFile])
	if block == nil {
		t.Fatal("expected peer certificate PEM")
	}
	peerCert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatalf("expected peer certificate to parse: %v", err)
	}
	if got := peerCert.DNSNames[0]; got != "*.kura-tuist-eu-1-headless.kura.svc.cluster.local" {
		t.Fatalf("expected peer certificate to cover StatefulSet pod DNS names, got %q", got)
	}
	publicPortFound := false
	for _, port := range container.Ports {
		if port.Name == "https" {
			publicPortFound = true
			break
		}
	}
	if publicPortFound {
		t.Fatal("expected https container port to stay absent because regional Kura ingress terminates TLS")
	}
	for _, name := range []string{
		"KURA_FILE_DESCRIPTOR_POOL_SIZE",
		"KURA_FILE_DESCRIPTOR_ACQUIRE_TIMEOUT_MS",
		"KURA_SEGMENT_HANDLE_CACHE_SIZE",
		"KURA_MEMORY_SOFT_LIMIT_BYTES",
		"KURA_MEMORY_HARD_LIMIT_BYTES",
		"KURA_MANIFEST_CACHE_MAX_BYTES",
		"KURA_MAX_KEYVALUE_BYTES",
		"KURA_METADATA_STORE_MAX_OPEN_FILES",
		"KURA_METADATA_STORE_MAX_BACKGROUND_JOBS",
	} {
		if _, ok := env[name]; ok {
			t.Fatalf("expected %s to be derived from the runtime cgroup, but the controller set it explicitly", name)
		}
	}
	if container.Lifecycle == nil || container.Lifecycle.PreStop == nil || container.Lifecycle.PreStop.Exec == nil {
		t.Fatal("expected preStop exec hook to be configured")
	}
	if grace := sts.Spec.Template.Spec.TerminationGracePeriodSeconds; grace == nil || *grace < drainCompletionTimeoutMs/1000+preStopDelaySeconds {
		t.Fatalf("expected terminationGracePeriodSeconds to cover the drain budget, got %v", grace)
	}
	if len(container.EnvFrom) == 0 || container.EnvFrom[0].SecretRef == nil || container.EnvFrom[0].SecretRef.Name != sharedSecretsName {
		t.Fatalf("expected envFrom to reference %q Secret", sharedSecretsName)
	}
	if container.EnvFrom[0].SecretRef.Optional == nil || !*container.EnvFrom[0].SecretRef.Optional {
		t.Fatal("expected shared secret envFrom to be optional so a missing Secret does not crash the pod")
	}
	if got := container.Resources.Requests.Cpu().String(); got != "500m" {
		t.Fatalf("expected default CPU request, got %q", got)
	}
	if _, ok := sts.Spec.Template.Annotations["kubernetes.io/ingress-bandwidth"]; ok {
		t.Fatal("expected no default ingress bandwidth annotation")
	}
	if got := sts.Spec.Template.Annotations["prometheus.io/scrape"]; got != "true" {
		t.Fatalf("expected Prometheus scrape annotation, got %q", got)
	}
	if got := sts.Spec.Template.Annotations["prometheus.io/port-name"]; got != "http" {
		t.Fatalf("expected Prometheus port-name annotation, got %q", got)
	}
	if got := sts.Spec.Template.Annotations["prometheus.io/path"]; got != "/metrics" {
		t.Fatalf("expected Prometheus path annotation, got %q", got)
	}
	if got := sts.Spec.Template.Annotations[sharedSecretsRVAnnotation]; got != "12345" {
		t.Fatalf("expected shared secrets resource version annotation, got %q", got)
	}
	if got := sts.Spec.Template.Spec.NodeSelector["node.cluster.x-k8s.io/pool"]; got != "kura" {
		t.Fatalf("expected kura node pool selector, got %q", got)
	}
	if got := len(sts.Spec.Template.Spec.TopologySpreadConstraints); got != 1 {
		t.Fatalf("expected one topology spread constraint, got %d", got)
	}
	if got := sts.Spec.Template.Spec.TopologySpreadConstraints[0].TopologyKey; got != "kubernetes.io/hostname" {
		t.Fatalf("expected hostname topology spread, got %q", got)
	}
	if got := sts.Spec.Template.Labels["tuist.dev/account"]; got != "tuist" {
		t.Fatalf("expected pod template account label, got %q", got)
	}
	if got := sts.Spec.Template.Labels["tuist.dev/region"]; got != "eu" {
		t.Fatalf("expected pod template region label, got %q", got)
	}
	if got := env["KURA_TMP_DIR"]; got != "/var/cache/kura/tmp" {
		t.Fatalf("expected KURA_TMP_DIR to use the persistent data volume, got %q", got)
	}
	for _, mount := range container.VolumeMounts {
		if mount.Name == "tmp" || mount.MountPath == "/tmp/kura" {
			t.Fatalf("expected no tmp emptyDir mount, got %v", mount)
		}
	}
	for i := range sts.Spec.Template.Spec.Volumes {
		if sts.Spec.Template.Spec.Volumes[i].Name == "tmp" {
			t.Fatal("expected no tmp emptyDir volume")
		}
	}
	retention := sts.Spec.PersistentVolumeClaimRetentionPolicy
	if retention == nil {
		t.Fatal("expected PVC retention policy to be set")
	}
	if retention.WhenDeleted != appsv1.DeletePersistentVolumeClaimRetentionPolicyType {
		t.Fatalf("expected whenDeleted=Delete (clean up on destroy), got %q", retention.WhenDeleted)
	}
	if retention.WhenScaled != appsv1.RetainPersistentVolumeClaimRetentionPolicyType {
		t.Fatalf("expected whenScaled=Retain (preserve cache on scale-down), got %q", retention.WhenScaled)
	}
	if got := sts.Spec.VolumeClaimTemplates[0].Labels["tuist.dev/account"]; got != "tuist" {
		t.Fatalf("expected PVC account label, got %q", got)
	}
	if got := sts.Spec.VolumeClaimTemplates[0].Labels["tuist.dev/region"]; got != "eu" {
		t.Fatalf("expected PVC region label, got %q", got)
	}
	if got := *sts.Spec.VolumeClaimTemplates[0].Spec.StorageClassName; got != "hcloud-volumes" {
		t.Fatalf("expected storage class, got %q", got)
	}
	if got := sts.Spec.VolumeClaimTemplates[0].Spec.Resources.Requests.Storage().String(); got != "200Gi" {
		t.Fatalf("expected PVC size, got %q", got)
	}

	policy := &networkingv1.NetworkPolicy{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, policy); err != nil {
		t.Fatalf("expected NetworkPolicy to be created: %v", err)
	}
	if got := policy.Spec.PodSelector.MatchLabels["app.kubernetes.io/instance"]; got != instance.Name {
		t.Fatalf("expected NetworkPolicy to select this instance's pods, got %q", got)
	}
	if len(policy.Spec.Ingress) != 3 {
		t.Fatalf("expected NetworkPolicy to have 3 ingress rules, got %d", len(policy.Spec.Ingress))
	}
	peerPorts := policy.Spec.Ingress[1].Ports
	if got := peerPorts[0].Port.StrVal; got != "peer" {
		t.Fatalf("expected same-account NetworkPolicy rule to expose peer, got %q", got)
	}
	if got := policy.Spec.Ingress[1].From[0].PodSelector.MatchLabels["tuist.dev/account"]; got != "tuist" {
		t.Fatalf("expected same-account NetworkPolicy peer selector, got %q", got)
	}
	ingressPorts := policy.Spec.Ingress[2].Ports
	if len(policy.Spec.Ingress[2].From) != 1 || policy.Spec.Ingress[2].From[0].NamespaceSelector == nil {
		t.Fatalf("expected regional Kura ingress NetworkPolicy rule to allow cluster namespaces, got %v", policy.Spec.Ingress[2].From)
	}
	if len(ingressPorts) != 2 {
		t.Fatalf("expected regional Kura ingress NetworkPolicy rule to expose HTTP and gRPC, got %d ports", len(ingressPorts))
	}
	if got := ingressPorts[0].Port.StrVal; got != "http" {
		t.Fatalf("expected regional Kura ingress NetworkPolicy rule to expose http, got %q", got)
	}
	if got := ingressPorts[1].Port.StrVal; got != "grpc" {
		t.Fatalf("expected regional Kura ingress NetworkPolicy rule to expose grpc, got %q", got)
	}
}

func TestKuraGatewayReconcileCreatesDedicatedIngressInfrastructure(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	gateway := &kurav1alpha1.KuraGateway{
		ObjectMeta: metav1.ObjectMeta{Name: "kgw-abc123-us-east", Namespace: "kura"},
		Spec: kurav1alpha1.KuraGatewaySpec{
			Region:              "us-east",
			IngressClassName:    "kura-us-east-kgw-abc123",
			ControllerClassName: "k8s.io/kura-us-east-kgw-abc123-ingress-nginx",
			ControllerImage:     "registry.k8s.io/ingress-nginx/controller:v1.11.3",
			Replicas:            ptr(int32(3)),
			NodeSelector:        map[string]string{"node.cluster.x-k8s.io/pool": "kura-us-east"},
			LoadBalancerAnnotations: map[string]string{
				"load-balancer.hetzner.cloud/name":               "tuist-kgw-abc123-us-east-ingress",
				"load-balancer.hetzner.cloud/location":           "ash",
				"load-balancer.hetzner.cloud/uses-proxyprotocol": "true",
			},
		},
	}
	reconciler := &KuraGatewayReconciler{
		Client:                    fake.NewClientBuilder().WithScheme(scheme).WithObjects(gateway).WithStatusSubresource(gateway).Build(),
		Scheme:                    scheme,
		GatewayServiceAccountName: "tuist-kura-controller-gateway-ingress-nginx",
	}

	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: gateway.Name, Namespace: gateway.Namespace}}); err != nil {
		t.Fatal(err)
	}

	service := &corev1.Service{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: gatewayWorkloadName(gateway), Namespace: gateway.Namespace}, service); err != nil {
		t.Fatalf("expected dedicated gateway LoadBalancer Service: %v", err)
	}
	if service.Spec.Type != corev1.ServiceTypeLoadBalancer {
		t.Fatalf("expected LoadBalancer Service, got %q", service.Spec.Type)
	}
	if service.Spec.ExternalTrafficPolicy != corev1.ServiceExternalTrafficPolicyLocal {
		t.Fatalf("expected externalTrafficPolicy Local, got %q", service.Spec.ExternalTrafficPolicy)
	}
	if got := service.Annotations["load-balancer.hetzner.cloud/location"]; got != "ash" {
		t.Fatalf("expected Hetzner location annotation, got %q", got)
	}
	if got := service.Annotations["load-balancer.hetzner.cloud/uses-proxyprotocol"]; got != "true" {
		t.Fatalf("expected proxy protocol annotation, got %q", got)
	}
	if got := service.Annotations["load-balancer.hetzner.cloud/node-selector"]; got != "node.cluster.x-k8s.io/pool=kura-us-east" {
		t.Fatalf("expected Hetzner LB node selector annotation, got %q", got)
	}

	ingressClass := &networkingv1.IngressClass{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: "kura-us-east-kgw-abc123"}, ingressClass); err != nil {
		t.Fatalf("expected dedicated IngressClass: %v", err)
	}
	if got := ingressClass.Spec.Controller; got != "k8s.io/kura-us-east-kgw-abc123-ingress-nginx" {
		t.Fatalf("expected dedicated controller class, got %q", got)
	}
	updatedGateway := &kurav1alpha1.KuraGateway{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: gateway.Name, Namespace: gateway.Namespace}, updatedGateway); err != nil {
		t.Fatal(err)
	}
	if got := updatedGateway.Status.IngressClassName; got != "kura-us-east-kgw-abc123" {
		t.Fatalf("expected reconciled ingress class name to be persisted immediately, got %q", got)
	}

	configMap := &corev1.ConfigMap{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: gatewayWorkloadName(gateway), Namespace: gateway.Namespace}, configMap); err != nil {
		t.Fatalf("expected dedicated gateway ConfigMap: %v", err)
	}
	if got := configMap.Data["use-proxy-protocol"]; got != "true" {
		t.Fatalf("expected proxy protocol enabled in nginx config, got %q", got)
	}
	if got := configMap.Data["proxy-request-buffering"]; got != "off" {
		t.Fatalf("expected request buffering disabled in nginx config, got %q", got)
	}
	if got := configMap.Data["client-body-buffer-size"]; got != "4m" {
		t.Fatalf("expected raised client body buffer for upload throughput, got %q", got)
	}
	if got := configMap.Data["http-snippet"]; got != "http2_body_preread_size 4m;" {
		t.Fatalf("expected raised HTTP/2 body preread window, got %q", got)
	}
	if got := configMap.Data["http2-max-concurrent-streams"]; got != "32" {
		t.Fatalf("expected bounded HTTP/2 concurrent streams, got %q", got)
	}

	deployment := &appsv1.Deployment{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: gatewayWorkloadName(gateway), Namespace: gateway.Namespace}, deployment); err != nil {
		t.Fatalf("expected dedicated gateway Deployment: %v", err)
	}
	if got := *deployment.Spec.Replicas; got != 3 {
		t.Fatalf("expected configured replicas, got %d", got)
	}
	if got := deployment.Spec.Template.Spec.ServiceAccountName; got != "tuist-kura-controller-gateway-ingress-nginx" {
		t.Fatalf("expected shared dynamic gateway ServiceAccount, got %q", got)
	}
	if got := deployment.Spec.Template.Spec.NodeSelector["node.cluster.x-k8s.io/pool"]; got != "kura-us-east" {
		t.Fatalf("expected gateway to stay on the regional Kura pool, got %q", got)
	}
	container := deployment.Spec.Template.Spec.Containers[0]
	if got := container.Image; got != "registry.k8s.io/ingress-nginx/controller:v1.11.3" {
		t.Fatalf("expected configured ingress-nginx image, got %q", got)
	}
	if !containsString(container.Args, "--ingress-class=kura-us-east-kgw-abc123") {
		t.Fatalf("expected dedicated ingress class arg, got %v", container.Args)
	}
	if !containsString(container.Args, "--watch-namespace=$(POD_NAMESPACE)") {
		t.Fatalf("expected namespace-scoped ingress watch, got %v", container.Args)
	}
}

func TestKuraInstanceReconcilePeerTLSSecretCreatesValidMaterial(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-1", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle: "tuist",
			TenantID:      "tuist",
			Region:        "eu",
			Image:         "ghcr.io/tuist/kura:0.5.2",
		},
	}
	reconciler := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance).Build(),
		Scheme: scheme,
	}

	if err := reconciler.reconcilePeerTLSSecret(ctx, instance); err != nil {
		t.Fatal(err)
	}

	secret := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: peerTLSSecretName(instance), Namespace: instance.Namespace}, secret); err != nil {
		t.Fatalf("expected peer TLS Secret to be created: %v", err)
	}
	if secret.Type != corev1.SecretTypeOpaque {
		t.Fatalf("expected opaque Secret, got %q", secret.Type)
	}
	if !peerTLSSecretDataValid(secret.Data, instance, nil) {
		t.Fatal("expected generated peer TLS data to validate")
	}
	if got := secret.Labels["tuist.dev/account"]; got != "tuist" {
		t.Fatalf("expected account label, got %q", got)
	}
	if len(secret.OwnerReferences) != 1 || secret.OwnerReferences[0].Name != instance.Name {
		t.Fatalf("expected Secret to be owned by KuraInstance, got %v", secret.OwnerReferences)
	}

	block, _ := pem.Decode(secret.Data[peerTLSCertFile])
	if block == nil {
		t.Fatal("expected peer certificate PEM")
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatalf("expected peer certificate to parse: %v", err)
	}
	if !containsString(cert.DNSNames, "*.kura-tuist-eu-1-headless.kura.svc.cluster.local") {
		t.Fatalf("expected peer certificate SANs to cover StatefulSet pod DNS names, got %v", cert.DNSNames)
	}
	if !containsExtKeyUsage(cert.ExtKeyUsage, x509.ExtKeyUsageServerAuth) ||
		!containsExtKeyUsage(cert.ExtKeyUsage, x509.ExtKeyUsageClientAuth) {
		t.Fatalf("expected peer certificate to support server and client auth, got %v", cert.ExtKeyUsage)
	}
}

func TestKuraInstanceReconcilePeerTLSSecretPreservesValidMaterial(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-1", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle: "tuist",
			TenantID:      "tuist",
			Region:        "eu",
			Image:         "ghcr.io/tuist/kura:0.5.2",
		},
	}
	validData, err := generateSelfSignedPeerTLSSecretData(instance)
	if err != nil {
		t.Fatal(err)
	}
	secret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: peerTLSSecretName(instance), Namespace: instance.Namespace},
		Data:       cloneSecretData(validData),
	}
	reconciler := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, secret).Build(),
		Scheme: scheme,
	}

	if err := reconciler.reconcilePeerTLSSecret(ctx, instance); err != nil {
		t.Fatal(err)
	}

	updated := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: peerTLSSecretName(instance), Namespace: instance.Namespace}, updated); err != nil {
		t.Fatal(err)
	}
	if !secretDataEqual(validData, updated.Data) {
		t.Fatal("expected existing valid peer TLS material to be preserved")
	}
}

func TestKuraInstanceReconcilePeerTLSSecretRegeneratesInvalidMaterial(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-1", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle: "tuist",
			TenantID:      "tuist",
			Region:        "eu",
			Image:         "ghcr.io/tuist/kura:0.5.2",
		},
	}
	invalidData := map[string][]byte{
		peerTLSCAFile:   []byte("not a ca"),
		peerTLSCertFile: []byte("not a cert"),
		peerTLSKeyFile:  []byte("not a key"),
	}
	secret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: peerTLSSecretName(instance), Namespace: instance.Namespace},
		Data:       cloneSecretData(invalidData),
	}
	reconciler := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, secret).Build(),
		Scheme: scheme,
	}

	if err := reconciler.reconcilePeerTLSSecret(ctx, instance); err != nil {
		t.Fatal(err)
	}

	updated := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: peerTLSSecretName(instance), Namespace: instance.Namespace}, updated); err != nil {
		t.Fatal(err)
	}
	if !peerTLSSecretDataValid(updated.Data, instance, nil) {
		t.Fatal("expected invalid peer TLS material to be regenerated")
	}
	if secretDataEqual(invalidData, updated.Data) {
		t.Fatal("expected regenerated peer TLS material to differ from invalid input")
	}
}

func meshInstance(name, account string) *kurav1alpha1.KuraInstance {
	return &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle: account,
			TenantID:      account,
			Region:        "eu",
			Image:         "ghcr.io/tuist/kura:0.5.2",
			Mesh:          true,
		},
	}
}

func meshTestScheme(t *testing.T) *runtime.Scheme {
	t.Helper()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	return scheme
}

func TestKuraInstanceReconcilePeerTLSSecretMeshSignsLeafWithAccountCA(t *testing.T) {
	ctx := context.Background()
	scheme := meshTestScheme(t)

	instance := meshInstance("kura-tuist-eu-1", "tuist")
	reconciler := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance).Build(),
		Scheme: scheme,
	}
	if err := reconciler.reconcilePeerTLSSecret(ctx, instance); err != nil {
		t.Fatal(err)
	}

	caSecret := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: accountPeerCASecretName(instance), Namespace: instance.Namespace}, caSecret); err != nil {
		t.Fatalf("expected per-account CA Secret to be created: %v", err)
	}
	if len(caSecret.Data[peerCACertFile]) == 0 || len(caSecret.Data[peerCAKeyFile]) == 0 {
		t.Fatal("expected per-account CA Secret to hold a CA cert and key")
	}

	leaf := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: peerTLSSecretName(instance), Namespace: instance.Namespace}, leaf); err != nil {
		t.Fatalf("expected peer leaf Secret to be created: %v", err)
	}
	if !peerTLSSecretDataValid(leaf.Data, instance, caSecret.Data[peerCACertFile]) {
		t.Fatal("expected mesh leaf to validate against the account CA")
	}
	if string(leaf.Data[peerTLSCAFile]) != string(caSecret.Data[peerCACertFile]) {
		t.Fatal("expected leaf Secret to embed the account CA cert")
	}
	block, _ := pem.Decode(leaf.Data[peerTLSCertFile])
	if block == nil {
		t.Fatal("expected leaf certificate PEM")
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatalf("parse leaf certificate: %v", err)
	}
	if !containsString(cert.DNSNames, accountPeerServiceDNSName(instance)) {
		t.Fatalf("expected leaf SANs to cover the account peer Service, got %v", cert.DNSNames)
	}
}

func TestKuraInstanceReconcilePeerTLSSecretMeshSharesAccountCA(t *testing.T) {
	ctx := context.Background()
	scheme := meshTestScheme(t)

	eu := meshInstance("kura-tuist-eu-1", "tuist")
	scw := meshInstance("kura-tuist-scw-1", "tuist")
	reconciler := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(eu, scw).Build(),
		Scheme: scheme,
	}
	if err := reconciler.reconcilePeerTLSSecret(ctx, eu); err != nil {
		t.Fatal(err)
	}
	if err := reconciler.reconcilePeerTLSSecret(ctx, scw); err != nil {
		t.Fatal(err)
	}

	euLeaf := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: peerTLSSecretName(eu), Namespace: eu.Namespace}, euLeaf); err != nil {
		t.Fatal(err)
	}
	scwLeaf := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: peerTLSSecretName(scw), Namespace: scw.Namespace}, scwLeaf); err != nil {
		t.Fatal(err)
	}
	if string(euLeaf.Data[peerTLSCAFile]) != string(scwLeaf.Data[peerTLSCAFile]) {
		t.Fatal("expected both instances of the account to share one peer CA")
	}

	caSecret := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: accountPeerCASecretName(eu), Namespace: eu.Namespace}, caSecret); err != nil {
		t.Fatal(err)
	}
	// A leaf issued for one instance validates against the shared account
	// CA the other instance also trusts — that is what lets them peer.
	if !peerTLSSecretDataValid(scwLeaf.Data, scw, caSecret.Data[peerCACertFile]) {
		t.Fatal("expected the second instance's leaf to validate against the shared account CA")
	}
}

func TestKuraInstanceReconcilePeerTLSSecretMeshIsolatesAccounts(t *testing.T) {
	ctx := context.Background()
	scheme := meshTestScheme(t)

	alpha := meshInstance("kura-alpha-eu-1", "alpha")
	bravo := meshInstance("kura-bravo-eu-1", "bravo")
	reconciler := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(alpha, bravo).Build(),
		Scheme: scheme,
	}
	if err := reconciler.reconcilePeerTLSSecret(ctx, alpha); err != nil {
		t.Fatal(err)
	}
	if err := reconciler.reconcilePeerTLSSecret(ctx, bravo); err != nil {
		t.Fatal(err)
	}

	alphaLeaf := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: peerTLSSecretName(alpha), Namespace: alpha.Namespace}, alphaLeaf); err != nil {
		t.Fatal(err)
	}
	bravoCA := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: accountPeerCASecretName(bravo), Namespace: bravo.Namespace}, bravoCA); err != nil {
		t.Fatal(err)
	}
	if string(alphaLeaf.Data[peerTLSCAFile]) == string(bravoCA.Data[peerCACertFile]) {
		t.Fatal("expected different accounts to get different peer CAs")
	}
	// Account alpha's leaf must not chain to account bravo's CA: that is
	// the TLS-layer wall that keeps one account out of another's mesh.
	if peerTLSSecretDataValid(alphaLeaf.Data, alpha, bravoCA.Data[peerCACertFile]) {
		t.Fatal("expected account alpha's leaf to be rejected under account bravo's CA")
	}
	roots := x509.NewCertPool()
	if !roots.AppendCertsFromPEM(bravoCA.Data[peerCACertFile]) {
		t.Fatal("expected bravo CA to parse")
	}
	block, _ := pem.Decode(alphaLeaf.Data[peerTLSCertFile])
	if block == nil {
		t.Fatal("expected alpha leaf PEM")
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatalf("parse alpha leaf: %v", err)
	}
	if _, err := cert.Verify(x509.VerifyOptions{Roots: roots, KeyUsages: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth}}); err == nil {
		t.Fatal("expected alpha leaf verification under bravo CA to fail")
	}
}

func TestKuraInstanceReconcileCrossRegionAccountPeerService(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-1", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle:     "tuist",
			TenantID:          "tuist",
			Region:            "eu",
			Image:             "ghcr.io/tuist/kura:0.5.2",
			PeerTLSSecretName: "kura-cross-region-peer-tls",
		},
	}
	peerSecret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-cross-region-peer-tls", Namespace: instance.Namespace},
	}
	reconciler := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, peerSecret).WithStatusSubresource(instance).Build(),
		Scheme: scheme,
	}

	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}); err != nil {
		t.Fatal(err)
	}

	peerService := &corev1.Service{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: accountPeerServiceName(instance), Namespace: instance.Namespace}, peerService); err != nil {
		t.Fatalf("expected account peer headless Service to be created: %v", err)
	}
	if peerService.Spec.ClusterIP != corev1.ClusterIPNone {
		t.Fatalf("expected account peer service to be headless, got %q", peerService.Spec.ClusterIP)
	}
	if got := peerService.Spec.Selector["tuist.dev/account"]; got != "tuist" {
		t.Fatalf("expected account peer service to select all account pods, got %q", got)
	}
	if _, ok := peerService.Spec.Selector[podNameLabel]; ok {
		t.Fatal("expected account peer service not to pin to the public primary pod")
	}
	if got := peerService.Spec.Ports[0].TargetPort.StrVal; got != "peer" {
		t.Fatalf("expected peer service to target the peer port, got %q", got)
	}
	legacyPeerService := &corev1.Service{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: peerServiceName(instance), Namespace: instance.Namespace}, legacyPeerService); !apierrors.IsNotFound(err) {
		t.Fatalf("expected legacy peer LoadBalancer Service to be absent, got %v", err)
	}

	sts := &appsv1.StatefulSet{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		t.Fatal(err)
	}
	env := map[string]string{}
	for _, envVar := range sts.Spec.Template.Spec.Containers[0].Env {
		env[envVar.Name] = envVar.Value
	}
	if got, ok := env["KURA_PEER_GATEWAY_URL"]; ok {
		t.Fatalf("expected no peer gateway URL env, got %q", got)
	}
	if got := env["KURA_GLOBAL_DISCOVERY_DNS_NAME"]; got != "kura-tuist-peers.kura.svc.cluster.local" {
		t.Fatalf("expected global discovery DNS env, got %q", got)
	}
	peerTLSVolume := volumeByName(sts.Spec.Template.Spec.Volumes, peerTLSVolumeName)
	if peerTLSVolume == nil || peerTLSVolume.Secret == nil {
		t.Fatal("expected peer TLS Secret volume")
	}
	if got := peerTLSVolume.Secret.SecretName; got != "kura-cross-region-peer-tls" {
		t.Fatalf("expected shared peer TLS Secret to be mounted, got %q", got)
	}

	generatedSecret := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name + "-peer-tls", Namespace: instance.Namespace}, generatedSecret); !apierrors.IsNotFound(err) {
		t.Fatalf("expected no generated per-instance peer TLS Secret when a shared Secret is configured, got %v", err)
	}

	policy := &networkingv1.NetworkPolicy{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, policy); err != nil {
		t.Fatal(err)
	}
	if len(policy.Spec.Ingress) != 3 {
		t.Fatalf("expected NetworkPolicy to include same-account peer rule, got %d rules", len(policy.Spec.Ingress))
	}
	if got := policy.Spec.Ingress[1].Ports[0].Port.StrVal; got != "peer" {
		t.Fatalf("expected same-account NetworkPolicy rule to expose peer port, got %q", got)
	}
	if got := policy.Spec.Ingress[1].From[0].PodSelector.MatchLabels["tuist.dev/account"]; got != "tuist" {
		t.Fatalf("expected same-account NetworkPolicy peer selector, got %q", got)
	}
}

func TestPeerTLSDNSNamesIncludesMeshPublicPeerHost(t *testing.T) {
	instance := meshInstance("kura-tuist-eu-1", "tuist")
	if containsString(peerTLSDNSNames(instance), "peer.tuist.kura.tuist.dev") {
		t.Fatal("did not expect the public peer host in SANs before it is set")
	}

	instance.Spec.MeshPublicPeerHost = "peer.tuist.kura.tuist.dev"
	if !containsString(peerTLSDNSNames(instance), "peer.tuist.kura.tuist.dev") {
		t.Fatalf("expected peer SANs to cover the public peer host, got %v", peerTLSDNSNames(instance))
	}
}

func TestKuraInstanceReconcileMeshPublicPeerExposure(t *testing.T) {
	ctx := context.Background()
	scheme := meshTestScheme(t)

	instance := meshInstance("kura-tuist-eu-1", "tuist")
	instance.Spec.MeshPublicPeerHost = "peer.tuist-eu-central-1.kura.tuist.dev"
	instance.Spec.MeshExternalPeers = []string{"https://kura.acme.example:7443"}
	instance.Spec.MeshPublicPeerLoadBalancerAnnotations = map[string]string{
		"load-balancer.hetzner.cloud/location":      "fsn1",
		"load-balancer.hetzner.cloud/node-selector": "node.cluster.x-k8s.io/pool=kura",
	}
	reconciler := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance).WithStatusSubresource(instance).Build(),
		Scheme: scheme,
	}
	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}); err != nil {
		t.Fatal(err)
	}

	lb := &corev1.Service{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: accountPublicPeerServiceName(instance), Namespace: instance.Namespace}, lb); err != nil {
		t.Fatalf("expected public peer Service to be created: %v", err)
	}
	if lb.Spec.Type != corev1.ServiceTypeLoadBalancer {
		t.Fatalf("expected public peer Service to be a LoadBalancer, got %q", lb.Spec.Type)
	}
	if got := lb.Annotations["external-dns.alpha.kubernetes.io/hostname"]; got != instance.Spec.MeshPublicPeerHost {
		t.Fatalf("expected external-dns hostname annotation, got %q", got)
	}
	if got := lb.Annotations["load-balancer.hetzner.cloud/node-selector"]; got != "node.cluster.x-k8s.io/pool=kura" {
		t.Fatalf("expected node-selector annotation to restrict LB targets, got %q", got)
	}
	if got := lb.Annotations["load-balancer.hetzner.cloud/location"]; got != "fsn1" {
		t.Fatalf("expected hcloud location annotation, got %q", got)
	}
	if got := lb.Spec.Selector["tuist.dev/account"]; got != "tuist" {
		t.Fatalf("expected public peer Service to select all account pods, got %q", got)
	}
	if got := lb.Spec.Ports[0].TargetPort.StrVal; got != "peer" {
		t.Fatalf("expected public peer Service to target the peer port, got %q", got)
	}

	sts := &appsv1.StatefulSet{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		t.Fatal(err)
	}
	env := map[string]string{}
	for _, envVar := range sts.Spec.Template.Spec.Containers[0].Env {
		env[envVar.Name] = envVar.Value
	}
	if got := env["KURA_PEERS"]; got != "https://kura.acme.example:7443" {
		t.Fatalf("expected KURA_PEERS to seed the self-hosted peer, got %q", got)
	}

	policy := &networkingv1.NetworkPolicy{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, policy); err != nil {
		t.Fatal(err)
	}
	publicPeerAllowed := false
	for _, rule := range policy.Spec.Ingress {
		for _, from := range rule.From {
			if from.IPBlock != nil && from.IPBlock.CIDR == "0.0.0.0/0" {
				for _, p := range rule.Ports {
					if p.Port != nil && p.Port.StrVal == "peer" {
						publicPeerAllowed = true
					}
				}
			}
		}
	}
	if !publicPeerAllowed {
		t.Fatal("expected NetworkPolicy to allow the peer port from off-cluster (public peer plane)")
	}

	caSecret := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: accountPeerCASecretName(instance), Namespace: instance.Namespace}, caSecret); err != nil {
		t.Fatal(err)
	}
	leaf := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: peerTLSSecretName(instance), Namespace: instance.Namespace}, leaf); err != nil {
		t.Fatal(err)
	}
	if !peerTLSSecretDataValid(leaf.Data, instance, caSecret.Data[peerCACertFile]) {
		t.Fatal("expected the mesh leaf to validate, including the public peer host SAN")
	}
	block, _ := pem.Decode(leaf.Data[peerTLSCertFile])
	if block == nil {
		t.Fatal("expected leaf certificate PEM")
	}
	cert, err := x509.ParseCertificate(block.Bytes)
	if err != nil {
		t.Fatalf("parse leaf certificate: %v", err)
	}
	if !containsString(cert.DNSNames, instance.Spec.MeshPublicPeerHost) {
		t.Fatalf("expected leaf SANs to cover the public peer host, got %v", cert.DNSNames)
	}

	// A non-mesh instance of the SAME account (e.g. a private runner-cache
	// region) must not delete the account-level public peer Service its
	// mesh-enabled sibling owns — otherwise they churn it every reconcile.
	sibling := meshInstance("kura-tuist-scw-1", "tuist")
	sibling.Spec.Mesh = false
	if err := reconciler.Create(ctx, sibling); err != nil {
		t.Fatal(err)
	}
	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: sibling.Name, Namespace: sibling.Namespace}}); err != nil {
		t.Fatal(err)
	}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: accountPublicPeerServiceName(instance), Namespace: instance.Namespace}, lb); err != nil {
		t.Fatalf("expected public peer Service to survive a non-mesh sibling's reconcile, got %v", err)
	}
}

func TestKuraInstanceReconcileWithoutSharedTLSDoesNotEnableGlobalDiscovery(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-1", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle: "tuist",
			TenantID:      "tuist",
			Region:        "eu",
			Image:         "ghcr.io/tuist/kura:0.5.2",
		},
	}
	reconciler := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance).WithStatusSubresource(instance).Build(),
		Scheme: scheme,
	}

	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}); err != nil {
		t.Fatal(err)
	}

	peerService := &corev1.Service{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: accountPeerServiceName(instance), Namespace: instance.Namespace}, peerService); !apierrors.IsNotFound(err) {
		t.Fatalf("expected account peer service to stay absent until shared peer TLS is configured, got %v", err)
	}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: peerServiceName(instance), Namespace: instance.Namespace}, peerService); !apierrors.IsNotFound(err) {
		t.Fatalf("expected legacy peer LoadBalancer Service to stay absent, got %v", err)
	}

	sts := &appsv1.StatefulSet{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		t.Fatal(err)
	}
	env := map[string]string{}
	for _, envVar := range sts.Spec.Template.Spec.Containers[0].Env {
		env[envVar.Name] = envVar.Value
	}
	if _, ok := env["KURA_PEER_GATEWAY_URL"]; ok {
		t.Fatal("expected peer gateway URL to stay disabled until shared peer TLS is configured")
	}
	if _, ok := env["KURA_GLOBAL_DISCOVERY_DNS_NAME"]; ok {
		t.Fatal("expected global discovery to stay disabled until shared peer TLS is configured")
	}

	generatedSecret := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name + "-peer-tls", Namespace: instance.Namespace}, generatedSecret); err != nil {
		t.Fatalf("expected generated per-instance peer TLS Secret to remain in use: %v", err)
	}
}

func TestKuraInstanceReconcileExposesGRPCWhenHostSet(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-1", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle:    "tuist",
			TenantID:         "tuist",
			Region:           "eu",
			Image:            "ghcr.io/tuist/kura:0.5.2",
			PublicHost:       "tuist-eu-1.kura.tuist.dev",
			GRPCPublicHost:   "grpc.tuist-eu-1.kura.tuist.dev",
			IngressClassName: "kura-eu-central",
			StorageClassName: "hcloud-volumes",
		},
	}

	reconciler := &KuraInstanceReconciler{
		Client:            fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance).WithStatusSubresource(instance).Build(),
		Scheme:            scheme,
		GRPCClusterIssuer: "letsencrypt-prod",
	}

	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}); err != nil {
		t.Fatal(err)
	}

	grpcService := &corev1.Service{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: grpcServiceName(instance), Namespace: instance.Namespace}, grpcService); !apierrors.IsNotFound(err) {
		t.Fatalf("expected legacy gRPC LoadBalancer Service to be absent, got %v", err)
	}

	grpcIngress := &networkingv1.Ingress{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: grpcServiceName(instance), Namespace: instance.Namespace}, grpcIngress); err != nil {
		t.Fatalf("expected gRPC regional Kura ingress to be created: %v", err)
	}
	if grpcIngress.Spec.IngressClassName == nil || *grpcIngress.Spec.IngressClassName != "kura-eu-central" {
		t.Fatalf("expected gRPC ingress class kura-eu-central, got %v", grpcIngress.Spec.IngressClassName)
	}
	if got := grpcIngress.Spec.TLS[0].SecretName; got != grpcTLSSecretName(instance) {
		t.Fatalf("expected gRPC ingress to terminate with cert-manager Secret, got %q", got)
	}
	if got := grpcIngress.Spec.Rules[0].Host; got != "grpc.tuist-eu-1.kura.tuist.dev" {
		t.Fatalf("expected gRPC ingress host, got %q", got)
	}
	backend := grpcIngress.Spec.Rules[0].HTTP.Paths[0].Backend.Service
	if backend == nil || backend.Name != instance.Name || backend.Port.Name != "grpc" {
		t.Fatalf("expected gRPC ingress to route to %s:grpc, got %#v", instance.Name, backend)
	}
	if got := grpcIngress.Annotations["nginx.ingress.kubernetes.io/backend-protocol"]; got != "GRPC" {
		t.Fatalf("expected gRPC ingress backend protocol, got %q", got)
	}

	cert := &unstructured.Unstructured{}
	cert.SetGroupVersionKind(certificateGVK())
	if err := reconciler.Get(ctx, types.NamespacedName{Name: grpcTLSSecretName(instance), Namespace: instance.Namespace}, cert); err != nil {
		t.Fatalf("expected cert-manager Certificate to be created: %v", err)
	}
	if got, _, _ := unstructured.NestedString(cert.Object, "spec", "secretName"); got != grpcTLSSecretName(instance) {
		t.Fatalf("expected Certificate secretName, got %q", got)
	}
	if got, _, _ := unstructured.NestedString(cert.Object, "spec", "issuerRef", "name"); got != "letsencrypt-prod" {
		t.Fatalf("expected ClusterIssuer ref, got %q", got)
	}
	if got, _, _ := unstructured.NestedStringSlice(cert.Object, "spec", "dnsNames"); len(got) != 1 || got[0] != "grpc.tuist-eu-1.kura.tuist.dev" {
		t.Fatalf("expected gRPC Certificate dnsNames to include the regional host, got %v", got)
	}

	sts := &appsv1.StatefulSet{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		t.Fatal(err)
	}
	container := sts.Spec.Template.Spec.Containers[0]
	env := map[string]string{}
	for _, envVar := range container.Env {
		env[envVar.Name] = envVar.Value
	}
	if _, ok := env["KURA_GRPC_TLS_CERT_PATH"]; ok {
		t.Fatal("expected gRPC TLS cert env to be absent because regional Kura ingress terminates TLS")
	}
	if _, ok := env["KURA_GRPC_TLS_KEY_PATH"]; ok {
		t.Fatal("expected gRPC TLS key env to be absent because regional Kura ingress terminates TLS")
	}
	for _, mount := range container.VolumeMounts {
		if mount.Name == "grpc-tls" {
			t.Fatal("expected gRPC TLS secret not to be mounted into the kura container")
		}
	}

	updated := &kurav1alpha1.KuraInstance{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, updated); err != nil {
		t.Fatal(err)
	}
	if got := updated.Status.GRPCPublicURL; got != "grpcs://grpc.tuist-eu-1.kura.tuist.dev" {
		t.Fatalf("expected gRPC public URL in status, got %q", got)
	}
}

func TestKuraInstanceReconcilePreservesExplicitOTLPTracesEndpoint(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-us-east-1", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle: "tuist",
			TenantID:      "tuist",
			Region:        "us-east",
			Image:         "ghcr.io/tuist/kura:0.5.2",
			ExtraEnv: []corev1.EnvVar{{
				Name:  otlpTracesEndpointEnvVar,
				Value: "http://custom-collector.observability.svc.cluster.local:4318/v1/traces",
			}},
		},
	}

	reconciler := &KuraInstanceReconciler{
		Client:             fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance).WithStatusSubresource(instance).Build(),
		Scheme:             scheme,
		OTLPTracesEndpoint: "http://k8s-monitoring-alloy-receiver.observability.svc.cluster.local:4318/v1/traces",
	}

	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}); err != nil {
		t.Fatal(err)
	}

	sts := &appsv1.StatefulSet{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		t.Fatal(err)
	}

	container := sts.Spec.Template.Spec.Containers[0]
	otlpEnvCount := 0
	for _, envVar := range container.Env {
		if envVar.Name != otlpTracesEndpointEnvVar {
			continue
		}
		otlpEnvCount++
		if envVar.Value != "http://custom-collector.observability.svc.cluster.local:4318/v1/traces" {
			t.Fatalf("expected explicit OTLP traces endpoint to be preserved, got %q", envVar.Value)
		}
	}
	if otlpEnvCount != 1 {
		t.Fatalf("expected exactly one %s env var, got %d", otlpTracesEndpointEnvVar, otlpEnvCount)
	}
}

func TestKuraInstanceReconcileSkipsGRPCWhenHostUnset(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-1", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle: "tuist",
			TenantID:      "tuist",
			Region:        "eu",
			Image:         "ghcr.io/tuist/kura:0.5.2",
			PublicHost:    "tuist-eu-1.kura.tuist.dev",
		},
	}

	reconciler := &KuraInstanceReconciler{
		Client:            fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance).WithStatusSubresource(instance).Build(),
		Scheme:            scheme,
		GRPCClusterIssuer: "letsencrypt-prod",
	}

	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}); err != nil {
		t.Fatal(err)
	}

	grpcService := &corev1.Service{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: grpcServiceName(instance), Namespace: instance.Namespace}, grpcService); !apierrors.IsNotFound(err) {
		t.Fatalf("expected no legacy gRPC LoadBalancer Service when grpcPublicHost is unset, got %v", err)
	}
	grpcIngress := &networkingv1.Ingress{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: grpcServiceName(instance), Namespace: instance.Namespace}, grpcIngress); !apierrors.IsNotFound(err) {
		t.Fatalf("expected no gRPC Ingress when grpcPublicHost is unset, got %v", err)
	}
}

func TestKuraInstanceReconcilePreservesExistingStatefulSetVolumeClaimTemplateAndExpandsPVCs(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	replicas := int32(2)
	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-1", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle: "tuist",
			TenantID:      "tuist",
			Region:        "eu",
			Image:         "ghcr.io/tuist/kura:0.5.3",
			Replicas:      &replicas,
			StorageSize:   "200Gi",
		},
	}
	legacyInstance := instance.DeepCopy()
	legacyInstance.Spec.Image = "ghcr.io/tuist/kura:0.5.2"
	legacyInstance.Spec.StorageSize = "20Gi"
	sts := &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace},
		Spec: appsv1.StatefulSetSpec{
			Replicas:             &replicas,
			Selector:             &metav1.LabelSelector{MatchLabels: selectorLabels(instance)},
			Template:             podTemplate(legacyInstance, "", "production", ""),
			VolumeClaimTemplates: []corev1.PersistentVolumeClaim{dataVolumeClaim(legacyInstance)},
		},
	}
	pvc0 := dataPersistentVolumeClaim(instance, 0, "20Gi")
	pvc1 := dataPersistentVolumeClaim(instance, 1, "20Gi")

	reconciler := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().
			WithScheme(scheme).
			WithObjects(instance, sts, pvc0, pvc1).
			WithStatusSubresource(instance).
			Build(),
		Scheme: scheme,
	}

	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}); err != nil {
		t.Fatal(err)
	}

	updatedSts := &appsv1.StatefulSet{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, updatedSts); err != nil {
		t.Fatal(err)
	}
	if got := updatedSts.Spec.Template.Spec.Containers[0].Image; got != "ghcr.io/tuist/kura:0.5.3" {
		t.Fatalf("expected StatefulSet pod template to be updated, got %q", got)
	}
	if got := updatedSts.Spec.VolumeClaimTemplates[0].Spec.Resources.Requests.Storage().String(); got != "20Gi" {
		t.Fatalf("expected existing StatefulSet PVC template to be preserved, got %q", got)
	}

	for _, name := range []string{pvc0.Name, pvc1.Name} {
		pvc := &corev1.PersistentVolumeClaim{}
		if err := reconciler.Get(ctx, types.NamespacedName{Name: name, Namespace: instance.Namespace}, pvc); err != nil {
			t.Fatal(err)
		}
		if got := pvc.Spec.Resources.Requests.Storage().String(); got != "200Gi" {
			t.Fatalf("expected PVC %s to expand to 200Gi, got %q", name, got)
		}
	}
}

func TestKuraInstanceReconcileDoesNotShrinkPVCs(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	replicas := int32(1)
	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-1", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle: "tuist",
			TenantID:      "tuist",
			Region:        "eu",
			Image:         "ghcr.io/tuist/kura:0.5.3",
			Replicas:      &replicas,
			StorageSize:   "20Gi",
		},
	}
	stsInstance := instance.DeepCopy()
	stsInstance.Spec.StorageSize = "200Gi"
	sts := &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace},
		Spec: appsv1.StatefulSetSpec{
			Replicas:             &replicas,
			Selector:             &metav1.LabelSelector{MatchLabels: selectorLabels(instance)},
			Template:             podTemplate(stsInstance, "", "production", ""),
			VolumeClaimTemplates: []corev1.PersistentVolumeClaim{dataVolumeClaim(stsInstance)},
		},
	}
	pvc := dataPersistentVolumeClaim(instance, 0, "200Gi")

	reconciler := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().
			WithScheme(scheme).
			WithObjects(instance, sts, pvc).
			WithStatusSubresource(instance).
			Build(),
		Scheme: scheme,
	}

	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}); err != nil {
		t.Fatal(err)
	}

	updatedPVC := &corev1.PersistentVolumeClaim{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: pvc.Name, Namespace: pvc.Namespace}, updatedPVC); err != nil {
		t.Fatal(err)
	}
	if got := updatedPVC.Spec.Resources.Requests.Storage().String(); got != "200Gi" {
		t.Fatalf("expected PVC not to shrink, got %q", got)
	}
}

func TestKuraInstanceSpecSupportsLocalWorkloadOverrides(t *testing.T) {
	replicas := int32(1)
	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-local-controller", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle: "tuist",
			TenantID:      "tuist",
			Region:        "local-controller",
			Image:         "ghcr.io/tuist/kura:0.5.2",
			Replicas:      &replicas,
			NodeSelector:  map[string]string{"kubernetes.io/os": "linux"},
			StorageSize:   "10Gi",
		},
	}

	stsTemplate := podTemplate(instance, "", "production", "")
	if got := stsTemplate.Spec.NodeSelector["kubernetes.io/os"]; got != "linux" {
		t.Fatalf("expected local node selector, got %q", got)
	}
	if _, ok := stsTemplate.Spec.NodeSelector["node.cluster.x-k8s.io/pool"]; ok {
		t.Fatalf("expected custom node selector to replace managed default")
	}

	pvc := dataVolumeClaim(instance)
	if got := pvc.Spec.Resources.Requests.Storage().String(); got != "10Gi" {
		t.Fatalf("expected local PVC size, got %q", got)
	}
}

func dataPersistentVolumeClaim(instance *kurav1alpha1.KuraInstance, ordinal int, storage string) *corev1.PersistentVolumeClaim {
	return &corev1.PersistentVolumeClaim{
		ObjectMeta: metav1.ObjectMeta{
			Name:      fmt.Sprintf("data-%s-%d", instance.Name, ordinal),
			Namespace: instance.Namespace,
			Labels:    labels(instance),
		},
		Spec: corev1.PersistentVolumeClaimSpec{
			AccessModes: []corev1.PersistentVolumeAccessMode{corev1.ReadWriteOncePod},
			Resources: corev1.VolumeResourceRequirements{
				Requests: corev1.ResourceList{corev1.ResourceStorage: resource.MustParse(storage)},
			},
		},
	}
}

func TestRolloutStatusRequiresUpdatedReadyReplicas(t *testing.T) {
	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-central-1", Generation: 2},
		Spec: kurav1alpha1.KuraInstanceSpec{
			Image: "ghcr.io/tuist/kura:0.5.3",
		},
		Status: kurav1alpha1.KuraInstanceStatus{
			ObservedImage: "ghcr.io/tuist/kura:0.5.2",
		},
	}
	sts := &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Generation: 2},
		Status: appsv1.StatefulSetStatus{
			ObservedGeneration: 2,
			ReadyReplicas:      3,
			UpdatedReplicas:    1,
			CurrentRevision:    "kura-abc",
			UpdateRevision:     "kura-def",
		},
	}

	status := rolloutStatusFromStatefulSet(instance, sts)

	if status.phase != "Pending" {
		t.Fatalf("expected rollout to remain pending, got %q", status.phase)
	}
	if status.observedImage != "ghcr.io/tuist/kura:0.5.2" {
		t.Fatalf("expected observed image to stay on previous image, got %q", status.observedImage)
	}
}

func TestRolloutStatusMarksReadyOnlyForCurrentRevision(t *testing.T) {
	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-central-1", Generation: 2},
		Spec: kurav1alpha1.KuraInstanceSpec{
			Image: "ghcr.io/tuist/kura:0.5.3",
		},
		Status: kurav1alpha1.KuraInstanceStatus{
			ObservedImage: "ghcr.io/tuist/kura:0.5.2",
		},
	}
	sts := &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Generation: 2},
		Status: appsv1.StatefulSetStatus{
			ObservedGeneration: 2,
			ReadyReplicas:      3,
			UpdatedReplicas:    3,
			CurrentRevision:    "kura-def",
			UpdateRevision:     "kura-def",
		},
	}

	status := rolloutStatusFromStatefulSet(instance, sts)

	if status.phase != "Ready" {
		t.Fatalf("expected rollout to be ready, got %q", status.phase)
	}
	if status.observedImage != "ghcr.io/tuist/kura:0.5.3" {
		t.Fatalf("expected observed image to advance, got %q", status.observedImage)
	}
}

func containsString(values []string, needle string) bool {
	for _, value := range values {
		if value == needle {
			return true
		}
	}
	return false
}

func containsExtKeyUsage(values []x509.ExtKeyUsage, needle x509.ExtKeyUsage) bool {
	for _, value := range values {
		if value == needle {
			return true
		}
	}
	return false
}

func cloneSecretData(data map[string][]byte) map[string][]byte {
	clone := make(map[string][]byte, len(data))
	for key, value := range data {
		clone[key] = bytes.Clone(value)
	}
	return clone
}

func secretDataEqual(left, right map[string][]byte) bool {
	if len(left) != len(right) {
		return false
	}
	for key, leftValue := range left {
		rightValue, ok := right[key]
		if !ok || !bytes.Equal(leftValue, rightValue) {
			return false
		}
	}
	return true
}

func kuraPod(instanceName, namespace string, ordinal int, ready bool) *corev1.Pod {
	return kuraPodCreatedAt(instanceName, namespace, ordinal, ready, time.Time{})
}

func kuraPodCreatedAt(instanceName, namespace string, ordinal int, ready bool, createdAt time.Time) *corev1.Pod {
	status := corev1.ConditionFalse
	if ready {
		status = corev1.ConditionTrue
	}
	podName := fmt.Sprintf("%s-%d", instanceName, ordinal)
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      podName,
			Namespace: namespace,
			Labels: map[string]string{
				"app.kubernetes.io/name":             "kura",
				"app.kubernetes.io/instance":         instanceName,
				"statefulset.kubernetes.io/pod-name": podName,
			},
		},
		Status: corev1.PodStatus{
			Conditions: []corev1.PodCondition{{Type: corev1.PodReady, Status: status}},
		},
	}
	if !createdAt.IsZero() {
		pod.CreationTimestamp = metav1.NewTime(createdAt)
	}
	return pod
}

func TestChoosePrimaryPod(t *testing.T) {
	const name = "kura-tuist-eu-1"
	type podSpec struct {
		ordinal int
		ready   bool
	}
	cases := []struct {
		title   string
		current string
		pods    []podSpec
		want    string
	}{
		{"defaults to ordinal 0 before any pod is ready", "", nil, name + "-0"},
		{"picks the lowest ready ordinal", "", []podSpec{{0, true}, {1, true}, {2, true}}, name + "-0"},
		{"sticks to the current primary while it stays ready", name + "-1", []podSpec{{0, true}, {1, true}, {2, true}}, name + "-1"},
		{"fails over to the lowest ready pod when the current primary is unready", name + "-0", []podSpec{{0, false}, {1, true}, {2, true}}, name + "-1"},
		{"keeps the current primary when nothing is ready", name + "-1", []podSpec{{0, false}, {1, false}}, name + "-1"},
		{"orders ordinals numerically, not lexically", "", []podSpec{{2, true}, {10, true}}, name + "-2"},
	}

	for _, tc := range cases {
		t.Run(tc.title, func(t *testing.T) {
			pods := make([]corev1.Pod, 0, len(tc.pods))
			for _, spec := range tc.pods {
				pods = append(pods, *kuraPod(name, "kura", spec.ordinal, spec.ready))
			}
			if got := choosePrimaryPod(tc.current, name, pods, nil); got != tc.want {
				t.Fatalf("choosePrimaryPod(%q) = %q, want %q", tc.current, got, tc.want)
			}
		})
	}
}

func TestChoosePrimaryPodUsesRuntimeRoutability(t *testing.T) {
	const name = "kura-tuist-eu-1"
	pods := []corev1.Pod{
		*kuraPod(name, "kura", 0, true),
		*kuraPod(name, "kura", 1, true),
		*kuraPod(name, "kura", 2, true),
	}
	routable := map[string]bool{
		name + "-0": true,
		name + "-1": false,
		name + "-2": true,
	}

	if got := choosePrimaryPod(name+"-1", name, pods, routable); got != name+"-0" {
		t.Fatalf("expected runtime-unhealthy primary to fail over to lowest routable pod, got %q", got)
	}
}

func TestPrimaryPodHealthIgnoresFreshPodsWhenReplicated(t *testing.T) {
	const name = "kura-tuist-eu-1"
	now := time.Now()
	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "kura"},
		Spec:       kurav1alpha1.KuraInstanceSpec{Replicas: ptr(int32(3))},
	}
	pods := []corev1.Pod{
		*kuraPodCreatedAt(name, "kura", 0, true, now.Add(-2*time.Minute)),
		*kuraPodCreatedAt(name, "kura", 1, true, now.Add(-30*time.Minute)),
		*kuraPodCreatedAt(name, "kura", 2, true, now.Add(-30*time.Minute)),
	}
	reconciler := &KuraInstanceReconciler{
		RuntimeStatusClient: fakeRuntimeStatusClient{
			statuses: map[string]runtimeStatus{
				name + "-0": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2},
				name + "-1": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2},
				name + "-2": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2},
			},
		},
	}

	routable := reconciler.primaryPodHealth(context.Background(), instance, pods)
	if routable[name+"-0"] {
		t.Fatal("expected fresh pod to be excluded from primary routing")
	}
	if !routable[name+"-1"] || !routable[name+"-2"] {
		t.Fatalf("expected older pods to stay routable, got %v", routable)
	}
	if got := choosePrimaryPod(name+"-0", name, pods, routable); got != name+"-1" {
		t.Fatalf("expected fresh current primary to fail over to an older routable pod, got %q", got)
	}
}

func TestRuntimeStatusRoutable(t *testing.T) {
	routable := runtimeStatus{Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2}
	if !runtimeStatusRoutable(routable, 3) {
		t.Fatal("expected serving pod with a peer to be routable")
	}

	isolated := runtimeStatus{Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 1}
	if runtimeStatusRoutable(isolated, 3) {
		t.Fatal("expected isolated three-replica pod to be unroutable")
	}

	singleReplica := runtimeStatus{Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 1}
	if !runtimeStatusRoutable(singleReplica, 1) {
		t.Fatal("expected single-replica pod to be routable with one ring member")
	}
}

func TestKuraInstanceReconcilePinsPublicBackendServiceToPrimaryPod(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-1", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle:    "tuist",
			TenantID:         "tuist",
			Region:           "eu",
			Image:            "ghcr.io/tuist/kura:0.5.2",
			PublicHost:       "tuist-eu-1.kura.tuist.dev",
			GRPCPublicHost:   "grpc.tuist-eu-1.kura.tuist.dev",
			StorageClassName: "hcloud-volumes",
		},
	}
	sharedSecret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: sharedSecretsName, Namespace: instance.Namespace, ResourceVersion: "1"},
	}
	client := fake.NewClientBuilder().WithScheme(scheme).WithStatusSubresource(instance, &corev1.Pod{}).WithObjects(
		instance,
		sharedSecret,
		kuraPod(instance.Name, instance.Namespace, 0, true),
		kuraPod(instance.Name, instance.Namespace, 1, true),
		kuraPod(instance.Name, instance.Namespace, 2, true),
	).Build()
	reconciler := &KuraInstanceReconciler{
		Client: client,
		Scheme: scheme,
		RuntimeStatusClient: fakeRuntimeStatusClient{
			statuses: map[string]runtimeStatus{
				instance.Name + "-0": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2},
				instance.Name + "-1": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2},
				instance.Name + "-2": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2},
			},
		},
	}

	req := ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}
	if _, err := reconciler.Reconcile(ctx, req); err != nil {
		t.Fatal(err)
	}

	assertServiceRoutesTo(t, reconciler, instance.Name, instance.Namespace, instance.Name+"-0")

	setPodReady(t, reconciler, instance.Name+"-0", instance.Namespace, false)
	if _, err := reconciler.Reconcile(ctx, req); err != nil {
		t.Fatal(err)
	}
	assertServiceRoutesTo(t, reconciler, instance.Name, instance.Namespace, instance.Name+"-1")

	setPodReady(t, reconciler, instance.Name+"-0", instance.Namespace, true)
	if _, err := reconciler.Reconcile(ctx, req); err != nil {
		t.Fatal(err)
	}
	assertServiceRoutesTo(t, reconciler, instance.Name, instance.Namespace, instance.Name+"-1")
}

func TestKuraInstanceReconcileFailsOverFromRuntimeUnroutablePrimary(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-eu-1", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle:    "tuist",
			TenantID:         "tuist",
			Region:           "eu",
			Image:            "ghcr.io/tuist/kura:0.5.2",
			PublicHost:       "tuist-eu-1.kura.tuist.dev",
			GRPCPublicHost:   "grpc.tuist-eu-1.kura.tuist.dev",
			StorageClassName: "hcloud-volumes",
		},
	}
	sharedSecret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: sharedSecretsName, Namespace: instance.Namespace, ResourceVersion: "1"},
	}
	publicService := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace},
		Spec: corev1.ServiceSpec{
			Selector: primaryServiceSelector(instance, instance.Name+"-1"),
		},
	}
	client := fake.NewClientBuilder().WithScheme(scheme).WithStatusSubresource(instance, &corev1.Pod{}).WithObjects(
		instance,
		sharedSecret,
		publicService,
		kuraPod(instance.Name, instance.Namespace, 0, true),
		kuraPod(instance.Name, instance.Namespace, 1, true),
		kuraPod(instance.Name, instance.Namespace, 2, true),
	).Build()
	reconciler := &KuraInstanceReconciler{
		Client: client,
		Scheme: scheme,
		RuntimeStatusClient: fakeRuntimeStatusClient{
			statuses: map[string]runtimeStatus{
				instance.Name + "-0": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2},
				instance.Name + "-1": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 1},
				instance.Name + "-2": {Ready: true, State: "serving", WriterLockOwned: true, RingMembers: 2},
			},
		},
	}

	req := ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}
	if _, err := reconciler.Reconcile(ctx, req); err != nil {
		t.Fatal(err)
	}

	assertServiceRoutesTo(t, reconciler, instance.Name, instance.Namespace, instance.Name+"-0")
}

func assertServiceRoutesTo(t *testing.T, r *KuraInstanceReconciler, name, namespace, wantPod string) {
	t.Helper()
	service := &corev1.Service{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: name, Namespace: namespace}, service); err != nil {
		t.Fatalf("get service %s: %v", name, err)
	}
	if got := service.Spec.Selector[podNameLabel]; got != wantPod {
		t.Fatalf("expected service %s to route to %q, got %q", name, wantPod, got)
	}
	if got := service.Spec.Selector["app.kubernetes.io/instance"]; got != name && service.Spec.Selector["app.kubernetes.io/name"] != "kura" {
		t.Fatalf("expected service %s to keep the instance selector labels, got %v", name, service.Spec.Selector)
	}
}

func volumeByName(volumes []corev1.Volume, name string) *corev1.Volume {
	for i := range volumes {
		if volumes[i].Name == name {
			return &volumes[i]
		}
	}
	return nil
}

func setPodReady(t *testing.T, r *KuraInstanceReconciler, name, namespace string, ready bool) {
	t.Helper()
	pod := &corev1.Pod{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: name, Namespace: namespace}, pod); err != nil {
		t.Fatalf("get pod %s: %v", name, err)
	}
	status := corev1.ConditionFalse
	if ready {
		status = corev1.ConditionTrue
	}
	pod.Status.Conditions = []corev1.PodCondition{{Type: corev1.PodReady, Status: status}}
	if err := r.Status().Update(context.Background(), pod); err != nil {
		t.Fatalf("update pod %s: %v", name, err)
	}
}

type fakeRuntimeStatusClient struct {
	statuses map[string]runtimeStatus
	err      error
}

func (c fakeRuntimeStatusClient) Status(_ context.Context, pod corev1.Pod) (runtimeStatus, error) {
	if c.err != nil {
		return runtimeStatus{}, c.err
	}
	status, ok := c.statuses[pod.Name]
	if !ok {
		return runtimeStatus{}, fmt.Errorf("missing fake status for %s", pod.Name)
	}
	return status, nil
}

func TestKuraInstanceReconcileExposesNodePortDataPlane(t *testing.T) {
	ctx := context.Background()
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}

	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-scw-fr-par", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle:    "tuist",
			TenantID:         "tuist",
			Region:           "scw-fr-par-runners",
			Image:            "ghcr.io/tuist/kura:0.5.2",
			StorageClassName: "scw-bssd",
			Private:          true,
			ExposeNodePort:   true,
			ClientCIDRs:      []string{"172.16.0.0/22"},
			PodAnnotations:   map[string]string{"kubernetes.io/egress-bandwidth": "500M"},
			NodeSelector:     map[string]string{"node.cluster.x-k8s.io/pool": "kura-scw-fr-par"},
		},
	}
	sharedSecret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: sharedSecretsName, Namespace: instance.Namespace, ResourceVersion: "1"},
	}
	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{Name: "scw-node-1", Labels: map[string]string{"tuist.dev/pn-ipv4": "172.16.0.2"}},
	}
	pod := kuraPod(instance.Name, instance.Namespace, 0, true)
	pod.Spec.NodeName = node.Name

	client := fake.NewClientBuilder().WithScheme(scheme).WithStatusSubresource(instance, &corev1.Pod{}).WithObjects(
		instance,
		sharedSecret,
		node,
		pod,
	).Build()
	reconciler := &KuraInstanceReconciler{
		Client: client,
		Scheme: scheme,
		RuntimeStatusClient: fakeRuntimeStatusClient{
			statuses: map[string]runtimeStatus{
				instance.Name + "-0": {Ready: true, State: "serving", WriterLockOwned: true},
			},
		},
	}

	req := ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}
	if _, err := reconciler.Reconcile(ctx, req); err != nil {
		t.Fatal(err)
	}

	service := &corev1.Service{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name + "-external", Namespace: instance.Namespace}, service); err != nil {
		t.Fatalf("get external service: %v", err)
	}
	if service.Spec.Type != corev1.ServiceTypeNodePort {
		t.Fatalf("expected NodePort service, got %q", service.Spec.Type)
	}
	if service.Spec.ExternalTrafficPolicy != corev1.ServiceExternalTrafficPolicyLocal {
		t.Fatalf("expected externalTrafficPolicy Local, got %q", service.Spec.ExternalTrafficPolicy)
	}
	if len(service.Spec.Ports) != 2 {
		t.Fatalf("expected http+grpc only on the external service, got %v", service.Spec.Ports)
	}
	if got := service.Spec.Selector[podNameLabel]; got != instance.Name+"-0" {
		t.Fatalf("expected external service pinned to primary pod, got %q", got)
	}

	// The fake client never allocates NodePorts; simulate the API
	// server so the second reconcile must preserve them.
	for i := range service.Spec.Ports {
		switch service.Spec.Ports[i].Name {
		case "http":
			service.Spec.Ports[i].NodePort = 30080
		case "grpc":
			service.Spec.Ports[i].NodePort = 30051
		}
	}
	if err := reconciler.Update(ctx, service); err != nil {
		t.Fatal(err)
	}
	if _, err := reconciler.Reconcile(ctx, req); err != nil {
		t.Fatal(err)
	}

	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name + "-external", Namespace: instance.Namespace}, service); err != nil {
		t.Fatal(err)
	}
	allocated := map[string]int32{}
	for _, port := range service.Spec.Ports {
		allocated[port.Name] = port.NodePort
	}
	if allocated["http"] != 30080 || allocated["grpc"] != 30051 {
		t.Fatalf("expected allocated NodePorts preserved across reconciles, got %v", allocated)
	}

	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, instance); err != nil {
		t.Fatal(err)
	}
	if instance.Status.NodeAddress != "172.16.0.2" {
		t.Fatalf("expected status.nodeAddress from the node's pn-ipv4 label, got %q", instance.Status.NodeAddress)
	}
	if instance.Status.NodePortHTTP != 30080 || instance.Status.NodePortGRPC != 30051 {
		t.Fatalf("expected status NodePorts 30080/30051, got %d/%d", instance.Status.NodePortHTTP, instance.Status.NodePortGRPC)
	}

	policy := &networkingv1.NetworkPolicy{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, policy); err != nil {
		t.Fatal(err)
	}
	foundIPBlock := false
	for _, rule := range policy.Spec.Ingress {
		for _, peer := range rule.From {
			if peer.IPBlock != nil && peer.IPBlock.CIDR == "172.16.0.0/22" {
				foundIPBlock = true
			}
		}
	}
	if !foundIPBlock {
		t.Fatalf("expected NetworkPolicy ipBlock rule for client CIDR, got %+v", policy.Spec.Ingress)
	}

	sts := &appsv1.StatefulSet{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		t.Fatal(err)
	}
	annotations := sts.Spec.Template.Annotations
	if annotations["kubernetes.io/egress-bandwidth"] != "500M" {
		t.Fatalf("expected pod annotation passthrough, got %v", annotations)
	}
	if annotations["prometheus.io/scrape"] != "true" {
		t.Fatalf("expected controller-owned annotations preserved, got %v", annotations)
	}

	instance.Spec.ExposeNodePort = false
	if err := reconciler.Update(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if _, err := reconciler.Reconcile(ctx, req); err != nil {
		t.Fatal(err)
	}
	err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name + "-external", Namespace: instance.Namespace}, &corev1.Service{})
	if !apierrors.IsNotFound(err) {
		t.Fatalf("expected external service deleted when exposure is disabled, got %v", err)
	}
}

func TestKuraInstancePodTemplateRendersTolerations(t *testing.T) {
	ctx := context.Background()
	scheme := meshTestScheme(t)

	instance := &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{Name: "kura-tuist-scw-fr-par", Namespace: "kura"},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle: "tuist",
			TenantID:      "tuist",
			Region:        "scw-fr-par-runners",
			Image:         "ghcr.io/tuist/kura:0.5.2",
			Private:       true,
			NodeSelector:  map[string]string{"node.cluster.x-k8s.io/pool": "kura-scw-fr-par"},
			Tolerations: []corev1.Toleration{{
				Key:      "tuist.dev/runner-cache",
				Operator: corev1.TolerationOpExists,
				Effect:   corev1.TaintEffectNoSchedule,
			}},
		},
	}
	sharedSecret := &corev1.Secret{
		ObjectMeta: metav1.ObjectMeta{Name: sharedSecretsName, Namespace: instance.Namespace, ResourceVersion: "12345"},
	}
	reconciler := &KuraInstanceReconciler{
		Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, sharedSecret).WithStatusSubresource(instance).Build(),
		Scheme: scheme,
	}
	if _, err := reconciler.Reconcile(ctx, ctrl.Request{NamespacedName: types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}}); err != nil {
		t.Fatal(err)
	}

	sts := &appsv1.StatefulSet{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		t.Fatal(err)
	}
	found := false
	for _, tol := range sts.Spec.Template.Spec.Tolerations {
		if tol.Key == "tuist.dev/runner-cache" && tol.Effect == corev1.TaintEffectNoSchedule {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected the runner-cache toleration on the pod template, got %#v", sts.Spec.Template.Spec.Tolerations)
	}
}
