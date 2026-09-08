package macos

import (
	"context"
	"fmt"
	"time"

	"github.com/go-logr/logr"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/client-go/tools/record"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/controller/controllerutil"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/macos-host-bootstrap"
)

// This file holds everything the macOS machine kinds share once a host is in
// hand: the host-config drift bookkeeping, the terminal-failure rules, the
// per-Machine sizing overlay, and the per-host tailnet egress Service.
//
// It is shared rather than copied because the rules here are the ones this
// provider has repeatedly got wrong in ways that are invisible until a fleet
// has been running stale config for weeks: a Config field wired into the
// bootstrap push but not the drift push, a terminal phase overwritten by the
// reconcile tail so the stuck-Failed alert could never fire, a hash compared
// against the last-applied value instead of the failed one so the retry cap
// reset every reconcile. A second macOS kind written by copy would inherit
// whichever of those it copied on a bad day.
//
// What is NOT here is anything about where a host comes from. Acquiring,
// rebooting and giving up on a host differ per kind: a provider API call
// versus a PDU outlet, releasing to a pool versus quarantining hardware we
// own, so each kind owns those.

// operatorName is the value stamped on `app.kubernetes.io/managed-by` for
// every object this operator owns. It names the OPERATOR (whose Deployment and
// leader-election lease carry the same name), not the machine kind, so it stays
// the same for the rack fleet: the Services alloy discovers must look
// identical whoever owns the hardware.
const operatorName = "capi-scaleway-applesilicon"

// hostAgentMachine is the surface these helpers need from a macOS machine CR.
// Both kinds satisfy it through the embedded infrav1.HostAgentStatus.
type hostAgentMachine interface {
	client.Object
	HostAgent() *infrav1.HostAgentStatus
}

// hostConfigDrift reports whether the host config the operator would push
// (operatorHash) differs from what the Machine last recorded (machineHash). An
// empty operatorHash (hash not computed) never drifts. An empty machineHash on
// a non-empty operatorHash drifts once: the migration case for machines
// provisioned before the hash existed.
func hostConfigDrift(operatorHash, machineHash string) bool {
	return operatorHash != "" && machineHash != operatorHash
}

// terminalPhasePinned reports whether the reconcile tail must leave
// Status.Phase alone because the machine holds a terminal failure.
//
// The drift gate SKIPS a terminal machine rather than returning early, so
// every reconcile after the one that recorded the failure still falls through
// to the tail. Writing "Ready" there overwrote the "Failed" that
// recordUpdateFailure had just set (within a single reconcile interval)
// leaving machines that carried FailureReason while reporting phase Ready.
//
// That combination is invisible to alerting: the "stuck Failed" rule keys on
// phase="Failed" persisting for 30m, and the phase flapped back to Ready in
// ~5m, so the rule could never fire. Three production hosts sat wedged on a
// stale tart-kubelet for weeks with the alert green. Pinning the phase is what
// makes the terminal state observable; clearUpdateFailure lifts it.
func terminalPhasePinned(failureReason *string) bool {
	return failureReason != nil
}

// shouldClearTerminalFailure reports whether a terminal host-config-update
// failure should be cleared so the drift loop retries.
//
// Two independent exits:
//
// Config drift: the operator's desired config differs from the one that
// exhausted its retry budget (failedHash), NOT from the last successfully
// applied hash. A broken config can never be applied, so the applied hash never
// advances to it and a desired-vs-applied comparison would report drift
// forever, resetting the cap on every reconcile and retrying the same broken
// config indefinitely. Keyed on the failed hash instead, an unchanged broken
// config keeps its terminal state while a genuinely new (typically fixed)
// config gets a fresh budget.
//
// Cooldown: retryAfter has elapsed since the failure. Config drift alone reads
// every terminal failure as a verdict on the CONFIG, but most are a verdict on
// REACHABILITY: the operator could not open :22. Such a host stayed terminal
// until someone shipped an unrelated config change or hand-patched its status,
// all the while Ready, schedulable, and running jobs against a frozen host
// config, which is how a fleet ends up with hosts silently missing a
// networking fix. The cooldown bounds a persistently-broken config to one fresh
// attempt budget per interval rather than per reconcile, so the cap still does
// its job.
func shouldClearTerminalFailure(
	desiredHash, failedHash string,
	terminalFailure bool,
	lastFailure *metav1.Time,
	retryAfter time.Duration,
	now time.Time,
) bool {
	if !terminalFailure {
		return false
	}
	if desiredHash != "" && desiredHash != failedHash {
		return true
	}
	// A terminal CR recorded before this field existed carries no
	// timestamp; treat it as due rather than stranding it forever.
	if retryAfter <= 0 {
		return false
	}
	if lastFailure == nil {
		return true
	}
	return !now.Before(lastFailure.Time.Add(retryAfter))
}

// recordUpdateFailure increments the drift-loop retry counter and, once it
// crosses maxAttempts, flips the CR into a terminal Failed state. The counter
// is reset on a successful push. We don't try to be clever about which step in
// the loop failed; from the CR's perspective, any failure that prevents the
// config landing on the host counts the same. Recovery is automatic once the
// operator's desired host config drifts or the cooldown elapses (see
// clearUpdateFailure), and operator-driven before then: `kubectl patch` to
// clear status.failureReason + zero status.tartKubeletUpdateAttempts.
func recordUpdateFailure(machine hostAgentMachine, err error, maxAttempts int32, operatorHash string, logger logr.Logger, recorder record.EventRecorder) {
	status := machine.HostAgent()
	status.TartKubeletUpdateAttempts++
	// Stamped on every failure, not only the terminal one, so the cooldown
	// measures from the last attempt actually made.
	status.LastUpdateFailureTime = &metav1.Time{Time: time.Now()}
	logger.Error(err, "host config update step failed",
		"attempt", status.TartKubeletUpdateAttempts,
		"max", maxAttempts)
	if maxAttempts > 0 && status.TartKubeletUpdateAttempts >= maxAttempts {
		reason := "TartKubeletUpdateExceededRetries"
		msg := fmt.Sprintf("tart-kubelet update failed %d times: %v",
			status.TartKubeletUpdateAttempts, err)
		status.FailureReason = &reason
		status.FailureMessage = &msg
		// Record the desired config that exhausted its budget so the
		// self-heal only fires for a genuinely different config, not the same
		// broken one (whose HostConfigHash never advances because it can't be
		// applied) on every subsequent reconcile.
		status.FailedHostConfigHash = operatorHash
		status.Phase = "Failed"
		recorder.Eventf(machine, corev1.EventTypeWarning, reason, "%s", msg)
		logger.Error(err, "host config update permanently failed; CR transitioned to Failed",
			"attempts", status.TartKubeletUpdateAttempts)
		return
	}
	recorder.Eventf(machine, corev1.EventTypeWarning, "AgentRollFailed",
		"tart-kubelet update attempt %d/%d: %v",
		status.TartKubeletUpdateAttempts, maxAttempts, err)
}

// clearUpdateFailure resets the drift-loop retry counter and lifts the terminal
// Failed state so the loop resumes. Called when the operator's desired host
// config has drifted since the failure was recorded: the new config is a fresh
// target (typically a fix) that deserves its own retry budget rather than the
// old config's terminal verdict, so a bad rollout self-heals on the next config
// push instead of stranding every affected host on a manual `kubectl patch`.
// Also called when the retry cooldown has elapsed, which is what recovers a
// host that was merely unreachable. The caller passes which of the two applies
// so the log and Event name the real trigger. No-op when there is nothing to
// clear.
//
// LastUpdateFailureTime is deliberately left in place: it records when the host
// last failed, and the next failure re-stamps it. Clearing it here would make a
// re-failed host read as never-failed.
func clearUpdateFailure(machine hostAgentMachine, reason string, logger logr.Logger, recorder record.EventRecorder) {
	status := machine.HostAgent()
	if status.FailureReason == nil && status.FailureMessage == nil && status.TartKubeletUpdateAttempts == 0 {
		return
	}
	logger.Info("clearing terminal host config update failure; retrying",
		"reason", reason,
		"previousAttempts", status.TartKubeletUpdateAttempts)
	status.FailureReason = nil
	status.FailureMessage = nil
	status.FailedHostConfigHash = ""
	status.TartKubeletUpdateAttempts = 0
	if status.Phase == "Failed" {
		status.Phase = ""
	}
	recorder.Eventf(machine, corev1.EventTypeNormal, "AgentRollRetried",
		"cleared the terminal tart-kubelet update failure (%s); retrying", reason)
}

// hostSizing is the SKU-shaped slice of a Machine's spec: the fields that are
// fleet-wide in the host-config hash but overridable per host, so one operator
// can run a heterogeneous fleet.
//
// It is a value rather than a pointer to either machine kind so that
// applyHostSizing and the hash have exactly one implementation. The per-kind
// resolvers (which spec field wins over which operator default) stay with their
// kind; what they produce is this.
type hostSizing struct {
	HostCPU              int
	HostMemoryMB         int
	MaxPods              int
	GuestCapacity        int
	RunnerCacheVolumeGiB int
}

// applyHostSizing overlays one host's sizing onto the fleet config. It is the
// one seam between fleet-wide and per-host: everything else in a
// bootstrap.Config is either identical fleet-wide or lives in PerHost.
//
// Both push paths go through it, so neither can push a config the operator did
// not hash: hostConfigHashFor calls the same function with an empty PerHost.
func applyHostSizing(fleet bootstrap.Config, sizing hostSizing, perHost bootstrap.PerHost) bootstrap.Config {
	cfg := fleet
	cfg.HostCPU = sizing.HostCPU
	cfg.HostMemoryMB = sizing.HostMemoryMB
	cfg.MaxPods = sizing.MaxPods
	cfg.RunnerCacheVolumeGiB = sizing.RunnerCacheVolumeGiB

	// Both of these are per-guest host resources, so they follow the host's
	// guest capacity rather than being knobs of their own.
	//
	// A single-guest host resolves both to 1, which is what tart-kubelet
	// already defaults to, and the plist renderer omits a flag whose value is
	// the default, so an existing fleet's rendered config (and therefore its
	// host-config hash) is unchanged by this and does not drift.
	cfg.VNCRelayPortCount = sizing.GuestCapacity
	cfg.MinGoldensKept = sizing.GuestCapacity

	return cfg.WithPerHost(perHost)
}

// hostConfigHashFor is the fingerprint of the config a host with this sizing
// should be running. It hashes exactly what applyHostSizing would push, so a
// host is only ever stamped with a hash of the config it actually received.
//
// Computed per machine rather than once per fleet because the sizing fields are
// overridable per Machine. A single fleet constant was correct for every host
// that took the fleet defaults and quietly wrong for one that did not: the
// operator pushed the overridden config and then stamped the fleet hash on it,
// so the host read as converged to a config it had never been sent, and a later
// change to the overridden field could not drift it.
func hostConfigHashFor(fleet bootstrap.Config, sizing hostSizing) string {
	return bootstrap.HostConfigHash(applyHostSizing(fleet, sizing, bootstrap.PerHost{}))
}

// egressConfig is the chart-driven Tailscale egress wiring, shared by both
// macOS kinds because a mini is reached the same way whoever owns the hardware.
type egressConfig struct {
	Namespace      string
	ProxyGroup     string
	MagicDNSSuffix string
	// ManagedBy is the operator name stamped on the Service's
	// `app.kubernetes.io/managed-by` label.
	ManagedBy string
}

func (c egressConfig) enabled() bool {
	return c.ProxyGroup != "" && c.Namespace != ""
}

// egressServiceHost is the in-cluster DNS name of a mini's tailnet egress
// Service. Resolving it routes any cluster Pod to the mini over the
// ProxyGroup's tailnet identity, on the ports the Service declares. Empty when
// the tailnet egress is disabled (OSS / self-hosted), so callers fall back to
// the host's own address.
func egressServiceHost(cfg egressConfig, machineName string) string {
	if !cfg.enabled() {
		return ""
	}
	return fmt.Sprintf("%s.%s.svc.cluster.local", machineName, cfg.Namespace)
}

// reconcileEgressService maintains one ExternalName Service per Mac mini in the
// egress namespace. The Tailscale K8s operator detects the
// `tailscale.com/tailnet-fqdn` annotation and rewrites the Service's
// externalName to point at a ClusterIP fronting the named ProxyGroup; from then
// on any cluster Pod that resolves the Service DNS gets routed through the
// ProxyGroup's tailnet identity to the mini.
//
// Idempotent via CreateOrUpdate: a re-reconcile with no spec change is a noop on
// the apiserver. A disabled egressConfig short-circuits the whole thing for
// OSS/self-hosted clusters.
func reconcileEgressService(
	ctx context.Context,
	c client.Client,
	cfg egressConfig,
	machineName, fleetName string,
	guests int,
) error {
	if cfg.ProxyGroup == "" {
		return nil
	}
	if cfg.MagicDNSSuffix == "" {
		return fmt.Errorf("EgressMagicDNSSuffix empty but EgressProxyGroup=%q set", cfg.ProxyGroup)
	}
	if cfg.Namespace == "" {
		return fmt.Errorf("EgressNamespace empty but EgressProxyGroup=%q set", cfg.ProxyGroup)
	}

	// FQDN is the tailnet hostname (= machineName; see bootstrap's
	// `tailscale up --hostname=$NodeName`) suffixed with the tailnet's
	// MagicDNS domain (operator flag, set per env in the chart).
	fqdn := machineName + "." + cfg.MagicDNSSuffix

	svc := &corev1.Service{ObjectMeta: metav1.ObjectMeta{
		Name:      machineName,
		Namespace: cfg.Namespace,
	}}
	_, err := controllerutil.CreateOrUpdate(ctx, c, svc, func() error {
		if svc.Labels == nil {
			svc.Labels = map[string]string{}
		}
		// Labels alloy-metrics' Service-role discovery filters on
		// (`tuist.dev/macmini-egress=true`). They are identical for every
		// macOS kind on purpose: a rack mini and a rented one are scraped by
		// the same job, and making managed-by kind-specific would silently
		// drop whichever kind the scrape config didn't name.
		svc.Labels["app.kubernetes.io/managed-by"] = cfg.ManagedBy
		svc.Labels["app.kubernetes.io/component"] = "macmini-egress"
		svc.Labels["tuist.dev/macmini-egress"] = "true"
		svc.Labels["tuist.dev/macmini-machine"] = machineName
		if fleetName != "" {
			svc.Labels["tuist.dev/fleet"] = fleetName
		} else {
			delete(svc.Labels, "tuist.dev/fleet")
		}

		if svc.Annotations == nil {
			svc.Annotations = map[string]string{}
		}
		svc.Annotations["tailscale.com/tailnet-fqdn"] = fqdn
		svc.Annotations["tailscale.com/proxy-group"] = cfg.ProxyGroup

		svc.Spec.Type = corev1.ServiceTypeExternalName
		// On first create, seed externalName with a syntactically valid
		// placeholder. The Tailscale operator rewrites it at admission time to
		// a ClusterIP Service fronting the ProxyGroup; on re-reconcile we don't
		// stamp it back, so the operator's rewrite sticks.
		if svc.Spec.ExternalName == "" {
			svc.Spec.ExternalName = "placeholder." + cfg.Namespace + ".svc.cluster.local"
		}
		// Named ports the ProxyGroup forwards to the mini over the tailnet.
		// alloy-metrics filters on port_name to dispatch the scrape ports
		// (9100/8080) to the right job; vnc-relay fronts the dashboard; ssh
		// (:22) carries the host-config drift update, so the operator can roll
		// config over the tailnet when the mini's public :22 is filtered. The
		// tailnet ACL must also grant tcp:22 from tag:tuist-k8s-<env> to
		// tag:tuist-macmini-<env> (infra/tailscale/acls.json). pod-metrics
		// (:9091) reaches tart-kubelet's host-side metrics forwarder, which
		// proxies to the Tart guest's PromEx endpoint. It has to come through
		// this egress like every other mini port: the cluster CNI installs no
		// route for 100.64.0.0/10, so a generic Pod cannot dial a mini's
		// tailnet IPv4 directly.
		//
		// vnc-relay is a RANGE, one port per guest the host can run: the relay
		// is per-Pod but a pinned port is per-host, so a dual-guest mini binds
		// 5900 and 5901 and the ProxyGroup has to forward both. The first port
		// keeps the bare `vnc-relay` name so a single-guest host's Service is
		// unchanged; subsequent ones are suffixed. tart-kubelet picks whichever
		// is free and republishes the actual port on the Pod annotation, so
		// nothing downstream has to know which guest won which port.
		svc.Spec.Ports = []corev1.ServicePort{
			{Name: "node-exporter", Port: 9100, Protocol: corev1.ProtocolTCP},
			{Name: "tart-kubelet", Port: 8080, Protocol: corev1.ProtocolTCP},
			{Name: "pod-metrics", Port: 9091, Protocol: corev1.ProtocolTCP},
		}
		for offset := 0; offset < guests; offset++ {
			name := "vnc-relay"
			if offset > 0 {
				name = fmt.Sprintf("vnc-relay-%d", offset+1)
			}
			svc.Spec.Ports = append(svc.Spec.Ports, corev1.ServicePort{
				Name:     name,
				Port:     int32(DashboardVNCRelayPort + offset),
				Protocol: corev1.ProtocolTCP,
			})
		}
		svc.Spec.Ports = append(svc.Spec.Ports,
			corev1.ServicePort{Name: "ssh", Port: 22, Protocol: corev1.ProtocolTCP})
		return nil
	})
	return err
}

// nodeBootstrapGrace is how long after BootstrappedCondition flips to True we
// tolerate a missing Node before deciding it's drift. tart-kubelet's launchd job
// typically registers within ~30s of bootstrap completion; 2 min absorbs
// apiserver + watch propagation delays without giving up so long that a deploy
// waits multiple reconcile cycles to detect the drift.
const nodeBootstrapGrace = 2 * time.Minute

// nodeMissingAfterBootstrap reports that bootstrap previously succeeded
// (BootstrappedCondition=True for at least nodeBootstrapGrace) but the Node
// tart-kubelet registered no longer exists.
//
// Causes seen in practice: upstream CAPI core deleting the Node during
// workload-cluster reconcile churn, a manual `kubectl delete node`, or a
// cluster-level cleanup controller. The host itself is still allocated and its
// launchd job still loaded, so re-running bootstrap reloads launchd and
// tart-kubelet re-registers: no re-provisioning, and the existing per-machine
// token, ServiceAccount and ClusterRoleBinding stay in place. Callers flip the
// condition False and let the bootstrap gate drive the repair.
//
// The grace window is what stops the initial post-bootstrap requeue from
// looking like drift while the first registration is still propagating.
func nodeMissingAfterBootstrap(
	ctx context.Context,
	c client.Client,
	machine conditions.Getter,
	nodeName string,
) (bool, error) {
	cond := conditions.Get(machine, BootstrappedCondition)
	if cond == nil || cond.Status != corev1.ConditionTrue {
		return false, nil
	}
	if time.Since(cond.LastTransitionTime.Time) < nodeBootstrapGrace {
		return false, nil
	}
	err := c.Get(ctx, client.ObjectKey{Name: nodeName}, &corev1.Node{})
	if apierrors.IsNotFound(err) {
		return true, nil
	}
	if err != nil {
		return false, err
	}
	return false, nil
}
