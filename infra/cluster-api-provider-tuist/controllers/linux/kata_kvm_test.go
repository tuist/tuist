package linux

import (
	"context"
	"os/exec"
	"strings"
	"testing"

	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/cluster-api/util/conditions"
)

func kvmReadyHarness(t *testing.T) *kataHarness {
	t.Helper()
	h := newKataHarness(t, true, map[string]string{KataRuntimeSelectorLabel: "true"})
	h.node.Annotations[kataHostConfigAnnotation] = kataHostConfigRevision(h.node)
	if err := h.client.Update(context.Background(), h.node); err != nil {
		t.Fatal(err)
	}
	return h
}

func (h *kataHarness) reconcileKVM(t *testing.T) (bool, error) {
	t.Helper()
	return reconcileLinuxKataKVM(context.Background(), h.client, h.r.CredentialsManager,
		h.machine, h.machine.Name, h.machine.Spec.FleetName, h.r.hostOptions(h.machine), h.liveNode())
}

func TestKataKVMKernelMatchesKataVersion(t *testing.T) {
	if !strings.HasPrefix(kataKVMKernelRelease, kataVersion+"-") {
		t.Fatalf("kata-kvm-kernel@%s is built for another Kata release than kataVersion %s; rebuild it from that release's packaging", kataKVMKernelRelease, kataVersion)
	}
}

func TestKataKVMRepairScript(t *testing.T) {
	for _, user := range []string{"root", "ubuntu"} {
		script := renderKataKVMRepairScript(linuxCloudInitOptions{BootstrapUser: user})
		cmd := exec.Command("/bin/bash", "-n")
		cmd.Stdin = strings.NewReader(script)
		if out, err := cmd.CombinedOutput(); err != nil {
			t.Fatalf("invalid repair script: %v: %s", err, out)
		}
		for _, want := range []string{
			"sha256sum -c " + kataKVMKernelName() + ".sha256",
			"releases/download/kata-kvm-kernel@" + kataKVMKernelRelease + "/" + kataKVMKernelName(),
			"ln -sfn \"$kernel\" " + kataKVMKernelLink,
			`"kernel_verity_params", "kernel"]`,
			"/sys/module/kvm_amd/parameters/nested",
			"/sys/module/kvm_intel/parameters/nested",
			kataKVMUnavailableMarker,
		} {
			if !strings.Contains(script, want) {
				t.Errorf("repair script for %s lacks %q", user, want)
			}
		}
		// The host's /dev/kvm keeps its distribution mode; the CDI spec sets
		// the container's. Nor may installing a kernel disturb running VMs.
		for _, banned := range []string{"chmod", "udev", "restart containerd", "restart kubelet", "reboot"} {
			if strings.Contains(script, banned) {
				t.Errorf("repair script for %s contains %q", user, banned)
			}
		}
	}
}

func TestKataKVMWaitsForTheVerifiedRuntime(t *testing.T) {
	h := newKataHarness(t, true, map[string]string{KataRuntimeSelectorLabel: "true"})
	requeue, err := h.reconcileKVM(t)
	if err != nil || requeue {
		t.Fatalf("reconcile = (%v, %v), want a no-op until the Kata host configuration is verified", requeue, err)
	}
	if conditions.Get(h.machine, KataKVMReadyCondition) != nil {
		t.Fatal("KataKVMReady set before the runtime it installs into was verified")
	}
}

func TestKataKVMCurrentProofNeedsNoRepair(t *testing.T) {
	h := kvmReadyHarness(t)
	if err := setKataKVMNodeState(context.Background(), h.client, h.liveNode(), kataKVMRevision(h.liveNode()), true); err != nil {
		t.Fatal(err)
	}
	requeue, err := h.reconcileKVM(t)
	if err != nil || requeue {
		t.Fatalf("reconcile = (%v, %v), want no SSH for a current proof", requeue, err)
	}
	if !conditions.IsTrue(h.machine, KataKVMReadyCondition) {
		t.Fatal("KataKVMReady not true for a current proof")
	}
}

func TestKataKVMUnavailableHostIsNotRetried(t *testing.T) {
	h := kvmReadyHarness(t)
	if err := setKataKVMNodeState(context.Background(), h.client, h.liveNode(), kataKVMRevision(h.liveNode())+":unavailable", false); err != nil {
		t.Fatal(err)
	}
	requeue, err := h.reconcileKVM(t)
	if err != nil || requeue {
		t.Fatalf("reconcile = (%v, %v), want a host without nesting left alone until it reboots", requeue, err)
	}
	if h.liveNode().Labels[kataKVMNodeLabel] != "" {
		t.Fatal("host without nesting carries the KVM label")
	}
}

// A reboot can bring a host back without nesting, so the label must not
// outlive the boot it was proven on.
func TestKataKVMLabelIsWithdrawnWhenTheProofLapses(t *testing.T) {
	h := kvmReadyHarness(t)
	if err := setKataKVMNodeState(context.Background(), h.client, h.liveNode(), "previous-boot", true); err != nil {
		t.Fatal(err)
	}
	if _, err := h.reconcileKVM(t); err != nil {
		t.Fatal(err)
	}
	node := h.liveNode()
	if node.Labels[kataKVMNodeLabel] != "" {
		t.Fatal("KVM label kept on a host whose proof is from another boot")
	}
	if node.Labels[KataRuntimeSelectorLabel] != "true" {
		t.Fatal("withdrawing KVM touched the Kata runtime label")
	}
}

func TestKataKVMRepairFailureNeverLabels(t *testing.T) {
	h := kvmReadyHarness(t)
	h.node = h.liveNode()
	h.node.Status.Addresses = []corev1.NodeAddress{{Type: corev1.NodeInternalIP, Address: "127.0.0.1"}}
	if err := h.client.Status().Update(context.Background(), h.node); err != nil {
		t.Fatal(err)
	}
	if _, err := h.reconcileKVM(t); err == nil {
		t.Fatal("expected repair to fail against an unreachable host")
	}
	if h.liveNode().Labels[kataKVMNodeLabel] != "" {
		t.Fatal("failed repair labelled the node")
	}
	cond := conditions.Get(h.machine, KataKVMReadyCondition)
	if cond == nil || cond.Status != corev1.ConditionFalse || cond.Reason != KataKVMRepairFailedReason {
		t.Fatalf("failed repair must be visible: %v", cond)
	}
	if conditions.Get(h.machine, KataRuntimeReadyCondition) != nil && !conditions.IsTrue(h.machine, KataRuntimeReadyCondition) {
		t.Fatal("a KVM failure must not mark the Kata runtime unready")
	}
}

func TestKataKVMLabelRemovedWhenKataIsOff(t *testing.T) {
	h := newKataHarness(t, false, map[string]string{kataKVMNodeLabel: "true"})
	if _, err := h.reconcileKVM(t); err != nil {
		t.Fatal(err)
	}
	if h.liveNode().Labels[kataKVMNodeLabel] != "" {
		t.Fatal("KVM label kept on a machine that no longer runs Kata")
	}
}
