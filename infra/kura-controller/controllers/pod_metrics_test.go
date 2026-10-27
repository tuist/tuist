package controllers

import (
	"context"
	"reflect"
	"testing"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	metricsv1beta1 "k8s.io/metrics/pkg/apis/metrics/v1beta1"
	metricsfake "k8s.io/metrics/pkg/client/clientset/versioned/fake"
)

func TestPodCPUUsageExcludesDiagnosticsAndMissingRuntime(t *testing.T) {
	usage := func(name, cpu string) metricsv1beta1.ContainerMetrics {
		return metricsv1beta1.ContainerMetrics{Name: name, Usage: corev1.ResourceList{corev1.ResourceCPU: resource.MustParse(cpu)}}
	}
	fake := metricsfake.NewSimpleClientset()
	for _, item := range []*metricsv1beta1.PodMetrics{
		{ObjectMeta: metav1.ObjectMeta{Name: "both", Namespace: "kura"}, Containers: []metricsv1beta1.ContainerMetrics{usage("connectivity-probe", "50m"), usage("kura", "12m")}},
		{ObjectMeta: metav1.ObjectMeta{Name: "probe-only", Namespace: "kura"}, Containers: []metricsv1beta1.ContainerMetrics{usage("connectivity-probe", "50m")}},
		{ObjectMeta: metav1.ObjectMeta{Name: "idle", Namespace: "kura"}, Containers: []metricsv1beta1.ContainerMetrics{usage("kura", "0")}},
	} {
		if err := fake.Tracker().Create(metricsv1beta1.SchemeGroupVersion.WithResource("pods"), item, "kura"); err != nil {
			t.Fatal(err)
		}
	}
	client := &metricsServerClient{client: fake}
	got, err := client.PodCPUMilli(context.Background(), "kura", nil)
	if err != nil {
		t.Fatal(err)
	}
	if !reflect.DeepEqual(got, map[string]int64{"both": 12, "idle": 0}) {
		t.Fatalf("sidecar or missing Kura polluted CPU signal: %v", got)
	}
}
