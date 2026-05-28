package nodeagent

import (
	"context"
	"errors"
	"testing"

	corev1 "k8s.io/api/core/v1"
)

func conditionByType(conds []corev1.NodeCondition, t corev1.NodeConditionType) (corev1.NodeCondition, bool) {
	for _, c := range conds {
		if c.Type == t {
			return c, true
		}
	}
	return corev1.NodeCondition{}, false
}

func TestConfigureNodeSeedsDiskPressureFalse(t *testing.T) {
	m := &Maintainer{NodeName: "mac-mini-1"}
	node := &corev1.Node{}

	m.configureNode(node)

	dp, ok := conditionByType(node.Status.Conditions, corev1.NodeDiskPressure)
	if !ok {
		t.Fatal("expected a DiskPressure condition to be seeded")
	}
	if dp.Status != corev1.ConditionFalse {
		t.Fatalf("DiskPressure = %q, want False", dp.Status)
	}
}

func TestApplyDiskPressureSetsTrueWithDetail(t *testing.T) {
	m := &Maintainer{
		DiskPressure: func(context.Context) (bool, string, error) {
			return true, "vm-x at 100%", nil
		},
	}
	node := &corev1.Node{}
	m.configureNode(node)

	m.applyDiskPressure(context.Background(), node)

	dp, _ := conditionByType(node.Status.Conditions, corev1.NodeDiskPressure)
	if dp.Status != corev1.ConditionTrue {
		t.Fatalf("DiskPressure = %q, want True", dp.Status)
	}
	if dp.Reason != "TartKubeletHasDiskPressure" {
		t.Fatalf("Reason = %q", dp.Reason)
	}
	if dp.Message != "vm-x at 100%" {
		t.Fatalf("Message = %q", dp.Message)
	}
}

func TestApplyDiskPressureSetsFalse(t *testing.T) {
	m := &Maintainer{
		DiskPressure: func(context.Context) (bool, string, error) {
			return false, "", nil
		},
	}
	node := &corev1.Node{}
	m.configureNode(node)

	m.applyDiskPressure(context.Background(), node)

	dp, _ := conditionByType(node.Status.Conditions, corev1.NodeDiskPressure)
	if dp.Status != corev1.ConditionFalse {
		t.Fatalf("DiskPressure = %q, want False", dp.Status)
	}
}

func TestApplyDiskPressureKeepsPriorValueOnProbeError(t *testing.T) {
	m := &Maintainer{
		DiskPressure: func(context.Context) (bool, string, error) {
			return false, "", errors.New("guest agent unreachable")
		},
	}
	node := &corev1.Node{}
	m.configureNode(node)
	// Simulate a prior heartbeat that observed pressure.
	setCondition(&node.Status.Conditions, corev1.NodeDiskPressure, corev1.ConditionTrue, "TartKubeletHasDiskPressure", "vm-x at 100%")

	m.applyDiskPressure(context.Background(), node)

	dp, _ := conditionByType(node.Status.Conditions, corev1.NodeDiskPressure)
	if dp.Status != corev1.ConditionTrue {
		t.Fatalf("DiskPressure = %q, want unchanged True on probe error", dp.Status)
	}
}

func TestApplyDiskPressureNilProbeIsNoop(t *testing.T) {
	m := &Maintainer{} // no probe
	node := &corev1.Node{}
	m.configureNode(node)

	m.applyDiskPressure(context.Background(), node)

	dp, ok := conditionByType(node.Status.Conditions, corev1.NodeDiskPressure)
	if !ok || dp.Status != corev1.ConditionFalse {
		t.Fatalf("expected seeded False to remain, got ok=%v status=%q", ok, dp.Status)
	}
}
