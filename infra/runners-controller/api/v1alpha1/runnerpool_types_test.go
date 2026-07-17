package v1alpha1

import (
	"encoding/json"
	"strings"
	"testing"
)

// Guards the autoscaling fields whose CRD default is non-zero while
// `minimum: 0` makes zero a valid setting. A zero dropped by `omitempty`
// is indistinguishable from "unset", so the apiserver replaces it with
// the CRD default — and the controller serializes the whole spec every
// time it adds the drain finalizer.
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

// Fields whose CRD default equals their Go zero value keep `omitempty`,
// preserving the wire shape the RunnerPoolSpec doc comment describes.
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
