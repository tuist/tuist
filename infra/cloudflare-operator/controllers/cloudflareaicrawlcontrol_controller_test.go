package controllers

import (
	"context"
	"encoding/json"
	"testing"

	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	cfv1alpha1 "github.com/tuist/tuist/infra/cloudflare-operator/api/v1alpha1"
)

type fakeAICrawlCF struct {
	current     json.RawMessage
	updateCalls int
	updated     json.RawMessage
}

func (f *fakeAICrawlCF) GetAICrawlControl(_ context.Context, _ string) (json.RawMessage, error) {
	return f.current, nil
}

func (f *fakeAICrawlCF) UpdateAICrawlControl(_ context.Context, _ string, cfg json.RawMessage) (json.RawMessage, error) {
	f.updateCalls++
	f.updated = append(f.updated[:0], cfg...)
	f.current = f.updated
	return f.updated, nil
}

func sampleAICrawlControl(uid string, config []byte) *cfv1alpha1.CloudflareAICrawlControl {
	return &cfv1alpha1.CloudflareAICrawlControl{
		ObjectMeta: metaWithUID("tuist-dev-policy", uid),
		Spec: cfv1alpha1.CloudflareAICrawlControlSpec{
			ZoneID: "zone-abc",
			Config: cfv1alpha1.NewRawJSON(config),
		},
	}
}

// TestAICrawlControlReconcile_PushesWhenDrifted proves the reconciler
// PUTs when live config bytes differ from desired.
func TestAICrawlControlReconcile_PushesWhenDrifted(t *testing.T) {
	desired := []byte(`{"ai_bots_action":"block"}`)
	cr := sampleAICrawlControl("uid-aicc-abc", desired)

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeAICrawlCF{current: []byte(`{"ai_bots_action":"allow"}`)}

	r := &CloudflareAICrawlControlReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.updateCalls != 1 {
		t.Fatalf("expected 1 update call, got %d", cf.updateCalls)
	}
}

// TestAICrawlControlReconcile_NoOpWhenInSync confirms byte-equal
// payloads do not trigger a PUT.
func TestAICrawlControlReconcile_NoOpWhenInSync(t *testing.T) {
	sameBytes := []byte(`{"ai_bots_action":"block"}`)
	cr := sampleAICrawlControl("uid-aicc-sync", sameBytes)

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeAICrawlCF{current: sameBytes}

	r := &CloudflareAICrawlControlReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.updateCalls != 0 {
		t.Fatalf("expected no writes when in sync, got %d", cf.updateCalls)
	}
}
