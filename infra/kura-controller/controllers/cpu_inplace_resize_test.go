package controllers

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/schema"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/apimachinery/pkg/util/validation/field"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/client/interceptor"
)

type cpuResizeFixture struct {
	instance *kurav1alpha1.KuraInstance
	sts      *appsv1.StatefulSet
	now      time.Time
}

// newCPUResizeFixture is a two-replica instance whose StatefulSet controller
// has observed a held template moving the request from 100m to 150m: revision
// "rev-a" is what the pods run, "rev-b" is the update revision.
func newCPUResizeFixture() cpuResizeFixture {
	now := time.Date(2026, 10, 21, 11, 19, 0, 0, time.UTC)
	instance := meshInstance("kura-acme-eu-east-1", "acme")
	instance.Spec.Replicas = ptr(int32(2))
	sts := &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{
			Name:        instance.Name,
			Namespace:   instance.Namespace,
			UID:         "sts-uid",
			Generation:  2,
			Annotations: map[string]string{cpuResizeHoldAnnotation: now.Format(time.RFC3339)},
		},
		Spec: appsv1.StatefulSetSpec{
			Replicas:       ptr(int32(2)),
			UpdateStrategy: onDelete(),
			Template:       cpuResizeTemplate("150m", instance.Spec.Image),
		},
		Status: appsv1.StatefulSetStatus{
			ObservedGeneration: 2,
			Replicas:           2,
			CurrentRevision:    "rev-a",
			UpdateRevision:     "rev-b",
		},
	}
	return cpuResizeFixture{instance: instance, sts: sts, now: now}
}

func cpuResizeTemplate(cpu, image string) corev1.PodTemplateSpec {
	return corev1.PodTemplateSpec{
		ObjectMeta: metav1.ObjectMeta{Labels: map[string]string{"app": "kura"}},
		Spec: corev1.PodSpec{Containers: []corev1.Container{{
			Name:  kuraContainerName,
			Image: image,
			Resources: corev1.ResourceRequirements{Requests: corev1.ResourceList{
				corev1.ResourceCPU:    resource.MustParse(cpu),
				corev1.ResourceMemory: resource.MustParse("512Mi"),
			}},
		}}},
	}
}

func (f cpuResizeFixture) revision(t *testing.T, name string, template corev1.PodTemplateSpec) *appsv1.ControllerRevision {
	t.Helper()
	raw, err := json.Marshal(map[string]any{"spec": map[string]any{"template": template}})
	if err != nil {
		t.Fatal(err)
	}
	return &appsv1.ControllerRevision{
		ObjectMeta: metav1.ObjectMeta{
			Name:      name,
			Namespace: f.instance.Namespace,
			OwnerReferences: []metav1.OwnerReference{{
				APIVersion: "apps/v1",
				Kind:       "StatefulSet",
				Name:       f.sts.Name,
				UID:        f.sts.UID,
				Controller: ptr(true),
			}},
		},
		Data: runtime.RawExtension{Raw: raw},
	}
}

func (f cpuResizeFixture) pod(name, revision, cpu string) *corev1.Pod {
	labels := selectorLabels(f.instance)
	labels[appsv1.ControllerRevisionHashLabelKey] = revision
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: f.instance.Namespace, UID: types.UID(name + "-uid"), Labels: labels},
		Spec: corev1.PodSpec{
			NodeName: "node-a",
			Containers: []corev1.Container{{
				Name:  kuraContainerName,
				Image: f.instance.Spec.Image,
				Resources: corev1.ResourceRequirements{Requests: corev1.ResourceList{
					corev1.ResourceCPU:    resource.MustParse(cpu),
					corev1.ResourceMemory: resource.MustParse("512Mi"),
				}},
			}},
		},
		Status: corev1.PodStatus{
			Phase: corev1.PodRunning,
			ContainerStatuses: []corev1.ContainerStatus{{
				Name:      kuraContainerName,
				Resources: &corev1.ResourceRequirements{Requests: corev1.ResourceList{corev1.ResourceCPU: resource.MustParse(cpu)}},
			}},
		},
	}
}

type resizeCall struct {
	pod   string
	patch string
}

func (f cpuResizeFixture) reconciler(t *testing.T, resizeErr error, objects ...client.Object) (*KuraInstanceReconciler, *[]resizeCall, *[]string) {
	t.Helper()
	scheme := meshTestScheme(t)
	resizes := &[]resizeCall{}
	deletes := &[]string{}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(append([]client.Object{f.instance, f.sts}, objects...)...).
		WithInterceptorFuncs(interceptor.Funcs{
			SubResourcePatch: func(ctx context.Context, c client.Client, subResource string, obj client.Object, patch client.Patch, opts ...client.SubResourcePatchOption) error {
				if subResource != "resize" {
					return c.SubResource(subResource).Patch(ctx, obj, patch, opts...)
				}
				data, err := patch.Data(obj)
				if err != nil {
					return err
				}
				if patch.Type() != types.StrategicMergePatchType {
					t.Fatalf("resize patch type = %s, want a strategic merge patch", patch.Type())
				}
				*resizes = append(*resizes, resizeCall{pod: obj.GetName(), patch: string(data)})
				if resizeErr != nil {
					return resizeErr
				}
				return c.SubResource(subResource).Patch(ctx, obj, patch, opts...)
			},
			Delete: func(ctx context.Context, c client.WithWatch, obj client.Object, opts ...client.DeleteOption) error {
				*deletes = append(*deletes, obj.GetName())
				return c.Delete(ctx, obj, opts...)
			},
		}).Build()
	return &KuraInstanceReconciler{Client: c, Scheme: scheme}, resizes, deletes
}

func getStatefulSet(t *testing.T, r *KuraInstanceReconciler, f cpuResizeFixture) *appsv1.StatefulSet {
	t.Helper()
	sts := &appsv1.StatefulSet{}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(f.sts), sts); err != nil {
		t.Fatal(err)
	}
	return sts
}

func getPod(t *testing.T, r *KuraInstanceReconciler, name string) *corev1.Pod {
	t.Helper()
	pod := &corev1.Pod{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: name, Namespace: "kura"}, pod); err != nil {
		t.Fatal(err)
	}
	return pod
}

func assertCPUResizeHeld(t *testing.T, sts *appsv1.StatefulSet) {
	t.Helper()
	if sts.Spec.UpdateStrategy.Type != appsv1.OnDeleteStatefulSetStrategyType {
		t.Fatalf("update strategy = %s, want OnDelete while the resize is in flight", sts.Spec.UpdateStrategy.Type)
	}
	if _, held := sts.Annotations[cpuResizeHoldAnnotation]; !held {
		t.Fatal("CPU resize hold annotation removed while the resize is in flight")
	}
}

func assertCPUResizeReleased(t *testing.T, sts *appsv1.StatefulSet) {
	t.Helper()
	if sts.Spec.UpdateStrategy.Type != appsv1.RollingUpdateStatefulSetStrategyType ||
		sts.Spec.UpdateStrategy.RollingUpdate == nil || sts.Spec.UpdateStrategy.RollingUpdate.Partition == nil ||
		*sts.Spec.UpdateStrategy.RollingUpdate.Partition != 0 {
		t.Fatalf("update strategy = %+v, want RollingUpdate with partition 0", sts.Spec.UpdateStrategy)
	}
	if _, held := sts.Annotations[cpuResizeHoldAnnotation]; held {
		t.Fatal("CPU resize hold annotation kept after release")
	}
}

// The incident this exists for: a band change re-templated the StatefulSet
// and rolled both pods, draining clients mid-upload.
func TestReconcileHoldsACPURequestChangeInsteadOfRollingThePods(t *testing.T) {
	ctx := context.Background()
	scheme := meshTestScheme(t)
	instance := meshInstance("kura-acme-eu-east-1", "acme")
	instance.Status.CPUAutosize = &kurav1alpha1.KuraInstanceCPUAutosize{RequestMilli: 100}
	sharedSecret := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: sharedSecretsName, Namespace: instance.Namespace, ResourceVersion: "1"}}
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(instance, sharedSecret).WithStatusSubresource(instance).Build()
	r := &KuraInstanceReconciler{Client: c, Scheme: scheme}
	request := ctrl.Request{NamespacedName: client.ObjectKeyFromObject(instance)}

	if _, err := r.Reconcile(ctx, request); err != nil {
		t.Fatal(err)
	}
	sts := &appsv1.StatefulSet{}
	if err := c.Get(ctx, request.NamespacedName, sts); err != nil {
		t.Fatal(err)
	}
	if _, held := sts.Annotations[cpuResizeHoldAnnotation]; held || sts.Spec.UpdateStrategy.Type == appsv1.OnDeleteStatefulSetStrategyType {
		t.Fatalf("a new StatefulSet has no pods to restart and should not be held: %+v", sts.Spec.UpdateStrategy)
	}

	if err := c.Get(ctx, request.NamespacedName, instance); err != nil {
		t.Fatal(err)
	}
	instance.Status.CPUAutosize.RequestMilli = 150
	if err := c.Status().Update(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if _, err := r.Reconcile(ctx, request); err != nil {
		t.Fatal(err)
	}

	if err := c.Get(ctx, request.NamespacedName, sts); err != nil {
		t.Fatal(err)
	}
	if got := sts.Spec.Template.Spec.Containers[0].Resources.Requests.Cpu().String(); got != "150m" {
		t.Fatalf("templated CPU request = %q, want 150m", got)
	}
	assertCPUResizeHeld(t, sts)
}

func TestCPUResizeHoldResizesPodsInPlaceAndReleasesWithoutARoll(t *testing.T) {
	ctx := context.Background()
	f := newCPUResizeFixture()
	r, resizes, deletes := f.reconciler(t, nil,
		f.revision(t, "rev-a", cpuResizeTemplate("100m", f.instance.Spec.Image)),
		f.revision(t, "rev-b", cpuResizeTemplate("150m", f.instance.Spec.Image)),
		f.pod("kura-acme-eu-east-1-0", "rev-a", "100m"),
		f.pod("kura-acme-eu-east-1-1", "rev-a", "100m"),
	)

	if err := r.reconcileCPUResizeHold(ctx, f.instance, f.now); err != nil {
		t.Fatal(err)
	}
	if len(*resizes) != 2 {
		t.Fatalf("resize calls = %+v, want one per pod", *resizes)
	}
	for _, call := range *resizes {
		if call.patch != `{"spec":{"containers":[{"name":"kura","resources":{"requests":{"cpu":"150m"}}}]}}` {
			t.Fatalf("resize patch for %s = %s", call.pod, call.patch)
		}
	}
	for _, name := range []string{"kura-acme-eu-east-1-0", "kura-acme-eu-east-1-1"} {
		if got := getPod(t, r, name).Labels[appsv1.ControllerRevisionHashLabelKey]; got != "rev-a" {
			t.Fatalf("%s revision = %s before the kubelet applied the resize, want rev-a", name, got)
		}
	}
	assertCPUResizeHeld(t, getStatefulSet(t, r, f))

	// The kubelet applies the new request to the running containers.
	for _, name := range []string{"kura-acme-eu-east-1-0", "kura-acme-eu-east-1-1"} {
		pod := getPod(t, r, name)
		pod.Status.ContainerStatuses[0].Resources.Requests[corev1.ResourceCPU] = resource.MustParse("150m")
		if err := r.Status().Update(ctx, pod); err != nil {
			t.Fatal(err)
		}
	}
	if err := r.reconcileCPUResizeHold(ctx, f.instance, f.now.Add(30*time.Second)); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"kura-acme-eu-east-1-0", "kura-acme-eu-east-1-1"} {
		if got := getPod(t, r, name).Labels[appsv1.ControllerRevisionHashLabelKey]; got != "rev-b" {
			t.Fatalf("%s revision = %s, want the update revision rev-b", name, got)
		}
	}
	// Until the StatefulSet controller counts the relabelled pods, it could
	// still act on the old labels, so the hold stays.
	assertCPUResizeHeld(t, getStatefulSet(t, r, f))

	sts := getStatefulSet(t, r, f)
	sts.Status.UpdatedReplicas = 2
	if err := r.Status().Update(ctx, sts); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcileCPUResizeHold(ctx, f.instance, f.now.Add(time.Minute)); err != nil {
		t.Fatal(err)
	}
	assertCPUResizeReleased(t, getStatefulSet(t, r, f))
	if len(*deletes) != 0 {
		t.Fatalf("deleted pods %v, want every pod kept running", *deletes)
	}
	if len(*resizes) != 2 {
		t.Fatalf("resize calls = %d, want no repeat once applied", len(*resizes))
	}
}

func TestCPUResizeHoldRollsARevisionThatChangesMoreThanTheRequest(t *testing.T) {
	ctx := context.Background()
	f := newCPUResizeFixture()
	f.sts.Spec.Template = cpuResizeTemplate("150m", "ghcr.io/tuist/kura:0.6.0")
	r, resizes, _ := f.reconciler(t, nil,
		f.revision(t, "rev-a", cpuResizeTemplate("100m", f.instance.Spec.Image)),
		f.revision(t, "rev-b", cpuResizeTemplate("150m", "ghcr.io/tuist/kura:0.6.0")),
		f.pod("kura-acme-eu-east-1-0", "rev-a", "100m"),
		f.pod("kura-acme-eu-east-1-1", "rev-a", "100m"),
	)

	if err := r.reconcileCPUResizeHold(ctx, f.instance, f.now); err != nil {
		t.Fatal(err)
	}
	if len(*resizes) != 0 {
		t.Fatalf("resized %+v, want an image change left to the rolling update", *resizes)
	}
	assertCPUResizeReleased(t, getStatefulSet(t, r, f))
}

// A resize the API refuses outright, such as one that would change the pod's
// QoS class, gets the restart it was meant to avoid rather than a stuck hold.
func TestCPUResizeHoldRollsWhenTheResizeIsRefused(t *testing.T) {
	ctx := context.Background()
	f := newCPUResizeFixture()
	refused := apierrors.NewInvalid(schema.GroupKind{Kind: "Pod"}, "kura-acme-eu-east-1-0", field.ErrorList{
		field.Invalid(field.NewPath("spec", "containers"), nil, "Pod QoS is immutable"),
	})
	r, _, _ := f.reconciler(t, refused,
		f.revision(t, "rev-a", cpuResizeTemplate("100m", f.instance.Spec.Image)),
		f.revision(t, "rev-b", cpuResizeTemplate("150m", f.instance.Spec.Image)),
		f.pod("kura-acme-eu-east-1-0", "rev-a", "100m"),
	)

	if err := r.reconcileCPUResizeHold(ctx, f.instance, f.now); err != nil {
		t.Fatal(err)
	}
	assertCPUResizeReleased(t, getStatefulSet(t, r, f))
}

func TestCPUResizeHoldRollsWhenTheResizeStalls(t *testing.T) {
	ctx := context.Background()
	f := newCPUResizeFixture()
	r, resizes, _ := f.reconciler(t, nil,
		f.revision(t, "rev-a", cpuResizeTemplate("100m", f.instance.Spec.Image)),
		f.revision(t, "rev-b", cpuResizeTemplate("150m", f.instance.Spec.Image)),
		f.pod("kura-acme-eu-east-1-0", "rev-a", "150m"),
	)

	if err := r.reconcileCPUResizeHold(ctx, f.instance, f.now.Add(cpuResizeStallTimeout)); err != nil {
		t.Fatal(err)
	}
	if len(*resizes) != 0 {
		t.Fatalf("resized %+v after the stall timeout", *resizes)
	}
	assertCPUResizeReleased(t, getStatefulSet(t, r, f))
}

// Until the StatefulSet controller has observed the held template, its update
// revision still names the previous one and every pod would look current.
func TestCPUResizeHoldWaitsForTheStatefulSetToObserveTheTemplate(t *testing.T) {
	ctx := context.Background()
	f := newCPUResizeFixture()
	f.sts.Generation = 3
	r, resizes, _ := f.reconciler(t, nil,
		f.revision(t, "rev-a", cpuResizeTemplate("100m", f.instance.Spec.Image)),
		f.revision(t, "rev-b", cpuResizeTemplate("150m", f.instance.Spec.Image)),
		f.pod("kura-acme-eu-east-1-0", "rev-a", "100m"),
	)

	if err := r.reconcileCPUResizeHold(ctx, f.instance, f.now); err != nil {
		t.Fatal(err)
	}
	if len(*resizes) != 0 {
		t.Fatalf("resized %+v before the StatefulSet observed its template", *resizes)
	}
	assertCPUResizeHeld(t, getStatefulSet(t, r, f))
}

// A pod that never scheduled serves nothing; OnDelete recreates it from the
// update revision at the new request.
func TestCPUResizeHoldReplacesAnUnscheduledPod(t *testing.T) {
	ctx := context.Background()
	f := newCPUResizeFixture()
	pending := f.pod("kura-acme-eu-east-1-1", "rev-a", "100m")
	pending.Spec.NodeName = ""
	pending.Status = corev1.PodStatus{Phase: corev1.PodPending}
	r, resizes, deletes := f.reconciler(t, nil,
		f.revision(t, "rev-a", cpuResizeTemplate("100m", f.instance.Spec.Image)),
		f.revision(t, "rev-b", cpuResizeTemplate("150m", f.instance.Spec.Image)),
		pending,
	)

	if err := r.reconcileCPUResizeHold(ctx, f.instance, f.now); err != nil {
		t.Fatal(err)
	}
	if len(*resizes) != 0 || len(*deletes) != 1 || (*deletes)[0] != pending.Name {
		t.Fatalf("resizes = %+v, deletes = %v, want only the unscheduled pod replaced", *resizes, *deletes)
	}
}

// After a schedule cap brings the template back to the request the pods run,
// the StatefulSet controller reuses their revision, but the pod spec still
// carries the raise the kubelet deferred.
func TestCPUResizeHoldRevertsARaiseOnAPodAlreadyOnTheUpdateRevision(t *testing.T) {
	ctx := context.Background()
	f := newCPUResizeFixture()
	f.sts.Spec.Template = cpuResizeTemplate("100m", f.instance.Spec.Image)
	f.sts.Status.UpdateRevision = "rev-a"
	f.sts.Status.UpdatedReplicas = 1
	f.sts.Status.Replicas = 1
	f.instance.Spec.Replicas = ptr(int32(1))
	deferred := f.pod("kura-acme-eu-east-1-0", "rev-a", "150m")
	deferred.Status.ContainerStatuses[0].Resources.Requests[corev1.ResourceCPU] = resource.MustParse("100m")
	r, resizes, _ := f.reconciler(t, nil,
		f.revision(t, "rev-a", cpuResizeTemplate("100m", f.instance.Spec.Image)),
		deferred,
	)

	if err := r.reconcileCPUResizeHold(ctx, f.instance, f.now); err != nil {
		t.Fatal(err)
	}
	if len(*resizes) != 1 || (*resizes)[0].pod != deferred.Name {
		t.Fatalf("resizes = %+v, want the deferred raise reverted to 100m", *resizes)
	}
	assertCPUResizeHeld(t, getStatefulSet(t, r, f))

	if err := r.reconcileCPUResizeHold(ctx, f.instance, f.now.Add(30*time.Second)); err != nil {
		t.Fatal(err)
	}
	assertCPUResizeReleased(t, getStatefulSet(t, r, f))
}

func TestCPUResizeHoldYieldsToARecovery(t *testing.T) {
	ctx := context.Background()
	f := newCPUResizeFixture()
	f.instance.Status.ReplicaRecovery = &kurav1alpha1.ReplicaRecoveryStatus{}
	r, resizes, _ := f.reconciler(t, nil, f.pod("kura-acme-eu-east-1-0", "rev-a", "100m"))

	if err := r.reconcileCPUResizeHold(ctx, f.instance, f.now); err != nil {
		t.Fatal(err)
	}
	sts := getStatefulSet(t, r, f)
	if _, held := sts.Annotations[cpuResizeHoldAnnotation]; held || sts.Spec.UpdateStrategy.Type != appsv1.OnDeleteStatefulSetStrategyType || len(*resizes) != 0 {
		t.Fatalf("strategy = %+v, annotations = %v, resizes = %+v; want the recovery's OnDelete kept and the marker dropped", sts.Spec.UpdateStrategy, sts.Annotations, *resizes)
	}
}

func TestHoldCPURequestChange(t *testing.T) {
	now := time.Date(2026, 10, 21, 11, 19, 0, 0, time.UTC)
	partitioned := rollingUpdate()
	partitioned.RollingUpdate.Partition = ptr(int32(1))

	for _, tc := range []struct {
		name         string
		created      bool
		strategy     appsv1.StatefulSetUpdateStrategy
		annotations  map[string]string
		fromCPU      string
		wantHeld     bool
		wantStrategy appsv1.StatefulSetUpdateStrategyType
	}{
		{name: "holds a rolling update whose request changes", created: true, strategy: rollingUpdate(), fromCPU: "100m", wantHeld: true, wantStrategy: appsv1.OnDeleteStatefulSetStrategyType},
		{name: "leaves an unchanged request rolling", created: true, strategy: rollingUpdate(), fromCPU: "150m", wantStrategy: appsv1.RollingUpdateStatefulSetStrategyType},
		{name: "leaves a new StatefulSet rolling", strategy: rollingUpdate(), fromCPU: "100m", wantStrategy: appsv1.RollingUpdateStatefulSetStrategyType},
		{name: "leaves an operator's OnDelete unmarked", created: true, strategy: onDelete(), fromCPU: "100m", wantStrategy: appsv1.OnDeleteStatefulSetStrategyType},
		{name: "leaves an operator's partition alone", created: true, strategy: partitioned, fromCPU: "100m", wantStrategy: appsv1.RollingUpdateStatefulSetStrategyType},
		{
			name:         "refreshes its own hold",
			created:      true,
			strategy:     onDelete(),
			annotations:  map[string]string{cpuResizeHoldAnnotation: now.Add(-time.Hour).Format(time.RFC3339)},
			fromCPU:      "100m",
			wantHeld:     true,
			wantStrategy: appsv1.OnDeleteStatefulSetStrategyType,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			sts := &appsv1.StatefulSet{
				ObjectMeta: metav1.ObjectMeta{Annotations: tc.annotations},
				Spec:       appsv1.StatefulSetSpec{UpdateStrategy: tc.strategy, Template: cpuResizeTemplate("150m", "kura")},
			}
			if tc.created {
				sts.ResourceVersion = "7"
			}
			previous := cpuResizeTemplate(tc.fromCPU, "kura")

			holdCPURequestChange(sts, &previous, now)

			if sts.Spec.UpdateStrategy.Type != tc.wantStrategy {
				t.Fatalf("strategy = %s, want %s", sts.Spec.UpdateStrategy.Type, tc.wantStrategy)
			}
			stamp, held := sts.Annotations[cpuResizeHoldAnnotation]
			if held != tc.wantHeld {
				t.Fatalf("held = %t, want %t", held, tc.wantHeld)
			}
			if held && stamp != now.Format(time.RFC3339) {
				t.Fatalf("hold stamp = %s, want the time of this change", stamp)
			}
		})
	}
}

// A data volume resize takes over the CPU hold, so the hold is released with
// the resize instead of being left behind while pods are rebuilt.
func TestStorageResizeTakesOverACPUResizeHold(t *testing.T) {
	ctx := context.Background()
	scheme := meshTestScheme(t)
	f := newResizeHoldFixture(150)
	sts := f.statefulSet(onDelete(), "150m", map[string]string{cpuResizeHoldAnnotation: time.Now().UTC().Format(time.RFC3339)})
	c := fake.NewClientBuilder().WithScheme(scheme).WithObjects(f.instance, sts).Build()
	r := &KuraInstanceReconciler{Client: c, Scheme: scheme}

	held, err := r.holdRolloutForResize(ctx, f.instance)
	if err != nil {
		t.Fatal(err)
	}
	if !held {
		t.Fatal("want the template reconcilable under the hold")
	}
	if err := c.Get(ctx, client.ObjectKeyFromObject(sts), sts); err != nil {
		t.Fatal(err)
	}
	if _, cpuHeld := sts.Annotations[cpuResizeHoldAnnotation]; cpuHeld || sts.Annotations[resizeRolloutHoldAnnotation] != "true" {
		t.Fatalf("annotations = %v, want the hold handed to the data volume resize", sts.Annotations)
	}
}

func TestScheduleCapBacksOffAnInPlaceRaiseTheNodeCannotFit(t *testing.T) {
	now := time.Date(2026, 10, 21, 11, 19, 0, 0, time.UTC)
	resizePending := func(reason string, since time.Duration) corev1.Pod {
		pod := runningPod("kura-acme-us-east-1-0", 1000)
		pod.Status.Conditions = []corev1.PodCondition{{
			Type:               podResizePendingCondition,
			Status:             corev1.ConditionTrue,
			Reason:             reason,
			LastTransitionTime: metav1.NewTime(now.Add(-since)),
		}}
		return pod
	}

	for _, tc := range []struct {
		name    string
		pod     corev1.Pod
		wantCap bool
	}{
		{name: "infeasible caps at once", pod: resizePending(podResizeReasonInfeasible, 0), wantCap: true},
		{name: "deferred waits for room to free up", pod: resizePending(podResizeReasonDeferred, cpuResizeDeferredGrace-time.Second)},
		{name: "deferred past the grace caps", pod: resizePending(podResizeReasonDeferred, cpuResizeDeferredGrace), wantCap: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			instance := &kurav1alpha1.KuraInstance{Status: kurav1alpha1.KuraInstanceStatus{
				CPUAutosize: &kurav1alpha1.KuraInstanceCPUAutosize{RequestMilli: 1000},
			}}

			applyScheduleCap(instance, []corev1.Pod{tc.pod}, now)

			if got := cpuRequestMilli(instance); (got < 1000) != tc.wantCap {
				t.Fatalf("template request = %dm, want capped = %t", got, tc.wantCap)
			}
		})
	}
}
