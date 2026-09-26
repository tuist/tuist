package macos

import (
	"context"
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

	// defaultQuarantineRetryAfter is how long a host's bootstrap is held off
	// after the machine controller gave up bootstrapping it.
	//
	// Matches the drift loop's terminal-failure cooldown, and for the same
	// reason: most exhaustions are a verdict on the config being pushed rather
	// than on the hardware, and the fix arrives in a later operator image. A
	// quarantine that never expires would keep a healthy box out of the fleet
	// until someone with write access to rackhosts/status intervened, which
	// through the kubectl gateway is nobody.
	defaultQuarantineRetryAfter = 30 * time.Minute

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
		Help: "Observed outlet state of each RackHost: 1 = on, 0 = off. A host whose outlet could not be read publishes no series, which is what capt_rackhost_power_reachable is for. Labels: host, site.",
	}, []string{"host", "site"})

	rackHostPowerReachableGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackhost_power_reachable",
		Help: "1 when the RackHost's outlet was readable on the last reconcile, 0 when it was not (or the host has no outlet configured). A sustained 0 means the fleet has no remote reboot for that box: the host may be perfectly healthy, but the next wedge needs someone on site. Labels: host, site.",
	}, []string{"host", "site"})

	rackHostQuarantinedGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
		Name: "capt_rackhost_quarantined",
		Help: "1 while the RackHost's bootstrap is held off after the machine controller exhausted its attempts on it, 0 otherwise. Labels: host, site.",
	}, []string{"host", "site"})
)

func init() {
	metrics.Registry.MustRegister(rackHostPowerGauge, rackHostPowerReachableGauge, rackHostQuarantinedGauge)
}

// RackHostReconciler owns the physical inventory: it keeps the CAPI Machine
// and the RackAppleSiliconMachine that make each host a node, keeps each
// host's observed power state current, serves one-shot operator power
// actions, and expires quarantines. Bootstrapping the host is the machine
// reconciler's.
type RackHostReconciler struct {
	client.Client
	Scheme   *runtime.Scheme
	Recorder record.EventRecorder

	// Machines makes each host a node. Nil keeps no Machines.
	Machines *RackMachines

	// Power resolves a host's driver. Nil disables every power path: hosts
	// report Unknown power, and PowerReachable goes False with a reason naming
	// the missing wiring.
	Power *power.Registry

	// SecretsNamespace is where per-endpoint power credential Secrets live (the
	// operator's own namespace, same as every other Secret it reads).
	SecretsNamespace string

	// EgressNamespace and EgressProxyGroup, when both set, put an egress
	// Service in front of each PDU address (`pdu-<address>`), which the power
	// paths dial in place of the address. Empty dials the PDU directly.
	EgressNamespace  string
	EgressProxyGroup string

	// PowerCycleSettle overrides how long a cycle holds the outlet down. Zero
	// means defaultPowerCycleSettle. Not an operator-facing knob (no flag and
	// no chart value reach it): it exists so the recovery ladder is testable
	// without ten seconds of real sleep per case, and so a future PDU whose
	// hardware wants a different interval has somewhere to say so.
	PowerCycleSettle time.Duration

	// QuarantineRetryAfter is how long a quarantine holds before the host's
	// bootstrap starts over. Zero means defaultQuarantineRetryAfter; negative
	// disables the expiry, which makes a quarantine permanent and should only
	// be chosen by an operator who has another way to clear one.
	QuarantineRetryAfter time.Duration
}

func (r *RackHostReconciler) quarantineRetryAfter() time.Duration {
	if r.QuarantineRetryAfter != 0 {
		return r.QuarantineRetryAfter
	}
	return defaultQuarantineRetryAfter
}

// expireQuarantine lifts a quarantine that has aged out, so the machine
// controller bootstraps the host again. Reports whether it cleared one. A
// quarantine with no timestamp is lifted on sight.
func (r *RackHostReconciler) expireQuarantine(ctx context.Context, host *infrav1.RackHost) bool {
	if !host.Status.Quarantined {
		return false
	}
	retryAfter := r.quarantineRetryAfter()
	if retryAfter < 0 {
		return false
	}
	if at := host.Status.QuarantinedAt; at != nil && time.Since(at.Time) < retryAfter {
		return false
	}

	reason := host.Status.QuarantineReason
	r.Recorder.Eventf(host, corev1.EventTypeNormal, "QuarantineExpired",
		"Bootstrapping again after %s in quarantine. It was quarantined for: %s", retryAfter, reason)
	log.FromContext(ctx).Info("quarantine expired; the host is bootstrapped again",
		"host", host.Name, "wasQuarantinedFor", reason)
	host.Status.Quarantined = false
	host.Status.QuarantineReason = ""
	host.Status.QuarantinedAt = nil
	return true
}

func (r *RackHostReconciler) powerCycleSettle() time.Duration {
	if r.PowerCycleSettle > 0 {
		return r.PowerCycleSettle
	}
	return defaultPowerCycleSettle
}

// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackhosts,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackhosts/status,verbs=get;update;patch
// +kubebuilder:rbac:groups=infrastructure.cluster.x-k8s.io,resources=rackapplesiliconmachines,verbs=get;list;watch;create;update;patch;delete
// +kubebuilder:rbac:groups=cluster.x-k8s.io,resources=machines,verbs=get;list;watch;create;update;patch;delete

func (r *RackHostReconciler) Reconcile(ctx context.Context, req ctrl.Request) (result ctrl.Result, err error) {
	logger := log.FromContext(ctx).WithValues("rackhost", req.NamespacedName)

	host := &infrav1.RackHost{}
	if getErr := r.Get(ctx, req.NamespacedName, host); getErr != nil {
		if apierrors.IsNotFound(getErr) {
			forgetRackHostMetrics(req.Name)
			return ctrl.Result{}, reconcilePDUEgressServices(ctx, r.Client, r.egressConfig())
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

	// A deleted host's Machine, and with it the host's Node, goes through its
	// owner reference.
	if !host.DeletionTimestamp.IsZero() {
		return ctrl.Result{}, nil
	}

	if r.expireQuarantine(ctx, host) {
		return ctrl.Result{Requeue: true}, nil
	}

	machineResult, machineErr := r.reconcileMachine(ctx, host)
	if machineErr != nil {
		logger.Error(machineErr, "keep the host's Machine; will retry")
	}

	if egressErr := reconcilePDUEgressServices(ctx, r.Client, r.egressConfig()); egressErr != nil {
		logger.Error(egressErr, "keep the PDU egress Services; will retry")
		r.Recorder.Eventf(host, corev1.EventTypeWarning, "PowerEgressFailed", "%v", egressErr)
	}

	if actionErr := r.runRequestedPowerAction(ctx, host); actionErr != nil {
		logger.Error(actionErr, "run requested power action; will retry")
		return ctrl.Result{RequeueAfter: time.Minute}, nil
	}

	r.observePower(ctx, host)

	if machineErr != nil {
		return ctrl.Result{}, machineErr
	}
	if !machineResult.IsZero() {
		return machineResult, nil
	}
	return ctrl.Result{RequeueAfter: powerPollInterval}, nil
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
				action, host.Status.Machine, PowerActionForceAnnotation)
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
	if host.Status.Machine == "" {
		return false, nil
	}
	node := &corev1.Node{}
	err := r.Get(ctx, types.NamespacedName{Name: host.Status.Machine}, node)
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
// still a node.
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

func (r *RackHostReconciler) outletFor(ctx context.Context, host *infrav1.RackHost) (power.Driver, power.Outlet, error) {
	return rackHostOutlet(ctx, r.Client, r.Power, r.SecretsNamespace, r.egressConfig(), host)
}

func (r *RackHostReconciler) egressConfig() egressConfig {
	return egressConfig{
		Namespace:  r.EgressNamespace,
		ProxyGroup: r.EgressProxyGroup,
		ManagedBy:  operatorName,
	}
}

func recordRackHostMetrics(host *infrav1.RackHost) {
	labels := []string{host.Name, host.Spec.Location.Site}

	rackHostQuarantinedGauge.DeletePartialMatch(prometheus.Labels{"host": host.Name})
	rackHostQuarantinedGauge.WithLabelValues(labels...).Set(boolGauge(host.Status.Quarantined))

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
	for _, g := range []*prometheus.GaugeVec{rackHostPowerGauge, rackHostPowerReachableGauge, rackHostQuarantinedGauge} {
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
		Owns(&clusterv1.Machine{}).
		Watches(
			&infrav1.RackAppleSiliconMachine{},
			handler.EnqueueRequestsFromMapFunc(rackHostForRackMachine),
		).
		Complete(r)
}

// rackHostForRackMachine maps a machine event to the host it is.
func rackHostForRackMachine(_ context.Context, o client.Object) []reconcile.Request {
	m, ok := o.(*infrav1.RackAppleSiliconMachine)
	if !ok || m.Spec.Host == "" {
		return nil
	}
	return []reconcile.Request{{
		NamespacedName: types.NamespacedName{Namespace: m.Namespace, Name: m.Spec.Host},
	}}
}
