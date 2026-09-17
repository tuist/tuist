package controllers

import (
	"context"
	"fmt"
	"testing"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	batchv1 "k8s.io/api/batch/v1"
	corev1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"sigs.k8s.io/controller-runtime/pkg/event"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

func suspendableInstance(suspended bool) *kurav1alpha1.KuraInstance {
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
			Suspended:         suspended,
		},
	}
}

func suspensionTestReconciler(t *testing.T, objects ...client.Object) *KuraInstanceReconciler {
	t.Helper()
	scheme, mapper := dnsEndpointScheme(t)
	statusObjects := []client.Object{}
	for _, object := range objects {
		if _, ok := object.(*kurav1alpha1.KuraInstance); ok {
			statusObjects = append(statusObjects, object)
		}
	}
	c := fake.NewClientBuilder().
		WithScheme(scheme).
		WithRESTMapper(mapper).
		WithObjects(objects...).
		WithStatusSubresource(statusObjects...).
		Build()
	return &KuraInstanceReconciler{Client: c, APIReader: c, Scheme: scheme}
}

func reconcileInstance(t *testing.T, r *KuraInstanceReconciler, instance *kurav1alpha1.KuraInstance) ctrl.Result {
	t.Helper()
	result, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: client.ObjectKeyFromObject(instance)})
	if err != nil {
		t.Fatal(err)
	}
	return result
}

func statefulSetWithReplicas(instance *kurav1alpha1.KuraInstance, count int32) *appsv1.StatefulSet {
	return &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace},
		Spec:       appsv1.StatefulSetSpec{Replicas: ptr(count)},
	}
}

func retainedClaim(instance *kurav1alpha1.KuraInstance, ordinal int, storage string) *corev1.PersistentVolumeClaim {
	claim := dataPersistentVolumeClaim(instance, ordinal, storage)
	claim.Spec.StorageClassName = &instance.Spec.StorageClassName
	return claim
}

func wipedClaim(instance *kurav1alpha1.KuraInstance, ordinal int, storage string) *corev1.PersistentVolumeClaim {
	claim := retainedClaim(instance, ordinal, storage)
	claim.Annotations = map[string]string{volumeWipedAnnotation: "2026-09-16T12:00:00Z"}
	return claim
}

func scheduledKuraPod(instance *kurav1alpha1.KuraInstance, ordinal int, node string) *corev1.Pod {
	pod := kuraPod(instance.Name, instance.Namespace, ordinal, true)
	pod.Spec.NodeName = node
	return pod
}

func unschedulableKuraPod(instance *kurav1alpha1.KuraInstance, ordinal int) *corev1.Pod {
	pod := kuraPod(instance.Name, instance.Namespace, ordinal, false)
	pod.Status.Phase = corev1.PodPending
	pod.Status.Conditions = append(pod.Status.Conditions, corev1.PodCondition{
		Type:    corev1.PodScheduled,
		Status:  corev1.ConditionFalse,
		Reason:  corev1.PodReasonUnschedulable,
		Message: "0/3 nodes are available: 1 Insufficient memory, 2 node(s) had volume node affinity conflict.",
	})
	return pod
}

func getObject(t *testing.T, r *KuraInstanceReconciler, name string, object client.Object) error {
	t.Helper()
	return r.Get(context.Background(), types.NamespacedName{Name: name, Namespace: "kura"}, object)
}

func completeJob(t *testing.T, r *KuraInstanceReconciler, name string, condition batchv1.JobConditionType) {
	t.Helper()
	job := &batchv1.Job{}
	if err := getObject(t, r, name, job); err != nil {
		t.Fatalf("get job %s: %v", name, err)
	}
	job.Status.Conditions = append(job.Status.Conditions, batchv1.JobCondition{Type: condition, Status: corev1.ConditionTrue})
	if condition == batchv1.JobComplete {
		job.Status.Succeeded = 1
	} else {
		job.Status.Failed = 1
	}
	if err := r.Status().Update(context.Background(), job); err != nil {
		t.Fatalf("update job %s: %v", name, err)
	}
}

// Suspension is what makes a return fast, so it must leave every object that
// routes to the instance exactly as it was and only stop what runs.
func TestSuspendedInstanceScalesToZeroAndKeepsWhatAddressesIt(t *testing.T) {
	instance := suspendableInstance(true)
	service := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace},
		Spec:       corev1.ServiceSpec{Selector: primaryServiceSelector(instance, instance.Name+"-0")},
	}
	ingress := &networkingv1.Ingress{ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace}}
	peerSecret := &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: peerTLSSecretName(instance), Namespace: instance.Namespace}}
	endpoint := &unstructured.Unstructured{}
	endpoint.SetGroupVersionKind(dnsEndpointGVK)
	endpoint.SetNamespace(instance.Namespace)
	endpoint.SetName(instance.Name + "-public-dns")
	if err := unstructured.SetNestedSlice(endpoint.Object, []interface{}{
		map[string]interface{}{"dnsName": instance.Spec.PublicHost, "recordType": "A", "targets": []interface{}{"203.0.113.50"}},
	}, "spec", "endpoints"); err != nil {
		t.Fatal(err)
	}
	r := suspensionTestReconciler(t,
		instance,
		statefulSetWithReplicas(instance, 2),
		service,
		ingress,
		peerSecret,
		endpoint,
		scheduledKuraPod(instance, 0, "box-1"),
		retainedClaim(instance, 0, "16Gi"),
	)

	result := reconcileInstance(t, r, instance)

	sts := &appsv1.StatefulSet{}
	if err := getObject(t, r, instance.Name, sts); err != nil {
		t.Fatal(err)
	}
	if sts.Spec.Replicas == nil || *sts.Spec.Replicas != 0 {
		t.Fatalf("expected the StatefulSet scaled to zero, got %v", sts.Spec.Replicas)
	}
	storedService := &corev1.Service{}
	if err := getObject(t, r, instance.Name, storedService); err != nil {
		t.Fatalf("expected the client Service to be kept: %v", err)
	}
	if got := storedService.Spec.Selector[podNameLabel]; got != instance.Name+"-0" {
		t.Fatalf("expected the primary selector to be kept, got %q", got)
	}
	if err := getObject(t, r, instance.Name, &networkingv1.Ingress{}); err != nil {
		t.Fatalf("expected the Ingress to be kept: %v", err)
	}
	if err := getObject(t, r, peerTLSSecretName(instance), &corev1.Secret{}); err != nil {
		t.Fatalf("expected the peer TLS Secret to be kept: %v", err)
	}
	storedEndpoint := &unstructured.Unstructured{}
	storedEndpoint.SetGroupVersionKind(dnsEndpointGVK)
	if err := getObject(t, r, instance.Name+"-public-dns", storedEndpoint); err != nil {
		t.Fatalf("expected the customer DNSEndpoint to be kept with no pod scheduled: %v", err)
	}

	// The pod is still stopping: nothing may mount its volume yet.
	if err := getObject(t, r, wipeJobName(instance, fmt.Sprintf("data-%s-0", instance.Name)), &batchv1.Job{}); !apierrors.IsNotFound(err) {
		t.Fatalf("expected no wipe while a pod still holds the volume, got %v", err)
	}
	stored := &kurav1alpha1.KuraInstance{}
	if err := getObject(t, r, instance.Name, stored); err != nil {
		t.Fatal(err)
	}
	if stored.Status.Phase == suspendedPhase {
		t.Fatal("an instance whose pods are still stopping is not suspended yet")
	}
	if result.RequeueAfter == 0 {
		t.Fatal("expected a suspension in progress to be requeued")
	}
}

func TestSuspendedInstanceEmptiesRetainedVolumesOnceItsPodsHaveStopped(t *testing.T) {
	instance := suspendableInstance(true)
	instance.Status.ObservedImage = instance.Spec.Image
	r := suspensionTestReconciler(t,
		instance,
		statefulSetWithReplicas(instance, 0),
		retainedClaim(instance, 0, "16Gi"),
		retainedClaim(instance, 1, "16Gi"),
	)

	reconcileInstance(t, r, instance)

	for ordinal := 0; ordinal < 2; ordinal++ {
		claimName := fmt.Sprintf("data-%s-%d", instance.Name, ordinal)
		job := &batchv1.Job{}
		if err := getObject(t, r, wipeJobName(instance, claimName), job); err != nil {
			t.Fatalf("expected a wipe job for %s: %v", claimName, err)
		}
		pod := job.Spec.Template.Spec
		if len(pod.Volumes) != 1 || pod.Volumes[0].PersistentVolumeClaim == nil || pod.Volumes[0].PersistentVolumeClaim.ClaimName != claimName {
			t.Fatalf("expected the wipe job to mount %s, got %#v", claimName, pod.Volumes)
		}
		if len(pod.Containers) != 1 || pod.Containers[0].Image != instance.Spec.Image {
			t.Fatalf("expected the wipe to run on the instance's image, which its machine already holds, got %#v", pod.Containers)
		}
		if pod.RestartPolicy != corev1.RestartPolicyNever {
			t.Fatalf("expected RestartPolicy Never, got %q", pod.RestartPolicy)
		}
		if len(pod.Tolerations) != 1 || pod.Tolerations[0].Key != "tuist.dev/kura" {
			t.Fatalf("expected the wipe to tolerate what the instance tolerates, got %#v", pod.Tolerations)
		}
		podLabels := job.Spec.Template.Labels
		if podLabels["app.kubernetes.io/name"] == "kura" {
			t.Fatalf("a wipe pod must never be selected as one of the instance's replicas, got labels %v", podLabels)
		}
	}
	stored := &kurav1alpha1.KuraInstance{}
	if err := getObject(t, r, instance.Name, stored); err != nil {
		t.Fatal(err)
	}
	if stored.Status.Phase == suspendedPhase {
		t.Fatal("an instance whose volumes still hold content is not suspended yet")
	}

	for ordinal := 0; ordinal < 2; ordinal++ {
		completeJob(t, r, wipeJobName(instance, fmt.Sprintf("data-%s-%d", instance.Name, ordinal)), batchv1.JobComplete)
	}
	result := reconcileInstance(t, r, instance)

	for ordinal := 0; ordinal < 2; ordinal++ {
		claimName := fmt.Sprintf("data-%s-%d", instance.Name, ordinal)
		claim := &corev1.PersistentVolumeClaim{}
		if err := getObject(t, r, claimName, claim); err != nil {
			t.Fatalf("expected %s to be retained: %v", claimName, err)
		}
		if claim.Annotations[volumeWipedAnnotation] == "" {
			t.Fatalf("expected %s to be marked wiped, got %v", claimName, claim.Annotations)
		}
		if err := getObject(t, r, wipeJobName(instance, claimName), &batchv1.Job{}); !apierrors.IsNotFound(err) {
			t.Fatalf("expected the finished wipe job for %s to be removed, got %v", claimName, err)
		}
	}
	if err := getObject(t, r, instance.Name, stored); err != nil {
		t.Fatal(err)
	}
	if stored.Status.Phase != suspendedPhase {
		t.Fatalf("expected phase %q, got %q (%s)", suspendedPhase, stored.Status.Phase, stored.Status.Message)
	}
	if stored.Status.ObservedGeneration != instance.Generation {
		t.Fatalf("expected observedGeneration %d, got %d", instance.Generation, stored.Status.ObservedGeneration)
	}
	if stored.Status.ObservedImage != "" {
		t.Fatalf("a suspended instance runs no image, got observedImage %q", stored.Status.ObservedImage)
	}
	if result.RequeueAfter != 0 {
		t.Fatalf("a suspended instance must leave the periodic requeue, got %v", result.RequeueAfter)
	}
}

// A volume that could not be emptied in place is released instead, so
// suspension still discards the cache; the return then provisions a fresh one.
func TestSuspendedInstanceReleasesAVolumeItCouldNotEmpty(t *testing.T) {
	instance := suspendableInstance(true)
	claimName := fmt.Sprintf("data-%s-0", instance.Name)
	r := suspensionTestReconciler(t,
		instance,
		statefulSetWithReplicas(instance, 0),
		retainedClaim(instance, 0, "16Gi"),
	)

	reconcileInstance(t, r, instance)
	completeJob(t, r, wipeJobName(instance, claimName), batchv1.JobFailed)
	reconcileInstance(t, r, instance)

	if err := getObject(t, r, claimName, &corev1.PersistentVolumeClaim{}); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the volume that could not be emptied to be released, got %v", err)
	}
	reconcileInstance(t, r, instance)
	stored := &kurav1alpha1.KuraInstance{}
	if err := getObject(t, r, instance.Name, stored); err != nil {
		t.Fatal(err)
	}
	if stored.Status.Phase != suspendedPhase {
		t.Fatalf("expected phase %q once no volume holds content, got %q (%s)", suspendedPhase, stored.Status.Phase, stored.Status.Message)
	}
}

// A marker only says the volume was empty when it was written. A pod that has
// been scheduled onto the volume since may have filled it.
func TestSuspendedInstanceDoesNotTrustAMarkerOnAVolumeAPodHasRunOn(t *testing.T) {
	instance := suspendableInstance(true)
	claimName := fmt.Sprintf("data-%s-0", instance.Name)
	r := suspensionTestReconciler(t,
		instance,
		statefulSetWithReplicas(instance, 2),
		wipedClaim(instance, 0, "16Gi"),
		scheduledKuraPod(instance, 0, "box-1"),
	)

	reconcileInstance(t, r, instance)

	claim := &corev1.PersistentVolumeClaim{}
	if err := getObject(t, r, claimName, claim); err != nil {
		t.Fatal(err)
	}
	if _, ok := claim.Annotations[volumeWipedAnnotation]; ok {
		t.Fatalf("expected the marker to be cleared while a pod is scheduled on the volume, got %v", claim.Annotations)
	}
}

func TestResumingInstanceScalesBackOntoItsVolumes(t *testing.T) {
	instance := suspendableInstance(false)
	r := suspensionTestReconciler(t,
		instance,
		statefulSetWithReplicas(instance, 0),
		wipedClaim(instance, 0, "16Gi"),
		wipedClaim(instance, 1, "16Gi"),
	)

	reconcileInstance(t, r, instance)

	sts := &appsv1.StatefulSet{}
	if err := getObject(t, r, instance.Name, sts); err != nil {
		t.Fatal(err)
	}
	if sts.Spec.Replicas == nil || *sts.Spec.Replicas != 2 {
		t.Fatalf("expected the StatefulSet scaled back to 2, got %v", sts.Spec.Replicas)
	}
	for ordinal := 0; ordinal < 2; ordinal++ {
		if err := getObject(t, r, fmt.Sprintf("data-%s-%d", instance.Name, ordinal), &corev1.PersistentVolumeClaim{}); err != nil {
			t.Fatalf("expected the retained volume to be reused: %v", err)
		}
	}
}

// A return keeps the customer host published while its pods are not scheduled
// yet. Deleting the record for that moment would undo what suspension kept.
func TestResumingInstanceKeepsItsCustomerDNSRecordBeforeAPodIsScheduled(t *testing.T) {
	instance := suspendableInstance(false)
	r := suspensionTestReconciler(t,
		instance,
		statefulSetWithReplicas(instance, 0),
		wipedClaim(instance, 0, "16Gi"),
		wipedClaim(instance, 1, "16Gi"),
		publicDNSEndpoint(instance.Name+"-public-dns", instance.Spec.PublicHost, "203.0.113.50"),
	)

	reconcileInstance(t, r, instance)

	endpoint := &unstructured.Unstructured{}
	endpoint.SetGroupVersionKind(dnsEndpointGVK)
	if err := getObject(t, r, instance.Name+"-public-dns", endpoint); err != nil {
		t.Fatalf("expected the customer DNSEndpoint to survive the return: %v", err)
	}
	if targets := recordTargets(t, endpoint); len(targets) != 1 || targets[0] != "203.0.113.50" {
		t.Fatalf("expected the record to keep its target until a pod is scheduled, got %v", targets)
	}
}

func wipeJobCreated(t *testing.T, instance *kurav1alpha1.KuraInstance, claimName string, age time.Duration) *batchv1.Job {
	t.Helper()
	job := wipeJob(instance, claimName)
	job.CreationTimestamp = metav1.NewTime(time.Now().Add(-age))
	return job
}

func TestWipeJobHasADeadline(t *testing.T) {
	job := wipeJob(suspendableInstance(true), "data-kura-acme-eu-west-1-0")

	if job.Spec.ActiveDeadlineSeconds == nil || *job.Spec.ActiveDeadlineSeconds != int64(wipeJobDeadline.Seconds()) {
		t.Fatalf("expected the wipe job to have a %v deadline, got %v", wipeJobDeadline, job.Spec.ActiveDeadlineSeconds)
	}
}

// A wipe whose pod never runs, because its volume's machine is gone or
// cordoned, never fails on its own. Once it is past its deadline the volume
// is released like one whose wipe failed, so suspension finishes.
func TestSuspendedInstanceReleasesAVolumeWhoseWipeOutlivedItsDeadline(t *testing.T) {
	instance := suspendableInstance(true)
	claimName := fmt.Sprintf("data-%s-0", instance.Name)
	r := suspensionTestReconciler(t,
		instance,
		statefulSetWithReplicas(instance, 0),
		retainedClaim(instance, 0, "16Gi"),
		wipeJobCreated(t, instance, claimName, wipeJobDeadline+time.Minute),
	)

	reconcileInstance(t, r, instance)

	if err := getObject(t, r, claimName, &corev1.PersistentVolumeClaim{}); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the volume whose wipe never finished to be released, got %v", err)
	}
	if err := getObject(t, r, wipeJobName(instance, claimName), &batchv1.Job{}); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the expired wipe job to be removed, got %v", err)
	}
}

func TestSuspendedInstanceWaitsOnAWipeInsideItsDeadline(t *testing.T) {
	instance := suspendableInstance(true)
	claimName := fmt.Sprintf("data-%s-0", instance.Name)
	r := suspensionTestReconciler(t,
		instance,
		statefulSetWithReplicas(instance, 0),
		retainedClaim(instance, 0, "16Gi"),
		wipeJobCreated(t, instance, claimName, time.Minute),
	)

	reconcileInstance(t, r, instance)

	if err := getObject(t, r, claimName, &corev1.PersistentVolumeClaim{}); err != nil {
		t.Fatalf("expected the volume to be kept while its wipe runs: %v", err)
	}
	if err := getObject(t, r, wipeJobName(instance, claimName), &batchv1.Job{}); err != nil {
		t.Fatalf("expected the running wipe job to be kept: %v", err)
	}
}

// A return waits on a wipe still running, but not past the wipe's deadline:
// the volume is released and the return goes ahead once its claim is gone.
func TestResumingInstanceIsNotHeldByAWipeThatOutlivedItsDeadline(t *testing.T) {
	instance := suspendableInstance(false)
	claimName := fmt.Sprintf("data-%s-0", instance.Name)
	r := suspensionTestReconciler(t,
		instance,
		statefulSetWithReplicas(instance, 0),
		retainedClaim(instance, 0, "16Gi"),
		wipedClaim(instance, 1, "16Gi"),
		wipeJobCreated(t, instance, claimName, wipeJobDeadline+time.Minute),
	)

	reconcileInstance(t, r, instance)
	reconcileInstance(t, r, instance)

	sts := &appsv1.StatefulSet{}
	if err := getObject(t, r, instance.Name, sts); err != nil {
		t.Fatal(err)
	}
	if sts.Spec.Replicas == nil || *sts.Spec.Replicas != 2 {
		t.Fatalf("expected the return to scale up once the expired wipe is settled, got %v", sts.Spec.Replicas)
	}
	if err := getObject(t, r, claimName, &corev1.PersistentVolumeClaim{}); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the volume whose wipe never finished to be released, got %v", err)
	}
}

// A retained volume pins its pod to one machine, and nothing reserved room
// there while the instance was suspended. An empty volume costs nothing to
// give up, so it is released and the pod is placed wherever there is room.
func TestResumingInstanceReleasesAnEmptyVolumeWhoseMachineHasNoRoom(t *testing.T) {
	instance := suspendableInstance(false)
	r := suspensionTestReconciler(t,
		instance,
		unschedulableKuraPod(instance, 0),
		wipedClaim(instance, 0, "16Gi"),
		unschedulableKuraPod(instance, 1),
		retainedClaim(instance, 1, "16Gi"),
	)
	pods, err := r.instancePods(context.Background(), instance)
	if err != nil {
		t.Fatal(err)
	}

	if err := r.reconcileWipedVolumes(context.Background(), instance, pods); err != nil {
		t.Fatal(err)
	}

	if err := getObject(t, r, fmt.Sprintf("data-%s-0", instance.Name), &corev1.PersistentVolumeClaim{}); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the empty volume to be released, got %v", err)
	}
	if err := getObject(t, r, instance.Name+"-0", &corev1.Pod{}); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the pod pinned to it to be replaced, got %v", err)
	}
	if err := getObject(t, r, fmt.Sprintf("data-%s-1", instance.Name), &corev1.PersistentVolumeClaim{}); err != nil {
		t.Fatalf("a volume that may hold cache must not be released for a scheduling failure: %v", err)
	}
	if err := getObject(t, r, instance.Name+"-1", &corev1.Pod{}); err != nil {
		t.Fatalf("expected the pod on a volume that may hold cache to stay: %v", err)
	}
}

func TestReconcileClearsTheWipedMarkerOnceAPodIsScheduledOnTheVolume(t *testing.T) {
	instance := suspendableInstance(false)
	pending := kuraPod(instance.Name, instance.Namespace, 1, false)
	pending.Status.Phase = corev1.PodPending
	r := suspensionTestReconciler(t,
		instance,
		scheduledKuraPod(instance, 0, "box-1"),
		wipedClaim(instance, 0, "16Gi"),
		pending,
		wipedClaim(instance, 1, "16Gi"),
	)
	pods, err := r.instancePods(context.Background(), instance)
	if err != nil {
		t.Fatal(err)
	}

	if err := r.reconcileWipedVolumes(context.Background(), instance, pods); err != nil {
		t.Fatal(err)
	}

	scheduled := &corev1.PersistentVolumeClaim{}
	if err := getObject(t, r, fmt.Sprintf("data-%s-0", instance.Name), scheduled); err != nil {
		t.Fatal(err)
	}
	if _, ok := scheduled.Annotations[volumeWipedAnnotation]; ok {
		t.Fatalf("expected the marker cleared once a pod is scheduled on the volume, got %v", scheduled.Annotations)
	}
	unscheduled := &corev1.PersistentVolumeClaim{}
	if err := getObject(t, r, fmt.Sprintf("data-%s-1", instance.Name), unscheduled); err != nil {
		t.Fatal(err)
	}
	if unscheduled.Annotations[volumeWipedAnnotation] == "" {
		t.Fatalf("a pod that never ran cannot have filled its volume, got %v", unscheduled.Annotations)
	}
}

// A return can come with a larger claim. The volumes it would rebuild one at a
// time behind a serving sibling are empty, so they are dropped straight away.
func TestResumingInstanceDropsEmptyVolumesThatAreTooSmall(t *testing.T) {
	instance := suspendableInstance(false)
	sts := statefulSetWithReplicas(instance, 0)
	sts.Spec.VolumeClaimTemplates = []corev1.PersistentVolumeClaim{dataVolumeClaim(instance)}
	r := suspensionTestReconciler(t,
		instance,
		sts,
		wipedClaim(instance, 0, "8Gi"),
		retainedClaim(instance, 1, "8Gi"),
	)

	inProgress, err := r.reconcileDataStorageResize(context.Background(), instance)
	if err != nil {
		t.Fatal(err)
	}

	if !inProgress {
		t.Fatal("expected the StatefulSet to wait for the dropped volume before scaling up")
	}
	if err := getObject(t, r, fmt.Sprintf("data-%s-0", instance.Name), &corev1.PersistentVolumeClaim{}); !apierrors.IsNotFound(err) {
		t.Fatalf("expected the empty, too-small volume to be dropped, got %v", err)
	}
	if err := getObject(t, r, fmt.Sprintf("data-%s-1", instance.Name), &corev1.PersistentVolumeClaim{}); err != nil {
		t.Fatalf("a volume that may hold cache keeps the rolling rebuild: %v", err)
	}
}

func TestPodSchedulingFailureTriggersAReconcile(t *testing.T) {
	predicate := podRoutabilityChangedPredicate()
	pending := kuraPod("kura-acme", "kura", 0, false)
	unschedulable := pending.DeepCopy()
	unschedulable.Status.Conditions = append(unschedulable.Status.Conditions, corev1.PodCondition{
		Type:   corev1.PodScheduled,
		Status: corev1.ConditionFalse,
		Reason: corev1.PodReasonUnschedulable,
	})

	if !predicate.Update(event.UpdateEvent{ObjectOld: pending, ObjectNew: unschedulable}) {
		t.Fatal("expected a pod the scheduler cannot place to trigger a reconcile")
	}
	if predicate.Update(event.UpdateEvent{ObjectOld: unschedulable, ObjectNew: unschedulable.DeepCopy()}) {
		t.Fatal("expected a repeated scheduling failure not to trigger another reconcile")
	}
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
			sts := statefulSetWithReplicas(instance, 2)
			sts.Spec.Template = legacyTemplate(instance, instance.Spec.Image)
			return sts
		}},
		{name: "image change", wantFastProbe: true, existing: func(instance *kurav1alpha1.KuraInstance) *appsv1.StatefulSet {
			sts := statefulSetWithReplicas(instance, 2)
			sts.Spec.Template = legacyTemplate(instance, "ghcr.io/tuist/kura:0.8.0")
			return sts
		}},
		{name: "return from suspension", wantFastProbe: true, existing: func(instance *kurav1alpha1.KuraInstance) *appsv1.StatefulSet {
			sts := statefulSetWithReplicas(instance, 0)
			sts.Spec.Template = legacyTemplate(instance, instance.Spec.Image)
			return sts
		}},
		{name: "already on fast probes", wantFastProbe: true, existing: func(instance *kurav1alpha1.KuraInstance) *appsv1.StatefulSet {
			sts := statefulSetWithReplicas(instance, 2)
			sts.Spec.Template = podTemplate(instance, "", "", "", false, false, true)
			return sts
		}},
	} {
		t.Run(tc.name, func(t *testing.T) {
			instance := suspendableInstance(false)
			objects := []client.Object{instance}
			if sts := tc.existing(instance); sts != nil {
				objects = append(objects, sts)
			}
			r := suspensionTestReconciler(t, objects...)

			if err := r.reconcileStatefulSet(context.Background(), instance); err != nil {
				t.Fatal(err)
			}

			sts := &appsv1.StatefulSet{}
			if err := getObject(t, r, instance.Name, sts); err != nil {
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
// a starting pod or before taking a serving pod out of its Service.
func TestFastProbesKeepTheirBudgets(t *testing.T) {
	budget := func(probe *corev1.Probe) time.Duration {
		threshold := probe.FailureThreshold
		if threshold == 0 {
			threshold = 3
		}
		return time.Duration(probe.PeriodSeconds*threshold) * time.Second
	}

	if got, want := budget(startupProbe(true)), budget(startupProbe(false)); got != want || got != 300*time.Second {
		t.Fatalf("startup budget = %v, want %v (and 300s)", got, want)
	}
	if got, want := budget(readinessProbe(true)), budget(readinessProbe(false)); got != want {
		t.Fatalf("readiness failure budget = %v, want %v", got, want)
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
// names does not matter until one is. Re-deriving it from no evidence moved a
// resuming instance to the co-hosted port and back, and every change is an nginx
// reload the regional gateway rate-limits, holding back the ready endpoint.
func TestReconcileGRPCIngressKeepsItsPortWhileNoPodIsReady(t *testing.T) {
	ctx := context.Background()
	instance := suspendableInstance(false)
	r := suspensionTestReconciler(t, instance)
	backendPort := func() string {
		t.Helper()
		ingress := &networkingv1.Ingress{}
		if err := getObject(t, r, grpcServiceName(instance), ingress); err != nil {
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
