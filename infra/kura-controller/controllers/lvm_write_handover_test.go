package controllers

import (
	"context"
	"encoding/json"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"testing"
)

func TestThinWritePreparationPinsBothProcessesBeforeRouting(t *testing.T) {
	for _, tc := range []struct {
		name                                                                 string
		pending, sourceRestart, targetRestart, podReplacement, wrongEndpoint bool
	}{
		{name: "verified destination"}, {name: "pending retains source", pending: true}, {name: "source restart", sourceRestart: true}, {name: "destination restart", targetRestart: true}, {name: "destination replacement", podReplacement: true}, {name: "other endpoint", wrongEndpoint: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ctx := context.Background()
			f := newResizeHoldFixture(600)
			f.instance.Spec.StorageClassName = thinLocalStorageClass
			source, target := f.servingPod(0, "600m"), f.servingPod(1, "600m")
			source.UID = types.UID("source-uid")
			target.UID = types.UID("target-uid")
			source.Status.PodIP = "10.0.0.1"
			target.Status.PodIP = "10.0.0.2"
			statuses := map[string]runtimeStatus{source.Name: {Ready: true, ConnectionIncarnation: "current-boot", BackfillInitialCycle: backfillCycleComplete}, target.Name: {Ready: true, ConnectionIncarnation: "target-boot", BackfillInitialCycle: backfillCycleComplete}}
			c := fake.NewClientBuilder().WithScheme(meshTestScheme(t)).WithObjects(source, target, &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: peerTLSSecretName(f.instance), Namespace: f.instance.Namespace}}).Build()
			r := &KuraInstanceReconciler{Client: c, RuntimeStatusClient: fakeRuntimeStatusClient{statuses: statuses}, PublicConnectionRetirer: stubConnectionRetirer{ready: !tc.pending}}
			ready, err := r.lvmHandoverReady(ctx, f.instance, 0)
			if err != nil || ready {
				t.Fatalf("initial intent: %v %v", ready, err)
			}
			if err := c.Get(ctx, client.ObjectKeyFromObject(source), source); err != nil {
				t.Fatal(err)
			}
			if source.Annotations[lvmRebuildAnnotation] != "" {
				t.Fatal("demoted before preparation")
			}
			var intent lvmWriteTarget
			if err := json.Unmarshal([]byte(source.Annotations[lvmWriteTargetAnnotation]), &intent); err != nil {
				t.Fatal(err)
			}
			if intent.UID != string(target.UID) || intent.Target.Incarnation != "target-boot" || intent.SourceIncarnation != "current-boot" {
				t.Fatalf("unbound intent: %+v", intent)
			}
			if tc.sourceRestart {
				v := statuses[source.Name]
				v.ConnectionIncarnation = "restarted"
				statuses[source.Name] = v
			}
			if tc.targetRestart {
				v := statuses[target.Name]
				v.ConnectionIncarnation = "restarted"
				statuses[target.Name] = v
			}
			if tc.podReplacement {
				target.UID = "replacement"
				if err := c.Update(ctx, target); err != nil {
					t.Fatal(err)
				}
			}
			ready, err = r.lvmHandoverReady(ctx, f.instance, 0)
			if ready {
				t.Fatal("deleted before endpoint observation")
			}
			if tc.sourceRestart || tc.targetRestart || tc.podReplacement {
				if err == nil {
					t.Fatal("accepted changed identity")
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if err := c.Get(ctx, client.ObjectKeyFromObject(source), source); err != nil {
				t.Fatal(err)
			}
			if tc.pending {
				if source.Annotations[lvmRebuildAnnotation] != "" {
					t.Fatal("demoted while pending")
				}
				return
			}
			if source.Annotations[lvmRebuildAnnotation] == "" {
				t.Fatal("verified donor not marked")
			}
			ref := &corev1.ObjectReference{Name: target.Name, UID: target.UID}
			if tc.wrongEndpoint {
				ref = &corev1.ObjectReference{Name: "unverified", UID: "other"}
			}
			if err := c.Create(ctx, &corev1.Endpoints{ObjectMeta: metav1.ObjectMeta{Name: f.instance.Name, Namespace: f.instance.Namespace}, Subsets: []corev1.EndpointSubset{{Addresses: []corev1.EndpointAddress{{IP: "10.0.0.2", TargetRef: ref}}}}}); err != nil {
				t.Fatal(err)
			}
			ready, err = r.lvmHandoverReady(ctx, f.instance, 0)
			if err != nil || ready == tc.wrongEndpoint {
				t.Fatalf("handoff ready=%v err=%v", ready, err)
			}
		})
	}
}
