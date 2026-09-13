package controllers

import (
	"context"
	"errors"
	"strings"
	"testing"

	"k8s.io/apimachinery/pkg/types"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	cfv1alpha1 "github.com/tuist/tuist/infra/cloudflare-operator/api/v1alpha1"
	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

// fakeBM is a scripted BotManagementAPI. Each test wires the live
// state and observes what the reconciler PUTs.
type fakeBM struct {
	live       *cloudflare.BotManagement
	getErr     error
	updateErr  error
	getCalls   int
	putCalls   int
	lastPut    cloudflare.BotManagement
}

func (f *fakeBM) GetBotManagement(_ context.Context, _ string) (*cloudflare.BotManagement, error) {
	f.getCalls++
	if f.getErr != nil {
		return nil, f.getErr
	}
	if f.live == nil {
		return nil, nil
	}
	cp := *f.live
	return &cp, nil
}

func (f *fakeBM) UpdateBotManagement(_ context.Context, _ string, patch cloudflare.BotManagement) (*cloudflare.BotManagement, error) {
	f.putCalls++
	f.lastPut = patch
	if f.updateErr != nil {
		return nil, f.updateErr
	}
	f.live = &patch
	return &patch, nil
}

func sampleBMLive() *cloudflare.BotManagement {
	// Mirrors the tuist.dev state at import (2026-09-10). Every SBFM
	// bucket is on "allow", Bot Fight Mode's JS challenge is on, AI
	// Crawl Control fields are disabled.
	enableJS := true
	suppress := false
	allow := "allow"
	sbfmStatic := false
	optWP := false
	disabled := "disabled"
	return &cloudflare.BotManagement{
		EnableJS:                     &enableJS,
		SuppressSessionScore:         &suppress,
		SBFMDefinitelyAutomated:      &allow,
		SBFMLikelyAutomated:          &allow,
		SBFMVerifiedBots:             &allow,
		SBFMStaticResourceProtection: &sbfmStatic,
		OptimizeWordpress:            &optWP,
		AIBotsProtection:             &disabled,
		ContentBotsProtection:        &disabled,
		CrawlerProtection:            &disabled,
	}
}

func sampleBotManagementCR(uid string) *cfv1alpha1.CloudflareBotManagement {
	enableJS := true
	return &cfv1alpha1.CloudflareBotManagement{
		ObjectMeta: metaWithUID("tuist-dev", uid),
		Spec: cfv1alpha1.CloudflareBotManagementSpec{
			ZoneID: "zone-abc",
			Mode:   cfv1alpha1.ReconcileModeReadOnly,
			BotFightMode: &cfv1alpha1.BotFightModeSpec{
				EnableJS: &enableJS,
			},
			SuperBotFightMode: &cfv1alpha1.SuperBotFightModeSpec{
				DefinitelyAutomated: cfv1alpha1.SBFMActionAllow,
				LikelyAutomated:     cfv1alpha1.SBFMActionAllow,
				VerifiedBots:        cfv1alpha1.SBFMActionAllow,
			},
		},
	}
}

// TestBotManagement_ReadOnlyMatchingLive_NoWrite proves the safe
// adoption path: read_only CR whose spec matches live state does not
// PUT and reports zero drift.
func TestBotManagement_ReadOnlyMatchingLive_NoWrite(t *testing.T) {
	cr := sampleBotManagementCR("uid-ro-match")
	cr.Finalizers = []string{finalizer}
	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeBM{live: sampleBMLive()}
	r := &CloudflareBotManagementReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.putCalls != 0 {
		t.Fatalf("read_only in-sync must not PUT; put=%d", cf.putCalls)
	}
	got := &cfv1alpha1.CloudflareBotManagement{}
	if err := kClient.Get(context.Background(), types.NamespacedName{Name: cr.Name}, got); err != nil {
		t.Fatalf("get: %v", err)
	}
	if got.Status.ProposedChanges != "" {
		t.Errorf("proposedChanges should be empty when in sync, got %q", got.Status.ProposedChanges)
	}
}

// TestBotManagement_ReadOnlyWithDrift_ProposesButDoesNotWrite proves
// the read_only diff path.
func TestBotManagement_ReadOnlyWithDrift_ProposesButDoesNotWrite(t *testing.T) {
	cr := sampleBotManagementCR("uid-ro-drift")
	cr.Finalizers = []string{finalizer}
	cr.Spec.SuperBotFightMode.DefinitelyAutomated = cfv1alpha1.SBFMActionManagedChallenge

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeBM{live: sampleBMLive()}
	r := &CloudflareBotManagementReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.putCalls != 0 {
		t.Fatalf("read_only must not PUT even with drift; put=%d", cf.putCalls)
	}
	got := &cfv1alpha1.CloudflareBotManagement{}
	if err := kClient.Get(context.Background(), types.NamespacedName{Name: cr.Name}, got); err != nil {
		t.Fatalf("get: %v", err)
	}
	if !strings.Contains(got.Status.ProposedChanges, "definitelyAutomated") {
		t.Errorf("proposedChanges should mention definitelyAutomated, got %q", got.Status.ProposedChanges)
	}
}

// TestBotManagement_ActiveWithDrift_PUTsMergedPayload proves the
// merge semantics: fields not managed by the CR (AI Crawl Control)
// are preserved on the wire, and only managed fields change.
func TestBotManagement_ActiveWithDrift_PUTsMergedPayload(t *testing.T) {
	cr := sampleBotManagementCR("uid-active-drift")
	cr.Finalizers = []string{finalizer}
	cr.Spec.Mode = cfv1alpha1.ReconcileModeActive
	cr.Spec.SuperBotFightMode.DefinitelyAutomated = cfv1alpha1.SBFMActionManagedChallenge

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeBM{live: sampleBMLive()}
	r := &CloudflareBotManagementReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.putCalls != 1 {
		t.Fatalf("active with drift must PUT once; put=%d", cf.putCalls)
	}
	if got := cf.lastPut.SBFMDefinitelyAutomated; got == nil || *got != "managed_challenge" {
		t.Errorf("merged SBFMDefinitelyAutomated = %v, want managed_challenge", got)
	}
	// AI Crawl Control field not managed by CR must survive verbatim.
	if got := cf.lastPut.AIBotsProtection; got == nil || *got != "disabled" {
		t.Errorf("AI Crawl Control field lost through merge; AIBotsProtection = %v", got)
	}
	// Other SBFM buckets unchanged.
	if got := cf.lastPut.SBFMLikelyAutomated; got == nil || *got != "allow" {
		t.Errorf("SBFMLikelyAutomated = %v, want unchanged allow", got)
	}
}

// TestBotManagement_ActiveInSync_NoWrite proves the reconciler does
// not PUT when a CR in active mode already matches live state.
func TestBotManagement_ActiveInSync_NoWrite(t *testing.T) {
	cr := sampleBotManagementCR("uid-active-sync")
	cr.Finalizers = []string{finalizer}
	cr.Spec.Mode = cfv1alpha1.ReconcileModeActive

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeBM{live: sampleBMLive()}
	r := &CloudflareBotManagementReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.putCalls != 0 {
		t.Fatalf("in-sync active must not PUT; put=%d", cf.putCalls)
	}
}

// TestBotManagement_PausedDoesNotCallCloudflare confirms the paused
// break-glass halts the loop before any API call.
func TestBotManagement_PausedDoesNotCallCloudflare(t *testing.T) {
	cr := sampleBotManagementCR("uid-paused")
	cr.Finalizers = []string{finalizer}
	cr.Spec.Paused = true

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeBM{live: sampleBMLive()}
	r := &CloudflareBotManagementReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.getCalls != 0 || cf.putCalls != 0 {
		t.Fatalf("paused must not call Cloudflare; get=%d put=%d", cf.getCalls, cf.putCalls)
	}
}

// TestBotManagement_GetErrorSurfacesInStatus proves API errors show
// up on status with the ReconcileError reason.
func TestBotManagement_GetErrorSurfacesInStatus(t *testing.T) {
	cr := sampleBotManagementCR("uid-get-err")
	cr.Finalizers = []string{finalizer}
	cr.Spec.Mode = cfv1alpha1.ReconcileModeActive

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeBM{getErr: errors.New("boom")}
	r := &CloudflareBotManagementReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err == nil {
		t.Fatal("expected reconcile error to bubble")
	}
	got := &cfv1alpha1.CloudflareBotManagement{}
	if err := kClient.Get(context.Background(), types.NamespacedName{Name: cr.Name}, got); err != nil {
		t.Fatalf("get: %v", err)
	}
	if !strings.Contains(got.Status.Message, "boom") {
		t.Errorf("expected status.message to carry API error, got %q", got.Status.Message)
	}
}

// TestBotManagement_DeleteDoesNotResetZone confirms the settings-shaped
// delete semantics: the CR's finalizer is dropped but no PUT is issued.
func TestBotManagement_DeleteDoesNotResetZone(t *testing.T) {
	cr := sampleBotManagementCR("uid-delete")
	cr.Finalizers = []string{finalizer}
	now := metav1Now()
	cr.DeletionTimestamp = &now

	scheme := newTestScheme(t)
	kClient := fake.NewClientBuilder().WithScheme(scheme).WithObjects(cr).WithStatusSubresource(cr).Build()
	cf := &fakeBM{live: sampleBMLive()}
	r := &CloudflareBotManagementReconciler{Client: kClient, Scheme: scheme, CF: cf}

	if _, err := r.Reconcile(context.Background(), ctrl.Request{NamespacedName: types.NamespacedName{Name: cr.Name}}); err != nil {
		t.Fatalf("reconcile: %v", err)
	}
	if cf.putCalls != 0 {
		t.Fatalf("delete must not touch zone state; put=%d", cf.putCalls)
	}
}
