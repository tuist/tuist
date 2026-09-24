package controllers

import (
	"context"
	"fmt"
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	"k8s.io/apimachinery/pkg/api/resource"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
)

const previousKuraImage = "ghcr.io/tuist/kura:0.8.0"

type heldPod struct {
	milli   int64
	node    string
	phase   corev1.PodPhase
	ordinal int
}

func scheduledPod(ordinal int, milli int64) heldPod {
	return heldPod{milli: milli, node: "box", phase: corev1.PodRunning, ordinal: ordinal}
}

func cpuHoldPod(instance *kurav1alpha1.KuraInstance, p heldPod) *corev1.Pod {
	return &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{
			Name:      fmt.Sprintf("%s-%d", instance.Name, p.ordinal),
			Namespace: instance.Namespace,
			Labels:    selectorLabels(instance),
		},
		Spec: corev1.PodSpec{
			NodeName: p.node,
			Containers: []corev1.Container{{
				Name: kuraContainerName,
				Resources: corev1.ResourceRequirements{Requests: corev1.ResourceList{
					corev1.ResourceCPU: *resource.NewMilliQuantity(p.milli, resource.DecimalSI),
				}},
			}},
		},
		Status: corev1.PodStatus{Phase: p.phase},
	}
}

func templateCPURequest(t *testing.T, r *KuraInstanceReconciler, instance *kurav1alpha1.KuraInstance) (int64, string) {
	t.Helper()
	sts := &appsv1.StatefulSet{}
	if err := getProbeTestObject(t, r, instance.Name, sts); err != nil {
		t.Fatal(err)
	}
	container := templateKuraContainer(&sts.Spec.Template)
	if container == nil {
		t.Fatal("template has no kura container")
	}
	return container.Resources.Requests.Cpu().MilliValue(), sts.ResourceVersion
}

// A replacement pod is built from the template and, on a node its local volume
// pins it to, can only use the room the pod it replaces frees. So the template
// never asks for more than a scheduled pod holds, and between image changes a
// sizing decision does not re-template the StatefulSet, which would roll it.
func TestTemplateCPURequestNeverExceedsWhatAScheduledPodHolds(t *testing.T) {
	for _, tc := range []struct {
		name      string
		autosize  int32
		cap       int32
		ceiling   int32
		liveMilli int64
		liveImage string
		pods      []heldPod
		want      int64
	}{
		{
			name:     "new instance takes the sized request",
			autosize: 400,
			want:     400,
		},
		{
			name:      "growth waits: a deleted pod comes back at the size it freed",
			autosize:  1500,
			ceiling:   1000,
			liveMilli: 150,
			pods:      []heldPod{scheduledPod(0, 150), scheduledPod(1, 150)},
			want:      150,
		},
		{
			name:      "shrink waits for the next image instead of rolling the instance",
			autosize:  50,
			liveMilli: 600,
			pods:      []heldPod{scheduledPod(0, 600), scheduledPod(1, 600)},
			want:      600,
		},
		{
			name:      "a template that drifted above paused pods comes back down to them",
			autosize:  1500,
			ceiling:   1000,
			liveMilli: 1000,
			pods:      []heldPod{scheduledPod(0, 150), scheduledPod(1, 150)},
			want:      150,
		},
		{
			name:      "an image change applies a shrink",
			autosize:  50,
			liveMilli: 600,
			liveImage: previousKuraImage,
			pods:      []heldPod{scheduledPod(0, 600), scheduledPod(1, 600)},
			want:      50,
		},
		{
			name:      "an image change does not grow past what a pod frees",
			autosize:  1000,
			liveMilli: 100,
			liveImage: previousKuraImage,
			pods:      []heldPod{scheduledPod(0, 100), scheduledPod(1, 100)},
			want:      100,
		},
		{
			name:      "the smaller of two pods bounds the template",
			autosize:  600,
			liveMilli: 600,
			pods:      []heldPod{scheduledPod(0, 600), scheduledPod(1, 100)},
			want:      100,
		},
		{
			name:      "a Pending pod holds nothing",
			autosize:  1000,
			liveMilli: 1000,
			pods: []heldPod{
				scheduledPod(0, 150),
				{milli: 1000, phase: corev1.PodPending, ordinal: 1},
			},
			want: 150,
		},
		{
			name:      "a terminal pod has released what it held",
			autosize:  600,
			liveMilli: 600,
			pods: []heldPod{
				scheduledPod(0, 600),
				{milli: 100, node: "box", phase: corev1.PodFailed, ordinal: 1},
			},
			want: 600,
		},
		{
			name:      "the schedule cap still lowers a held request",
			autosize:  600,
			cap:       250,
			liveMilli: 600,
			pods:      []heldPod{scheduledPod(0, 600)},
			want:      250,
		},
		{
			name:      "a lowered plan ceiling still bounds the request",
			autosize:  1500,
			ceiling:   1000,
			liveMilli: 1500,
			pods:      []heldPod{scheduledPod(0, 1500), scheduledPod(1, 1500)},
			want:      1000,
		},
		{
			name:      "no scheduled pod keeps the live request",
			autosize:  50,
			liveMilli: 400,
			pods:      []heldPod{{milli: 400, phase: corev1.PodPending, ordinal: 0}},
			want:      400,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			instance := probeTestInstance()
			instance.Spec.CPUCeilingMilli = tc.ceiling
			instance.Status.CPUAutosize = &kurav1alpha1.KuraInstanceCPUAutosize{
				RequestMilli:     tc.autosize,
				ScheduleCapMilli: tc.cap,
			}
			objects := []client.Object{instance}
			if tc.liveMilli > 0 {
				sts := probeTestStatefulSet(instance, 2)
				sts.Spec.Template = podTemplate(instance, "", "", "", false, false, true)
				container := &sts.Spec.Template.Spec.Containers[0]
				container.Resources.Requests[corev1.ResourceCPU] = *resource.NewMilliQuantity(tc.liveMilli, resource.DecimalSI)
				delete(container.Resources.Limits, corev1.ResourceCPU)
				if tc.liveImage != "" {
					container.Image = tc.liveImage
				}
				objects = append(objects, sts)
			}
			for _, p := range tc.pods {
				objects = append(objects, cpuHoldPod(instance, p))
			}
			r := probeTestReconciler(t, objects...)

			if err := r.reconcileStatefulSet(context.Background(), instance); err != nil {
				t.Fatal(err)
			}
			got, version := templateCPURequest(t, r, instance)
			if got != tc.want {
				t.Fatalf("template CPU request = %dm, want %dm", got, tc.want)
			}

			// The next pass reads back its own decision; re-templating again
			// would mint a revision and roll the instance for nothing.
			if err := r.reconcileStatefulSet(context.Background(), instance); err != nil {
				t.Fatal(err)
			}
			if again, next := templateCPURequest(t, r, instance); again != got || next != version {
				t.Fatalf("second pass moved the template from %dm (rv %s) to %dm (rv %s)", got, version, again, next)
			}
		})
	}
}
