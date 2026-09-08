package macos

import (
	"context"
	"fmt"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/cluster-api/util/patch"
	ctrl "sigs.k8s.io/controller-runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/handler"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/metrics"
	"sigs.k8s.io/controller-runtime/pkg/reconcile"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/power"
)

const (
	// PowerReachableCondition reports whether the host's outlet could be read.
	// False is not a host fault (the mini may be running perfectly) but it
	// does mean the fleet has lost its only remote reboot for that box, which
	// is worth surfacing before the reboot is needed rather than at the moment
	// a wedged host cannot be recovered.
	PowerReachableCondition clusterv1.ConditionType = "PowerReachable"

	// PowerActionAnnotation asks the controller to act on the host's outlet
	// once: `on`, `off`, or `cycle`. The controller clears it after acting, so
	// re-applying the same manifest does not re-fire the action.
	PowerActionAnnotation = "tuist.dev/power-action"

	// PowerActionForceAnnotation ("true") permits an action that would cut
	// power to a host whose Node is Ready and schedulable. Without it those are
	// refused: the normal reason to reach for this is a wedged host, and a
	// wedged host is not the one still taking work.
	PowerActionForceAnnotation = "tuist.dev/power-action-force"

	// defaultPowerCycleSettle is how long Cycle holds the outlet down. Long
	// enough for a Mac mini's PSU to discharge so the machine genuinely
	// cold-boots; a shorter interval can leave it in exactly the state the
	// cycle was meant to clear.
	defaultPowerCycleSettle = 10 * time.Second

	// powerPollInterval is how often a host's outlet is read when nothing else
	// wakes the reconciler. Outlet state changes only when we change it or when
	// someone unplugs something, so this is a liveness check on the PDU path
	// rather than a state poll, and it is deliberately slow: a rack's worth of
	// hosts on one plug endpoint should not be a constant HTTP load.
	powerPollInterval = 5 * time.Minute
)

var (
	rackHostPowerGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackhost_power",
		Help: "Observed outlet state of each RackHost: 1 = on, 0 = off. A host whose outlet could not be read publishes no series, which is what capt_rackhost_power_reachable is for. Labels: host, pool, site.",
	}, []string{"host", "pool", "site"})

	rackHostPowerReachableGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackhost_power_reachable",
		Help: "1 when the RackHost's outlet was readable on the last reconcile, 0 when it was not (or the host has no outlet configured). A sustained 0 means the fleet has no remote reboot for that box: the host may be perfectly healthy, but the next wedge needs someone on site. Labels: host, pool, site.",
	}, []string{"host", "pool", "site"})

	rackHostClaimedGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackhost_claimed",
		Help: "1 when the RackHost is held by a StaticAppleSiliconMachine, 0 when it is free. Summed per pool this is the rack's utilisation, and free == 0 is what a MachineDeployment scale-up will fail to satisfy. Labels: host, pool, site, quarantined.",
	}, []string{"host", "pool", "site", "quarantined"})
)

func init() {
	metrics.Registry.MustRegister(rackHostPowerGauge, rackHostPowerReachableGauge, rackHostClaimedGauge)
}

// RackHostReconciler owns the physical inventory: it keeps each host's observed
// power state current, serves one-shot operator power actions, and releases a
// claim whose machine no longer exists.
//
// It deliberately does NOT claim, bootstrap or bind hosts. The claim belongs to
// the machine reconciler, because the claim and the Machine's own status have
// to move together; splitting it across two controllers would put a
// half-claimed host between them.
type RackHostReconciler struct {
	client.Client
	Scheme   *runtime.Scheme
	Recorder record.EventRecorder

	// Power resolves a host's driver. Nil disables every power path: the
	// controller still tracks claims and orphans, hosts report Unknown power,
	// and PowerReachable goes False with a reason naming the missing wiring.
	Power *power.Registry

	// SecretsNamespace is where per-endpoint power credential Secrets live (the
	// operator's own namespace, same as every other Secret it reads).
	SecretsNamespace string

	// PowerCycleSettle overrides how long a cycle holds the outlet down. Zero
	// means defaultPowerCycleSettle. Not an operator-facing knob (no flag and
	// no chart value reach it): it exists so the recovery ladder is testable
	// without ten seconds of real sleep per case, and so a future PDU whose
	// hardware wants a different interval has somewhere to say so.
	PowerCycleSettle time.Duration
}

func (r *RackHostReconciler) powerCycleSettle() time.Duration {
	if r.PowerCycleSettle > 0 {
		return r.PowerCycleSettle
	}
	return defaultPowerCycleSettle
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackhosts,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackhosts/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=staticapplesiliconmachines,verbs=get;list;watch

func (r *RackHostReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	logger := log.FromContext(ctx).WithValues("rackhost", req.NamespacedName)

	host := &infrav1.RackHost{}
	if getErr := r.Get(ctx, req.NamespacedName, host); getErr != nil {
		if apierrors.IsNotFound(getErr) {
			forgetRackHostMetrics(req.Name)
			return ctrl.Result{}, nil
		}
		return ctrl.Result{}, getErr
	}

	patchHelper, helperErr := patch.NewHelper(host, r.Client)
	if helperErr != nil {
		return ctrl.Result{}, helperErr
	}
	defer func() {
		if patchErr := patchHelper.Patch(ctx, host); patchErr != nil && err == nil {
			err = patchErr
		}
	}()
	defer func() { recordRackHostMetrics(host) }()

	// A host being deleted keeps no state worth converging. There is no
	// finalizer: this CR owns no external resource; the physical machine
	// outlives every Kubernetes object, which is the entire difference between
	// hardware we own and capacity we rent, so deleting it is deleting an
	// inventory record and nothing else.
	if !host.DeletionTimestamp.IsZero() {
		return ctrl.Result{}, nil
	}

	// Release a claim whose machine is gone. The machine's own delete path
	// releases the host, so this only fires for what never reached it: a
	// force-delete that bypassed the finalizer, or a crash between the RackHost
	// claim write and the Machine status write. Without it the last free host in
	// a rack can strand held by nothing, and a MachineDeployment scale-up then
	// waits forever on capacity that is physically idle.
	if released, releaseErr := r.releaseIfOrphaned(ctx, host); releaseErr != nil {
		logger.Error(releaseErr, "check for an orphaned claim; will retry")
		return ctrl.Result{RequeueAfter: time.Minute}, nil
	} else if released {
		return ctrl.Result{Requeue: true}, nil
	}

	if actionErr := r.runRequestedPowerAction(ctx, host); actionErr != nil {
		logger.Error(actionErr, "run requested power action; will retry")
		return ctrl.Result{RequeueAfter: time.Minute}, nil
	}

	r.observePower(ctx, host)

	return ctrl.Result{RequeueAfter: powerPollInterval}, nil
}

// releaseIfOrphaned clears a claim held by a StaticAppleSiliconMachine that no
// longer exists. Reports whether it released.
//
// It reads the machine through the cached client, which is enough: a claim is
// only ever written after its Machine exists, so a stale-cache miss can only
// happen for a machine that was created and deleted within one cache sync: in
// which case releasing is the right answer anyway.
func (r *RackHostReconciler) releaseIfOrphaned(ctx context.Context, host *infrav1.RackHost) (bool, error) {
	if host.Status.ClaimedBy == "" {
		return false, nil
	}
	machine := &infrav1.StaticAppleSiliconMachine{}
	err := r.Get(ctx, types.NamespacedName{Namespace: host.Namespace, Name: host.Status.ClaimedBy}, machine)
	switch {
	case err == nil:
		return false, nil
	case !apierrors.IsNotFound(err):
		return false, err
	}

	r.Recorder.Eventf(host, corev1.EventTypeWarning, "ClaimReleased",
		"Released the claim held by %s: no such StaticAppleSiliconMachine. The host is free to be claimed again.",
		host.Status.ClaimedBy)
	log.FromContext(ctx).Info("released orphaned rack host claim",
		"host", host.Name, "claimedBy", host.Status.ClaimedBy)
	host.Status.ClaimedBy = ""
	host.Status.ClaimedAt = nil
	return true, nil
}

// runRequestedPowerAction executes and clears a one-shot power annotation.
func (r *RackHostReconciler) runRequestedPowerAction(ctx context.Context, host *infrav1.RackHost) error {
	action, requested := host.Annotations[PowerActionAnnotation]
	if !requested {
		return nil
	}

	// Clear first, whatever happens below. An action that failed and stayed
	// annotated would re-fire on every reconcile: for `cycle`, that is a host
	// power-cycled every minute for as long as nobody notices.
	defer func() {
		delete(host.Annotations, PowerActionAnnotation)
		delete(host.Annotations, PowerActionForceAnnotation)
	}()

	forced := host.Annotations[PowerActionForceAnnotation] == "true"
	cutsPower := action == "off" || action == "cycle"
	if cutsPower && !forced {
		serving, err := r.nodeIsServing(ctx, host)
		if err != nil {
			return err
		}
		if serving {
			r.Recorder.Eventf(host, corev1.EventTypeWarning, "PowerActionRefused",
				"Refused %q: %s is Ready and schedulable, so this would kill running work. Cordon the node first, or set %s=true to override.",
				action, host.Status.ClaimedBy, PowerActionForceAnnotation)
			return nil
		}
	}

	driver, outlet, err := r.outletFor(ctx, host)
	if err != nil {
		r.Recorder.Eventf(host, corev1.EventTypeWarning, "PowerActionFailed",
			"Could not run %q: %v", action, err)
		return nil
	}

	switch action {
	case "on":
		err = driver.Set(ctx, outlet, true)
	case "off":
		err = driver.Set(ctx, outlet, false)
	case "cycle":
		err = power.Cycle(ctx, driver, outlet, r.powerCycleSettle())
	default:
		r.Recorder.Eventf(host, corev1.EventTypeWarning, "PowerActionInvalid",
			"Unknown %s value %q; expected on, off or cycle", PowerActionAnnotation, action)
		return nil
	}
	if err != nil {
		r.Recorder.Eventf(host, corev1.EventTypeWarning, "PowerActionFailed",
			"%s failed: %v", action, err)
		return nil
	}

	host.Status.LastPowerAction = action
	host.Status.LastPowerActionTime = &metav1.Time{Time: time.Now()}
	r.Recorder.Eventf(host, corev1.EventTypeNormal, "PowerAction",
		"Ran %q on %s", action, outlet)
	return nil
}

// nodeIsServing reports whether this host's Node is Ready and still accepting
// work. A cordoned node counts as not serving: cordoning is how an operator
// says they are about to take the box away, and requiring force after that
// would be friction with no safety left to buy.
func (r *RackHostReconciler) nodeIsServing(ctx context.Context, host *infrav1.RackHost) (bool, error) {
	if host.Status.ClaimedBy == "" {
		return false, nil
	}
	node := &corev1.Node{}
	err := r.Get(ctx, types.NamespacedName{Name: host.Status.ClaimedBy}, node)
	switch {
	case apierrors.IsNotFound(err):
		return false, nil
	case err != nil:
		return false, err
	case node.Spec.Unschedulable:
		return false, nil
	}
	for _, cond := range node.Status.Conditions {
		if cond.Type == corev1.NodeReady {
			return cond.Status == corev1.ConditionTrue, nil
		}
	}
	return false, nil
}

// observePower reads the outlet and records what it found. Deliberately not
// fatal to the reconcile: a host whose plug is unreachable is still a host, and
// failing here would stop the claim bookkeeping above from converging.
func (r *RackHostReconciler) observePower(ctx context.Context, host *infrav1.RackHost) {
	driver, outlet, err := r.outletFor(ctx, host)
	if err != nil {
		host.Status.Power = string(power.StateUnknown)
		conditions.MarkFalse(host, PowerReachableCondition, "PowerNotConfigured",
			clusterv1.ConditionSeverityWarning, "%v", err)
		return
	}

	state, err := driver.State(ctx, outlet)
	if err != nil {
		host.Status.Power = string(power.StateUnknown)
		conditions.MarkFalse(host, PowerReachableCondition, "PowerUnreachable",
			clusterv1.ConditionSeverityWarning,
			"could not read %s: %v", outlet, err)
		return
	}

	if host.Status.Power != string(state) && host.Status.Power != "" {
		// An outlet that changed without us asking is worth an event: it is
		// either someone at the rack or a plug that lost its own power, and
		// both explain a host that vanished.
		r.Recorder.Eventf(host, corev1.EventTypeNormal, "PowerStateChanged",
			"Outlet moved from %s to %s", host.Status.Power, state)
	}
	host.Status.Power = string(state)
	conditions.MarkTrue(host, PowerReachableCondition)
}

// outletFor resolves the driver and the fully-populated outlet, reading the
// endpoint's credentials when the host names a Secret.
func (r *RackHostReconciler) outletFor(ctx context.Context, host *infrav1.RackHost) (power.Driver, power.Outlet, error) {
	if host.Spec.Power == nil {
		return nil, power.Outlet{}, fmt.Errorf("host has no power outlet configured; it cannot be rebooted remotely")
	}
	if r.Power == nil {
		return nil, power.Outlet{}, fmt.Errorf("no power drivers wired into this operator build")
	}
	driver, err := r.Power.Get(host.Spec.Power.Driver)
	if err != nil {
		return nil, power.Outlet{}, err
	}

	outlet := power.Outlet{
		Driver: host.Spec.Power.Driver,
		Host:   host.Spec.Power.Host,
		Outlet: host.Spec.Power.Outlet,
	}
	if ref := host.Spec.Power.CredentialsSecretRef; ref != nil && ref.Name != "" {
		secret := &corev1.Secret{}
		if err := r.Get(ctx, types.NamespacedName{Namespace: r.SecretsNamespace, Name: ref.Name}, secret); err != nil {
			return nil, power.Outlet{}, fmt.Errorf("read power credentials %s/%s: %w", r.SecretsNamespace, ref.Name, err)
		}
		outlet.Username = string(secret.Data["username"])
		outlet.Password = string(secret.Data["password"])
	}
	return driver, outlet, nil
}

func recordRackHostMetrics(host *infrav1.RackHost) {
	labels := []string{host.Name, host.Spec.Pool, host.Spec.Location.Site}

	rackHostClaimedGauge.DeletePartialMatch(prometheus.Labels{"host": host.Name})
	rackHostClaimedGauge.WithLabelValues(append(labels,
		fmt.Sprintf("%t", host.Status.Quarantined))...).Set(boolGauge(host.Status.ClaimedBy != ""))

	switch power.State(host.Status.Power) {
	case power.StateOn, power.StateOff:
		rackHostPowerGauge.WithLabelValues(labels...).Set(boolGauge(power.State(host.Status.Power) == power.StateOn))
		rackHostPowerReachableGauge.WithLabelValues(labels...).Set(1)
	default:
		// No power series at all rather than a 0: a 0 here would be
		// indistinguishable from "the outlet is off", and those two want
		// opposite responses from whoever is looking.
		rackHostPowerGauge.DeletePartialMatch(prometheus.Labels{"host": host.Name})
		rackHostPowerReachableGauge.WithLabelValues(labels...).Set(0)
	}
}

func forgetRackHostMetrics(name string) {
	for _, g := range []*prometheus.GaugeVec{rackHostPowerGauge, rackHostPowerReachableGauge, rackHostClaimedGauge} {
		g.DeletePartialMatch(prometheus.Labels{"host": name})
	}
}

func boolGauge(b bool) float64 {
	if b {
		return 1
	}
	return 0
}

func (r *RackHostReconciler) SetupWithManager(mgr ctrl.Manager) error {
	return ctrl.NewControllerManagedBy(mgr).
		For(&infrav1.RackHost{}).
		// Wake on the machines that hold claims, so a deleted machine's host is
		// freed on the spot rather than at the next poll interval: that
		// latency is a scale-up sitting on NoAvailableHost.
		Watches(
			&infrav1.StaticAppleSiliconMachine{},
			handler.EnqueueRequestsFromMapFunc(rackHostForStaticMachine),
		).
		Complete(r)
}

// rackHostForStaticMachine maps a machine event to the host it holds.
func rackHostForStaticMachine(_ context.Context, o client.Object) []reconcile.Request {
	m, ok := o.(*infrav1.StaticAppleSiliconMachine)
	if !ok || m.Status.RackHost == "" {
		return nil
	}
	return []reconcile.Request{{
		NamespacedName: types.NamespacedName{Namespace: m.Namespace, Name: m.Status.RackHost},
	}}
}
