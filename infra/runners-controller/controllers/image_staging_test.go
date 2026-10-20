package controllers

import (
	"context"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/tools/record"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	tuistv1 "github.com/tuist/tuist/infra/runners-controller/api/v1alpha1"
	"github.com/tuist/tuist/infra/runners-controller/internal/podtemplate"
)

const (
	stagingOldImage = "ghcr.io/tuist/tuist-runner:macos-26-1-1-0.36.0"
	stagingNewImage = "ghcr.io/tuist/tuist-runner:macos-26-1-1-0.36.1"
)

var stagingNow = time.Date(2026, 10, 19, 9, 0, 0, 0, time.UTC)

func stagingNode(name string, goldens ...string) *corev1.Node {
	node := &corev1.Node{
		ObjectMeta: metav1.ObjectMeta{
			Name: name,
			Labels: map[string]string{
				macosFleetLabel: "tuist-runners-fleet",
				nodeOSLabel:     macosNodeOSDarwin,
			},
		},
		Status: corev1.NodeStatus{
			Conditions: []corev1.NodeCondition{{Type: corev1.NodeReady, Status: corev1.ConditionTrue}},
		},
	}
	for _, image := range goldens {
		node.Labels[podtemplate.GoldenNodeAffinityKey(image)] = "true"
	}
	return node
}

// stagingPool is a pool on the new image that still serves the old one and
// last wanted runners a day ago, like a customer's pool between sessions
// when a runner image release lands.
func stagingPool() *tuistv1.RunnerPool {
	pool := newPool("macos-26-1-1-12vcpu-28gb", stagingNewImage, 0)
	pool.Status.ObservedImage = stagingNewImage
	pool.Status.ImageRolledAt = metav1.NewTime(stagingNow.Add(-time.Minute))
	pool.Status.ServingImage = stagingOldImage
	lastDemand := metav1.NewTime(stagingNow.Add(-24 * time.Hour))
	pool.Status.LastDemandAt = &lastDemand
	return pool
}

func reconcileStaging(t *testing.T, objects ...client.Object) (client.Client, *record.FakeRecorder) {
	t.Helper()
	scheme := mustScheme(t)
	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithObjects(objects...).
		WithStatusSubresource(&tuistv1.RunnerPool{}).
		Build()
	recorder := record.NewFakeRecorder(4)
	r := &RunnerPoolReconciler{
		Client:      c,
		Scheme:      scheme,
		DispatchURL: "http://dispatch",
		Recorder:    recorder,
		Now:         func() time.Time { return stagingNow },
	}
	for _, object := range objects {
		pool, ok := object.(*tuistv1.RunnerPool)
		if !ok {
			continue
		}
		if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: nn(pool.Namespace, pool.Name)}); err != nil {
			t.Fatalf("reconcile %s: %v", pool.Name, err)
		}
	}
	return c, recorder
}

func getPool(t *testing.T, c client.Client, name string) *tuistv1.RunnerPool {
	t.Helper()
	pool := &tuistv1.RunnerPool{}
	if err := c.Get(context.Background(), nn("tuist-runners", name), pool); err != nil {
		t.Fatalf("get pool: %v", err)
	}
	return pool
}

func prewarmImages(t *testing.T, c client.Client, name string) map[string]string {
	t.Helper()
	node := &corev1.Node{}
	if err := c.Get(context.Background(), client.ObjectKey{Name: name}, node); err != nil {
		t.Fatalf("get node: %v", err)
	}
	out := map[string]string{}
	for key, value := range node.Annotations {
		if key == podtemplate.PrewarmImageAnnotationKey(value) {
			out[key] = value
		}
	}
	return out
}

func podImages(pods []corev1.Pod) []string {
	images := make([]string, 0, len(pods))
	for i := range pods {
		images = append(images, pods[i].Spec.Containers[0].Image)
	}
	return images
}

func TestReconcile_KeepsServingImageUntilHostsHoldTheNewOne(t *testing.T) {
	pool := stagingPool()
	pool.Spec.Replicas = 1
	c, _ := reconcileStaging(t, pool,
		stagingNode("b01", stagingOldImage),
		stagingNode("b02", stagingOldImage),
		stagingNode("b03"),
	)

	if got := getPool(t, c, pool.Name).Status.ServingImage; got != stagingOldImage {
		t.Fatalf("ServingImage = %q, want %q until hosts hold the new image", got, stagingOldImage)
	}
	var pods corev1.PodList
	if err := c.List(context.Background(), &pods, client.InNamespace("tuist-runners")); err != nil {
		t.Fatalf("list pods: %v", err)
	}
	if got := podImages(pods.Items); len(got) != 1 || got[0] != stagingOldImage {
		t.Fatalf("pod images = %v, want one pod on %s", got, stagingOldImage)
	}
	for _, name := range []string{"b01", "b02"} {
		got := prewarmImages(t, c, name)
		if got[podtemplate.PrewarmImageAnnotationKey(stagingNewImage)] != stagingNewImage {
			t.Fatalf("node %s prewarm annotations = %v, want the new image staged on a host holding the old one", name, got)
		}
		if got[podtemplate.PrewarmImageAnnotationKey(stagingOldImage)] != stagingOldImage {
			t.Fatalf("node %s prewarm annotations = %v, want the serving image kept", name, got)
		}
	}
	if got := prewarmImages(t, c, "b03"); len(got) != 0 {
		t.Fatalf("node b03 prewarm annotations = %v, want none", got)
	}
}

func TestReconcile_PromotesOnceEnoughHostsHoldTheNewImage(t *testing.T) {
	pool := stagingPool()
	c, recorder := reconcileStaging(t, pool,
		stagingNode("b01", stagingOldImage, stagingNewImage),
		stagingNode("b02", stagingNewImage),
		stagingNode("b03"),
	)

	updated := getPool(t, c, pool.Name)
	if updated.Status.ServingImage != stagingNewImage {
		t.Fatalf("ServingImage = %q, want %q", updated.Status.ServingImage, stagingNewImage)
	}
	if updated.Status.ObservedImage != stagingNewImage {
		t.Fatalf("ObservedImage = %q, want %q kept through the promotion", updated.Status.ObservedImage, stagingNewImage)
	}
	select {
	case event := <-recorder.Events:
		if want := "Normal RunnerImagePromoted New runners use " + stagingNewImage + ": 2 of 3 healthy hosts hold it"; event != want {
			t.Fatalf("event = %q, want %q", event, want)
		}
	default:
		t.Fatal("no RunnerImagePromoted event")
	}
}

func TestReconcile_PromotesAfterTheStagingDeadline(t *testing.T) {
	pool := stagingPool()
	pool.Status.ImageRolledAt = metav1.NewTime(stagingNow.Add(-imageStagingTimeout))
	c, _ := reconcileStaging(t, pool, stagingNode("b01", stagingOldImage), stagingNode("b02"))

	if got := getPool(t, c, pool.Name).Status.ServingImage; got != stagingNewImage {
		t.Fatalf("ServingImage = %q, want %q after the deadline", got, stagingNewImage)
	}
}

func TestReconcile_PromotesAtOnceWithoutRecentDemand(t *testing.T) {
	pool := stagingPool()
	pool.Status.LastDemandAt = nil
	c, _ := reconcileStaging(t, pool, stagingNode("b01", stagingOldImage), stagingNode("b02"))

	if got := getPool(t, c, pool.Name).Status.ServingImage; got != stagingNewImage {
		t.Fatalf("ServingImage = %q, want %q: nothing is staged for a pool without demand", got, stagingNewImage)
	}
	for _, name := range []string{"b01", "b02"} {
		if got := prewarmImages(t, c, name); len(got) != 0 {
			t.Fatalf("node %s prewarm annotations = %v, want none", name, got)
		}
	}
}

func TestReconcile_FirstSeenPoolKeepsServingTheObservedImage(t *testing.T) {
	pool := newPool("macos-26-6", stagingNewImage, 1)
	pool.Status.ObservedImage = stagingOldImage
	pool.Status.ImageRolledAt = metav1.NewTime(stagingNow.Add(-time.Minute))
	c, _ := reconcileStaging(t, pool, stagingNode("b01"), stagingNode("b02"))

	updated := getPool(t, c, pool.Name)
	if updated.Status.ServingImage != stagingOldImage {
		t.Fatalf("ServingImage = %q, want %q (what the pool's Pods already run)", updated.Status.ServingImage, stagingOldImage)
	}
}

func TestReconcile_LinuxPoolsUseSpecImage(t *testing.T) {
	pool := newPool("linux-4vcpu-16gb", stagingNewImage, 1)
	pool.Spec.OS = "linux"
	pool.Status.ObservedImage = stagingOldImage
	c, _ := reconcileStaging(t, pool)

	var pods corev1.PodList
	if err := c.List(context.Background(), &pods, client.InNamespace("tuist-runners")); err != nil {
		t.Fatalf("list pods: %v", err)
	}
	if got := podImages(pods.Items); len(got) != 1 || got[0] != stagingNewImage {
		t.Fatalf("pod images = %v, want one pod on %s", got, stagingNewImage)
	}
	if got := getPool(t, c, pool.Name).Status.ServingImage; got != "" {
		t.Fatalf("ServingImage = %q, want it unset on Linux", got)
	}
}

func TestPlanImagePrewarm(t *testing.T) {
	floor := func(n int32) *tuistv1.RunnerPoolAutoscaling {
		return &tuistv1.RunnerPoolAutoscaling{Enabled: true, MinWarmPoolFloor: &n}
	}
	recent := metav1.NewTime(stagingNow.Add(-6 * 24 * time.Hour))
	stale := metav1.NewTime(stagingNow.Add(-8 * 24 * time.Hour))

	small := newPool("macos-26-1-1", stagingOldImage, 0)
	small.Status.LastDemandAt = &recent
	large := newPool("macos-26-1-1-12vcpu-28gb", stagingOldImage, 0)
	large.Spec.Autoscaling = floor(2)
	idle := newPool("macos-26-0-1", "ghcr.io/tuist/tuist-runner:macos-26-0-1-0.36.1", 0)
	idle.Status.LastDemandAt = &stale

	asked := stagingNode("b04")
	asked.Annotations = map[string]string{podtemplate.PrewarmImageAnnotationKey(stagingOldImage): stagingOldImage}
	busy := stagingNode("b05", "ghcr.io/tuist/tuist-runner:macos-27-0-0.36.1")
	cordoned := stagingNode("b00", stagingOldImage)
	cordoned.Spec.Unschedulable = true
	nodes := []corev1.Node{
		*cordoned,
		*stagingNode("b01", stagingOldImage),
		*busy,
		*stagingNode("b02"),
		*asked,
		*stagingNode("b03"),
	}

	plan := planImagePrewarm([]*tuistv1.RunnerPool{small, large, idle}, nodes, stagingNow)

	key := podtemplate.PrewarmImageAnnotationKey(stagingOldImage)
	var holders []string
	for _, name := range []string{"b01", "b02", "b03", "b04", "b05"} {
		if plan[name][key] == stagingOldImage {
			holders = append(holders, name)
		}
		for other := range plan[name] {
			if other != key {
				t.Fatalf("node %s planned %s, want only the 26.1.1 image: the idle pool's demand is older than the window", name, other)
			}
		}
	}
	// The 12 vCPU pool's floor of 2 asks for 3 hosts: the host holding the
	// image, the host already asked for it, then the emptier of the rest.
	if want := []string{"b01", "b02", "b04"}; len(holders) != len(want) || holders[0] != want[0] || holders[1] != want[1] || holders[2] != want[2] {
		t.Fatalf("hosts for %s = %v, want %v", stagingOldImage, holders, want)
	}
	if _, planned := plan["b00"]; planned {
		t.Fatal("cordoned node b00 is in the plan, want it left alone")
	}
}
