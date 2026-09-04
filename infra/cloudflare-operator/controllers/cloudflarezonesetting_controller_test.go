package controllers

import (
	"context"
	"encoding/json"
	"testing"

	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	cfv1alpha1 "github.com/tuist/tuist/infra/cloudflare-operator/api/v1alpha1"
	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

type fakeZoneSettingCF struct {
	current     *cloudflare.ZoneSetting
	getErr      error
	updated     json.RawMessage
	updateErr   error
	updateCalls int
}

func (f *fakeZoneSettingCF) GetZoneSetting(_ context.Context, _, _ string) (*cloudflare.ZoneSetting, error) {
	return f.current, f.getErr
}

func (f *fakeZoneSettingCF) UpdateZoneSetting(_ context.Context, _, settingID string, value json.RawMessage) (*cloudflare.ZoneSetting, error) {
	f.updateCalls++
	if f.updateErr != nil {
		return nil, f.updateErr
	}
	f.updated = append(f.updated[:0], value...)
	return &cloudflare.ZoneSetting{ID: settingID, Value: value}, nil
}

func sampleZoneSetting(uid, settingID string, value []byte) *cfv1alpha1.CloudflareZoneSetting {
	return &cfv1alpha1.CloudflareZoneSetting{
		ObjectMeta: metaWithUID("challenge-passage-6h", uid),
		Spec: cfv1alpha1.CloudflareZoneSettingSpec{
			ZoneID:    "zone-abc",
			SettingID: settingID,
			Value:     cfv1alpha1.NewRawJSON(value),
		},
	}
}

// TestZoneSettingReconcile_UpdatesWhenValueDiffers is the meaningful
// path: CR says 21600, live says 1800, reconciler PATCHes.
func TestZoneSettingReconcile_UpdatesWhenValueDiffers(t *testing.T) {
	cr := sampleZoneSetting("uid-zs-abc", "challenge_ttl", []byte("21600"))
	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeZoneSettingCF{current: &cloudflare.ZoneSetting{ID: "challenge_ttl", Value: []byte("1800")}}

	r := &CloudflareZoneSettingReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.updateCalls != 1 {
		t.Fatalf("expected 1 UpdateZoneSetting call, got %d", cf.updateCalls)
	}
	if string(cf.updated) != "21600" {
		t.Errorf("updated value = %q, want 21600", cf.updated)
	}
}

// TestZoneSettingReconcile_NoOpWhenInSync makes sure a value that
// matches doesn't trigger a spurious PATCH.
func TestZoneSettingReconcile_NoOpWhenInSync(t *testing.T) {
	cr := sampleZoneSetting("uid-zs-sync", "challenge_ttl", []byte("21600"))
	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeZoneSettingCF{current: &cloudflare.ZoneSetting{ID: "challenge_ttl", Value: []byte("21600")}}

	r := &CloudflareZoneSettingReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.updateCalls != 0 {
		t.Fatalf("expected no writes when in sync, got %d", cf.updateCalls)
	}
}
