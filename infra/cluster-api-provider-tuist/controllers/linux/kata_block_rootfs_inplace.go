package linux

import (
	"context"
	"errors"
	"fmt"
	"time"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	conditions "github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/capiconditions"
	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	"k8s.io/apimachinery/pkg/types"
	"k8s.io/client-go/tools/record"
	clusterv1 "sigs.k8s.io/cluster-api/api/core/v1beta1"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// A box that joined without KataBlockRootfs is converted in place, so turning
// the field on for a fleet reaches its existing boxes without a reinstall. The
// pool is two loop files under /data, so nothing about the disk changes: the
// conversion writes the pool unit, points the kata-qemu handler at devmapper,
// adds the Kata drop-in and restarts containerd. A containerd restart leaves
// running containers alone (their shims outlive it), but a Kata container made
// before it keeps its virtiofs rootfs, so the box is cordoned and its runner
// Pods, busy or idle, are waited out first: the runners-controller retires the
// idle ones once the Node is cordoned, and busy ones finish their job.
//
// At most KataBlockRootfsMaxConverting boxes are out of service for it at once,
// counted across every Node by the annotation that marks a box this conversion
// cordoned. The reconciler runs one machine at a time, so the count it reads is
// the one it acts on.
const (
	// kataBlockRootfsAnnotation records the conversion revision a Node carries.
	kataBlockRootfsAnnotation = "tuist.dev/kata-block-rootfs"
	// kataBlockRootfsRevision is bumped deliberately, only when a box that has
	// the pool must be drained again to pick up a change.
	kataBlockRootfsRevision = "1"
	// kataBlockRootfsConvertingAnnotation holds a rollout slot while a box
	// drains and converts. Its value says whether the Node was already cordoned
	// by someone else, in which case it stays cordoned afterwards.
	kataBlockRootfsConvertingAnnotation = "tuist.dev/kata-block-rootfs-converting"
	kataBlockRootfsCordonedByUs         = "cordoned"
	kataBlockRootfsWasCordoned          = "was-cordoned"

	KataBlockRootfsReadyCondition clusterv1.ConditionType = "KataBlockRootfsReady"

	kataBlockRootfsWaitingForSlotReason = "WaitingForRolloutSlot"
	kataBlockRootfsWaitingForJobsReason = "WaitingForRunnerJobs"
	kataBlockRootfsFailedReason         = "ConversionFailed"

	// kataBlockRootfsPendingExit is the probe's exit status for a box that is
	// not converted yet, as opposed to one the probe could not check.
	kataBlockRootfsPendingExit = 10
)

// DefaultKataBlockRootfsMaxConverting is the rollout's concurrency when the
// manager is not told otherwise.
const DefaultKataBlockRootfsMaxConverting = 1

const kataQemuHandlerTable = `\[plugins\.'io\.containerd\.cri\.v1\.runtime'\.containerd\.runtimes\.kata-qemu\]`
const kataQemuOptionsTable = `\[plugins\.'io\.containerd\.cri\.v1\.runtime'\.containerd\.runtimes\.kata-qemu\.options\]`

// kataHandlerSnapshotterSed sets the kata-qemu handler's snapshotter in a
// config bootstrap already wrote the handler into (bootstrap's append is
// skipped once the handler exists). It replaces any snapshotter line in the
// handler table, so it is idempotent, and leaves the options table alone.
const kataHandlerSnapshotterSed = `/^` + kataQemuHandlerTable + `$/,/^` + kataQemuOptionsTable + `$/{
/^snapshotter = /d
/^` + kataQemuOptionsTable + `$/i snapshotter = "devmapper"
}`

// kataDevmapperLoaded is true once the running containerd loaded the devmapper
// snapshotter, which is what makes the handler's snapshotter line mean anything.
const kataDevmapperLoaded = `ctr plugins ls | awk '$1 == "io.containerd.snapshotter.v1" && $2 == "devmapper" { print $NF }' | grep -qx ok`

// renderKataBlockRootfsProbeScript exits 0 on a converted box,
// kataBlockRootfsPendingExit on one that is not, and anything else when it
// could not tell. It changes nothing, so it runs without a drain: a box that
// was bootstrapped with the field, or converted before its Node was stamped,
// is stamped without being taken out of service.
func renderKataBlockRootfsProbeScript(opts linuxCloudInitOptions) string {
	sudo, _ := escalation(opts.BootstrapUser)
	return fmt.Sprintf(`#!/usr/bin/env bash
set -euo pipefail
%[1]sbash -s <<'TUIST_KATA_BLOCK_ROOTFS_PROBE'
set -euo pipefail
pending() { echo "tuist: $1" >&2; exit %[2]d; }
dmsetup status %[3]s 2>/dev/null | grep -q thin-pool || pending "the devmapper pool is not active"
sed -n "/^%[4]s$/,/^%[5]s$/p" /etc/containerd/config.toml | grep -qx 'snapshotter = "devmapper"' || pending "the kata-qemu handler does not use devmapper"
diff -q - %[6]s > /dev/null 2>&1 <<'TUIST_KATA_BLOCK_ROOTFS_DROPIN' || pending "the Kata block rootfs drop-in is missing or differs"
%[7]sTUIST_KATA_BLOCK_ROOTFS_DROPIN
%[8]s || pending "containerd has not loaded the devmapper snapshotter"
TUIST_KATA_BLOCK_ROOTFS_PROBE
`, sudo, kataBlockRootfsPendingExit, kataDevmapperPool, kataQemuHandlerTable, kataQemuOptionsTable,
		kataBlockRootfsDropInPath, kataBlockRootfsDropIn, kataDevmapperLoaded)
}

// renderKataBlockRootfsConvertScript converts a drained box. Everything before
// the handler edit leaves the box as it was when it fails (the pool unit is
// WantedBy containerd, not RequiredBy), so a box whose /data cannot hold the
// pool keeps serving on virtiofs once uncordoned by hand. The handler edit and
// the restart come last, and the script only exits 0 once the running
// containerd loaded devmapper.
func renderKataBlockRootfsConvertScript(opts linuxCloudInitOptions) string {
	sudo, sudoE := escalation(opts.BootstrapUser)
	return fmt.Sprintf(`#!/usr/bin/env bash
set -euxo pipefail
export DEBIAN_FRONTEND=noninteractive
%[1]s
if ! command -v thin_check > /dev/null; then
  apt_retry %[2]sapt-get update
  apt_retry %[2]sapt-get install -y thin-provisioning-tools
fi
%[3]s%[4]ssed -i "$(cat <<'TUIST_KATA_HANDLER_SED'
%[5]s
TUIST_KATA_HANDLER_SED
)" /etc/containerd/config.toml
%[4]ssed -n "/^%[6]s$/,/^%[7]s$/p" /etc/containerd/config.toml | grep -qx 'snapshotter = "devmapper"'
%[4]ssystemctl restart containerd
%[4]ssystemctl is-active --quiet containerd
for attempt in $(seq 30); do
  %[4]sbash -c %[8]s && exit 0
  sleep 2
done
echo "tuist: containerd did not load the devmapper snapshotter after the restart" >&2
exit 1
`, aptRetry, sudoE, kataBlockRootfsSetup(sudo), sudo, kataHandlerSnapshotterSed,
		kataQemuHandlerTable, kataQemuOptionsTable, shellSingleQuote(kataDevmapperLoaded))
}

// kataBlockRootfsConversion is what reconcileKataBlockRootfs needs from its
// caller. Run executes a script on the box and returns its error, wrapping an
// *ssh.ExitError for a non-zero exit.
type kataBlockRootfsConversion struct {
	Client        client.Client
	Reader        client.Reader
	Recorder      record.EventRecorder
	Object        conditions.Setter
	MaxConverting int
	Run           func(ctx context.Context, script string) error
}

// reconcileKataBlockRootfs brings a Ready box whose Machine wants
// KataBlockRootfs onto it in place. It returns requeue=true while it has work
// left. It never fails the Machine: the box serves on virtiofs until converted.
func reconcileKataBlockRootfs(ctx context.Context, k kataBlockRootfsConversion, wanted bool, opts linuxCloudInitOptions, node *corev1.Node) (time.Duration, error) {
	logger := log.FromContext(ctx)
	slot := node.Annotations[kataBlockRootfsConvertingAnnotation]

	if !wanted || node.Annotations[kataBlockRootfsAnnotation] == kataBlockRootfsRevision {
		if !wanted {
			conditions.Delete(k.Object, KataBlockRootfsReadyCondition)
		} else {
			conditions.MarkTrue(k.Object, KataBlockRootfsReadyCondition)
		}
		if slot != "" {
			return 0, releaseKataBlockRootfsSlot(ctx, k.Client, node, slot, false)
		}
		return 0, nil
	}

	if slot == "" {
		probeErr := k.Run(ctx, renderKataBlockRootfsProbeScript(opts))
		if probeErr == nil {
			conditions.MarkTrue(k.Object, KataBlockRootfsReadyCondition)
			return 0, stampKataBlockRootfs(ctx, k.Client, node)
		}
		// *ssh.ExitError carries the exit status.
		var exitErr interface{ ExitStatus() int }
		if !errors.As(probeErr, &exitErr) || exitErr.ExitStatus() != kataBlockRootfsPendingExit {
			conditions.MarkFalse(k.Object, KataBlockRootfsReadyCondition, kataBlockRootfsFailedReason,
				clusterv1.ConditionSeverityWarning, "could not check the devmapper rootfs on the box: %v", probeErr)
			return 0, fmt.Errorf("probe the kata block rootfs: %w", probeErr)
		}

		taken, err := kataBlockRootfsSlotsTaken(ctx, k.Reader)
		if err != nil {
			return 0, err
		}
		limit := k.MaxConverting
		if limit <= 0 {
			limit = DefaultKataBlockRootfsMaxConverting
		}
		if taken >= limit {
			conditions.MarkFalse(k.Object, KataBlockRootfsReadyCondition, kataBlockRootfsWaitingForSlotReason,
				clusterv1.ConditionSeverityInfo, "%d of %d boxes are converting to the devmapper rootfs; waiting for a slot", taken, limit)
			return time.Minute, nil
		}
		slot = kataBlockRootfsCordonedByUs
		if node.Spec.Unschedulable {
			slot = kataBlockRootfsWasCordoned
		}
		before := node.DeepCopy()
		if node.Annotations == nil {
			node.Annotations = map[string]string{}
		}
		node.Annotations[kataBlockRootfsConvertingAnnotation] = slot
		node.Spec.Unschedulable = true
		if err := k.Client.Patch(ctx, node, client.MergeFrom(before)); err != nil {
			return 0, fmt.Errorf("take a devmapper rollout slot on Node %s: %w", node.Name, err)
		}
		k.event(k.Object, corev1.EventTypeNormal, "KataBlockRootfsDraining",
			"Node %s is cordoned to move its Kata rootfs onto devmapper", node.Name)
	}

	running, err := holdReleaseForRunnerJobs(ctx, k.Client, node.Name)
	if err != nil {
		return 0, err
	}
	if len(running) > 0 {
		conditions.MarkFalse(k.Object, KataBlockRootfsReadyCondition, kataBlockRootfsWaitingForJobsReason,
			clusterv1.ConditionSeverityInfo, "%s", releaseHeldMessage(node.Name, running))
		return runnerJobsRecheckInterval, nil
	}

	if err := k.Run(ctx, renderKataBlockRootfsConvertScript(opts)); err != nil {
		// The box stays cordoned: whether the handler was already edited is
		// unknown, and a kata Pod placed on a half-converted box burns its job.
		conditions.MarkFalse(k.Object, KataBlockRootfsReadyCondition, kataBlockRootfsFailedReason,
			clusterv1.ConditionSeverityError, "moving the Kata rootfs onto devmapper failed; Node %s stays cordoned: %v", node.Name, err)
		k.event(k.Object, corev1.EventTypeWarning, "KataBlockRootfsFailed", "%v", err)
		return 0, fmt.Errorf("convert the kata rootfs to devmapper: %w", err)
	}
	if err := releaseKataBlockRootfsSlot(ctx, k.Client, node, slot, true); err != nil {
		return 0, err
	}
	conditions.MarkTrue(k.Object, KataBlockRootfsReadyCondition)
	k.event(k.Object, corev1.EventTypeNormal, "KataBlockRootfsConverted",
		"Node %s runs Kata containers on a devmapper rootfs", node.Name)
	logger.Info("moved the Kata rootfs onto devmapper in place", "node", node.Name)
	return 0, nil
}

func kataBlockRootfsSlotsTaken(ctx context.Context, reader client.Reader) (int, error) {
	nodes := &corev1.NodeList{}
	if err := reader.List(ctx, nodes); err != nil {
		return 0, fmt.Errorf("list Nodes for the devmapper rollout: %w", err)
	}
	taken := 0
	for i := range nodes.Items {
		if nodes.Items[i].Annotations[kataBlockRootfsConvertingAnnotation] != "" {
			taken++
		}
	}
	return taken, nil
}

func stampKataBlockRootfs(ctx context.Context, c client.Client, node *corev1.Node) error {
	before := node.DeepCopy()
	if node.Annotations == nil {
		node.Annotations = map[string]string{}
	}
	node.Annotations[kataBlockRootfsAnnotation] = kataBlockRootfsRevision
	if err := c.Patch(ctx, node, client.MergeFrom(before)); err != nil {
		return fmt.Errorf("stamp Node %s with the devmapper rootfs: %w", node.Name, err)
	}
	return nil
}

// releaseKataBlockRootfsSlot frees the rollout slot and uncordons the Node if
// the conversion cordoned it. One patch, so the stamp, the uncordon and the
// slot never disagree.
func releaseKataBlockRootfsSlot(ctx context.Context, c client.Client, node *corev1.Node, slot string, converted bool) error {
	before := node.DeepCopy()
	delete(node.Annotations, kataBlockRootfsConvertingAnnotation)
	if converted {
		node.Annotations[kataBlockRootfsAnnotation] = kataBlockRootfsRevision
	}
	if slot == kataBlockRootfsCordonedByUs {
		node.Spec.Unschedulable = false
	}
	if err := c.Patch(ctx, node, client.MergeFrom(before)); err != nil {
		return fmt.Errorf("release the devmapper rollout slot on Node %s: %w", node.Name, err)
	}
	return nil
}

// wantsKataBlockRootfs reads the field from the Machine and from the template
// the fleet's MachineDeployment clones it from. The fleets are OnDelete, so a
// Machine keeps the template it was cloned from: turning the field on in the
// template is what reaches the boxes already running. Turning it off reaches
// none of them, since the conversion is one way, and new boxes skip it.
func (r *OVHDedicatedMachineReconciler) wantsKataBlockRootfs(ctx context.Context, machine *infrav1.OVHDedicatedMachine) (bool, error) {
	if !machine.Spec.KataRuntime {
		return false, nil
	}
	if machine.Spec.KataBlockRootfs {
		return true, nil
	}
	name := machine.Annotations[clusterv1.TemplateClonedFromNameAnnotation]
	if name == "" {
		return false, nil
	}
	template := &infrav1.OVHDedicatedMachineTemplate{}
	if err := r.Get(ctx, types.NamespacedName{Namespace: machine.Namespace, Name: name}, template); err != nil {
		if apierrors.IsNotFound(err) {
			return false, nil
		}
		return false, fmt.Errorf("read OVHDedicatedMachineTemplate %s: %w", name, err)
	}
	return template.Spec.Template.Spec.KataBlockRootfs, nil
}

func (r *OVHDedicatedMachineReconciler) reconcileKataBlockRootfs(ctx context.Context, machine *infrav1.OVHDedicatedMachine, node *corev1.Node) (time.Duration, error) {
	wanted, err := r.wantsKataBlockRootfs(ctx, machine)
	if err != nil {
		return 0, err
	}
	opts := r.hostOptions(machine, node.Status.NodeInfo.KubeletVersion)
	opts.KataBlockRootfs = wanted
	return reconcileKataBlockRootfs(ctx, kataBlockRootfsConversion{
		Client:        r.Client,
		Reader:        r.reader(),
		Recorder:      r.Recorder,
		Object:        machine,
		MaxConverting: r.KataBlockRootfsMaxConverting,
		Run: func(ctx context.Context, script string) error {
			if r.KataBlockRootfsRunScript != nil {
				return r.KataBlockRootfsRunScript(ctx, machine, script)
			}
			return r.runPinnedHostScript(ctx, machine, "kata devmapper rootfs conversion", script)
		},
	}, wanted, opts, node)
}

func (k kataBlockRootfsConversion) event(object client.Object, eventType, reason, format string, args ...any) {
	if k.Recorder != nil {
		k.Recorder.Eventf(object, eventType, reason, format, args...)
	}
}
