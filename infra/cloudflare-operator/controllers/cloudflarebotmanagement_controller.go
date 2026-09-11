// CloudflareBotManagement reconciler: a settings-shaped kind rather
// than a ruleset-shaped one. There is no ref, no ruleset, no rule id
// to track — the identity is spec.zoneId, and reconciliation is a
// single GET / diff / PUT against /zones/{zoneId}/bot_management.
//
// Merge semantics: the reconciler GETs the live state, overlays only
// the fields the CR explicitly sets (nil pointers left alone), and
// PUTs the merged result. That way fields Cloudflare stores which the
// CR does not model (AI Crawl Control today) round-trip verbatim and
// are not clobbered on the wire — same defensive pattern the ruleset
// reconciler uses for adopted rules.
//
// Delete semantics: the finalizer is dropped without changing zone
// state. Resetting a zone's bot management on `kubectl delete` would
// be an unexpectedly large blast radius, so the CR mirrors the "do
// nothing on delete" default from AGENTS.md.
package controllers

import (
	"context"
	"errors"
	"fmt"
	"reflect"
	"sort"
	"strings"
	"time"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	cfv1alpha1 "github.com/tuist/tuist/infra/cloudflare-operator/api/v1alpha1"
	"github.com/tuist/tuist/infra/cloudflare-operator/internal/cloudflare"
)

// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarebotmanagements,verbs=get;list;watch;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarebotmanagements/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=cloudflare.tuist.dev,resources=cloudflarebotmanagements/finalizers,verbs=update

// BotManagementAPI is the Cloudflare surface the reconciler needs.
// Kept narrow so tests can supply a scripted fake without pulling in
// the full HTTP client.
type BotManagementAPI interface {
	GetBotManagement(ctx context.Context, zoneID string) (*cloudflare.BotManagement, error)
	UpdateBotManagement(ctx context.Context, zoneID string, patch cloudflare.BotManagement) (*cloudflare.BotManagement, error)
}

type CloudflareBotManagementReconciler struct {
	client.Client
	Scheme         *runtime.Scheme
	CF             BotManagementAPI
	ResyncInterval time.Duration
}

func (r *CloudflareBotManagementReconciler) Reconcile(ctx context.Context, req ctrl.Request) (ctrl.Result, error) {
	logger := log.FromContext(ctx).WithValues("cloudflarebotmanagement", req.Name)
	cr := &cfv1alpha1.CloudflareBotManagement{}
	if err := r.Get(ctx, req.NamespacedName, cr); err != nil {
		return ctrl.Result{}, client.IgnoreNotFound(err)
	}

	if cr.Spec.Paused {
		message := "paused"
		if !cr.DeletionTimestamp.IsZero() {
			message = "paused: delete held"
		}
		return ctrl.Result{RequeueAfter: resyncOrDefault(r.ResyncInterval)}, r.writeStatus(
			ctx, cr, message, "",
			cfv1alpha1.ReasonPaused, metav1.ConditionFalse, cr.Status.ObservedGeneration,
		)
	}

	if !cr.DeletionTimestamp.IsZero() {
		return r.reconcileDelete(ctx, cr)
	}
	added, err := ensureFinalizer(ctx, r.Client, cr)
	if err != nil {
		return ctrl.Result{}, err
	}
	if added {
		return ctrl.Result{}, nil
	}

	live, err := r.CF.GetBotManagement(ctx, cr.Spec.ZoneID)
	if err != nil {
		_ = r.writeStatus(ctx, cr, fmt.Sprintf("get bot_management: %v", err), "", cfv1alpha1.ReasonReconcileError, metav1.ConditionFalse, cr.Status.ObservedGeneration)
		return ctrl.Result{}, fmt.Errorf("get bot_management: %w", err)
	}
	if live == nil {
		err := errors.New("cloudflare returned no bot_management result")
		_ = r.writeStatus(ctx, cr, err.Error(), "", cfv1alpha1.ReasonReconcileError, metav1.ConditionFalse, cr.Status.ObservedGeneration)
		return ctrl.Result{}, err
	}

	merged, diffs := mergeBotManagement(*live, cr.Spec)

	if len(diffs) == 0 {
		if err := r.writeStatus(ctx, cr, "in sync", "", cfv1alpha1.ReasonReconciled, metav1.ConditionTrue, cr.Generation); err != nil {
			return ctrl.Result{}, err
		}
		return ctrl.Result{RequeueAfter: resyncOrDefault(r.ResyncInterval)}, nil
	}

	summary := strings.Join(diffs, "; ")

	if cr.Spec.EffectiveMode() == cfv1alpha1.ReconcileModeReadOnly {
		logger.Info("read_only: would update bot_management", "diff", summary)
		if err := r.writeStatus(ctx, cr, "read_only: would update", summary, cfv1alpha1.ReasonReadOnly, metav1.ConditionFalse, cr.Status.ObservedGeneration); err != nil {
			return ctrl.Result{}, err
		}
		return ctrl.Result{RequeueAfter: resyncOrDefault(r.ResyncInterval)}, nil
	}

	if _, err := r.CF.UpdateBotManagement(ctx, cr.Spec.ZoneID, merged); err != nil {
		_ = r.writeStatus(ctx, cr, fmt.Sprintf("update bot_management: %v", err), summary, cfv1alpha1.ReasonReconcileError, metav1.ConditionFalse, cr.Status.ObservedGeneration)
		return ctrl.Result{}, fmt.Errorf("update bot_management: %w", err)
	}
	logger.Info("updated bot_management", "diff", summary)
	if err := r.writeStatus(ctx, cr, "reconciled: "+summary, "", cfv1alpha1.ReasonReconciled, metav1.ConditionTrue, cr.Generation); err != nil {
		return ctrl.Result{}, err
	}
	return ctrl.Result{RequeueAfter: resyncOrDefault(r.ResyncInterval)}, nil
}

func (r *CloudflareBotManagementReconciler) reconcileDelete(ctx context.Context, cr *cfv1alpha1.CloudflareBotManagement) (ctrl.Result, error) {
	// Settings-shaped kind: never touch zone state on delete. The
	// operator only drops its finalizer so the CR can be removed.
	// If the user really wants to walk back a value they should do
	// so in a live CR before deleting it.
	return ctrl.Result{}, removeFinalizerAndPersist(ctx, r.Client, cr)
}

func (r *CloudflareBotManagementReconciler) writeStatus(
	ctx context.Context,
	cr *cfv1alpha1.CloudflareBotManagement,
	message, proposed, reason string,
	readyStatus metav1.ConditionStatus,
	observedGeneration int64,
) error {
	patch := client.MergeFrom(cr.DeepCopy())
	cr.Status.Message = message
	cr.Status.ProposedChanges = proposed
	cr.Status.Mode = cr.Spec.EffectiveMode()
	cr.Status.ObservedGeneration = observedGeneration
	if cr.Status.ManagedZoneID == "" && readyStatus == metav1.ConditionTrue {
		cr.Status.ManagedZoneID = cr.Spec.ZoneID
	}
	now := metav1Now()
	setCondition(&cr.Status.Conditions, metav1.Condition{
		Type:               cfv1alpha1.ConditionTypeReady,
		Status:             readyStatus,
		Reason:             reason,
		Message:            message,
		LastTransitionTime: now,
		ObservedGeneration: observedGeneration,
	})
	cr.Status.LastReconciledAt = &now
	return r.Status().Patch(ctx, cr, patch)
}

func (r *CloudflareBotManagementReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&cfv1alpha1.CloudflareBotManagement{}, builder.WithPredicates(predicate.Or(predicate.GenerationChangedPredicate{}, annotationOrDeletionChanged()))).
		Complete(r)
}

// mergeBotManagement overlays only the fields the CR explicitly sets
// onto the live Cloudflare state and returns both the merged payload
// (for PUT) and a sorted list of human-readable diff lines (for
// status.proposedChanges / status.message).
//
// Fields the CR does not set are left as-is on the merged payload so
// AI Crawl Control settings and any other zone-scoped state on the
// same endpoint round-trip verbatim.
func mergeBotManagement(live cloudflare.BotManagement, spec cfv1alpha1.CloudflareBotManagementSpec) (cloudflare.BotManagement, []string) {
	merged := live
	var diffs []string

	if spec.BotFightMode != nil {
		if spec.BotFightMode.EnableJS != nil {
			diffs = appendBoolDiff(diffs, "botFightMode.enableJs", live.EnableJS, spec.BotFightMode.EnableJS)
			merged.EnableJS = boolPtr(*spec.BotFightMode.EnableJS)
		}
		if spec.BotFightMode.SuppressSessionScore != nil {
			diffs = appendBoolDiff(diffs, "botFightMode.suppressSessionScore", live.SuppressSessionScore, spec.BotFightMode.SuppressSessionScore)
			merged.SuppressSessionScore = boolPtr(*spec.BotFightMode.SuppressSessionScore)
		}
		if spec.BotFightMode.UsingLatestModel != nil {
			diffs = appendBoolDiff(diffs, "botFightMode.usingLatestModel", live.UsingLatestModel, spec.BotFightMode.UsingLatestModel)
			merged.UsingLatestModel = boolPtr(*spec.BotFightMode.UsingLatestModel)
		}
	}

	if spec.SuperBotFightMode != nil {
		if spec.SuperBotFightMode.DefinitelyAutomated != "" {
			diffs = appendStringDiff(diffs, "superBotFightMode.definitelyAutomated", live.SBFMDefinitelyAutomated, string(spec.SuperBotFightMode.DefinitelyAutomated))
			merged.SBFMDefinitelyAutomated = stringPtr(string(spec.SuperBotFightMode.DefinitelyAutomated))
		}
		if spec.SuperBotFightMode.LikelyAutomated != "" {
			diffs = appendStringDiff(diffs, "superBotFightMode.likelyAutomated", live.SBFMLikelyAutomated, string(spec.SuperBotFightMode.LikelyAutomated))
			merged.SBFMLikelyAutomated = stringPtr(string(spec.SuperBotFightMode.LikelyAutomated))
		}
		if spec.SuperBotFightMode.VerifiedBots != "" {
			diffs = appendStringDiff(diffs, "superBotFightMode.verifiedBots", live.SBFMVerifiedBots, string(spec.SuperBotFightMode.VerifiedBots))
			merged.SBFMVerifiedBots = stringPtr(string(spec.SuperBotFightMode.VerifiedBots))
		}
		if spec.SuperBotFightMode.StaticResourceProtection != nil {
			diffs = appendBoolDiff(diffs, "superBotFightMode.staticResourceProtection", live.SBFMStaticResourceProtection, spec.SuperBotFightMode.StaticResourceProtection)
			merged.SBFMStaticResourceProtection = boolPtr(*spec.SuperBotFightMode.StaticResourceProtection)
		}
		if spec.SuperBotFightMode.OptimizeWordpress != nil {
			diffs = appendBoolDiff(diffs, "superBotFightMode.optimizeWordpress", live.OptimizeWordpress, spec.SuperBotFightMode.OptimizeWordpress)
			merged.OptimizeWordpress = boolPtr(*spec.SuperBotFightMode.OptimizeWordpress)
		}
	}

	sort.Strings(diffs)
	return merged, diffs
}

func appendBoolDiff(acc []string, field string, live *bool, desired *bool) []string {
	if reflect.DeepEqual(live, desired) {
		return acc
	}
	return append(acc, fmt.Sprintf("%s: %s -> %s", field, boolStr(live), boolStr(desired)))
}

func appendStringDiff(acc []string, field string, live *string, desired string) []string {
	if live != nil && *live == desired {
		return acc
	}
	return append(acc, fmt.Sprintf("%s: %s -> %q", field, stringStr(live), desired))
}

func boolPtr(v bool) *bool { return &v }

func stringPtr(v string) *string { return &v }

func boolStr(v *bool) string {
	if v == nil {
		return "<unset>"
	}
	if *v {
		return "true"
	}
	return "false"
}

func stringStr(v *string) string {
	if v == nil {
		return "<unset>"
	}
	return fmt.Sprintf("%q", *v)
}
