package controllers

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func authorityFixture(t *testing.T) (*ServingAuthorityReconciler, *kurav1alpha1.KuraInstance, map[string]runtimeStatus) {
	t.Helper()
	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = kurav1alpha1.AddToScheme(scheme)
	instance := &kurav1alpha1.KuraInstance{ObjectMeta: metav1.ObjectMeta{Name: "test", Namespace: "test", UID: "instance", Annotations: map[string]string{servingRollbackFloor: servingMode, "kura.tuist.dev/serving-authority-uid": "authority"}}, Spec: kurav1alpha1.KuraInstanceSpec{ServingMode: servingMode, Replicas: ptr(int32(2))}}
	objects := []client.Object{instance}
	statuses := map[string]runtimeStatus{}
	for _, name := range []string{"test-0", "test-1"} {
		pod := &corev1.Pod{ObjectMeta: metav1.ObjectMeta{Name: name, Namespace: "test", UID: types.UID(name), Labels: selectorLabels(instance)}, Spec: corev1.PodSpec{NodeName: "host-" + name}, Status: corev1.PodStatus{Phase: corev1.PodRunning, Conditions: []corev1.PodCondition{{Type: corev1.PodReady, Status: corev1.ConditionTrue}}}}
		objects = append(objects, pod)
		statuses[name] = runtimeStatus{Ready: true, State: "serving", WriterLockOwned: true, BackfillInitialCycle: backfillCycleComplete, ServingAuthority: servingReport{Capability: "positive-fence-v1", Enabled: true, Identity: servingHolder{InstanceUID: "instance", PodUID: name, Incarnation: "process-" + name, Host: pod.Spec.NodeName}}}
	}
	data, _ := json.Marshal(servingGrant{Holder: servingHolder{InstanceUID: "instance"}, Phase: "Preparing"})
	objects = append(objects, &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: "test-serving", Namespace: "test", UID: "authority"}, Data: map[string]string{"grant": string(data)}})
	c := fake.NewClientBuilder().WithScheme(scheme).WithStatusSubresource(instance).WithObjects(objects...).Build()
	return &ServingAuthorityReconciler{Client: c, Enabled: true, RuntimeStatusClient: fakeRuntimeStatusClient{statuses: statuses}}, instance, statuses
}
func authorityStep(t *testing.T, r *ServingAuthorityReconciler) servingGrant {
	t.Helper()
	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: "test", Namespace: "test"}}); err != nil {
		t.Fatal(err)
	}
	cm := &corev1.ConfigMap{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: "test-serving", Namespace: "test"}, cm); err != nil {
		t.Fatal(err)
	}
	var grant servingGrant
	if err := json.Unmarshal([]byte(cm.Data["grant"]), &grant); err != nil {
		t.Fatal(err)
	}
	return grant
}
func TestAuthorityNeverPromotesOnTimeoutAndRequiresExactPositiveFence(t *testing.T) {
	r, instance, statuses := authorityFixture(t)
	grant := authorityStep(t, r)
	if grant.Epoch != 1 || grant.PodName != "test-0" {
		t.Fatal(grant)
	}
	delete(statuses, "test-0")
	grant.ExpiresMS = time.Now().UnixMilli() + 1000
	writeAuthorityGrant(t, r, grant)
	grant = authorityStep(t, r)
	if grant.Phase != "Fencing" {
		t.Fatal(grant)
	}
	for range 3 {
		if next := authorityStep(t, r); next.Epoch != 1 || next.PodName != "test-0" {
			t.Fatal("timeout promoted", next)
		}
	}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(instance), instance); err != nil {
		t.Fatal(err)
	}
	target := statuses["test-1"].ServingAuthority.Identity
	instance.Spec.PrimaryPromotion = &kurav1alpha1.PrimaryPromotionRequest{PreviousEpoch: 1, PreviousPodUID: "wrong", PreviousIncarnation: grant.Holder.Incarnation, PreviousHost: grant.Holder.Host, FenceEvidence: "test power-off receipt", PodName: "test-1", PodUID: target.PodUID, Incarnation: target.Incarnation}
	if err := r.Update(context.Background(), instance); err != nil {
		t.Fatal(err)
	}
	if next := authorityStep(t, r); next.Epoch != 1 {
		t.Fatal("wrong identity promoted")
	}
	instance.Spec.PrimaryPromotion.PreviousPodUID = grant.Holder.PodUID
	if err := r.Update(context.Background(), instance); err != nil {
		t.Fatal(err)
	}
	next := authorityStep(t, r)
	if next.Epoch != 2 || next.PodName != "test-1" {
		t.Fatal(next)
	}
	// A recovered ordinal cannot take traffic back.
	statuses["test-0"] = statuses["test-1"]
	if again := authorityStep(t, r); again.Epoch != 2 || again.PodName != "test-1" {
		t.Fatal(again)
	}
}
func TestAuthorityRejectsMissingAndRecreatedEpochRecord(t *testing.T) {
	for _, recreate := range []bool{false, true} {
		r, _, _ := authorityFixture(t)
		authorityStep(t, r)
		cm := &corev1.ConfigMap{}
		key := types.NamespacedName{Name: "test-serving", Namespace: "test"}
		_ = r.Get(context.Background(), key, cm)
		_ = r.Delete(context.Background(), cm)
		if recreate {
			cm.UID = "replacement"
			cm.ResourceVersion = ""
			if err := r.Create(context.Background(), cm); err != nil {
				t.Fatal(err)
			}
		}
		if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: "test", Namespace: "test"}}); err == nil {
			t.Fatal("lost epoch authority accepted")
		}
	}
}
func TestHandoverRequiresMatchingReceiptAndExplicitRevokeAcknowledgment(t *testing.T) {
	r, instance, statuses := authorityFixture(t)
	grant := authorityStep(t, r)
	sample := statuses["test-0"]
	sample.ServingAuthority.Valid = true
	sample.ServingAuthority.Epoch = grant.Epoch
	sample.ServingAuthority.Observed = &grant
	statuses["test-0"] = sample
	target := statuses["test-1"].ServingAuthority.Identity
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(instance), instance); err != nil {
		t.Fatal(err)
	}
	instance.Spec.PlannedHandover = &kurav1alpha1.PlannedHandoverRequest{ID: "handover-1", PodName: "test-1", PodUID: target.PodUID, Incarnation: target.Incarnation}
	if err := r.Update(context.Background(), instance); err != nil {
		t.Fatal(err)
	}
	grant = authorityStep(t, r)
	if grant.Phase != "Quiescing" {
		t.Fatal(grant)
	}
	receipt := &handoverReceipt{ID: "handover-1", Source: grant.Holder, Destination: target, Incarnation: 7, Head: 9, FrontierMS: 100, Records: 3, Digest: "corpus-digest"}
	sample = statuses["test-0"]
	sample.ServingAuthority.Barrier = receipt
	statuses["test-0"] = sample
	if next := authorityStep(t, r); next.Phase != "Quiescing" {
		t.Fatal("unnamed destination accepted")
	}
	sample = statuses["test-1"]
	sample.ServingAuthority.Barrier = receipt
	statuses["test-1"] = sample
	grant = authorityStep(t, r)
	if grant.Phase != "Revoking" || grant.Epoch != 1 {
		t.Fatal(grant)
	}
	sample = statuses["test-0"]
	sample.ServingAuthority.Observed = &grant
	sample.ServingAuthority.Valid = false
	statuses["test-0"] = sample
	if next := authorityStep(t, r); next.Epoch != 1 {
		t.Fatal("missing revoke acknowledgment accepted")
	}
	sample.ServingAuthority.RevokedEpoch = 1
	statuses["test-0"] = sample
	grant = authorityStep(t, r)
	if grant.Epoch != 2 || grant.PodName != "test-1" || grant.Barrier == nil {
		t.Fatal(grant)
	}
}
func TestHandoverDeadlineAbortsWithoutChangingEpoch(t *testing.T) {
	r, _, statuses := authorityFixture(t)
	grant := authorityStep(t, r)
	grant.Phase = "Quiescing"
	grant.Handover = &handoverIntent{ID: "timeout", Destination: statuses["test-1"].ServingAuthority.Identity, DeadlineMS: time.Now().UnixMilli() - 1}
	cm := &corev1.ConfigMap{}
	_ = r.Get(context.Background(), types.NamespacedName{Name: "test-serving", Namespace: "test"}, cm)
	data, _ := json.Marshal(grant)
	cm.Data["grant"] = string(data)
	_ = r.Update(context.Background(), cm)
	next := authorityStep(t, r)
	if next.Epoch != 1 || next.Phase != "Serving" || next.Handover != nil || next.LastHandover != "timeout" {
		t.Fatal(next)
	}
}

func writeAuthorityGrant(t *testing.T, r *ServingAuthorityReconciler, grant servingGrant) {
	t.Helper()
	cm := &corev1.ConfigMap{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: "test-serving", Namespace: "test"}, cm); err != nil {
		t.Fatal(err)
	}
	data, err := json.Marshal(grant)
	if err != nil {
		t.Fatal(err)
	}
	cm.Data["grant"] = string(data)
	if err := r.Update(context.Background(), cm); err != nil {
		t.Fatal(err)
	}
}

func TestAuthorityObservationGapDoesNotRevokeOrRenewValidGrant(t *testing.T) {
	for _, phase := range []string{"Serving", "Quiescing"} {
		for _, gap := range []string{"probe", "readiness"} {
			t.Run(phase+"/"+gap, func(t *testing.T) {
				r, _, statuses := authorityFixture(t)
				grant := authorityStep(t, r)
				grant.Phase = phase
				if phase == "Quiescing" {
					grant.Handover = &handoverIntent{ID: "handover", Destination: statuses["test-1"].ServingAuthority.Identity, DeadlineMS: time.Now().UnixMilli() + 300000}
				}
				// Renewal is due, but an unobserved holder must not receive an extension.
				grant.ExpiresMS = time.Now().UnixMilli() + 9000
				writeAuthorityGrant(t, r, grant)
				sample := statuses["test-0"]
				pod := &corev1.Pod{}
				if err := r.Get(context.Background(), types.NamespacedName{Name: "test-0", Namespace: "test"}, pod); err != nil {
					t.Fatal(err)
				}
				if gap == "probe" {
					delete(statuses, "test-0")
				} else {
					pod.Status.Conditions[0].Status = corev1.ConditionFalse
					if err := r.Status().Update(context.Background(), pod); err != nil {
						t.Fatal(err)
					}
				}
				next := authorityStep(t, r)
				if next.Phase != phase || next.Epoch != grant.Epoch || next.ExpiresMS != grant.ExpiresMS {
					t.Fatalf("observation gap changed valid grant: %+v", next)
				}
				statuses["test-0"] = sample
				pod.Status.Conditions[0].Status = corev1.ConditionTrue
				if err := r.Status().Update(context.Background(), pod); err != nil {
					t.Fatal(err)
				}
				next = authorityStep(t, r)
				if next.Phase != phase || next.Epoch != grant.Epoch || next.Holder != grant.Holder || next.ExpiresMS <= grant.ExpiresMS {
					t.Fatalf("same holder did not resume renewal: %+v", next)
				}
				delete(statuses, "test-0")
				next.ExpiresMS = time.Now().UnixMilli() + 1000
				writeAuthorityGrant(t, r, next)
				next = authorityStep(t, r)
				if next.Phase != "Fencing" || next.Epoch != grant.Epoch || next.Holder != grant.Holder {
					t.Fatalf("expiry did not fence original holder: %+v", next)
				}
			})
		}
	}
}

func TestAuthorityExplicitRefusalFencesWithoutWaitingForExpiry(t *testing.T) {
	for _, phase := range []string{"Serving", "Quiescing"} {
		t.Run(phase, func(t *testing.T) {
			r, _, statuses := authorityFixture(t)
			grant := authorityStep(t, r)
			grant.Phase = phase
			if phase == "Quiescing" {
				grant.Handover = &handoverIntent{ID: "handover"}
			}
			writeAuthorityGrant(t, r, grant)
			sample := statuses["test-0"]
			sample.ServingAuthority.Observed = &grant
			sample.ServingAuthority.Valid = false
			statuses["test-0"] = sample
			next := authorityStep(t, r)
			if next.Phase != "Fencing" || next.Epoch != grant.Epoch {
				t.Fatalf("explicit refusal ignored: %+v", next)
			}
		})
	}
}

func TestAuthorityResumesOnlyThePositivelyFencedLiveWriter(t *testing.T) {
	for _, fault := range []string{"none", "old-runtime", "wrong-epoch", "wrong-observation", "wrong-holder", "restarted", "valid", "mutations", "missing", "handover", "operator-promotion"} {
		t.Run(fault, func(t *testing.T) {
			r, instance, statuses := authorityFixture(t)
			grant := authorityStep(t, r)
			grant.Phase = "Fencing"
			grant.ExpiresMS = time.Now().UnixMilli() - 1000
			if fault == "handover" {
				grant.Handover = &handoverIntent{ID: "interrupted"}
			}
			writeAuthorityGrant(t, r, grant)
			sample := statuses[grant.PodName]
			observed := grant
			sample.ServingAuthority.Observed = &observed
			sample.ServingAuthority.FencedEpoch = grant.Epoch
			switch fault {
			case "old-runtime":
				sample.ServingAuthority.FencedEpoch = 0
			case "wrong-epoch":
				sample.ServingAuthority.FencedEpoch++
			case "wrong-observation":
				observed.Phase = "Serving"
			case "wrong-holder":
				observed.Holder.Incarnation = "another-process"
			case "restarted":
				sample.ServingAuthority.Identity.Incarnation = "replacement"
			case "valid":
				sample.ServingAuthority.Valid = true
			case "mutations":
				sample.ServingAuthority.Mutations = 1
			case "operator-promotion":
				if err := r.Get(context.Background(), client.ObjectKeyFromObject(instance), instance); err != nil {
					t.Fatal(err)
				}
				instance.Spec.PrimaryPromotion = &kurav1alpha1.PrimaryPromotionRequest{PreviousEpoch: grant.Epoch}
				if err := r.Update(context.Background(), instance); err != nil {
					t.Fatal(err)
				}
			}
			statuses[grant.PodName] = sample
			if fault == "missing" {
				delete(statuses, grant.PodName)
			}
			next := authorityStep(t, r)
			if fault == "none" {
				if next.Phase != "Serving" || next.Epoch != grant.Epoch+1 || next.ResumeEpoch != grant.Epoch || next.Holder != grant.Holder || next.PodName != grant.PodName || next.Barrier != nil {
					t.Fatal(next)
				}
			} else if next.Phase != "Fencing" || next.Epoch != grant.Epoch {
				t.Fatal("unsafe resumption", next)
			}
		})
	}
}

func TestAuthorityPreservesResumeBindingWhenReplacementGrantExpires(t *testing.T) {
	r, _, statuses := authorityFixture(t)
	grant := authorityStep(t, r)
	grant.Phase = "Fencing"
	writeAuthorityGrant(t, r, grant)
	sample := statuses[grant.PodName]
	observed := grant
	sample.ServingAuthority.Observed = &observed
	sample.ServingAuthority.FencedEpoch = 1
	statuses[grant.PodName] = sample
	resumed := authorityStep(t, r)
	if resumed.Epoch != 2 || resumed.ResumeEpoch != 1 {
		t.Fatal(resumed)
	}
	// The runtime only received epoch 2 after its deadline, so it reports no
	// valid grant and still owns its positive acknowledgment for epoch 1.
	observed = resumed
	statuses[grant.PodName] = sample
	fenced := authorityStep(t, r)
	if fenced.Phase != "Fencing" || fenced.Epoch != 2 || fenced.ResumeEpoch != 1 {
		t.Fatal(fenced)
	}
	observed = fenced
	sample.ServingAuthority.FencedEpoch = 2
	statuses[grant.PodName] = sample
	next := authorityStep(t, r)
	if next.Phase != "Serving" || next.Epoch != 3 || next.ResumeEpoch != 2 || next.Holder != grant.Holder {
		t.Fatal(next)
	}
}

func TestHandoverWaitsForTheResumedServingGrant(t *testing.T) {
	r, instance, statuses := authorityFixture(t)
	initial := authorityStep(t, r)
	grant := initial
	grant.Epoch, grant.ResumeEpoch = 2, 1
	writeAuthorityGrant(t, r, grant)
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(instance), instance); err != nil {
		t.Fatal(err)
	}
	target := statuses["test-1"].ServingAuthority.Identity
	instance.Spec.PlannedHandover = &kurav1alpha1.PlannedHandoverRequest{ID: "pending", PodName: "test-1", PodUID: target.PodUID, Incarnation: target.Incarnation}
	if err := r.Update(context.Background(), instance); err != nil {
		t.Fatal(err)
	}
	sample := statuses["test-0"]
	initial.Phase = "Fencing"
	sample.ServingAuthority.Observed = &initial
	sample.ServingAuthority.FencedEpoch = 1
	statuses["test-0"] = sample
	if next := authorityStep(t, r); next.Phase != "Serving" || next.Handover != nil {
		t.Fatal("handover started before resume delivery", next)
	}
	sample.ServingAuthority.Observed = &grant
	sample.ServingAuthority.Valid, sample.ServingAuthority.Epoch = true, 2
	statuses["test-0"] = sample
	if next := authorityStep(t, r); next.Phase != "Quiescing" || next.Handover == nil {
		t.Fatal(next)
	}
}

// A terminating replica may finish an old renewal after another replica has
// positively observed expiration. Its stale write must not reopen that grant.
func TestAuthorityConcurrentRenewalCannotOverwriteFencing(t *testing.T) {
	for _, phase := range []string{"Serving", "Quiescing"} {
		t.Run(phase, func(t *testing.T) {
			r, _, statuses := authorityFixture(t)
			grant := authorityStep(t, r)
			grant.Phase = phase
			grant.ExpiresMS = time.Now().UnixMilli() + 5000
			if phase == "Quiescing" {
				grant.Handover = &handoverIntent{ID: "handover", Destination: statuses["test-1"].ServingAuthority.Identity, DeadlineMS: time.Now().UnixMilli() + 300000}
			}
			writeAuthorityGrant(t, r, grant)
			holder := statuses[grant.PodName]
			holder.ServingAuthority.Epoch = grant.Epoch
			holder.ServingAuthority.Valid = true
			holder.ServingAuthority.Observed = &grant
			statuses[grant.PodName] = holder
			oldStatuses := map[string]runtimeStatus{}
			for name, status := range statuses {
				oldStatuses[name] = status
			}
			reached, release := make(chan struct{}), make(chan struct{}, 1)
			defer close(release)
			old := *r
			old.Client = &pausedAuthorityPatch{Client: r.Client, reached: reached, release: release}
			old.RuntimeStatusClient = fakeRuntimeStatusClient{statuses: oldStatuses}
			done := make(chan error, 1)
			go func() {
				_, err := old.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: "test", Namespace: "test"}})
				done <- err
			}()
			select {
			case <-reached:
			case err := <-done:
				t.Fatalf("renewal did not reach grant patch: %v", err)
			case <-time.After(5 * time.Second):
				t.Fatal("renewal did not reach grant patch")
			}
			holder.ServingAuthority.Valid = false
			statuses[grant.PodName] = holder
			fenced := authorityStep(t, r)
			if fenced.Phase != "Fencing" || fenced.Epoch != grant.Epoch {
				t.Fatalf("expected fencing: %+v", fenced)
			}
			release <- struct{}{}
			select {
			case err := <-done:
				if !apierrors.IsConflict(err) {
					t.Fatalf("stale renewal should conflict, got %v", err)
				}
			case <-time.After(5 * time.Second):
				t.Fatal("stale renewal did not finish")
			}
			final := authorityStep(t, r)
			if final.Phase != "Fencing" || final.Epoch != fenced.Epoch || final.ExpiresMS != fenced.ExpiresMS || final.Holder != fenced.Holder {
				t.Fatalf("stale renewal changed fenced authority: %+v", final)
			}
		})
	}
}

type pausedAuthorityPatch struct {
	client.Client
	reached chan struct{}
	release chan struct{}
}

func (c *pausedAuthorityPatch) Patch(ctx context.Context, object client.Object, patch client.Patch, options ...client.PatchOption) error {
	if _, ok := object.(*corev1.ConfigMap); ok && object.GetName() == "test-serving" {
		close(c.reached)
		select {
		case <-c.release:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	return c.Client.Patch(ctx, object, patch, options...)
}

func preparationFixture(t *testing.T) (*ServingAuthorityReconciler, *kurav1alpha1.KuraInstance, map[string]runtimeStatus, servingGrant) {
	t.Helper()
	r, instance, statuses := authorityFixture(t)
	grant := authorityStep(t, r)
	source := statuses["test-0"]
	source.ServingAuthority.Valid, source.ServingAuthority.Epoch, source.ServingAuthority.Observed = true, grant.Epoch, &grant
	statuses["test-0"] = source
	target := statuses["test-1"]
	target.ServingAuthority.PreparationSupported = true
	statuses["test-1"] = target
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(instance), instance); err != nil {
		t.Fatal(err)
	}
	instance.Spec.PlannedHandover = &kurav1alpha1.PlannedHandoverRequest{ID: "prepare", PodName: "test-1", PodUID: target.ServingAuthority.Identity.PodUID, Incarnation: target.ServingAuthority.Identity.Incarnation}
	if err := r.Update(context.Background(), instance); err != nil {
		t.Fatal(err)
	}
	next := authorityStep(t, r)
	if next.Phase != "Serving" || next.Handover == nil || next.Epoch != grant.Epoch || next.Holder != grant.Holder || next.Barrier != nil {
		t.Fatal("preparation changed serving authority", next)
	}
	return r, instance, statuses, next
}

func TestHandoverPreparationRenewsSourceAndRequiresExactCompletion(t *testing.T) {
	r, _, statuses, grant := preparationFixture(t)
	preparationDeadline := grant.Handover.DeadlineMS
	grant.ExpiresMS = time.Now().UnixMilli() + 7000
	writeAuthorityGrant(t, r, grant)
	renewed := authorityStep(t, r)
	if renewed.Phase != "Serving" || renewed.ExpiresMS <= grant.ExpiresMS || renewed.Handover.DeadlineMS != preparationDeadline {
		t.Fatal("pending preparation did not renew only the serving lease", renewed)
	}
	target := statuses["test-1"]
	preparation := &handoverPreparation{Intent: *grant.Handover, Source: grant.Holder, Epoch: grant.Epoch + 1, Complete: true}
	target.ServingAuthority.Preparation = preparation
	statuses["test-1"] = target
	if next := authorityStep(t, r); next.Phase != "Serving" {
		t.Fatal("stale preparation authorized quiescence", next)
	}
	preparation.Epoch = grant.Epoch
	preparation.Intent.Destination.Incarnation = "stale"
	if next := authorityStep(t, r); next.Phase != "Serving" {
		t.Fatal("wrong destination preparation accepted", next)
	}
	preparation.Intent = *grant.Handover
	before := time.Now().UnixMilli()
	next := authorityStep(t, r)
	if next.Phase != "Quiescing" || next.Epoch != grant.Epoch || next.Holder != grant.Holder || next.Barrier != nil || next.Handover.DeadlineMS < before+300000 || next.Handover.DeadlineMS > time.Now().UnixMilli()+300000 {
		t.Fatal("completed preparation did not start the original bounded barrier", next)
	}
}

func TestHandoverPreparationAbortsWithoutGrantingStandbyAuthority(t *testing.T) {
	for _, scenario := range []string{"deadline", "cancel", "destination-replaced", "failure", "source-expired"} {
		t.Run(scenario, func(t *testing.T) {
			r, instance, statuses, grant := preparationFixture(t)
			switch scenario {
			case "deadline":
				grant.Handover.DeadlineMS = time.Now().UnixMilli() - 1
				writeAuthorityGrant(t, r, grant)
			case "cancel":
				instance.Spec.PlannedHandover = nil
				if err := r.Update(context.Background(), instance); err != nil {
					t.Fatal(err)
				}
			case "destination-replaced":
				target := statuses["test-1"]
				target.ServingAuthority.Identity.Incarnation = "replacement"
				statuses["test-1"] = target
			case "failure":
				target := statuses["test-1"]
				target.ServingAuthority.Preparation = &handoverPreparation{Intent: *grant.Handover, Source: grant.Holder, Epoch: grant.Epoch, Error: "retained repair failed"}
				statuses["test-1"] = target
			case "source-expired":
				grant.ExpiresMS = time.Now().UnixMilli()
				writeAuthorityGrant(t, r, grant)
			}
			next := authorityStep(t, r)
			expected := "Serving"
			if scenario == "source-expired" {
				expected = "Fencing"
			}
			if next.Phase != expected || next.Holder != grant.Holder || next.Epoch != grant.Epoch || next.Handover != nil || next.LastHandover != "prepare" || next.Barrier != nil {
				t.Fatal("preparation abort changed writer or retained a blocking intent", next)
			}
		})
	}
}

func exitHolderContainer(t *testing.T, r *ServingAuthorityReconciler, podName, incarnation string) {
	t.Helper()
	pod := &corev1.Pod{}
	if err := r.Get(context.Background(), types.NamespacedName{Name: podName, Namespace: "test"}, pod); err != nil {
		t.Fatal(err)
	}
	pod.Status.ContainerStatuses = []corev1.ContainerStatus{{
		Name:  kuraContainerName,
		State: corev1.ContainerState{Running: &corev1.ContainerStateRunning{}},
		LastTerminationState: corev1.ContainerState{Terminated: &corev1.ContainerStateTerminated{
			ContainerID: "containerd://exited", ExitCode: 137, Reason: "OOMKilled", Message: "kura-incarnation=" + incarnation,
		}},
	}}
	if err := r.Status().Update(context.Background(), pod); err != nil {
		t.Fatal(err)
	}
}

func TestAuthorityRestartsAVerifiedExitedHolderInPlace(t *testing.T) {
	r, _, statuses := authorityFixture(t)
	grant := authorityStep(t, r)
	previous := grant.Holder
	exitHolderContainer(t, r, "test-0", previous.Incarnation)
	restarted := statuses["test-0"]
	restarted.ServingAuthority.Identity.Incarnation = "process-test-0-restarted"
	statuses["test-0"] = restarted

	grant = authorityStep(t, r)
	if grant.Phase != "Fencing" || grant.HolderExit == nil || grant.Epoch != 1 {
		t.Fatal("a verified exit did not fence the holder at once", grant)
	}
	// Until the restarted process reports the inherited volume, nothing moves.
	if next := authorityStep(t, r); next.Phase != "Fencing" || next.Epoch != 1 {
		t.Fatal(next)
	}
	// The restarted process reports itself unready until it is granted.
	restarted.Ready = false
	restarted.ServingAuthority.ExitResume = &previous
	statuses["test-0"] = restarted
	grant = authorityStep(t, r)
	if grant.Phase != "Serving" || grant.Epoch != 2 || grant.PodName != "test-0" || grant.Holder != restarted.ServingAuthority.Identity {
		t.Fatal("the restarted container did not take the writer over", grant)
	}
	if grant.ExitResume == nil || grant.ExitResume.Holder != previous || grant.ExitResume.Epoch != 1 || grant.FenceEvidence == "" {
		t.Fatal(grant)
	}
	// The exited incarnation's message stays on the pod; it never names the new holder.
	if next := authorityStep(t, r); next.Phase != "Serving" || next.Epoch != 2 {
		t.Fatal(next)
	}
}

func TestAuthorityPromotesTheStandbyWhenTheExitedHolderDoesNotRestart(t *testing.T) {
	r, _, statuses := authorityFixture(t)
	grant := authorityStep(t, r)
	exitHolderContainer(t, r, "test-0", grant.Holder.Incarnation)
	delete(statuses, "test-0")
	grant = authorityStep(t, r)
	if grant.Phase != "Fencing" || grant.HolderExit == nil {
		t.Fatal(grant)
	}
	if next := authorityStep(t, r); next.Epoch != 1 {
		t.Fatal("promoted before the restart window elapsed", next)
	}
	grant.HolderExit.AtMS = time.Now().Add(-exitPromotionDelay).UnixMilli()
	writeAuthorityGrant(t, r, grant)
	next := authorityStep(t, r)
	if next.Phase != "Serving" || next.Epoch != 2 || next.PodName != "test-1" || next.Holder != statuses["test-1"].ServingAuthority.Identity || next.FenceEvidence != grant.HolderExit.Evidence || next.ExitResume != nil {
		t.Fatal("the standby was not promoted after the restart window", next)
	}
}

func TestAuthorityNeverTreatsAnotherIncarnationsExitAsFencing(t *testing.T) {
	r, instance, statuses := authorityFixture(t)
	grant := authorityStep(t, r)
	exitHolderContainer(t, r, "test-0", "an-earlier-incarnation")
	exitHolderContainer(t, r, "test-1", statuses["test-1"].ServingAuthority.Identity.Incarnation)
	grant.ExpiresMS = time.Now().UnixMilli() + 5000
	writeAuthorityGrant(t, r, grant)
	if next := authorityStep(t, r); next.Phase != "Serving" || next.HolderExit != nil {
		t.Fatal("an unrelated termination message fenced a live holder", next)
	}

	// An operator promotion for the current epoch takes precedence.
	exitHolderContainer(t, r, "test-0", grant.Holder.Incarnation)
	if next := authorityStep(t, r); next.Phase != "Fencing" {
		t.Fatal(next)
	}
	if err := r.Get(context.Background(), client.ObjectKeyFromObject(instance), instance); err != nil {
		t.Fatal(err)
	}
	instance.Spec.PrimaryPromotion = &kurav1alpha1.PrimaryPromotionRequest{PreviousEpoch: 1, PreviousPodUID: "test-0", PreviousIncarnation: "not-the-holder", PreviousHost: "host-test-0", FenceEvidence: "operator", PodName: "test-1"}
	if err := r.Update(context.Background(), instance); err != nil {
		t.Fatal(err)
	}
	fenced := authorityStep(t, r)
	fenced.HolderExit.AtMS = time.Now().Add(-exitPromotionDelay).UnixMilli()
	writeAuthorityGrant(t, r, fenced)
	if next := authorityStep(t, r); next.Epoch != 1 {
		t.Fatal("automatic promotion overrode an operator request", next)
	}
}
