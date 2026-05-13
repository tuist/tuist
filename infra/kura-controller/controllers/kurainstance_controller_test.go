package controllers

import (
	"context"
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	policyv1 "k8s.io/api/policy/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
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

	reconciler := &KuraInstanceReconciler{
		Client:            fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, legacyIngress).WithStatusSubresource(instance).Build(),
		Scheme:            scheme,
		GRPCClusterIssuer: "letsencrypt-prod",
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
		t.Fatalf("expected public Certificate dnsNames to include the public host, got %v", got)
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
	publicMountFound := false
	for _, mount := range container.VolumeMounts {
		if mount.Name == publicTLSVolumeName {
			publicMountFound = true
			break
		}
	}
	if !publicMountFound {
		t.Fatal("expected public TLS secret to be mounted into the kura container")
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
	var tmpVolume *corev1.Volume
	for i := range sts.Spec.Template.Spec.Volumes {
		if sts.Spec.Template.Spec.Volumes[i].Name == "tmp" {
			tmpVolume = &sts.Spec.Template.Spec.Volumes[i]
			break
		}
	}
	if tmpVolume == nil || tmpVolume.EmptyDir == nil || tmpVolume.EmptyDir.SizeLimit == nil {
		t.Fatal("expected tmp emptyDir to declare a sizeLimit")
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

	stsTemplate := podTemplate(instance)
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
