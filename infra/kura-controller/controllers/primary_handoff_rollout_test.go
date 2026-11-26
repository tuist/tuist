package controllers

import (
	"context"
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

const handoffInstance = "kura-acct-region"

func handoffPod(ordinal int, revision string, ready bool) corev1.Pod {
	pod := *kuraPod(handoffInstance, "kura", ordinal, ready)
	pod.Labels[appsv1.ControllerRevisionHashLabelKey] = revision
	pod.Spec.NodeName = "box"
	pod.UID = types.UID("uid-" + pod.Name)
	return pod
}

func handoffStatefulSet(updateRevision string) *appsv1.StatefulSet {
	sts := handoffStatefulSetObject()
	holdForPrimaryHandoff(sts)
	sts.Status = appsv1.StatefulSetStatus{Replicas: 2, UpdateRevision: updateRevision}
	return sts
}

func handoffStatefulSetObject() *appsv1.StatefulSet {
	sts := &appsv1.StatefulSet{}
	sts.Name, sts.Namespace = handoffInstance, "kura"
	return sts
}

// The order a RollingUpdate gets wrong on a two-replica instance whose primary
// is ordinal 0: the standby goes first, and the primary only once the role has
// left it.
func TestPrimaryHandoffReplacesTheStandbyFirstAndThePrimaryLast(t *testing.T) {
	primary := handoffInstance + "-0"
	for _, tc := range []struct {
		name    string
		pods    []corev1.Pod
		primary string
		replace string
		handoff bool
		release bool
	}{
		{
			name:    "standby before the primary, whatever its ordinal",
			pods:    []corev1.Pod{handoffPod(0, "old", true), handoffPod(1, "old", true)},
			primary: handoffInstance + "-1",
			replace: handoffInstance + "-0",
		},
		{
			name:    "the primary stays while it still holds the role",
			pods:    []corev1.Pod{handoffPod(0, "old", true), handoffPod(1, "new", true)},
			primary: primary,
		},
		{
			name:    "the former primary goes once the role has moved",
			pods:    []corev1.Pod{handoffPod(0, "old", true), handoffPod(1, "new", true)},
			primary: handoffInstance + "-1",
			replace: primary,
			handoff: true,
		},
		{
			name:    "nothing while the updated standby is not Ready",
			pods:    []corev1.Pod{handoffPod(0, "old", true), handoffPod(1, "new", false)},
			primary: handoffInstance + "-1",
		},
		{
			name:    "an unready stale standby serves nothing and goes at once",
			pods:    []corev1.Pod{handoffPod(0, "old", true), handoffPod(1, "old", false)},
			primary: primary,
			replace: handoffInstance + "-1",
		},
		{
			name:    "nothing while a replica is missing",
			pods:    []corev1.Pod{handoffPod(0, "old", true)},
			primary: primary,
		},
		{
			name:    "released once every pod is current",
			pods:    []corev1.Pod{handoffPod(0, "new", true), handoffPod(1, "new", true)},
			primary: primary,
			release: true,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			step := nextPrimaryHandoffStep(handoffInstance, 2, tc.pods, "new", tc.primary)
			got := ""
			if step.replace != nil {
				got = step.replace.Name
			}
			if got != tc.replace || step.handoff != tc.handoff || step.release != tc.release {
				t.Fatalf("step = {replace:%q handoff:%v release:%v wait:%q}, want {replace:%q handoff:%v release:%v}",
					got, step.handoff, step.release, step.wait, tc.replace, tc.handoff, tc.release)
			}
		})
	}
}

// Only the last stale pod is demoted, so the roles move off it to the updated
// replica and stay put while the standby is still being replaced.
func TestPrimaryHandoffDemotesOnlyTheLastStalePod(t *testing.T) {
	sts := handoffStatefulSet("new")
	if got := primaryHandoffDemotions(sts, []corev1.Pod{handoffPod(0, "old", true), handoffPod(1, "old", true)}); len(got) != 0 {
		t.Fatalf("demoted %v with two stale pods, want none", got)
	}
	got := primaryHandoffDemotions(sts, []corev1.Pod{handoffPod(0, "old", true), handoffPod(1, "new", true)})
	if len(got) != 1 || !got[handoffInstance+"-0"] {
		t.Fatalf("demoted %v, want the last stale pod", got)
	}
	if got := primaryHandoffDemotions(handoffStatefulSetObject(), []corev1.Pod{handoffPod(0, "old", true), handoffPod(1, "new", true)}); len(got) != 0 {
		t.Fatalf("demoted %v without the hold, want none", got)
	}
}

// End to end through primary selection: the role moves to the updated standby
// only once it has caught up, never to one still filling.
func TestSelectPrimaryHandsOffToACaughtUpUpdatedStandby(t *testing.T) {
	for _, tc := range []struct {
		cycle string
		want  string
	}{
		{cycle: "pending", want: handoffInstance + "-0"},
		{cycle: backfillCycleComplete, want: handoffInstance + "-1"},
	} {
		t.Run(tc.cycle, func(t *testing.T) {
			instance := evacInstance()
			sts := handoffStatefulSet("new")
			pod0, pod1 := handoffPod(0, "old", true), handoffPod(1, "new", true)
			r, _ := evacReconciler(t, stubRuntimeStatus{byPod: map[string]runtimeStatus{
				pod0.Name: routableStatus(backfillCycleComplete),
				pod1.Name: routableStatus(tc.cycle),
			}}, instance, sts, primaryService(pod0.Name), &pod0, &pod1)
			pods := []corev1.Pod{pod0, pod1}
			primary, _, err := r.selectPrimaryPod(context.Background(), instance, pods, r.sampleRuntimeStatuses(context.Background(), instance, pods))
			if err != nil {
				t.Fatal(err)
			}
			if primary != tc.want {
				t.Fatalf("primary = %s, want %s", primary, tc.want)
			}
		})
	}
}

// The former primary is deleted only once another pod is a ready endpoint of
// the client Service: a repointed selector alone is not traffic landing.
func TestPrimaryHandoffDeletesTheFormerPrimaryOnlyBehindAServingEndpoint(t *testing.T) {
	for _, endpoint := range []string{handoffInstance + "-0", handoffInstance + "-1"} {
		t.Run("endpoint="+endpoint, func(t *testing.T) {
			instance := evacInstance()
			sts := handoffStatefulSet("new")
			pod0, pod1 := handoffPod(0, "old", true), handoffPod(1, "new", true)
			r, c := evacReconciler(t, stubRuntimeStatus{}, instance, sts, servingEndpoints(endpoint), &pod0, &pod1)
			inFlight, err := r.reconcilePrimaryHandoffRollout(context.Background(), instance, pod1.Name)
			if err != nil {
				t.Fatal(err)
			}
			if !inFlight {
				t.Fatal("rollout reported done with a stale pod left")
			}
			wantDeleted := endpoint == pod1.Name
			if deleted := !podExists(t, c, pod0.Name); deleted != wantDeleted {
				t.Fatalf("former primary deleted = %v, want %v", deleted, wantDeleted)
			}
		})
	}
}

// A template change on a plain rolling update is held in the same write, but
// the first render a controller records is never mistaken for a change, and an
// operator's OnDelete is left alone.
func TestTemplateChangeIsHeldForThePrimaryHandoff(t *testing.T) {
	instance := evacInstance()
	render := func(image string) *appsv1.StatefulSet {
		sts := handoffStatefulSetObject()
		sts.ResourceVersion = "7"
		sts.Spec.UpdateStrategy = rollingUpdate()
		sts.Spec.Template.Spec.Containers = []corev1.Container{{Name: kuraContainerName, Image: image}}
		return sts
	}

	first := render("kura:1")
	holdTemplateChangeForPrimaryHandoff(instance, first)
	if primaryHandoffHeld(first) || first.Annotations[renderedTemplateDigestAnnotation] == "" {
		t.Fatalf("first render: strategy %+v annotations %v, want the digest recorded and no hold", first.Spec.UpdateStrategy, first.Annotations)
	}

	unchanged := render("kura:1")
	unchanged.Annotations = map[string]string{renderedTemplateDigestAnnotation: first.Annotations[renderedTemplateDigestAnnotation]}
	holdTemplateChangeForPrimaryHandoff(instance, unchanged)
	if primaryHandoffHeld(unchanged) {
		t.Fatal("held an unchanged template")
	}

	changed := render("kura:2")
	changed.Annotations = map[string]string{renderedTemplateDigestAnnotation: first.Annotations[renderedTemplateDigestAnnotation]}
	holdTemplateChangeForPrimaryHandoff(instance, changed)
	if !primaryHandoffHeld(changed) {
		t.Fatalf("changed template not held: %+v", changed.Spec.UpdateStrategy)
	}

	paused := render("kura:2")
	paused.Spec.UpdateStrategy = onDelete()
	paused.Annotations = map[string]string{renderedTemplateDigestAnnotation: first.Annotations[renderedTemplateDigestAnnotation]}
	holdTemplateChangeForPrimaryHandoff(instance, paused)
	if _, marked := paused.Annotations[primaryHandoffRolloutAnnotation]; marked {
		t.Fatal("took over an operator's OnDelete")
	}

	single := evacInstance()
	single.Spec.Replicas = ptr[int32](1)
	alone := render("kura:2")
	alone.Annotations = map[string]string{renderedTemplateDigestAnnotation: first.Annotations[renderedTemplateDigestAnnotation]}
	holdTemplateChangeForPrimaryHandoff(single, alone)
	if primaryHandoffHeld(alone) {
		t.Fatal("held a single replica, which has nothing to hand off to")
	}
}

// Once every pod runs the template the hold goes back to a rolling update.
func TestPrimaryHandoffReleasesWhenEveryReplicaIsCurrent(t *testing.T) {
	instance := evacInstance()
	sts := handoffStatefulSet("new")
	sts.Status.UpdatedReplicas = 2
	pod0, pod1 := handoffPod(0, "new", true), handoffPod(1, "new", true)
	s := evacScheme(t)
	c := fake.NewClientBuilder().WithScheme(s).WithObjects(instance, sts, &pod0, &pod1).WithStatusSubresource(sts).Build()
	r := &KuraInstanceReconciler{Client: c, Scheme: s}
	inFlight, err := r.reconcilePrimaryHandoffRollout(context.Background(), instance, pod0.Name)
	if err != nil {
		t.Fatal(err)
	}
	got := &appsv1.StatefulSet{}
	if err := c.Get(context.Background(), client.ObjectKeyFromObject(sts), got); err != nil {
		t.Fatal(err)
	}
	if inFlight || got.Spec.UpdateStrategy.Type != appsv1.RollingUpdateStatefulSetStrategyType {
		t.Fatalf("inFlight=%v strategy=%+v, want released", inFlight, got.Spec.UpdateStrategy)
	}
	if _, held := got.Annotations[primaryHandoffRolloutAnnotation]; held {
		t.Fatal("hold annotation kept after release")
	}
}
