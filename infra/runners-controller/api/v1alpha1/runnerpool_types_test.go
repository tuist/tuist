package v1alpha1

import (
	"encoding/json"
	"strings"
	"testing"
)

// The controller serializes the whole typed RunnerPool when it adds the
// drain finalizer (runnerpool_controller.go). Any field dropped by
// `omitempty` is indistinguishable from "unset" on that write, so the
// apiserver's structural-schema defaulting fills the CRD default back in
// and a deliberately-configured zero silently becomes the default for the
// pool's lifetime.
//
// This regression-guards the two autoscaling fields whose CRD default is
// non-zero while `minimum: 0` makes zero a valid setting. It caught a live
// production bug: three macOS pools configured `minWarmPoolFloor: 0` ran at
// the CRD default of 1, each reserving a Mac mini nobody asked for on a
// 9-host fleet.
func TestAutoscalingZeroValuesReachTheWire(t *testing.T) {
	payload, err := json.Marshal(RunnerPoolAutoscaling{Enabled: true})
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
			t.Errorf("zero value dropped from the serialized spec: want %s in %s\n"+
				"the apiserver will re-default this field to %s; drop `omitempty` from its json tag",
				field.json, got, field.crdDefault)
		}
	}
}

// Guards the inverse: fields whose CRD default equals their Go zero value
// are safe to omit, and keeping `omitempty` on them preserves the
// pre-autoscaling wire shape the RunnerPoolSpec doc comment describes.
func TestAutoscalingDefaultZeroFieldsStayOmitted(t *testing.T) {
	payload, err := json.Marshal(RunnerPoolAutoscaling{MinWarmPoolFloor: 1})
	if err != nil {
		t.Fatalf("marshal autoscaling: %v", err)
	}
	got := string(payload)

	for _, field := range []string{`"enabled"`, `"maxReplicas"`} {
		if strings.Contains(got, field) {
			t.Errorf("expected %s to be omitted at its zero value, got %s", field, got)
		}
	}
}
