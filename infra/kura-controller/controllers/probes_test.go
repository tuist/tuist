package controllers

import (
	"context"
	"testing"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

func probeTestInstance() *kurav1alpha1.KuraInstance {
	return &kurav1alpha1.KuraInstance{
		ObjectMeta: metav1.ObjectMeta{
			Name:       "kura-acme-eu-west-1",
			Namespace:  "kura",
			Generation: 7,
			Finalizers: []string{KuraInstanceFinalizer},
		},
		Spec: kurav1alpha1.KuraInstanceSpec{
			AccountHandle:     "acme",
			TenantID:          "acme",
			Region:            "eu-west",
			Image:             "ghcr.io/tuist/kura:0.9.0",
			PublicHost:        "acme-eu-west-1.kura.tuist.dev",
			PublicHostNetwork: true,
			IngressClassName:  "kura-eu-west",
			StorageClassName:  "scw-local-nvme",
			StorageSize:       "16Gi",
			Replicas:          ptr(int32(2)),
			NodeSelector:      map[string]string{"tuist.dev/pool": "kura-eu-west"},
			Tolerations:       []corev1.Toleration{{Key: "tuist.dev/kura", Operator: corev1.TolerationOpExists}},
		},
	}
}

func probeTestReconciler(t *testing.T, objects ...client.Object) *KuraInstanceReconciler {
	t.Helper()
	scheme, mapper := dnsEndpointScheme(t)
	c := fake.NewClientBuilder().WithScheme(scheme).WithRESTMapper(mapper).WithObjects(objects...).Build()
	return &KuraInstanceReconciler{Client: c, APIReader: c, Scheme: scheme}
}

func probeTestStatefulSet(instance *kurav1alpha1.KuraInstance, replicas int32) *appsv1.StatefulSet {
	return &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace},
		Spec:       appsv1.StatefulSetSpec{Replicas: ptr(replicas)},
	}
}

func getProbeTestObject(t *testing.T, r *KuraInstanceReconciler, name string, object client.Object) error {
	t.Helper()
	return r.Get(context.Background(), types.NamespacedName{Name: name, Namespace: "kura"}, object)
}

// Probe timings are part of the pod template, so changing them rolls every
// instance. They are adopted only when the pods are replaced anyway.
func TestStatefulSetAdoptsFastProbesOnlyWhenItsPodsAreReplacedAnyway(t *testing.T) {
	legacyTemplate := func(instance *kurav1alpha1.KuraInstance, image string) corev1.PodTemplateSpec {
		template := podTemplate(instance, "", "", "", false, false, false)
		template.Spec.Containers[0].Image = image
		return template
	}
	for _, tc := range []struct {
		name          string
		existing      func(*kurav1alpha1.KuraInstance) *appsv1.StatefulSet
		wantFastProbe bool
	}{
		{name: "new StatefulSet", existing: func(*kurav1alpha1.KuraInstance) *appsv1.StatefulSet { return nil }, wantFastProbe: true},
		{name: "running pods on the same image", wantFastProbe: false, existing: func(instance *kurav1alpha1.KuraInstance) *appsv1.StatefulSet {
			sts := probeTestStatefulSet(instance, 2)
			sts.Spec.Template = legacyTemplate(instance, instance.Spec.Image)
			return sts
		}},
		{name: "image change", wantFastProbe: true, existing: func(instance *kurav1alpha1.KuraInstance) *appsv1.StatefulSet {
			sts := probeTestStatefulSet(instance, 2)
			sts.Spec.Template = legacyTemplate(instance, "ghcr.io/tuist/kura:0.8.0")
			return sts
		}},
		{name: "already on fast probes", wantFastProbe: true, existing: func(instance *kurav1alpha1.KuraInstance) *appsv1.StatefulSet {
			sts := probeTestStatefulSet(instance, 2)
			sts.Spec.Template = podTemplate(instance, "", "", "", false, false, true)
			return sts
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			instance := probeTestInstance()
			objects := []client.Object{instance}
			if sts := tc.existing(instance); sts != nil {
				objects = append(objects, sts)
			}
			r := probeTestReconciler(t, objects...)

			if err := r.reconcileStatefulSet(context.Background(), instance); err != nil {
				t.Fatal(err)
			}

			sts := &appsv1.StatefulSet{}
			if err := getProbeTestObject(t, r, instance.Name, sts); err != nil {
				t.Fatal(err)
			}
			readiness := sts.Spec.Template.Spec.Containers[0].ReadinessProbe
			if got := readiness.PeriodSeconds == 1; got != tc.wantFastProbe {
				t.Fatalf("fast readiness probe = %v, want %v (%#v)", got, tc.wantFastProbe, readiness)
			}
		})
	}
}

// Faster probes must not change how long Kubernetes waits before giving up on
// a starting pod or before taking a serving pod out of its Service, whether the
// probe fails at once (connection refused) or hangs until its timeout. The
// kubelet runs a pod's probes one at a time, so a hanging probe fails once per
// period or per timeout, whichever is longer.
func TestFastProbesKeepTheirBudgets(t *testing.T) {
	threshold := func(probe *corev1.Probe) int32 {
		if probe.FailureThreshold == 0 {
			return 3
		}
		return probe.FailureThreshold
	}
	failingBudget := func(probe *corev1.Probe) time.Duration {
		return time.Duration(probe.PeriodSeconds*threshold(probe)) * time.Second
	}
	hangingBudget := func(probe *corev1.Probe) time.Duration {
		return time.Duration(max(probe.PeriodSeconds, probe.TimeoutSeconds)*threshold(probe)) * time.Second
	}

	for name, probes := range map[string][2]*corev1.Probe{
		"startup":   {startupProbe(true), startupProbe(false)},
		"readiness": {readinessProbe(true), readinessProbe(false)},
	} {
		fast, legacy := probes[0], probes[1]
		if got, want := failingBudget(fast), failingBudget(legacy); got != want {
			t.Fatalf("%s budget for a failing probe = %v, want %v", name, got, want)
		}
		if got, want := hangingBudget(fast), hangingBudget(legacy); got != want {
			t.Fatalf("%s budget for a hanging probe = %v, want %v", name, got, want)
		}
	}
	if got := failingBudget(startupProbe(true)); got != 300*time.Second {
		t.Fatalf("startup budget = %v, want 300s", got)
	}
	fastReadiness := readinessProbe(true)
	fastStartup := startupProbe(true)
	if fastReadiness.InitialDelaySeconds != 0 || fastReadiness.PeriodSeconds != 1 || fastStartup.PeriodSeconds != 1 {
		t.Fatalf("expected 1s probes with no initial delay, got readiness %#v startup %#v", fastReadiness, fastStartup)
	}
	if fastReadiness.HTTPGet.Path != "/ready" || fastStartup.HTTPGet.Path != "/up" {
		t.Fatalf("probe endpoints must not change, got readiness %q startup %q", fastReadiness.HTTPGet.Path, fastStartup.HTTPGet.Path)
	}
}

// A pod that is not ready receives no traffic, so which port the gRPC Ingress
// names does not matter until one is. Re-deriving it from no evidence moved an
// instance whose pods were all restarting to the co-hosted port and back, and
// every change is an nginx reload the regional gateway rate-limits, holding back
// the ready endpoint.
func TestReconcileGRPCIngressKeepsItsPortWhileNoPodIsReady(t *testing.T) {
	ctx := context.Background()
	instance := probeTestInstance()
	r := probeTestReconciler(t, instance)
	backendPort := func() string {
		t.Helper()
		ingress := &networkingv1.Ingress{}
		if err := getProbeTestObject(t, r, grpcServiceName(instance), ingress); err != nil {
			t.Fatal(err)
		}
		return ingress.Spec.Rules[0].HTTP.Paths[0].Backend.Service.Port.Name
	}
	primary := instance.Name + "-0"

	if err := r.reconcileGRPCIngress(ctx, instance, nil, nil, primary); err != nil {
		t.Fatal(err)
	}
	if got := backendPort(); got != "http" {
		t.Fatalf("a new Ingress with no pod to vouch for the gateway port starts on the co-hosted port, got %q", got)
	}

	serving := runtimeStatus{Ready: true, State: "serving", GatewayGRPCPort: gatewayGRPCPort}
	servingPods := []corev1.Pod{gatewayGRPCTestPod(primary, true, true), gatewayGRPCTestPod(instance.Name+"-1", true, true)}
	samples := map[string]runtimeStatus{primary: serving, instance.Name + "-1": serving}
	if err := r.reconcileGRPCIngress(ctx, instance, servingPods, samples, primary); err != nil {
		t.Fatal(err)
	}
	if got := backendPort(); got != "grpc" {
		t.Fatalf("expected the gateway port once the pods serve it, got %q", got)
	}

	for _, pods := range [][]corev1.Pod{
		nil,
		{gatewayGRPCTestPod(primary, false, true), gatewayGRPCTestPod(instance.Name+"-1", false, true)},
	} {
		if err := r.reconcileGRPCIngress(ctx, instance, pods, nil, primary); err != nil {
			t.Fatal(err)
		}
		if got := backendPort(); got != "grpc" {
			t.Fatalf("expected the port to stay while no pod is ready (%d pods), got %q", len(pods), got)
		}
	}
}
