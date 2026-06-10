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
	if service.Spec.Type != corev1.ServiceTypeLoadBalancer {
		t.Fatalf("expected public service to be a LoadBalancer, got %q", service.Spec.Type)
	}
	if service.Spec.ExternalTrafficPolicy != corev1.ServiceExternalTrafficPolicyLocal {
		t.Fatalf("expected local external traffic policy, got %q", service.Spec.ExternalTrafficPolicy)
	}
	if got := service.Spec.Ports[0].Port; got != httpsPort {
		t.Fatalf("expected public service port %d, got %d", httpsPort, got)
	}
	if got := service.Spec.Ports[0].TargetPort.StrVal; got != "https" {
		t.Fatalf("expected public service to target the TLS-terminating https port, got %q", got)
	}
	if got := service.Annotations["external-dns.alpha.kubernetes.io/hostname"]; got != "tuist-eu-1.kura.tuist.dev" {
		t.Fatalf("expected external-dns hostname, got %q", got)
	}
	if got := service.Annotations["load-balancer.hetzner.cloud/protocol"]; got != "tcp" {
		t.Fatalf("expected Hetzner LB tcp passthrough so Kura terminates TLS, got %q", got)
	}
	if _, ok := service.Annotations["load-balancer.hetzner.cloud/certificate-type"]; ok {
		t.Fatal("expected managed-cert annotations to be dropped now that cert-manager issues the public cert")
	}
	if got := service.Annotations["load-balancer.hetzner.cloud/health-check-protocol"]; got != "tcp" {
		t.Fatalf("expected health check to use TCP against the passthrough NodePort, got %q", got)
	}
	if _, ok := service.Annotations["load-balancer.hetzner.cloud/health-check-port"]; ok {
		t.Fatal("expected health check port annotation to be omitted so Hetzner probes the Service NodePort")
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
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, ingress); !apierrors.IsNotFound(err) {
		t.Fatalf("expected legacy ingress to be deleted, got %v", err)
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
	if env["KURA_PUBLIC_TLS_CERT_PATH"] == "" || env["KURA_PUBLIC_TLS_KEY_PATH"] == "" {
		t.Fatal("expected public TLS env paths to be configured when publicHost is set")
	}
	if got := env["KURA_HTTPS_PORT"]; got == "" {
		t.Fatal("expected KURA_HTTPS_PORT to be set when publicHost is set")
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
	publicMountFound := false
	peerMountFound := false
	for _, mount := range container.VolumeMounts {
		if mount.Name == publicTLSVolumeName {
			publicMountFound = true
		}
		if mount.Name == peerTLSVolumeName && mount.ReadOnly {
			peerMountFound = true
		}
	}
	if !publicMountFound {
		t.Fatal("expected public TLS secret to be mounted into the kura container")
	}
	if !peerMountFound {
		t.Fatal("expected peer mTLS secret to be mounted into the kura container")
	}
	peerSecret := &corev1.Secret{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: peerTLSSecretName(instance), Namespace: instance.Namespace}, peerSecret); err != nil {
		t.Fatalf("expected per-instance peer mTLS Secret to be created: %v", err)
	}
	if !peerTLSSecretDataValid(peerSecret.Data, instance) {
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
	if !publicPortFound {
		t.Fatal("expected https container port to be exposed when publicHost is set")
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
	publicPorts := policy.Spec.Ingress[2].Ports
	if len(policy.Spec.Ingress[2].From) != 0 {
		t.Fatalf("expected public NetworkPolicy rule to allow all sources, got %v", policy.Spec.Ingress[2].From)
	}
	if len(publicPorts) != 2 {
		t.Fatalf("expected public NetworkPolicy rule to expose HTTPS and gRPC, got %d ports", len(publicPorts))
	}
	if got := publicPorts[0].Port.StrVal; got != "https" {
		t.Fatalf("expected public NetworkPolicy rule to expose https, got %q", got)
	}
	if got := publicPorts[1].Port.StrVal; got != "grpc" {
		t.Fatalf("expected public NetworkPolicy rule to expose grpc, got %q", got)
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
	if !peerTLSSecretDataValid(secret.Data, instance) {
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
	validData, err := generatePeerTLSSecretData(instance)
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
	if !peerTLSSecretDataValid(updated.Data, instance) {
		t.Fatal("expected invalid peer TLS material to be regenerated")
	}
	if secretDataEqual(invalidData, updated.Data) {
		t.Fatal("expected regenerated peer TLS material to differ from invalid input")
	}
}

func TestKuraInstanceReconcileCrossRegionPeerGateway(t *testing.T) {
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
			AccountHandle:          "tuist",
			TenantID:               "tuist",
			Region:                 "eu",
			Image:                  "ghcr.io/tuist/kura:0.5.2",
			PeerPublicHost:         "peer.tuist-eu-1.kura.tuist.dev",
			GlobalDiscoveryDNSName: "tuist.kura-peers.tuist.dev",
			PeerTLSSecretName:      "kura-cross-region-peer-tls",
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
	if err := reconciler.Get(ctx, types.NamespacedName{Name: peerServiceName(instance), Namespace: instance.Namespace}, peerService); err != nil {
		t.Fatalf("expected peer LoadBalancer Service to be created: %v", err)
	}
	if peerService.Spec.Type != corev1.ServiceTypeLoadBalancer {
		t.Fatalf("expected peer service to be a LoadBalancer, got %q", peerService.Spec.Type)
	}
	if got := peerService.Spec.Selector[podNameLabel]; got != instance.Name+"-0" {
		t.Fatalf("expected peer service to route to the selected primary pod, got %q", got)
	}
	if got := peerService.Annotations["external-dns.alpha.kubernetes.io/hostname"]; got != "peer.tuist-eu-1.kura.tuist.dev" {
		t.Fatalf("expected peer external-dns hostname, got %q", got)
	}
	if got := peerService.Spec.Ports[0].TargetPort.StrVal; got != "peer" {
		t.Fatalf("expected peer service to target the peer port, got %q", got)
	}

	sts := &appsv1.StatefulSet{}
	if err := reconciler.Get(ctx, types.NamespacedName{Name: instance.Name, Namespace: instance.Namespace}, sts); err != nil {
		t.Fatal(err)
	}
	env := map[string]string{}
	for _, envVar := range sts.Spec.Template.Spec.Containers[0].Env {
		env[envVar.Name] = envVar.Value
	}
	if got := env["KURA_PEER_GATEWAY_URL"]; got != "https://peer.tuist-eu-1.kura.tuist.dev:7443" {
		t.Fatalf("expected peer gateway URL env, got %q", got)
	}
	if got := env["KURA_GLOBAL_DISCOVERY_DNS_NAME"]; got != "tuist.kura-peers.tuist.dev" {
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
	if len(policy.Spec.Ingress) != 4 {
		t.Fatalf("expected NetworkPolicy to include a cross-region peer rule, got %d rules", len(policy.Spec.Ingress))
	}
	if got := policy.Spec.Ingress[3].Ports[0].Port.StrVal; got != "peer" {
		t.Fatalf("expected cross-region NetworkPolicy rule to expose peer port, got %q", got)
	}
}

func TestKuraInstanceReconcilePeerGatewayWithoutSharedTLSDoesNotEnableGlobalDiscovery(t *testing.T) {
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
			AccountHandle:          "tuist",
			TenantID:               "tuist",
			Region:                 "eu",
			Image:                  "ghcr.io/tuist/kura:0.5.2",
			PeerPublicHost:         "peer.tuist-eu-1.kura.tuist.dev",
			GlobalDiscoveryDNSName: "tuist.kura-peers.tuist.dev",
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
	if err := reconciler.Get(ctx, types.NamespacedName{Name: peerServiceName(instance), Namespace: instance.Namespace}, peerService); err != nil {
		t.Fatalf("expected peer LoadBalancer Service to be created: %v", err)
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
	if err := reconciler.Get(ctx, types.NamespacedName{Name: grpcServiceName(instance), Namespace: instance.Namespace}, grpcService); err != nil {
		t.Fatalf("expected grpc LoadBalancer Service to be created: %v", err)
	}
	if grpcService.Spec.Type != corev1.ServiceTypeLoadBalancer {
		t.Fatalf("expected grpc service to be a LoadBalancer, got %q", grpcService.Spec.Type)
	}
	if grpcService.Annotations["load-balancer.hetzner.cloud/protocol"] != "tcp" {
		t.Fatalf("expected Hetzner LB tcp passthrough for gRPC, got %q", grpcService.Annotations["load-balancer.hetzner.cloud/protocol"])
	}
	if got := grpcService.Annotations["load-balancer.hetzner.cloud/health-check-protocol"]; got != "tcp" {
		t.Fatalf("expected gRPC health check to use TCP against the passthrough NodePort, got %q", got)
	}
	if grpcService.Annotations["external-dns.alpha.kubernetes.io/hostname"] != "grpc.tuist-eu-1.kura.tuist.dev" {
		t.Fatalf("expected gRPC external-dns hostname, got %q", grpcService.Annotations["external-dns.alpha.kubernetes.io/hostname"])
	}
	if got := grpcService.Spec.Ports[0].TargetPort.StrVal; got != "grpc" {
		t.Fatalf("expected gRPC LB to target the grpc container port, got %q", got)
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
	if env["KURA_GRPC_TLS_CERT_PATH"] == "" || env["KURA_GRPC_TLS_KEY_PATH"] == "" {
		t.Fatal("expected gRPC TLS env paths to be configured")
	}
	mountFound := false
	for _, mount := range container.VolumeMounts {
		if mount.Name == grpcTLSVolumeName {
			mountFound = true
			break
		}
	}
	if !mountFound {
		t.Fatal("expected gRPC TLS secret to be mounted into the kura container")
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
		t.Fatalf("expected no gRPC LoadBalancer Service when grpcPublicHost is unset, got %v", err)
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

func TestKuraInstanceReconcilePinsPublicServicesToPrimaryPod(t *testing.T) {
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
	assertServiceRoutesTo(t, reconciler, grpcServiceName(instance), instance.Namespace, instance.Name+"-0")

	setPodReady(t, reconciler, instance.Name+"-0", instance.Namespace, false)
	if _, err := reconciler.Reconcile(ctx, req); err != nil {
		t.Fatal(err)
	}
	assertServiceRoutesTo(t, reconciler, instance.Name, instance.Namespace, instance.Name+"-1")
	assertServiceRoutesTo(t, reconciler, grpcServiceName(instance), instance.Namespace, instance.Name+"-1")

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
	grpcService := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: grpcServiceName(instance), Namespace: instance.Namespace},
		Spec: corev1.ServiceSpec{
			Selector: primaryServiceSelector(instance, instance.Name+"-1"),
		},
	}

	client := fake.NewClientBuilder().WithScheme(scheme).WithStatusSubresource(instance, &corev1.Pod{}).WithObjects(
		instance,
		sharedSecret,
		publicService,
		grpcService,
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
	assertServiceRoutesTo(t, reconciler, grpcServiceName(instance), instance.Namespace, instance.Name+"-0")
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
