package controllers

import (
	"context"
	"errors"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/shadow"
)

func shadowFixture() (*tuistv1.RunnerPool, *corev1.Pod, *corev1.Node) {
	pool := newLinuxKataPool("pool", 1, 6)
	pool.Spec.PodCPUMilli = 2000
	pool.Spec.PodMemoryMB = 8192
	pod := newRunnerPod("warm", pool.Spec.Image, corev1.PodPending, pool.Name)
	pod.UID = types.UID("warm-uid")
	pod.Spec.NodeName = "node"
	pod.Labels["tuist.dev/runner"] = "true"
	pod.Spec.Containers = []corev1.Container{{Name: "runner", Image: pool.Spec.Image, Resources: corev1.ResourceRequirements{
		Requests: corev1.ResourceList{corev1.ResourceCPU: resource.MustParse("2"), corev1.ResourceMemory: resource.MustParse("8Gi")},
	}}}
	pod.Status.InitContainerStatuses = []corev1.ContainerStatus{{Name: "poller", State: corev1.ContainerState{Running: &corev1.ContainerStateRunning{}}}}
	node := readyLinuxRunnerNode("node", pool.Spec.FleetSelector)
	node.Labels["kubernetes.io/os"] = "linux"
	return pool, pod, node
}

func TestShadowWarmRunnerFiltering(t *testing.T) {
	for _, tc := range []struct {
		name   string
		mutate func(*tuistv1.RunnerPool, *corev1.Pod, *corev1.Node)
		want   int
	}{
		{"warm Linux init container", func(_ *tuistv1.RunnerPool, _ *corev1.Pod, _ *corev1.Node) {}, 1},
		{"busy", func(_ *tuistv1.RunnerPool, p *corev1.Pod, _ *corev1.Node) {
			p.Labels["tuist.dev/runner-pool-owner"] = "account"
		}, 0},
		{"claimed without owner", func(_ *tuistv1.RunnerPool, p *corev1.Pod, _ *corev1.Node) {
			p.Status.InitContainerStatuses[0].State = corev1.ContainerState{Terminated: &corev1.ContainerStateTerminated{}}
		}, 0},
		{"not booted", func(_ *tuistv1.RunnerPool, p *corev1.Pod, _ *corev1.Node) { p.Status.InitContainerStatuses = nil }, 0},
		{"cordoned", func(_ *tuistv1.RunnerPool, _ *corev1.Pod, n *corev1.Node) { n.Spec.Unschedulable = true }, 0},
		{"pressure", func(_ *tuistv1.RunnerPool, _ *corev1.Pod, n *corev1.Node) {
			n.Status.Conditions = append(n.Status.Conditions, corev1.NodeCondition{Type: corev1.NodeMemoryPressure, Status: corev1.ConditionTrue})
		}, 0},
		{"deleting", func(_ *tuistv1.RunnerPool, p *corev1.Pod, _ *corev1.Node) {
			at := metav1.Now()
			p.DeletionTimestamp = &at
		}, 0},
		{"operator drain", func(_ *tuistv1.RunnerPool, p *corev1.Pod, _ *corev1.Node) {
			p.Labels["tuist.dev/runner-operator-drain"] = "true"
		}, 0},
		{"stale image", func(_ *tuistv1.RunnerPool, p *corev1.Pod, _ *corev1.Node) { p.Spec.Containers[0].Image = "old" }, 0},
		{"changed shape", func(p *tuistv1.RunnerPool, _ *corev1.Pod, _ *corev1.Node) { p.Spec.PodMemoryMB = 16384 }, 0},
		{"different fleet", func(_ *tuistv1.RunnerPool, _ *corev1.Pod, n *corev1.Node) { n.Labels[fleetNodePoolLabel] = "other" }, 0},
		{"reserved for sibling", func(_ *tuistv1.RunnerPool, _ *corev1.Pod, n *corev1.Node) {
			n.Spec.Taints = []corev1.Taint{{Key: "tuist.dev/reserved-for", Value: "other", Effect: corev1.TaintEffectNoSchedule}}
		}, 0},
	} {
		t.Run(tc.name, func(t *testing.T) {
			pool, pod, node := shadowFixture()
			tc.mutate(pool, pod, node)
			rs, ids := shadowRunners([]tuistv1.RunnerPool{*pool}, []corev1.Pod{*pod}, []corev1.Node{*node})
			if len(rs) != tc.want || ids[pod.Name] != string(pod.UID) {
				t.Fatalf("runners=%+v identities=%v", rs, ids)
			}
		})
	}
}

func TestShadowMacHeartbeatAndCacheLocality(t *testing.T) {
	pool, pod, node := shadowFixture()
	pool.Spec.OS = "darwin"
	node.Labels = map[string]string{"kubernetes.io/os": "darwin", "tuist.dev/fleet": pool.Spec.FleetSelector, "tuist.dev/cache-master-42": "true"}
	pod.Status.Phase = corev1.PodRunning
	pod.Status.InitContainerStatuses = nil
	pod.Annotations = map[string]string{guestHeartbeatStateAnnotation: "polling", guestHeartbeatAtAnnotation: time.Now().UTC().Format(time.RFC3339)}
	rs, _ := shadowRunners([]tuistv1.RunnerPool{*pool}, []corev1.Pod{*pod}, []corev1.Node{*node})
	if len(rs) != 1 || rs[0].Platform != "macos" || !rs[0].ResidentAccounts[42] {
		t.Fatalf("%+v", rs)
	}
	pod.Annotations[guestHeartbeatAtAnnotation] = time.Now().Add(-time.Hour).UTC().Format(time.RFC3339)
	if rs, _ := shadowRunners([]tuistv1.RunnerPool{*pool}, []corev1.Pod{*pod}, []corev1.Node{*node}); len(rs) != 0 {
		t.Fatal("stale guest counted as warm")
	}
}

type shadowSourceFunc func(context.Context) (shadow.Snapshot, error)

func (f shadowSourceFunc) Snapshot(ctx context.Context) (shadow.Snapshot, error) { return f(ctx) }

// A Reader-only wrapper proves that collection needs no mutation capability.
type shadowReader struct{ client.Reader }

func TestShadowCollectionIsReadOnlyAndFailsClosed(t *testing.T) {
	pool, pod, node := shadowFixture()
	c := fake.NewClientBuilder().WithScheme(mustScheme(t)).WithObjects(pool, pod, node).Build()
	s := ShadowScheduler{Reader: shadowReader{c}, Namespace: pool.Namespace, Source: shadowSourceFunc(func(context.Context) (shadow.Snapshot, error) {
		return shadow.Snapshot{Version: 1, Complete: true, CapturedAt: time.Now()}, nil
	})}
	_, rs, _, err := s.collect(context.Background())
	if err != nil || len(rs) != 1 {
		t.Fatalf("%+v %v", rs, err)
	}
	var got tuistv1.RunnerPool
	if err := c.Get(context.Background(), client.ObjectKeyFromObject(pool), &got); err != nil {
		t.Fatal(err)
	}
	if got.Spec.Replicas != pool.Spec.Replicas {
		t.Fatal("shadow changed replicas")
	}
	s.Source = shadowSourceFunc(func(context.Context) (shadow.Snapshot, error) { return shadow.Snapshot{}, errors.New("unavailable") })
	if _, _, _, err := s.collect(context.Background()); err == nil {
		t.Fatal("ignored snapshot failure")
	}
	s.Source = shadowSourceFunc(func(context.Context) (shadow.Snapshot, error) {
		return shadow.Snapshot{Version: 1, Complete: false, CapturedAt: time.Now()}, nil
	})
	if _, _, _, err := s.collect(context.Background()); err == nil {
		t.Fatal("accepted partial snapshot")
	}
}
