package macos

import (
	"testing"

	"github.com/prometheus/client_golang/prometheus/testutil"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

func TestRecordMachinePhaseKeepsOneSeriesPerMachine(t *testing.T) {
	machinePhaseGauge.Reset()
	defer machinePhaseGauge.Reset()

	m := &infrav1.ScalewayAppleSiliconMachine{
		ObjectMeta: metav1.ObjectMeta{Name: "runner-1"},
		Spec:       infrav1.ScalewayAppleSiliconMachineSpec{FleetName: "tuist-tuist-runners-fleet"},
	}
	reason := "TartKubeletUpdateExceededRetries"
	m.Status.Phase = "Failed"
	m.Status.FailureReason = &reason
	recordMachinePhase(m)

	if got := testutil.CollectAndCount(machinePhaseGauge); got != 1 {
		t.Fatalf("series after first record = %d, want 1", got)
	}

	// Recovery: the machine transitions out of Failed. The stale Failed
	// series must be cleared so the alert stops firing.
	m.Status.Phase = "Ready"
	m.Status.FailureReason = nil
	recordMachinePhase(m)

	if got := testutil.CollectAndCount(machinePhaseGauge); got != 1 {
		t.Fatalf("series after transition = %d, want 1 (stale Failed series not cleared)", got)
	}
	if v := testutil.ToFloat64(machinePhaseGauge.WithLabelValues("runner-1", "tuist-tuist-runners-fleet", "Ready", "")); v != 1 {
		t.Fatalf("Ready gauge = %v, want 1", v)
	}

	forgetMachinePhase("runner-1")
	if got := testutil.CollectAndCount(machinePhaseGauge); got != 0 {
		t.Fatalf("series after forget = %d, want 0", got)
	}
}

func TestRecordMachinePhaseDefaultsEmptyPhaseToPending(t *testing.T) {
	machinePhaseGauge.Reset()
	defer machinePhaseGauge.Reset()

	m := &infrav1.ScalewayAppleSiliconMachine{
		ObjectMeta: metav1.ObjectMeta{Name: "runner-2"},
	}
	recordMachinePhase(m)

	if v := testutil.ToFloat64(machinePhaseGauge.WithLabelValues("runner-2", "", "Pending", "")); v != 1 {
		t.Fatalf("empty phase should record as Pending=1, got %v", v)
	}
}
