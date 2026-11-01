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
			var rebinds []migrationTarget
			var prepares []string
			statuses := map[string]runtimeStatus{source.Name: {Ready: true, ConnectionIncarnation: "current-boot", BackfillInitialCycle: backfillCycleComplete}, target.Name: {Ready: true, ConnectionIncarnation: "target-boot", BackfillInitialCycle: backfillCycleComplete}}
			c := fake.NewClientBuilder().WithScheme(meshTestScheme(t)).WithObjects(source, target, &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: peerTLSSecretName(f.instance), Namespace: f.instance.Namespace}}).Build()
			r := &KuraInstanceReconciler{Client: c, RuntimeStatusClient: fakeRuntimeStatusClient{statuses: statuses}, PublicConnectionRetirer: stubConnectionRetirer{ready: !tc.pending, rebinds: &rebinds, prepares: &prepares}}
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
				v := statuses[target.Name]
				v.ConnectionIncarnation = "restarted"
				statuses[target.Name] = v
				if err := c.Update(ctx, target); err != nil {
					t.Fatal(err)
				}
			}
			ready, err = r.lvmHandoverReady(ctx, f.instance, 0)
			if ready {
				t.Fatal("deleted before endpoint observation")
			}
			if tc.sourceRestart {
				// The restarted source acknowledged writes no bridge proved. It is
				// prepared again from scratch before anything moves.
				if err != nil || len(rebinds) != 0 {
					t.Fatalf("source restart: err=%v rebinds=%+v", err, rebinds)
				}
				if err := c.Get(ctx, client.ObjectKeyFromObject(source), source); err != nil {
					t.Fatal(err)
				}
				if err := json.Unmarshal([]byte(source.Annotations[lvmWriteTargetAnnotation]), &intent); err != nil {
					t.Fatal(err)
				}
				if intent.SourceIncarnation != "restarted" || intent.Target.Incarnation != "target-boot" || source.Annotations[lvmRebuildAnnotation] != "" {
					t.Fatalf("source restart intent: %+v", intent)
				}
				if _, err := r.lvmHandoverReady(ctx, f.instance, 0); err != nil {
					t.Fatal(err)
				}
				if prepares[len(prepares)-1] != "restarted" {
					t.Fatalf("prepared %v, want the restarted source process", prepares)
				}
				if err := c.Get(ctx, client.ObjectKeyFromObject(source), source); err != nil {
					t.Fatal(err)
				}
				if source.Annotations[lvmRebuildAnnotation] == "" {
					t.Fatal("re-prepared source not marked")
				}
				return
			}
			if tc.targetRestart || tc.podReplacement {
				// The destination restarted its process, in the same pod or a
				// replacement at the same URL. The source re-proves its data on the
				// new process before the intent names it.
				if err != nil {
					t.Fatal(err)
				}
				if len(rebinds) != 2 || rebinds[0].Incarnation != "target-boot" || rebinds[1].Incarnation != "restarted" {
					t.Fatalf("rebinds = %+v", rebinds)
				}
				if err := c.Get(ctx, client.ObjectKeyFromObject(source), source); err != nil {
					t.Fatal(err)
				}
				if err := json.Unmarshal([]byte(source.Annotations[lvmWriteTargetAnnotation]), &intent); err != nil {
					t.Fatal(err)
				}
				if intent.Target.Incarnation != "restarted" || intent.UID != string(target.UID) || source.Annotations[lvmRebuildAnnotation] != "" {
					t.Fatalf("rebound intent: %+v", intent)
				}
				ready, err = r.lvmHandoverReady(ctx, f.instance, 0)
				if err != nil || ready {
					t.Fatalf("after rebind: ready=%v err=%v", ready, err)
				}
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

func TestThinHandoffAbortsOnlyAnUndemotedSourceWhoseNodeWasUnselected(t *testing.T) {
	for _, tc := range []struct {
		name                         string
		selected, demoted, wantAbort bool
	}{
		{name: "unselected source is disarmed", wantAbort: true},
		{name: "selected source keeps its bridge", selected: true},
		{name: "demoted source is never disarmed", demoted: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			ctx := context.Background()
			f := newResizeHoldFixture(600)
			f.instance.Spec.StorageClassName = thinLocalStorageClass
			f.instance.Spec.DiskResource = string(kuraDiskResource)
			source, target := f.servingPod(0, "600m"), f.servingPod(1, "600m")
			source.Spec.NodeName = "source"
			intent := lvmWriteTarget{Pod: target.Name, UID: "target-uid", SourceIncarnation: "current-boot", Target: migrationTarget{URL: renderPodNodeURL(f.instance, target.Name, f.instance.Namespace), Incarnation: "target-boot"}}
			raw, _ := json.Marshal(intent)
			source.Annotations = map[string]string{lvmWriteTargetAnnotation: string(raw)}
			if tc.demoted {
				source.Annotations[lvmRebuildAnnotation] = "true"
			}
			node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "source"}, Spec: corev1.NodeSpec{Unschedulable: true}}
			if tc.selected {
				node.Annotations = map[string]string{lvmMigrationNodeAnnotation: "true"}
			}
			claim := f.claim(0, "32Gi")
			claim.Spec.StorageClassName = ptr(thinLocalStorageClass)
			claim.Spec.VolumeName = "legacy"
			pv := &corev1.PersistentVolume{ObjectMeta: metav1.ObjectMeta{Name: "legacy"}, Spec: corev1.PersistentVolumeSpec{
				PersistentVolumeSource: corev1.PersistentVolumeSource{CSI: &corev1.CSIPersistentVolumeSource{Driver: "kura-volumes.tuist.dev", VolumeHandle: "legacy", VolumeAttributes: map[string]string{"backing": "file"}}},
				NodeAffinity:           &corev1.VolumeNodeAffinity{Required: &corev1.NodeSelector{NodeSelectorTerms: []corev1.NodeSelectorTerm{{MatchExpressions: []corev1.NodeSelectorRequirement{{Key: corev1.LabelHostname, Operator: corev1.NodeSelectorOpIn, Values: []string{"source"}}}}}}},
			}}
			var aborts []migrationTarget
			statuses := map[string]runtimeStatus{source.Name: {Ready: true, ConnectionIncarnation: "current-boot"}, target.Name: {Ready: true, ConnectionIncarnation: "target-boot"}}
			c := fake.NewClientBuilder().WithScheme(meshTestScheme(t)).WithObjects(source, target, node, claim, pv, &corev1.Secret{ObjectMeta: metav1.ObjectMeta{Name: peerTLSSecretName(f.instance), Namespace: f.instance.Namespace}}).Build()
			r := &KuraInstanceReconciler{Client: c, RuntimeStatusClient: fakeRuntimeStatusClient{statuses: statuses}, PublicConnectionRetirer: stubConnectionRetirer{aborts: &aborts}}
			if err := r.abortUnselectedLVMHandoffs(ctx, f.instance); err != nil {
				t.Fatal(err)
			}
			if err := c.Get(ctx, client.ObjectKeyFromObject(source), source); err != nil {
				t.Fatal(err)
			}
			if tc.wantAbort != (len(aborts) == 1) || (len(aborts) == 1 && aborts[0] != intent.Target) {
				t.Fatalf("aborts = %+v, want abort %v", aborts, tc.wantAbort)
			}
			if tc.wantAbort == (source.Annotations[lvmWriteTargetAnnotation] != "") {
				t.Fatalf("write target annotation = %q after abort=%v", source.Annotations[lvmWriteTargetAnnotation], tc.wantAbort)
			}
		})
	}
}
