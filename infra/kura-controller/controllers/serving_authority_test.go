package controllers

import (
	"context"
	"encoding/json"
	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
	"testing"
	"time"
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
	sample := statuses["test-0"]
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
