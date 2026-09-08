package controllers

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	discoveryv1 "k8s.io/api/discovery/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

func privateRolloutFixture(t *testing.T) (*KuraInstanceReconciler, *kurav1alpha1.KuraInstance, []*corev1.Pod) {
	t.Helper()
	instance := evacInstance()
	instance.UID = "instance"
	instance.Spec.Private = true
	instance.Spec.ExposeNodePort = true
	instance.Spec.StorageSize = "50Gi"
	instance.Spec.Image = "kura:new"
	pods := []*corev1.Pod{evacPod(instance.Name+"-0", "runner-cache", true), evacPod(instance.Name+"-1", "runner-cache", true)}
	objects := []client.Object{instance, &appsv1.StatefulSet{
		ObjectMeta: metav1.ObjectMeta{Name: instance.Name, Namespace: instance.Namespace, Generation: 1},
		Spec: appsv1.StatefulSetSpec{
			Replicas: ptr[int32](2), UpdateStrategy: appsv1.StatefulSetUpdateStrategy{Type: appsv1.OnDeleteStatefulSetStrategyType},
		},
		Status: appsv1.StatefulSetStatus{ObservedGeneration: 1, CurrentRevision: "old", UpdateRevision: "new"},
	}}
	for _, pod := range pods {
		pod.UID = types.UID(pod.Name + "-original")
		pod.Labels[appsv1.StatefulSetRevisionLabel] = "old"
		objects = append(objects, pod, &corev1.PersistentVolumeClaim{ObjectMeta: metav1.ObjectMeta{
			Name: "data-" + pod.Name, Namespace: instance.Namespace, UID: types.UID("data-" + pod.Name),
		}})
	}
	for _, name := range []string{instance.Name, externalServiceName(instance)} {
		service := primaryService(pods[0].Name)
		service.Name = name
		if name == externalServiceName(instance) {
			service.Spec.Type = corev1.ServiceTypeNodePort
			service.Spec.Ports = []corev1.ServicePort{{Name: "http", Port: httpPort, NodePort: 30400}}
		}
		objects = append(objects, service, privateRolloutSlice(name, pods[0]))
	}
	node := evacNode("runner-cache", false)
	node.Labels["tuist.dev/pn-ipv4"] = "172.16.0.2"
	objects = append(objects, node)
	scheme := runtime.NewScheme()
	if err := clientgoscheme.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	if err := kurav1alpha1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	c := fake.NewClientBuilder().WithScheme(scheme).WithStatusSubresource(&appsv1.StatefulSet{}).WithObjects(objects...).Build()
	r := &KuraInstanceReconciler{Client: c, APIReader: c, Scheme: scheme, RuntimeStatusClient: stubRuntimeStatus{byPod: map[string]runtimeStatus{
		pods[0].Name: routableStatus(backfillCycleComplete), pods[1].Name: routableStatus(backfillCycleComplete),
	}}}
	return r, instance, pods
}

func privateRolloutSlice(service string, pod *corev1.Pod) *discoveryv1.EndpointSlice {
	return &discoveryv1.EndpointSlice{
		ObjectMeta:  metav1.ObjectMeta{Name: service + "-slice", Namespace: pod.Namespace, Labels: map[string]string{discoveryv1.LabelServiceName: service}},
		AddressType: discoveryv1.AddressTypeIPv4,
		Endpoints: []discoveryv1.Endpoint{{
			Addresses: []string{pod.Status.PodIP}, Conditions: discoveryv1.EndpointConditions{Ready: ptr(true)},
			TargetRef: &corev1.ObjectReference{Kind: "Pod", Name: pod.Name, Namespace: pod.Namespace, UID: pod.UID},
		}},
	}
}

func TestPrivateRolloutKeepsCacheThroughBothReplacements(t *testing.T) {
	ctx := context.Background()
	r, instance, pods := privateRolloutFixture(t)
	now := time.Now()
	step := func() {
		t.Helper()
		if err := r.reconcilePrivateRollout(ctx, instance, now); err != nil {
			t.Fatal(err)
		}
	}
	assertPresent := func(pod *corev1.Pod, present bool) {
		t.Helper()
		err := r.Get(ctx, client.ObjectKeyFromObject(pod), &corev1.Pod{})
		if (present && err != nil) || (!present && !apierrors.IsNotFound(err)) {
			t.Fatalf("pod %s present=%t: %v", pod.Name, present, err)
		}
	}
	step() // Record observed endpoint propagation before touching the standby.
	assertPresent(pods[0], true)
	assertPresent(pods[1], true)
	now = now.Add(time.Minute)
	step()
	assertPresent(pods[0], true)
	assertPresent(pods[1], false)

	// StatefulSet brings back the same ordinal on its own retained claim.
	pods[1].ResourceVersion = ""
	pods[1].UID = "standby-new-process"
	pods[1].Labels[appsv1.StatefulSetRevisionLabel] = "new"
	if err := r.Create(ctx, pods[1]); err != nil {
		t.Fatal(err)
	}
	samples := r.RuntimeStatusClient.(stubRuntimeStatus).byPod
	samples[pods[1].Name] = routableStatus("running")
	selectPrimary := func() string {
		t.Helper()
		primary, err := r.selectPrimaryPod(ctx, instance, []corev1.Pod{*pods[0], *pods[1]}, samples)
		if err != nil {
			t.Fatal(err)
		}
		return primary
	}
	if primary := selectPrimary(); primary != pods[0].Name {
		t.Fatalf("ready but backfilling standby stole traffic: %s", primary)
	}
	step()
	assertPresent(pods[0], true)
	samples[pods[1].Name] = routableStatus(backfillCycleComplete)
	primary := selectPrimary()
	if primary != pods[1].Name {
		t.Fatalf("caught-up standby should take traffic: %s", primary)
	}
	if err := r.reconcileService(ctx, instance, primary); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcileExternalService(ctx, instance, primary); err != nil {
		t.Fatal(err)
	}
	step() // Selectors changed but both endpoint slices still name ordinal 0.
	assertPresent(pods[0], true)
	for _, name := range []string{instance.Name, externalServiceName(instance)} {
		slice := &discoveryv1.EndpointSlice{}
		if err := r.Get(ctx, client.ObjectKey{Namespace: instance.Namespace, Name: name + "-slice"}, slice); err != nil {
			t.Fatal(err)
		}
		slice.Endpoints = privateRolloutSlice(name, pods[1]).Endpoints
		if err := r.Update(ctx, slice); err != nil {
			t.Fatal(err)
		}
		step() // NodePort must also propagate, then a fresh buffer must elapse.
		assertPresent(pods[0], true)
	}
	// Recreate the reconciler: handover timing must survive controller restart.
	r = &KuraInstanceReconciler{Client: r.Client, APIReader: r.APIReader, Scheme: r.Scheme, RuntimeStatusClient: r.RuntimeStatusClient}
	now = now.Add(time.Second)
	step()
	assertPresent(pods[0], true)
	now = now.Add(time.Minute)
	step()
	assertPresent(pods[0], false)
	assertPresent(pods[1], true)
	for _, pod := range pods {
		claim := &corev1.PersistentVolumeClaim{}
		if err := r.Get(ctx, client.ObjectKey{Namespace: instance.Namespace, Name: "data-" + pod.Name}, claim); err != nil || claim.UID != types.UID("data-"+pod.Name) {
			t.Fatalf("rollout must retain the original independent claim: %+v, %v", claim, err)
		}
	}
	endpoint, err := r.externalEndpoint(ctx, instance, primary)
	if err != nil || endpoint.nodePortCache != 30400 || endpoint.nodeAddress != "172.16.0.2" {
		t.Fatalf("NodePort address changed during process handover: %+v, %v", endpoint, err)
	}
	pods[0].ResourceVersion = ""
	pods[0].UID = "former-primary-new-process"
	pods[0].Labels[appsv1.StatefulSetRevisionLabel] = "new"
	if err := r.Create(ctx, pods[0]); err != nil {
		t.Fatal(err)
	}
	if selected := selectPrimary(); selected != primary {
		t.Fatalf("updated ordinal 0 must not steal the sticky primary: %s", selected)
	}
	step()
	assertPresent(pods[0], true)
	assertPresent(pods[1], true)
}

func TestPrivateRolloutHoldsUnsafeProgress(t *testing.T) {
	for _, scenario := range []string{"missing standby", "pending standby", "terminating standby", "backfilling", "degraded", "unreadable", "outbox", "ring mismatch", "scale-up ring skew", "different host", "unobserved revision", "stale endpoint UID", "endpoint regression"} {
		t.Run(scenario, func(t *testing.T) {
			ctx := context.Background()
			r, instance, pods := privateRolloutFixture(t)
			// Only the primary remains on the old revision, as during migration.
			pods[1].Labels[appsv1.StatefulSetRevisionLabel] = "new"
			samples := r.RuntimeStatusClient.(stubRuntimeStatus).byPod
			status := samples[pods[1].Name]
			switch scenario {
			case "pending standby":
				pods[1].Status.Conditions = nil
			case "terminating standby":
				pods[1].DeletionTimestamp = ptr(metav1.Now())
			case "backfilling":
				status.BackfillInitialCycle = "running"
			case "degraded":
				status.BackfillInitialCycle = backfillCycleDegraded
			case "outbox":
				status.OutboxMessages = 1
			case "ring mismatch":
				status.RingFingerprint = "isolated"
			case "scale-up ring skew":
				original := samples[pods[0].Name]
				original.RingMembers = 1
				samples[pods[0].Name] = original
				status.BackfillInitialCycle = "pending"
			case "different host":
				pods[1].Spec.NodeName = "another-box"
			case "unobserved revision":
				sts := &appsv1.StatefulSet{}
				if err := r.Get(ctx, client.ObjectKeyFromObject(instance), sts); err != nil {
					t.Fatal(err)
				}
				sts.Generation++
				if err := r.Update(ctx, sts); err != nil {
					t.Fatal(err)
				}
			}
			samples[pods[1].Name] = status
			if scenario == "unreadable" {
				delete(samples, pods[1].Name)
			}
			listed := []corev1.Pod{*pods[0], *pods[1]}
			if scenario == "missing standby" {
				listed = listed[:1]
				if err := r.Delete(ctx, pods[1]); err != nil {
					t.Fatal(err)
				}
			}
			primary, err := r.selectPrimaryPod(ctx, instance, listed, samples)
			if err != nil {
				t.Fatal(err)
			}
			if scenario != "stale endpoint UID" && scenario != "endpoint regression" && primary != pods[0].Name {
				t.Fatalf("unsafe handover to %s", primary)
			}
			// Even if both selectors name the new primary, stale endpoint state
			// must prevent deleting the previous serving process.
			if scenario == "stale endpoint UID" || scenario == "endpoint regression" {
				if err := r.Update(ctx, pods[1]); err != nil {
					t.Fatal(err)
				}
				for _, name := range []string{instance.Name, externalServiceName(instance)} {
					service := &corev1.Service{}
					if err := r.Get(ctx, client.ObjectKey{Namespace: instance.Namespace, Name: name}, service); err != nil {
						t.Fatal(err)
					}
					service.Spec.Selector[podNameLabel] = pods[1].Name
					if err := r.Update(ctx, service); err != nil {
						t.Fatal(err)
					}
				}
				sts := &appsv1.StatefulSet{}
				if err := r.Get(ctx, client.ObjectKeyFromObject(instance), sts); err != nil {
					t.Fatal(err)
				}
				old, _ := json.Marshal(privateRolloutHandover{Departing: pods[0].UID, Serving: pods[1].UID, Revision: "new", Since: time.Now().Add(-time.Hour)})
				sts.Annotations = map[string]string{privateRolloutHandoverAnnotation: string(old)}
				if err := r.Update(ctx, sts); err != nil {
					t.Fatal(err)
				}
				if scenario == "stale endpoint UID" {
					slice := &discoveryv1.EndpointSlice{}
					if err := r.Get(ctx, client.ObjectKey{Namespace: instance.Namespace, Name: instance.Name + "-slice"}, slice); err != nil {
						t.Fatal(err)
					}
					slice.Endpoints = privateRolloutSlice(instance.Name, pods[1]).Endpoints
					slice.Endpoints[0].TargetRef.UID = "previous-incarnation"
					if err := r.Update(ctx, slice); err != nil {
						t.Fatal(err)
					}
				}
				if err := r.reconcilePrivateRollout(ctx, instance, time.Now()); err != nil {
					t.Fatal(err)
				}
				if err := r.Get(ctx, client.ObjectKeyFromObject(instance), sts); err != nil || sts.Annotations[privateRolloutHandoverAnnotation] != "" {
					t.Fatalf("unsafe endpoints must reset propagation timer: %v", err)
				}
			}
			if err := r.Get(ctx, client.ObjectKeyFromObject(pods[0]), &corev1.Pod{}); err != nil {
				t.Fatalf("original cache must survive: %v", err)
			}
		})
	}
}

func TestPrivateRolloutStillFailsOverAfterPrimaryFailure(t *testing.T) {
	r, instance, pods := privateRolloutFixture(t)
	samples := r.RuntimeStatusClient.(stubRuntimeStatus).byPod
	pods[0].Status.Conditions = nil
	samples[pods[1].Name] = routableStatus("pending")
	primary, err := r.selectPrimaryPod(context.Background(), instance, []corev1.Pod{*pods[0], *pods[1]}, samples)
	if err != nil || primary != pods[1].Name {
		t.Fatalf("a failed primary must not block emergency failover: %s, %v", primary, err)
	}
}

func TestPrivateRolloutRepairsUnreadyStandbyWithOneServingRingMember(t *testing.T) {
	ctx := context.Background()
	r, instance, pods := privateRolloutFixture(t)
	standby := &corev1.Pod{}
	if err := r.Get(ctx, client.ObjectKeyFromObject(pods[1]), standby); err != nil {
		t.Fatal(err)
	}
	standby.Status.Conditions = nil
	if err := r.Status().Update(ctx, standby); err != nil {
		t.Fatal(err)
	}
	standby.Spec.NodeName = ""
	if err := r.Update(ctx, standby); err != nil {
		t.Fatal(err)
	}
	samples := r.RuntimeStatusClient.(stubRuntimeStatus).byPod
	primaryStatus := samples[pods[0].Name]
	primaryStatus.RingMembers = 1
	samples[pods[0].Name] = primaryStatus
	delete(samples, pods[1].Name)
	now := time.Now()
	for _, at := range []time.Time{now, now.Add(time.Minute)} {
		if err := r.reconcilePrivateRollout(ctx, instance, at); err != nil {
			t.Fatal(err)
		}
	}
	if err := r.Get(ctx, client.ObjectKeyFromObject(pods[1]), &corev1.Pod{}); !apierrors.IsNotFound(err) {
		t.Fatalf("failed standby should be recreated on the repaired template: %v", err)
	}
	if err := r.Get(ctx, client.ObjectKeyFromObject(pods[0]), &corev1.Pod{}); err != nil {
		t.Fatalf("serving primary must survive standby repair: %v", err)
	}
}

func TestPrivateRolloutScaleUpRetainsPrimaryAndBudgets(t *testing.T) {
	ctx := context.Background()
	r, instance, pods := privateRolloutFixture(t)
	if err := r.Delete(ctx, pods[1]); err != nil {
		t.Fatal(err)
	}
	sts := &appsv1.StatefulSet{}
	if err := r.Get(ctx, client.ObjectKeyFromObject(instance), sts); err != nil {
		t.Fatal(err)
	}
	sts.Spec.Replicas = ptr[int32](1)
	sts.Spec.UpdateStrategy.Type = appsv1.RollingUpdateStatefulSetStrategyType
	sts.Spec.VolumeClaimTemplates = []corev1.PersistentVolumeClaim{dataVolumeClaim(instance)}
	if err := r.Update(ctx, sts); err != nil {
		t.Fatal(err)
	}
	if err := r.reconcileStatefulSet(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.Get(ctx, client.ObjectKeyFromObject(instance), sts); err != nil {
		t.Fatal(err)
	}
	if *sts.Spec.Replicas != 2 || sts.Spec.UpdateStrategy.Type != appsv1.OnDeleteStatefulSetStrategyType {
		t.Fatal("scale-up and controlled rollout must be one StatefulSet update")
	}
	if len(sts.Spec.VolumeClaimTemplates) != 1 || sts.Spec.VolumeClaimTemplates[0].Name != "data" {
		t.Fatal("retain ordinal PVC identity during migration")
	}
	resources := sts.Spec.Template.Spec.Containers[0].Resources
	if resources.Requests.StorageEphemeral().String() != "50Gi" || resources.Requests.Memory().String() != "2Gi" || resources.Limits.Memory().String() != "4Gi" {
		t.Fatalf("each replica needs a full independent reservation: %+v", resources)
	}
	if len(sts.Spec.Template.Spec.Affinity.PodAffinity.RequiredDuringSchedulingIgnoredDuringExecution) != 1 {
		t.Fatal("NodePort replicas must co-locate to preserve the serving address")
	}
	if sts.Spec.Template.Spec.Containers[0].Lifecycle.PreStop == nil || *sts.Spec.Template.Spec.TerminationGracePeriodSeconds != terminationGracePeriodSeconds() {
		t.Fatal("rollout must retain the runtime drain hook and full grace budget")
	}
	if err := r.reconcilePrivateRollout(ctx, instance, time.Now().Add(time.Hour)); err != nil {
		t.Fatal(err)
	}
	if err := r.replaceUnreadyPodsForImageChange(ctx, instance); err != nil {
		t.Fatal(err)
	}
	if err := r.Get(ctx, client.ObjectKeyFromObject(pods[0]), &corev1.Pod{}); err != nil {
		t.Fatalf("scale-up must not restart the only existing process: %v", err)
	}
	sts.Status.ReadyReplicas = 2
	sts.Status.UpdatedReplicas = 2
	if got := rolloutStatusFromStatefulSet(instance, sts); got.phase != "Ready" {
		t.Fatalf("OnDelete completion must use updated replicas, not stale CurrentRevision: %+v", got)
	}
}
