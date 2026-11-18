package nodeagent

import (
	"context"
	"errors"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/types"
)

func TestHostPressureReadings(t *testing.T) {
	for _, tt := range []struct {
		level             uint32
		pressure, invalid bool
	}{{1, false, false}, {2, true, false}, {4, true, false}, {0, false, true}, {8, false, true}} {
		got, _, err := memoryPressure(tt.level)
		if got != tt.pressure || (err != nil) != tt.invalid {
			t.Errorf("memory level %d: pressure=%v err=%v", tt.level, got, err)
		}
	}
	for _, tt := range []struct {
		count, limit      uint64
		pressure, invalid bool
	}{{100, 1000, false, false}, {899, 1000, false, false}, {900, 1000, true, false}, {1001, 1000, true, false}, {0, 1000, false, true}, {1, 0, false, true}} {
		got, _, err := pidPressure(tt.count, tt.limit)
		if got != tt.pressure || (err != nil) != tt.invalid {
			t.Errorf("process count/limit %d/%d: pressure=%v err=%v", tt.count, tt.limit, got, err)
		}
	}
}

func TestRefreshRecoversUnknownHostPressureAndFailsClosedOnProbeError(t *testing.T) {
	old := metav1.NewTime(time.Now().Add(-time.Hour))
	node := &corev1.Node{ObjectMeta: metav1.ObjectMeta{Name: "mac-1"}}
	for _, kind := range []corev1.NodeConditionType{corev1.NodeMemoryPressure, corev1.NodePIDPressure} {
		node.Status.Conditions = append(node.Status.Conditions, corev1.NodeCondition{
			Type: kind, Status: corev1.ConditionUnknown, Reason: "NodeStatusNeverUpdated",
			LastHeartbeatTime: old, LastTransitionTime: old,
		})
	}
	c := newNodeFakeClient(node)
	var pressure bool
	var probeErr error
	probe := func(context.Context) (bool, string, error) { return pressure, "live reading", probeErr }
	m := &Maintainer{Client: c, NodeName: node.Name, MemoryPressure: probe, PIDPressure: probe}
	for _, want := range []corev1.ConditionStatus{corev1.ConditionFalse, corev1.ConditionTrue, corev1.ConditionUnknown, corev1.ConditionFalse} {
		pressure, probeErr = want == corev1.ConditionTrue, nil
		if want == corev1.ConditionUnknown {
			probeErr = errors.New("sysctl unavailable")
		}
		if err := m.refresh(context.Background()); err != nil {
			t.Fatal(err)
		}
		if err := c.Get(context.Background(), types.NamespacedName{Name: node.Name}, node); err != nil {
			t.Fatal(err)
		}
		for _, kind := range []corev1.NodeConditionType{corev1.NodeMemoryPressure, corev1.NodePIDPressure} {
			condition, ok := conditionByType(node.Status.Conditions, kind)
			if !ok || condition.Status != want || !condition.LastHeartbeatTime.After(old.Time) {
				t.Fatalf("%s: got %+v, want fresh %s", kind, condition, want)
			}
		}
	}
}
