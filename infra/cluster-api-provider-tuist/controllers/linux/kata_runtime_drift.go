package linux

import (
	"context"
	"fmt"

	"github.com/prometheus/client_golang/prometheus"
	corev1 "k8s.io/api/core/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/cluster-api/util/patch"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
	"sigs.k8s.io/controller-runtime/pkg/metrics"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

// KataRuntimeSelectorLabel is the node label the kata-qemu RuntimeClass selects
// on (infra/helm/tuist/templates/kata-qemu.yaml). It is the single observable
// that decides whether a runner Pod can land on the box, which is why the drift
// loop checks it rather than, say, the provider version that bootstrapped the
// node: it is true by construction that a node carrying this label is one the
// scheduler will place kata Pods on, and false by construction otherwise.
const KataRuntimeSelectorLabel = "katacontainers.io/kata-runtime"

// KataRuntimeReadyCondition reports whether a machine that asked for
// spec.kataRuntime actually ended up on a box that can run microVM Pods.
//
// It exists because the failure it names is otherwise invisible. The self-join
// is rendered exactly once, at bootstrap, by whichever provider pod happens to
// hold the leader lease at that moment — which during a rolling provider upgrade
// can be the OUTGOING pod, running a build that does not understand the field.
// The resulting node joins Ready, lands in the right pool with the right taints,
// runs every DaemonSet, logs no error anywhere, and never takes a single job.
// Both production and canary hit exactly that on 2026-08-31 (the chart created
// the Machine two seconds into the provider rollout) and it read as a scheduling
// bug for about an hour.
const KataRuntimeReadyCondition clusterv1.ConditionType = "KataRuntimeReady"

const (
	// KataRuntimeMissingReason is set the moment the gap is observed, before any
	// repair is attempted, so a box the operator cannot reach is loudly broken
	// instead of quietly retried.
	KataRuntimeMissingReason = "KataRuntimeMissing"

	// KataRuntimeRepairFailedReason is set when the in-place repair could not
	// complete: the box is unreachable, or it refused the runtime (e.g. its
	// containerd predates the v3 config syntax the handler is written in).
	KataRuntimeRepairFailedReason = "KataRuntimeRepairFailed"
)

// kataRuntimeReadyGauge is the alertable form of the condition. Only machines
// that asked for kata get a series, so `min_over_time(...) == 0` is a clean
// "a runner box has been unable to take jobs" alert with no cache-fleet noise.
var kataRuntimeReadyGauge = prometheus.NewGaugeVec(prometheus.GaugeOpts{
	Name: "capt_node_kata_runtime_ready",
	Help: "1 when a machine with spec.kataRuntime carries the katacontainers.io/kata-runtime node label the kata-qemu RuntimeClass selects on, 0 when it does not (the node is Ready but no runner Pod can schedule on it). Machines that never asked for kata publish no series.",
}, []string{"machine", "fleet"})

func init() {
	metrics.Registry.MustRegister(kataRuntimeReadyGauge)
}

func recordKataRuntimeReady(machine, fleet string, ready bool) {
	value := 0.0
	if ready {
		value = 1
	}
	kataRuntimeReadyGauge.WithLabelValues(machine, fleet).Set(value)
}

// forgetKataRuntimeMetric drops a machine's series once it stops asking for kata
// or its CR is gone, so a released box never alerts as a stuck runner node.
func forgetKataRuntimeMetric(machine string) {
	kataRuntimeReadyGauge.DeletePartialMatch(prometheus.Labels{"machine": machine})
}

// renderKataRuntimeRepairScript renders the minimal, idempotent script the
// repair pipes over SSH to an already-Ready node that joined without kata.
//
// This is deliberately NOT a re-bootstrap. It never touches apt sources, the
// kubelet install, the /data mounts, or the kubelet itself; it installs the
// runtime, registers the handler, and re-renders the kubelet unit. That
// restraint is what makes it safe to run unattended against a live box: the
// worst it does is restart containerd, which does not kill running containers
// (their shims are separate processes that outlive it and reattach), so no drain
// is needed and no running job is disturbed. Re-bootstrapping — the manual
// recovery used during the incident — would have wiped the box.
//
// The kubelet unit rewrite does not fix the live Node. kubelet applies
// --node-labels only when it CREATES the Node object; on restart against an
// existing Node it reconciles just the well-known kubernetes.io labels and
// ignores custom ones. So the unit is re-rendered for the node's next
// registration, and the controller patches the live Node itself.
//
// Both of those advertise the box to the scheduler, and neither may run ahead of
// the proof. The script verifies the runtime first and writes the unit last; the
// controller labels the live Node only on the script's exit status. Advertising
// a box whose repair did not finish turns "no Pod ever schedules" into "every
// Pod wedged in ContainerCreating", which is harder to diagnose and burns the
// job instead of queueing it.
func renderKataRuntimeRepairScript(opts linuxCloudInitOptions) string {
	sudo, sudoE := escalation(opts.BootstrapUser)
	kubeletUnit := kubeletUnitContent(
		opts.NodeName,
		taintArgFor(opts.Taints),
		instanceTypeOrDefault(opts.InstanceType),
		kataNodeLabelsArg(true),
	)
	return fmt.Sprintf(`#!/usr/bin/env bash
set -euxo pipefail
# The install below pulls zstd. The bootstrap gets its noninteractive frontend
# and a fresh package index from the steps that precede it; this script has no
# such steps, and a months-stale index on a long-running box no longer resolves
# the version it lists.
export DEBIAN_FRONTEND=noninteractive
%[4]sapt-get update
%[3]s
# Check the shim and the handler BEFORE the restart: containerd must never
# reload into a config naming a binary that is not on disk.
%[1]stest -x /opt/kata/bin/containerd-shim-kata-v2
%[1]sgrep -q "runtimes.kata-qemu" /etc/containerd/config.toml
# Unconditional, and it has to be. The append above is idempotent, so from the
# second attempt onwards the handler is already in the file; a restart
# conditioned on it being absent would be skipped forever, and a first attempt
# whose restart failed or timed out would leave a daemon still running the
# pre-kata config while every file check passes. Restarting each time is what
# makes "the script exited 0" mean "the running daemon loaded this config".
# It costs nothing here: this script only ever runs on a runner box the
# RuntimeClass cannot select yet, so there is no kata workload to blip, and a
# containerd restart does not kill running containers anyway.
%[1]ssystemctl restart containerd
%[1]ssystemctl is-active --quiet containerd
# The kubelet unit is written LAST, once the runtime is proven. It carries the
# kata node labels, and kubelet self-applies those when it registers a Node — so
# installing it before the runtime is verified would let a later Node
# re-registration advertise a box whose repair failed, turning "no Pod ever
# schedules" into "every Pod wedged in ContainerCreating". Failing before this
# point leaves the old unit in place, which fails closed.
%[1]stee /etc/systemd/system/kubelet.service > /dev/null <<'TUIST_EOF'
%[2]sTUIST_EOF
%[1]ssystemctl daemon-reload
`, sudo, ensureTrailingNewline(kubeletUnit), kataSetup(sudo, sudoE, true), sudoE)
}

// labelKataRuntimeNode patches the kata labels onto the live Node, which is the
// step that actually makes the kata-qemu RuntimeClass select the box. Only
// reached once the repair script has verified the runtime is installed.
func labelKataRuntimeNode(ctx context.Context, c client.Client, node *corev1.Node) error {
	helper, err := patch.NewHelper(node, c)
	if err != nil {
		return err
	}
	if node.Labels == nil {
		node.Labels = map[string]string{}
	}
	for _, label := range kataNodeLabels {
		node.Labels[label.Key] = label.Value
	}
	return helper.Patch(ctx, node)
}

// reconcileLinuxKataRuntimeDrift brings an already-Ready node onto the kata
// runtime its Machine spec asked for, in place.
//
// The Linux self-join is rendered once at bootstrap and nothing re-runs it, so a
// bootstrap-time capability that the rendering controller did not understand is
// missing forever — the fleet MachineDeployments even use `strategy: OnDelete`,
// so flipping the field on afterwards never rolls the existing machines either.
// This closes that hole for kata by reconciling the node's observed state
// against the spec rather than trusting that bootstrap got it right.
//
// It leaves Machine.Status.Ready alone: the node IS a healthy Kubernetes node,
// and failing the Machine would make CAPI churn a box that needs a two-minute
// in-place repair.
//
// Returns requeue=true when it did work or deferred, false when there was
// nothing to do. On a converged node this is one map lookup.
//
// Any future bootstrap-time capability on these kinds needs the same treatment:
// an observable on the Node, a check here, and a repair that is additive rather
// than a re-bootstrap. See infra/cluster-api-provider-tuist/AGENTS.md.
func reconcileLinuxKataRuntimeDrift(
	ctx context.Context,
	c client.Client,
	cm *credentials.Manager,
	machine conditions.Setter,
	machineName, fleet string,
	opts linuxCloudInitOptions,
	node *corev1.Node,
) (requeue bool, err error) {
	logger := log.FromContext(ctx)

	if !opts.KataRuntime {
		conditions.Delete(machine, KataRuntimeReadyCondition)
		forgetKataRuntimeMetric(machineName)
		return false, nil
	}
	if node.Labels[KataRuntimeSelectorLabel] == "true" {
		conditions.MarkTrue(machine, KataRuntimeReadyCondition)
		recordKataRuntimeReady(machineName, fleet, true)
		return false, nil
	}

	// Mark before attempting anything. Every path out of here that does not
	// finish the repair leaves the machine visibly broken, which is the whole
	// point: the incident's cost was that a node in this state looked healthy.
	conditions.MarkFalse(machine, KataRuntimeReadyCondition, KataRuntimeMissingReason,
		clusterv1.ConditionSeverityError,
		"node carries no %s label, so no runtimeClassName=kata-qemu Pod can schedule on it; repairing in place",
		KataRuntimeSelectorLabel)
	recordKataRuntimeReady(machineName, fleet, false)

	host := nodeInternalIP(node)
	if host == "" {
		logger.Info("deferring kata runtime repair until the node reports an InternalIP", "node", node.Name)
		return true, nil
	}

	privateKey, err := cm.EnsureFleetSSHKey(ctx, fleet)
	if err != nil {
		return false, fmt.Errorf("fleet ssh key for kata repair: %w", err)
	}
	known := ""
	if creds, fpErr := cm.GetMachineBootstrap(ctx, machineName); fpErr != nil {
		return false, fmt.Errorf("read host fingerprint for kata repair: %w", fpErr)
	} else if creds != nil {
		known = creds.HostFingerprint
	}
	hostKey := bootstrap.NewHostKeyState(known)

	sshErr := bootstrapOverSSH(ctx, opts.BootstrapUser, host, privateKey, renderKataRuntimeRepairScript(opts), hostKey)
	// Persist a newly TOFU'd key before anything else, matching the bootstrap and
	// kubelet-config paths: the key was observed even if the script then failed.
	if observed := hostKey.Observed(); observed != "" && observed != known {
		if perr := cm.SetMachineHostFingerprint(ctx, machineName, observed); perr != nil {
			logger.Error(perr, "persist host fingerprint after kata repair; will retry", "node", node.Name)
		}
	}
	if sshErr != nil {
		conditions.MarkFalse(machine, KataRuntimeReadyCondition, KataRuntimeRepairFailedReason,
			clusterv1.ConditionSeverityError,
			"could not install the kata runtime on %s, so the node still takes no runner job: %v", host, sshErr)
		return false, fmt.Errorf("repair kata runtime over ssh on %s: %w", host, sshErr)
	}
	if labelErr := labelKataRuntimeNode(ctx, c, node); labelErr != nil {
		return false, fmt.Errorf("label node for the kata-qemu RuntimeClass: %w", labelErr)
	}

	conditions.MarkTrue(machine, KataRuntimeReadyCondition)
	recordKataRuntimeReady(machineName, fleet, true)
	logger.Info("installed the kata runtime on a node that joined without it and labelled it for the kata-qemu RuntimeClass",
		"node", node.Name, "host", host)
	return true, nil
}
