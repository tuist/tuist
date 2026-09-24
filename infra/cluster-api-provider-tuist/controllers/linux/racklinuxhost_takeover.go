package linux

import (
	"context"
	"fmt"
	"sort"
	"strings"
	"time"

	corev1 "k8s.io/api/core/v1"
	apierrors "k8s.io/apimachinery/pkg/api/errors"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	clusterv1 "sigs.k8s.io/cluster-api/api/v1beta1"
	"sigs.k8s.io/cluster-api/util/conditions"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/log"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// A box is its boot MAC. Hosts sharing one are the same box under different
// names, and the one declared last is what the box becomes: it publishes the
// install, reboots the box into it through the system the box runs, and once
// it is on the tailnet deletes the names the box no longer runs.

// bootMACTwins are the other hosts of the host's namespace, not being deleted,
// that declare mac.
func (r *RackLinuxHostReconciler) bootMACTwins(ctx context.Context, host *infrav1.RackLinuxHost, mac string) ([]infrav1.RackLinuxHost, error) {
	if mac == "" {
		return nil, nil
	}
	hosts := &infrav1.RackLinuxHostList{}
	if err := r.List(ctx, hosts, client.InNamespace(host.Namespace)); err != nil {
		return nil, err
	}
	var twins []infrav1.RackLinuxHost
	for _, h := range hosts.Items {
		if h.Name != host.Name && h.DeletionTimestamp.IsZero() && strings.EqualFold(h.Spec.BootMAC, mac) {
			twins = append(twins, h)
		}
	}
	sort.Slice(twins, func(i, j int) bool { return twins[i].Name < twins[j].Name })
	return twins, nil
}

func sameBox(a, b *infrav1.RackLinuxHost) bool {
	return a.Spec.BootMAC != "" && strings.EqualFold(a.Spec.BootMAC, b.Spec.BootMAC)
}

// declaredAfter reports whether a was created after b, the later name on a
// tie.
func declaredAfter(a, b *infrav1.RackLinuxHost) bool {
	if !a.CreationTimestamp.Equal(&b.CreationTimestamp) {
		return b.CreationTimestamp.Before(&a.CreationTimestamp)
	}
	return a.Name > b.Name
}

// successor is a twin declared after the host that has an install published
// for the box or is on the tailnet: the host yields the box to it.
func successor(host *infrav1.RackLinuxHost, twins []infrav1.RackLinuxHost) *infrav1.RackLinuxHost {
	for i := range twins {
		t := &twins[i]
		if declaredAfter(t, host) && (t.Status.Install != nil || t.Status.Tailnet != nil) {
			return t
		}
	}
	return nil
}

// runningPredecessor is a twin declared before the host whose install is
// connected to the tailnet: the system the box runs now.
func runningPredecessor(host *infrav1.RackLinuxHost, twins []infrav1.RackLinuxHost) *infrav1.RackLinuxHost {
	for i := range twins {
		t := &twins[i]
		if declaredAfter(host, t) && t.Status.Tailnet != nil && t.Status.Tailnet.Connected {
			return t
		}
	}
	return nil
}

// takeOver reboots the box, which runs as running, into the host's install
// once the boot server serves it, and only once. running is nil while the box
// is off the tailnet.
func (r *RackLinuxHostReconciler) takeOver(ctx context.Context, host, running *infrav1.RackLinuxHost, now time.Time) (time.Duration, error) {
	inst := host.Status.Install
	if inst.TriggeredAt != nil {
		if running != nil && now.Sub(inst.TriggeredAt.Time) > rackReinstallBootTimeout {
			conditions.MarkFalse(host, InstalledCondition, "ReinstallDidNotBoot", clusterv1.ConditionSeverityWarning,
				"the box was rebooted at %s into its installer for %s's install and came back as %s; check its install stick or network boot entry and the boot server, then boot either by hand",
				inst.TriggeredAt.UTC().Format(time.RFC3339), host.Name, running.Name)
			return 0, nil
		}
		conditions.MarkFalse(host, InstalledCondition, "Reinstalling", clusterv1.ConditionSeverityInfo,
			"the box was rebooted into its installer for install %s", inst.KeyID)
		return 0, nil
	}
	if wait := inst.OfferedAt.Add(rackBootPropagation).Sub(now); wait > 0 {
		conditions.MarkFalse(host, InstalledCondition, "Reinstalling", clusterv1.ConditionSeverityInfo,
			"rebooting the box, which runs as %s, into install %s once the boot server serves it", running.Name, inst.KeyID)
		return wait, nil
	}
	if err := r.bootInstallerOnce(ctx, running); err != nil {
		r.Recorder.Eventf(host, corev1.EventTypeWarning, "ReinstallNotStarted",
			"Could not reboot %s's box into %s's installer: %v", running.Name, host.Name, err)
		conditions.MarkFalse(host, InstalledCondition, "ReinstallNotStarted", clusterv1.ConditionSeverityWarning, "%v", err)
		return time.Minute, nil
	}
	triggered := metav1.NewTime(now)
	inst.TriggeredAt = &triggered
	message := fmt.Sprintf("Rebooted %s's box (bootMAC %s) into its installer once, for install %s, so that it becomes %s",
		running.Name, host.Spec.BootMAC, inst.KeyID, host.Name)
	r.Recorder.Eventf(host, corev1.EventTypeNormal, "ReinstallStarted", "%s", message)
	r.Recorder.Eventf(running, corev1.EventTypeNormal, "Replacing", "%s", message)
	conditions.MarkFalse(host, InstalledCondition, "Reinstalling", clusterv1.ConditionSeverityInfo,
		"the box was rebooted into its installer for install %s", inst.KeyID)
	return 0, nil
}

// retireReplaced deletes the twins declared before the host once the host runs
// the box, on the tailnet with its install withdrawn, and they are not
// connected.
func (r *RackLinuxHostReconciler) retireReplaced(ctx context.Context, host *infrav1.RackLinuxHost, twins []infrav1.RackLinuxHost) error {
	if host.Status.Tailnet == nil || !host.Status.Tailnet.Connected || host.Status.Install != nil {
		return nil
	}
	for i := range twins {
		t := &twins[i]
		if !declaredAfter(host, t) || (t.Status.Tailnet != nil && t.Status.Tailnet.Connected) {
			continue
		}
		if err := r.Delete(ctx, t); err != nil && !apierrors.IsNotFound(err) {
			return fmt.Errorf("delete %s, whose box runs as %s now: %w", t.Name, host.Name, err)
		}
		message := fmt.Sprintf("Deleted RackLinuxHost %s: its box (bootMAC %s) joined the tailnet as %s", t.Name, host.Spec.BootMAC, host.Name)
		r.Recorder.Eventf(host, corev1.EventTypeNormal, "ReplacedHostDeleted", "%s", message)
		r.Recorder.Eventf(t, corev1.EventTypeNormal, "Replaced", "%s", message)
		log.FromContext(ctx).Info("deleted a rack host its box no longer runs", "host", t.Name, "replacement", host.Name)
	}
	return nil
}
