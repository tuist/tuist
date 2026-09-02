package linux

import (
	"context"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/cluster-api/util/conditions"
)

// The lift is additive and instantaneous: one xfs_quota call and one line of
// /etc/projects. Anything that restarts a daemon or touches the kubelet would
// disturb a live job, and nothing about removing a limit needs it.
func TestRenderContainerdQuotaLiftScript(t *testing.T) {
	script := renderContainerdQuotaLiftScript(linuxCloudInitOptions{BootstrapUser: "ubuntu"})

	for _, want := range []string{
		"limit -p bhard=0 $projid",
		"projid=100",
		`[ "$(findmnt -no FSTYPE "$data")" = xfs ] || exit 0`,
		"*,prjquota,*|*,pquota,*) ;;",
		`grep -v ":$dir$" /etc/projects`,
		"sudo xfs_quota",
	} {
		if !strings.Contains(script, want) {
			t.Fatalf("expected %q in the lift script, got:\n%s", want, script)
		}
	}
	for _, forbidden := range []string{"systemctl", "apt-get", "kubelet", "umount", "bhard=$bytes"} {
		if strings.Contains(script, forbidden) {
			t.Fatalf("lift script must not contain %q (not additive), got:\n%s", forbidden, script)
		}
	}
}

// A cache box keeps its quota: the taint is the whole reason it exists there.
// The check must not dial, so the harness leaves no InternalIP and the test
// asserts it returned before deferring on one.
func TestContainerdQuotaLeftInPlaceOnCacheBoxes(t *testing.T) {
	h := newKataHarness(t, false, nil)
	h.machine.Spec.NodeTaints = cacheFleetTaints()

	requeue, err := reconcileLinuxContainerdQuotaDrift(context.Background(), h.client, h.r.CredentialsManager,
		h.machine, h.machine.Name, h.machine.Spec.FleetName, h.r.hostOptions(h.machine), h.liveNode())
	if err != nil || requeue {
		t.Fatalf("expected a no-op on a cache box, got requeue=%v err=%v", requeue, err)
	}
	if cond := conditions.Get(h.machine, ContainerdQuotaLiftedCondition); cond != nil {
		t.Fatalf("expected no %s condition on a cache box, got %v", ContainerdQuotaLiftedCondition, cond)
	}
	if got := h.liveNode().Annotations[containerdQuotaLiftedAnnotation]; got != "" {
		t.Fatalf("cache box was stamped %q", got)
	}
}

// A runner box that the self-join already capped is visibly capped before any
// repair is attempted, so an unreachable box reads as a fault, not as pending.
func TestContainerdQuotaPresentIsSurfacedBeforeTheLift(t *testing.T) {
	h := newKataHarness(t, true, nil)
	h.machine.Spec.NodeTaints = []corev1.Taint{{Key: "tuist.dev/runner-tier", Value: "bare-metal", Effect: corev1.TaintEffectNoSchedule}}

	requeue, err := reconcileLinuxContainerdQuotaDrift(context.Background(), h.client, h.r.CredentialsManager,
		h.machine, h.machine.Name, h.machine.Spec.FleetName, h.r.hostOptions(h.machine), h.liveNode())
	if err != nil || !requeue {
		t.Fatalf("expected a deferral without an InternalIP, got requeue=%v err=%v", requeue, err)
	}
	cond := conditions.Get(h.machine, ContainerdQuotaLiftedCondition)
	if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != ContainerdQuotaPresentReason {
		t.Fatalf("expected %s=False/%s before the lift, got %v", ContainerdQuotaLiftedCondition, ContainerdQuotaPresentReason, cond)
	}
	if got := h.liveNode().Annotations[containerdQuotaLiftedAnnotation]; got != "" {
		t.Fatalf("node was stamped %q without a lift", got)
	}
}

// The Node is stamped only on the script's exit status. A failed dial must
// leave it unstamped so the next reconcile tries again, and must name the
// failure on the Machine.
func TestContainerdQuotaLiftFailureNeverStampsTheNode(t *testing.T) {
	h := newKataHarness(t, true, nil)
	h.machine.Spec.NodeTaints = []corev1.Taint{{Key: "tuist.dev/runner-tier", Value: "bare-metal", Effect: corev1.TaintEffectNoSchedule}}
	h.node.Status.Addresses = []corev1.NodeAddress{{Type: corev1.NodeInternalIP, Address: "127.0.0.1"}}
	if err := h.client.Status().Update(context.Background(), h.node); err != nil {
		t.Fatal(err)
	}

	requeue, err := reconcileLinuxContainerdQuotaDrift(context.Background(), h.client, h.r.CredentialsManager,
		h.machine, h.machine.Name, h.machine.Spec.FleetName, h.r.hostOptions(h.machine), h.liveNode())
	if err == nil {
		t.Fatalf("expected the lift to fail against an unreachable host, got requeue=%v", requeue)
	}
	if got := h.liveNode().Annotations[containerdQuotaLiftedAnnotation]; got != "" {
		t.Fatalf("node was stamped %q despite a failed lift", got)
	}
	cond := conditions.Get(h.machine, ContainerdQuotaLiftedCondition)
	if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != ContainerdQuotaLiftFailedReason {
		t.Fatalf("expected %s=False/%s after a failed lift, got %v", ContainerdQuotaLiftedCondition, ContainerdQuotaLiftFailedReason, cond)
	}
}

// Once stamped the check is a map lookup and never dials again, even with an
// address that would otherwise be tried.
func TestContainerdQuotaLiftNoOpWhenStamped(t *testing.T) {
	h := newKataHarness(t, true, nil)
	h.machine.Spec.NodeTaints = []corev1.Taint{{Key: "tuist.dev/runner-tier", Value: "bare-metal", Effect: corev1.TaintEffectNoSchedule}}
	h.node.Status.Addresses = []corev1.NodeAddress{{Type: corev1.NodeInternalIP, Address: "127.0.0.1"}}
	if err := h.client.Status().Update(context.Background(), h.node); err != nil {
		t.Fatal(err)
	}
	if err := stampContainerdQuotaLifted(context.Background(), h.client, h.liveNode()); err != nil {
		t.Fatal(err)
	}

	requeue, err := reconcileLinuxContainerdQuotaDrift(context.Background(), h.client, h.r.CredentialsManager,
		h.machine, h.machine.Name, h.machine.Spec.FleetName, h.r.hostOptions(h.machine), h.liveNode())
	if err != nil || requeue {
		t.Fatalf("expected a no-op on a stamped node, got requeue=%v err=%v", requeue, err)
	}
	cond := conditions.Get(h.machine, ContainerdQuotaLiftedCondition)
	if cond == nil || cond.Status != corev1.ConditionTrue {
		t.Fatalf("expected %s=True on a stamped node, got %v", ContainerdQuotaLiftedCondition, cond)
	}
}
