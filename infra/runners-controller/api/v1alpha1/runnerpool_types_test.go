package v1alpha1

import (
	"encoding/json"
	"strings"
	"testing"

	"k8s.io/utils/ptr"
)

// An explicit 0 on the two pointer fields must reach the wire. A zero
// dropped from the serialized spec is indistinguishable from "unset", so
// the apiserver replaces it with the CRD default — and the controller
// serializes the whole spec every time it adds the drain finalizer.
func TestAutoscalingExplicitZeroReachesTheWire(t *testing.T) {
	payload, err := json.Marshal(RunnerPoolAutoscaling{
		Enabled:                  true,
		MinWarmPoolFloor:         ptr.To[int32](0),
		ScaleDownCooldownSeconds: ptr.To[int32](0),
	})
	if err != nil {
		t.Fatalf("marshal autoscaling: %v", err)
	}
	got := string(payload)

	for _, field := range []struct {
		json       string
		crdDefault string
	}{
		{`"minWarmPoolFloor":0`, "1"},
		{`"scaleDownCooldownSeconds":0`, "300"},
	} {
		if !strings.Contains(got, field.json) {
			t.Errorf("explicit zero dropped from the serialized spec: want %s in %s\n"+
				"the apiserver will re-default this field to %s", field.json, got, field.crdDefault)
		}
	}
}

// An unset (nil) pointer field must be omitted, so a typed client that
// never set it sends nothing and the apiserver's CRD default applies —
// the distinction `*int32` exists to preserve.
func TestAutoscalingUnsetFieldsAreOmitted(t *testing.T) {
	payload, err := json.Marshal(RunnerPoolAutoscaling{Enabled: true, MaxReplicas: 9})
	if err != nil {
		t.Fatalf("marshal autoscaling: %v", err)
	}
	got := string(payload)

	for _, field := range []string{
		`"minWarmPoolFloor"`,
		`"scaleDownCooldownSeconds"`,
		`"maxReplicas":9`, // sanity: a set value is present
	} {
		want := field == `"maxReplicas":9`
		if strings.Contains(got, field) != want {
			t.Errorf("field %s present=%v, want present=%v in %s", field, !want, want, got)
		}
	}
}

// The decode side of the round-trip: helm renders `minWarmPoolFloor: 0`,
// and it must land as a non-nil pointer to 0 (a deliberate floor), while
// an absent field lands as nil (apiserver default applies). This is the
// exact case the pointer switch fixes.
func TestAutoscalingDecodePreservesZeroVsUnset(t *testing.T) {
	var withZero RunnerPoolAutoscaling
	if err := json.Unmarshal([]byte(`{"minWarmPoolFloor":0}`), &withZero); err != nil {
		t.Fatalf("unmarshal explicit zero: %v", err)
	}
	if withZero.MinWarmPoolFloor == nil || *withZero.MinWarmPoolFloor != 0 {
		t.Errorf("explicit zero decoded to %v, want non-nil 0", withZero.MinWarmPoolFloor)
	}

	var absent RunnerPoolAutoscaling
	if err := json.Unmarshal([]byte(`{"maxReplicas":9}`), &absent); err != nil {
		t.Fatalf("unmarshal absent: %v", err)
	}
	if absent.MinWarmPoolFloor != nil {
		t.Errorf("absent minWarmPoolFloor decoded to %v, want nil", absent.MinWarmPoolFloor)
	}
}

// The accessors return the CRD default for an unset field and the
// configured value otherwise, including a deliberate 0. They are how the
// controller reads these fields, so a nil never reaches the allocator as
// a raw 0.
func TestAutoscalingOrDefaultAccessors(t *testing.T) {
	unset := &RunnerPoolAutoscaling{}
	if got := unset.MinWarmPoolFloorOrDefault(); got != 1 {
		t.Errorf("unset MinWarmPoolFloor = %d, want CRD default 1", got)
	}
	if got := unset.ScaleDownCooldownSecondsOrDefault(); got != 300 {
		t.Errorf("unset ScaleDownCooldownSeconds = %d, want CRD default 300", got)
	}

	zero := &RunnerPoolAutoscaling{
		MinWarmPoolFloor:         ptr.To[int32](0),
		ScaleDownCooldownSeconds: ptr.To[int32](0),
	}
	if got := zero.MinWarmPoolFloorOrDefault(); got != 0 {
		t.Errorf("explicit-zero MinWarmPoolFloor = %d, want 0", got)
	}
	if got := zero.ScaleDownCooldownSecondsOrDefault(); got != 0 {
		t.Errorf("explicit-zero ScaleDownCooldownSeconds = %d, want 0", got)
	}

	set := &RunnerPoolAutoscaling{MinWarmPoolFloor: ptr.To[int32](3)}
	if got := set.MinWarmPoolFloorOrDefault(); got != 3 {
		t.Errorf("set MinWarmPoolFloor = %d, want 3", got)
	}

	// A nil receiver (autoscaling block absent) must not panic.
	var nilAuto *RunnerPoolAutoscaling
	if got := nilAuto.MinWarmPoolFloorOrDefault(); got != 1 {
		t.Errorf("nil-receiver MinWarmPoolFloor = %d, want CRD default 1", got)
	}
}

func TestProvisioningOrDefaultAccessors(t *testing.T) {
	unset := &RunnerPoolProvisioning{}
	if got := unset.MaxConcurrentPerFleetSelectorOrDefault(); got != 4 {
		t.Errorf("unset MaxConcurrentPerFleetSelector = %d, want 4", got)
	}
	if got := unset.StartTimeoutSecondsOrDefault(); got != 300 {
		t.Errorf("unset StartTimeoutSeconds = %d, want 300", got)
	}

	configured := &RunnerPoolProvisioning{
		MaxConcurrentPerFleetSelector: ptr.To[int32](2),
		StartTimeoutSeconds:           ptr.To[int32](0),
	}
	if got := configured.MaxConcurrentPerFleetSelectorOrDefault(); got != 2 {
		t.Errorf("configured MaxConcurrentPerFleetSelector = %d, want 2", got)
	}
	if got := configured.StartTimeoutSecondsOrDefault(); got != 0 {
		t.Errorf("explicit-zero StartTimeoutSeconds = %d, want 0", got)
	}

	var nilProvisioning *RunnerPoolProvisioning
	if got := nilProvisioning.MaxConcurrentPerFleetSelectorOrDefault(); got != 4 {
		t.Errorf("nil MaxConcurrentPerFleetSelector = %d, want 4", got)
	}
}

func TestProvisioningExplicitZeroStartTimeoutReachesTheWire(t *testing.T) {
	payload, err := json.Marshal(RunnerPoolProvisioning{
		StartTimeoutSeconds: ptr.To[int32](0),
	})
	if err != nil {
		t.Fatalf("marshal provisioning: %v", err)
	}
	if got := string(payload); !strings.Contains(got, `"startTimeoutSeconds":0`) {
		t.Fatalf("explicit zero start timeout dropped from serialized provisioning: %s", got)
	}
}
