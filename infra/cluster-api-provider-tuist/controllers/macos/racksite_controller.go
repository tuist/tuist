package macos

import (
	"context"
	"fmt"
	"sort"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/cluster-api/util/patch"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/builder"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
	"sigs.k8s.io/controller-runtime/pkg/predicate"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

const rackSiteDateLayout = "2006-01-02"

var rackSiteContractedPowerGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
	Name: "capt_racksite_contracted_power_watts",
	Help: "The site's contracted power in effect, in watts, from the RackSite's steps. No series before the first step or while the steps cannot be read. Labels: site.",
}, []string{"site"})

func init() {
	metrics.Registry.MustRegister(rackSiteContractedPowerGauge)
}

// RackSiteReconciler keeps a RackSite's status and
// capt_racksite_contracted_power_watts on the contracted power step in
// effect, and wakes at the next step's first day to move to it.
type RackSiteReconciler struct {
	client.Client
	Scheme *runtime.Scheme

	// Now is the clock. Nil means time.Now.
	Now func() time.Time
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=racksites,verbs=get;list;watch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=racksites/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackatses;rackpdus;rackhosts,verbs=get;list;watch
// +kubebuilder:rbac:groups="",resources=nodes,verbs=get;list;watch;patch

func (r *RackSiteReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	site := &infrav1.RackSite{}
	if getErr := r.Get(ctx, req.NamespacedName, site); getErr != nil {
		if client.IgnoreNotFound(getErr) == nil {
			rackSiteContractedPowerGauge.DeleteLabelValues(req.Name)
			return ctrl.Result{}, r.liftSiteHolds(ctx, req.Namespace, req.Name)
		}
		return ctrl.Result{}, getErr
	}
	helper, helperErr := patch.NewHelper(site, r.Client)
	if helperErr != nil {
		return ctrl.Result{}, helperErr
	}
	defer func() {
		if patchErr := helper.Patch(ctx, site); patchErr != nil && err == nil {
			err = patchErr
		}
	}()

	now := time.Now
	if r.Now != nil {
		now = r.Now
	}
	at := now().UTC()
	current, next, readErr := contractedPowerAt(site.Spec.ContractedPower, at)
	previous := site.Status.DeepCopy()
	site.Status = infrav1.RackSiteStatus{Conditions: previous.Conditions}
	var wait time.Duration
	switch {
	case readErr != nil:
		site.Status.Message = readErr.Error()
		rackSiteContractedPowerGauge.DeleteLabelValues(site.Name)
		current = nil
	default:
		if current != nil {
			site.Status.ContractedPowerWatts = current.Watts
			site.Status.ContractedPowerSince = current.From
			rackSiteContractedPowerGauge.WithLabelValues(site.Name).Set(float64(current.Watts))
		} else {
			rackSiteContractedPowerGauge.DeleteLabelValues(site.Name)
		}
		if next != nil {
			site.Status.NextContractedPowerChange = next.From
			from, _ := time.Parse(rackSiteDateLayout, next.From)
			wait = from.Sub(at)
		}
	}
	err = r.admitPower(ctx, site, previous, current, at)
	if site.Spec.PowerBudget != nil && (wait == 0 || wait > rackSitePowerInterval) {
		wait = rackSitePowerInterval
	}
	return ctrl.Result{RequeueAfter: wait}, err
}

// contractedPowerAt is the step in effect at now, nil before the first one,
// and the step after it, nil after the last.
func contractedPowerAt(steps []infrav1.RackSiteContractedPower, now time.Time) (current, next *infrav1.RackSiteContractedPower, err error) {
	type step struct {
		infrav1.RackSiteContractedPower
		from time.Time
	}
	sorted := make([]step, 0, len(steps))
	for _, s := range steps {
		from, parseErr := time.Parse(rackSiteDateLayout, s.From)
		if parseErr != nil {
			return nil, nil, fmt.Errorf("contracted power step %q is not a date in the form YYYY-MM-DD", s.From)
		}
		sorted = append(sorted, step{RackSiteContractedPower: s, from: from})
	}
	sort.Slice(sorted, func(i, j int) bool { return sorted[i].from.Before(sorted[j].from) })
	for i := range sorted {
		if sorted[i].from.After(now) {
			next = &sorted[i].RackSiteContractedPower
			break
		}
		current = &sorted[i].RackSiteContractedPower
	}
	return current, next, nil
}

func (r *RackSiteReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.RackSite{}, builder.WithPredicates(predicate.GenerationChangedPredicate{})).
		Complete(r)
}
