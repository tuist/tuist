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

// The script runs over SSH as the install user, and a per-line sudo does not
// cover a shell redirection: the open happens as that user before sudo runs.
// The lock fd reopens a root-owned file the bootstrap created, and /etc/projects
// is root-owned, so either would fail the script before the Node is stamped and
// the repair would retry forever. Every write therefore has to sit inside one
// root shell, and nothing inside that shell may carry its own sudo, since the
// heredoc is already root.
func TestContainerdQuotaLiftWritesRunInARootShell(t *testing.T) {
	script := renderContainerdQuotaLiftScript(linuxCloudInitOptions{BootstrapUser: "ubuntu"})

	const opener = "sudo bash -s <<'TUIST_ROOT'\n"
	open := strings.Index(script, opener)
	if open < 0 {
		t.Fatalf("expected the privileged block to open a root shell, got:\n%s", script)
	}
	bodyStart := open + len(opener)
	closeIdx := strings.Index(script[bodyStart:], "\nTUIST_ROOT\n")
	if closeIdx < 0 {
		t.Fatalf("expected the root heredoc to be terminated, got:\n%s", script)
	}
	// guards is everything before the escalation; root is the heredoc body
	// alone, excluding the opener line that carries the one legitimate sudo.
	guards, root := script[:open], script[bodyStart:bodyStart+closeIdx]

	for _, write := range []string{"exec 9>", "> /etc/projects", "> /tmp/projects.tuist", "xfs_quota", "flock"} {
		if strings.Contains(guards, write) {
			t.Fatalf("%q runs outside the root shell, where the redirection opens as the install user:\n%s", write, script)
		}
		if !strings.Contains(root, write) {
			t.Fatalf("expected %q inside the root shell, got:\n%s", write, script)
		}
	}
	if strings.Contains(root, "sudo") {
		t.Fatalf("root shell must not re-escalate, got:\n%s", root)
	}
	if !strings.Contains(guards, "findmnt") {
		t.Fatalf("read-only guards should run before escalating, got:\n%s", guards)
	}
	if !strings.Contains(root, "set -euxo pipefail") {
		t.Fatalf("a failure inside the root shell must propagate to the outer exit status, got:\n%s", root)
	}
}

// Root on the box (no BootstrapUser) needs no sudo, and the block must still be
// a heredoc-fed shell so the two renderings differ only by the prefix.
func TestContainerdQuotaLiftScriptAsRoot(t *testing.T) {
	script := renderContainerdQuotaLiftScript(linuxCloudInitOptions{})
	if strings.Contains(script, "sudo") {
		t.Fatalf("expected no sudo when bootstrapping as root, got:\n%s", script)
	}
	if !strings.Contains(script, "\nbash -s <<'TUIST_ROOT'\n") {
		t.Fatalf("expected the same heredoc shape without a prefix, got:\n%s", script)
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
