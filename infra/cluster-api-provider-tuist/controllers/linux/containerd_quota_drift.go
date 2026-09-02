package linux

import (
	"context"
	"fmt"
	"strings"

	corev1 "k8s.io/api/core/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/cluster-api/util/patch"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	"github.com/tuist/tuist/infra/cluster-api-provider-tuist/internal/credentials"
	bootstrap "github.com/tuist/tuist/infra/macos-host-bootstrap"
)

// containerdQuotaLiftedAnnotation records, on the Node, that the image-store
// project quota has been lifted from a box that never needed it. The quota is
// XFS on-disk metadata with no Kubernetes-visible observable, so like the
// kubelet-config hash this is stamped by the controller only once the lift has
// exited 0, and the check keys convergence on it.
const containerdQuotaLiftedAnnotation = "tuist.dev/containerd-quota-lifted"

// ContainerdQuotaLiftedCondition reports whether a box with no cache volumes
// still carries the image-store ceiling its self-join applied.
//
// The self-join is rendered once and the fleet MachineDeployments use
// strategy: OnDelete, so gating the quota on the cache taint at bootstrap
// reaches zero live machines. A runner box that already has the quota keeps
// failing every job once its containers' writable layers fill the 64 GiB
// project, on a disk that is otherwise empty, until something lifts it.
const ContainerdQuotaLiftedCondition clusterv1.ConditionType = "ContainerdQuotaLifted"

const (
	// ContainerdQuotaPresentReason is set before any lift is attempted, so a
	// box the operator cannot reach is visibly still capped rather than
	// silently retried.
	ContainerdQuotaPresentReason = "ContainerdQuotaPresent"

	// ContainerdQuotaLiftFailedReason is set when the in-place lift could not
	// complete: the box is unreachable, or xfs_quota refused.
	ContainerdQuotaLiftFailedReason = "ContainerdQuotaLiftFailed"
)

// renderContainerdQuotaLiftScript renders the idempotent script the repair
// pipes over SSH to a Ready non-cache box.
//
// Strictly additive: it changes one quota limit and one line of /etc/projects.
// No apt, no containerd restart, no kubelet, no /data remount, so it needs no
// drain and disturbs no running job. Lifting a project limit takes effect in
// the kernel immediately; writes that were failing with ENOSPC succeed on the
// next attempt without any process restarting.
//
// The guards match containerdQuotaScript exactly. Where any of them fail the
// self-join applied no quota, so there is nothing to lift and the script exits
// 0, which lets the controller stamp the Node and stop dialling.
func renderContainerdQuotaLiftScript(opts linuxCloudInitOptions) string {
	sudo, _ := escalation(opts.BootstrapUser)
	return fmt.Sprintf(`#!/usr/bin/env bash
set -euxo pipefail
data=/data
dir=/data/containerd
projid=%[2]d

mountpoint -q "$data" || exit 0
[ "$(findmnt -no SOURCE "$data")" != "$(findmnt -no SOURCE /)" ] || exit 0
[ "$(findmnt -no FSTYPE "$data")" = xfs ] || exit 0
case ",$(findmnt -no OPTIONS "$data")," in
  *,prjquota,*|*,pquota,*) ;;
  *) exit 0 ;;
esac

exec 9>/var/lock/tuist-kura-quota.lock
%[1]sflock 9

# bhard=0 is how xfs_quota removes a limit; the project keeps accounting, which
# is harmless and leaves usage readable if anyone asks.
%[1]sxfs_quota -x -c "limit -p bhard=0 $projid" "$data"
# Drop the /etc/projects entry so the usage exporter, should it ever run here,
# does not report a ceiling this box no longer has.
if [ -f /etc/projects ]; then
  %[1]sgrep -v ":$dir$" /etc/projects > /tmp/projects.tuist || true
  %[1]scat /tmp/projects.tuist > /etc/projects
  %[1]srm -f /tmp/projects.tuist
fi
`, sudo, containerdProjectID)
}

// stampContainerdQuotaLifted records the lift on the Node so the check is a
// map lookup from then on.
func stampContainerdQuotaLifted(ctx context.Context, c client.Client, node *corev1.Node) error {
	helper, err := patch.NewHelper(node, c)
	if err != nil {
		return err
	}
	if node.Annotations == nil {
		node.Annotations = map[string]string{}
	}
	node.Annotations[containerdQuotaLiftedAnnotation] = "true"
	return helper.Patch(ctx, node)
}

// reconcileLinuxContainerdQuotaDrift lifts the image-store quota, in place,
// from a Ready box whose spec says no cache volumes land on it.
//
// On a cache box (kura-cache taint) this deletes any stale condition and
// returns. On a stamped node it is one map lookup. Otherwise it marks the
// machine visibly capped, dials the box, lifts the limit, and stamps the Node
// only on the script's exit status.
//
// Returns requeue=true when it did work or deferred, false when there was
// nothing to do.
func reconcileLinuxContainerdQuotaDrift(
	ctx context.Context,
	c client.Client,
	cm *credentials.Manager,
	machine conditions.Setter,
	machineName, fleet string,
	opts linuxCloudInitOptions,
	node *corev1.Node,
) (requeue bool, err error) {
	logger := log.FromContext(ctx)

	if hostsKuraCacheVolumes(opts.Taints) {
		conditions.Delete(machine, ContainerdQuotaLiftedCondition)
		return false, nil
	}
	if node.Annotations[containerdQuotaLiftedAnnotation] == "true" {
		conditions.MarkTrue(machine, ContainerdQuotaLiftedCondition)
		return false, nil
	}

	conditions.MarkFalse(machine, ContainerdQuotaLiftedCondition, ContainerdQuotaPresentReason,
		clusterv1.ConditionSeverityError,
		"box hosts no cache volumes but its image store may still carry the %d GiB project quota, which fails every job once runner writable layers fill it; lifting in place",
		containerdQuotaBytes/(1024*1024*1024))

	host := nodeInternalIP(node)
	if host == "" {
		logger.Info("deferring containerd quota lift until the node reports an InternalIP", "node", node.Name)
		return true, nil
	}

	privateKey, err := cm.EnsureFleetSSHKey(ctx, fleet)
	if err != nil {
		return false, fmt.Errorf("fleet ssh key for containerd quota lift: %w", err)
	}
	known := ""
	if creds, fpErr := cm.GetMachineBootstrap(ctx, machineName); fpErr != nil {
		return false, fmt.Errorf("read host fingerprint for containerd quota lift: %w", fpErr)
	} else if creds != nil {
		known = creds.HostFingerprint
	}
	hostKey := bootstrap.NewHostKeyState(known)

	sshErr := bootstrapOverSSH(ctx, opts.BootstrapUser, host, privateKey, renderContainerdQuotaLiftScript(opts), hostKey)
	if observed := hostKey.Observed(); observed != "" && observed != known {
		if perr := cm.SetMachineHostFingerprint(ctx, machineName, observed); perr != nil {
			logger.Error(perr, "persist host fingerprint after containerd quota lift; will retry", "node", node.Name)
		}
	}
	if sshErr != nil {
		conditions.MarkFalse(machine, ContainerdQuotaLiftedCondition, ContainerdQuotaLiftFailedReason,
			clusterv1.ConditionSeverityError,
			"could not lift the image-store quota on %s, so the box still fails jobs once the project fills: %v", host, sshErr)
		return false, fmt.Errorf("lift containerd quota over ssh on %s: %w", host, sshErr)
	}
	if stampErr := stampContainerdQuotaLifted(ctx, c, node); stampErr != nil {
		return false, fmt.Errorf("stamp containerd quota lift: %w", stampErr)
	}

	conditions.MarkTrue(machine, ContainerdQuotaLiftedCondition)
	logger.Info("lifted the image-store quota from a box that hosts no cache volumes",
		"node", node.Name, "host", host, "taints", strings.Join(taintKeys(opts.Taints), ","))
	return true, nil
}

func taintKeys(taints []corev1.Taint) []string {
	keys := make([]string, 0, len(taints))
	for _, taint := range taints {
		keys = append(keys, taint.Key)
	}
	return keys
}
