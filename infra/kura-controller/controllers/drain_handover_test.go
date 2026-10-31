package controllers

import (
	"context"
	"encoding/json"
	"testing"
	"time"

	kurav1alpha1 "github.com/tuist/tuist/infra/kura-controller/api/v1alpha1"
	corev1 "k8s.io/api/core/v1"
	policyv1 "k8s.io/api/policy/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	clientgoscheme "k8s.io/client-go/kubernetes/scheme"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"
)

func TestRequestDrainHandover(t *testing.T) {
	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = kurav1alpha1.AddToScheme(scheme)
	holder := servingHolder{InstanceUID: "instance", PodUID: "pod-0", Incarnation: "incarnation-0", Host: "host-0"}
	standby := servingHolder{InstanceUID: "instance", PodUID: "pod-1", Incarnation: "incarnation-1", Host: "host-1"}
	serving := func() servingGrant {
		return servingGrant{Epoch: 14, Phase: "Serving", PodName: "test-0", Holder: holder, ExpiresMS: time.Now().Add(15 * time.Second).UnixMilli()}
	}
	ready := []corev1.PodCondition{{Type: corev1.PodReady, Status: corev1.ConditionTrue}}
	type fixture struct {
		grant   servingGrant
		nodes   map[string]bool
		mutate  func(*kurav1alpha1.KuraInstance)
		pods    func([]corev1.Pod)
		samples func(map[string]runtimeStatus)
	}
	run := func(t *testing.T, f fixture) *kurav1alpha1.PlannedHandoverRequest {
		t.Helper()
		instance := &kurav1alpha1.KuraInstance{ObjectMeta: metav1.ObjectMeta{Name: "test", Namespace: "test", UID: "instance", Annotations: map[string]string{servingRollbackFloor: servingMode}}, Spec: kurav1alpha1.KuraInstanceSpec{ServingMode: servingMode, Replicas: ptr(int32(2))}}
		if f.mutate != nil {
			f.mutate(instance)
		}
		data, _ := json.Marshal(f.grant)
		pods := []corev1.Pod{
			{ObjectMeta: metav1.ObjectMeta{Name: "test-0", Namespace: "test", UID: "pod-0"}, Spec: corev1.PodSpec{NodeName: "host-0"}, Status: corev1.PodStatus{Conditions: ready}},
			{ObjectMeta: metav1.ObjectMeta{Name: "test-1", Namespace: "test", UID: "pod-1"}, Spec: corev1.PodSpec{NodeName: "host-1"}, Status: corev1.PodStatus{Conditions: ready}},
		}
		if f.pods != nil {
			f.pods(pods)
		}
		samples := map[string]runtimeStatus{
			"test-0": {Ready: true, State: "serving", WriterLockOwned: true, BackfillInitialCycle: backfillCycleComplete, ServingAuthority: servingReport{Identity: holder}},
			"test-1": {Ready: true, State: "serving", WriterLockOwned: true, BackfillInitialCycle: backfillCycleComplete, ServingAuthority: servingReport{Identity: standby}},
		}
		if f.samples != nil {
			f.samples(samples)
		}
		objects := []client.Object{instance, &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: "test-serving", Namespace: "test"}, Data: map[string]string{"grant": string(data)}}}
		for name, cordoned := range f.nodes {
			objects = append(objects, &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: name}, Spec: corev1.NodeSpec{Unschedulable: cordoned}})
		}
		r := &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(objects...).Build(), Scheme: scheme}
		if err := r.requestDrainHandover(context.Background(), instance, pods, samples); err != nil {
			t.Fatal(err)
		}
		fresh := &kurav1alpha1.KuraInstance{}
		if err := r.Get(context.Background(), client.ObjectKeyFromObject(instance), fresh); err != nil {
			t.Fatal(err)
		}
		return fresh.Spec.PlannedHandover
	}
	cordoned := map[string]bool{"host-0": true, "host-1": false}

	t.Run("hands a cordoned holder over to the caught-up standby", func(t *testing.T) {
		got := run(t, fixture{grant: serving(), nodes: cordoned})
		want := kurav1alpha1.PlannedHandoverRequest{ID: "drain-incarnat-1", PodName: "test-1", PodUID: "pod-1", Incarnation: "incarnation-1"}
		if got == nil || *got != want {
			t.Fatalf("got %+v", got)
		}
	})

	t.Run("retries after an abandoned automatic handover", func(t *testing.T) {
		grant := serving()
		grant.LastHandover = "drain-incarnat-1"
		got := run(t, fixture{grant: grant, nodes: cordoned})
		if got == nil || got.ID != "drain-incarnat-2" {
			t.Fatalf("got %+v", got)
		}
	})

	t.Run("clears a consumed automatic request", func(t *testing.T) {
		grant := serving()
		grant.LastHandover = "drain-incarnat-1"
		got := run(t, fixture{grant: grant, nodes: cordoned, mutate: func(instance *kurav1alpha1.KuraInstance) {
			instance.Spec.PlannedHandover = &kurav1alpha1.PlannedHandoverRequest{ID: "drain-incarnat-1", PodName: "test-1"}
		}})
		if got != nil {
			t.Fatalf("got %+v", got)
		}
	})

	for name, f := range map[string]fixture{
		"a schedulable holder node": {grant: serving(), nodes: map[string]bool{"host-0": false, "host-1": false}},
		"a cordoned standby node":   {grant: serving(), nodes: map[string]bool{"host-0": true, "host-1": true}},
		"exhausted automatic attempts": {grant: func() servingGrant {
			g := serving()
			g.LastHandover = "drain-incarnat-3"
			return g
		}(), nodes: cordoned},
		"a handover already preparing": {grant: func() servingGrant {
			g := serving()
			g.Handover = &handoverIntent{ID: "operator"}
			return g
		}(), nodes: cordoned},
		"a grant that is fencing": {grant: func() servingGrant { g := serving(); g.Phase = "Fencing"; return g }(), nodes: cordoned},
		"a standby still catching up": {grant: serving(), nodes: cordoned, samples: func(samples map[string]runtimeStatus) {
			sample := samples["test-1"]
			sample.BackfillInitialCycle = "running"
			samples["test-1"] = sample
		}},
		"an unready standby": {grant: serving(), nodes: cordoned, pods: func(pods []corev1.Pod) {
			pods[1].Status.Conditions = nil
		}},
		"an unready holder": {grant: serving(), nodes: cordoned, pods: func(pods []corev1.Pod) {
			pods[0].Status.Conditions = nil
		}},
		"a standby on the holder's node": {grant: serving(), nodes: cordoned, pods: func(pods []corev1.Pod) {
			pods[1].Spec.NodeName = "host-0"
		}},
	} {
		t.Run("requests nothing for "+name, func(t *testing.T) {
			if got := run(t, f); got != nil {
				t.Fatalf("got %+v", got)
			}
		})
	}

	t.Run("leaves an operator request alone", func(t *testing.T) {
		operator := kurav1alpha1.PlannedHandoverRequest{ID: "operator-oct30", PodName: "test-1", PodUID: "pod-1", Incarnation: "incarnation-1"}
		got := run(t, fixture{grant: serving(), nodes: cordoned, mutate: func(instance *kurav1alpha1.KuraInstance) {
			instance.Spec.PlannedHandover = &operator
		}})
		if got == nil || *got != operator {
			t.Fatalf("got %+v", got)
		}
	})
}

func TestReconcilePodDisruptionBudgetForFencedHolder(t *testing.T) {
	scheme := runtime.NewScheme()
	_ = clientgoscheme.AddToScheme(scheme)
	_ = kurav1alpha1.AddToScheme(scheme)
	budget := func(t *testing.T, instance *kurav1alpha1.KuraInstance, grant *servingGrant) *policyv1.PodDisruptionBudget {
		t.Helper()
		objects := []client.Object{instance}
		if grant != nil {
			data, _ := json.Marshal(grant)
			objects = append(objects, &corev1.ConfigMap{ObjectMeta: metav1.ObjectMeta{Name: "test-serving", Namespace: "test"}, Data: map[string]string{"grant": string(data)}})
		}
		r := &KuraInstanceReconciler{Client: fake.NewClientBuilder().WithScheme(scheme).WithObjects(objects...).Build(), Scheme: scheme}
		if err := r.reconcilePodDisruptionBudget(context.Background(), instance); err != nil {
			t.Fatal(err)
		}
		if grant != nil {
			grant.PodName = "test-1"
			data, _ := json.Marshal(grant)
			cm := &corev1.ConfigMap{}
			if err := r.Get(context.Background(), types.NamespacedName{Namespace: "test", Name: "test-serving"}, cm); err != nil {
				t.Fatal(err)
			}
			cm.Data["grant"] = string(data)
			if err := r.Update(context.Background(), cm); err != nil {
				t.Fatal(err)
			}
			if err := r.reconcilePodDisruptionBudget(context.Background(), instance); err != nil {
				t.Fatal(err)
			}
		}
		pdb := &policyv1.PodDisruptionBudget{}
		if err := r.Get(context.Background(), types.NamespacedName{Namespace: "test", Name: "test"}, pdb); err != nil {
			t.Fatal(err)
		}
		return pdb
	}
	fenced := func() *kurav1alpha1.KuraInstance {
		return &kurav1alpha1.KuraInstance{ObjectMeta: metav1.ObjectMeta{Name: "test", Namespace: "test", UID: "instance", Annotations: map[string]string{servingRollbackFloor: servingMode}}, Spec: kurav1alpha1.KuraInstanceSpec{ServingMode: servingMode, Replicas: ptr(int32(2))}}
	}

	t.Run("covers only the holder and follows a handover", func(t *testing.T) {
		pdb := budget(t, fenced(), &servingGrant{Epoch: 14, Phase: "Serving", PodName: "test-0", Holder: servingHolder{InstanceUID: "instance"}})
		if pdb.Spec.MinAvailable != nil || pdb.Spec.MaxUnavailable == nil || pdb.Spec.MaxUnavailable.IntVal != 0 {
			t.Fatalf("got %+v", pdb.Spec)
		}
		if got := pdb.Spec.Selector.MatchLabels[podNameLabel]; got != "test-1" {
			t.Fatalf("selector names %q, want the new holder", got)
		}
	})

	t.Run("keeps the instance-wide budget before the first grant", func(t *testing.T) {
		pdb := budget(t, fenced(), nil)
		if pdb.Spec.MinAvailable == nil || pdb.Spec.MinAvailable.IntVal != 1 || pdb.Spec.MaxUnavailable != nil || pdb.Spec.Selector.MatchLabels[podNameLabel] != "" {
			t.Fatalf("got %+v", pdb.Spec)
		}
	})
}
