package shared

import (
	"testing"

	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
)

func TestDecideEgress(t *testing.T) {
	in := func(configured, budget int32, source string, reported, override int32, disabled bool) EgressInputs {
		return EgressInputs{ConfiguredMbps: configured, BudgetMbps: budget, Source: source,
			ReportedMbps: reported, OverrideMbps: override, Disabled: disabled}
	}
	want := func(node, budget int32, source string) EgressDecision {
		return EgressDecision{NodeMbps: node, BudgetMbps: budget, Source: source}
	}
	cases := []struct {
		name string
		in   EgressInputs
		want EgressDecision
	}{
		{"first reconcile seeds from the configured budget", in(3000, 0, "", 0, 0, false), want(3000, 3000, EgressSourceConfigured)},
		{"a reading above the budget raises it", in(3000, 3000, EgressSourceConfigured, 5000, 0, false), want(5000, 5000, EgressSourceDiscovery)},
		{"steady state", in(3000, 5000, EgressSourceDiscovery, 5000, 0, false), want(5000, 5000, EgressSourceDiscovery)},
		{"a lower reading never lowers", in(3000, 5000, EgressSourceDiscovery, 4000, 0, false), want(5000, 5000, EgressSourceDiscovery)},
		{"a garbage reading of 1 is refused", in(3000, 3000, EgressSourceConfigured, 1, 0, false), want(3000, 3000, EgressSourceConfigured)},
		{"no usable reading changes nothing", in(3000, 5000, EgressSourceDiscovery, 0, 0, false), want(5000, 5000, EgressSourceDiscovery)},
		{"a raised configured budget raises the node", in(6000, 5000, EgressSourceDiscovery, 5000, 0, false), want(6000, 6000, EgressSourceConfigured)},
		{"a lowered configured budget alone changes nothing", in(1000, 5000, EgressSourceDiscovery, 5000, 0, false), want(5000, 5000, EgressSourceDiscovery)},
		{"disabled freezes the budget rather than lowering it", in(3000, 5000, EgressSourceDiscovery, 1000, 0, true), want(5000, 5000, EgressSourceDiscovery)},
		{"disabled ignores a higher reading", in(3000, 3000, EgressSourceConfigured, 5000, 0, true), want(3000, 3000, EgressSourceConfigured)},
		{"a pin sets the node in either direction", in(3000, 5000, EgressSourceDiscovery, 5000, 1000, false), want(1000, 1000, EgressSourceManual)},
		{"a pin wins over disabled", in(3000, 5000, EgressSourceDiscovery, 0, 2000, true), want(2000, 2000, EgressSourceManual)},
		{"unpin re-derives: spec 3000, OVH 4000, was pinned to 8000", in(3000, 8000, EgressSourceManual, 4000, 0, false), want(4000, 4000, EgressSourceDiscovery)},
		{"unpin with OVH corrected but spec still higher lands on spec", in(3000, 1000, EgressSourceManual, 1000, 0, false), want(3000, 3000, EgressSourceConfigured)},
		{"unpin with spec corrected too lands on the reading", in(1000, 1000, EgressSourceManual, 1000, 0, false), want(1000, 1000, EgressSourceConfigured)},
		{"unpin with no usable reading lands on spec", in(3000, 1000, EgressSourceManual, 0, 0, false), want(3000, 3000, EgressSourceConfigured)},
		{"unpin while disabled lands on spec", in(3000, 8000, EgressSourceManual, 4000, 0, true), want(3000, 3000, EgressSourceConfigured)},
		{"no configured budget: ungoverned, pin ignored", in(0, 5000, EgressSourceDiscovery, 5000, 1000, false), want(0, 0, "")},
	}
	for _, tc := range cases {
		if got := DecideEgress(tc.in); got != tc.want {
			t.Errorf("%s: got %+v, want %+v", tc.name, got, tc.want)
		}
	}
}

func TestEgressOverrideMbps(t *testing.T) {
	cases := []struct {
		annotation string
		set        bool
		want       int32
	}{
		{"", false, 0},
		{"1000", true, 1000},
		{" 2500 ", true, 2500},
		{"0", true, 0},
		{"-5", true, 0},
		{"1Gbps", true, 0},
		{"", true, 0},
		{"99999999999", true, 0},
	}
	for _, tc := range cases {
		obj := &metav1.ObjectMeta{}
		if tc.set {
			obj.Annotations = map[string]string{EgressOverrideAnnotation: tc.annotation}
		}
		if got := EgressOverrideMbps(obj); got != tc.want {
			t.Errorf("EgressOverrideMbps(%q set=%v) = %d, want %d", tc.annotation, tc.set, got, tc.want)
		}
	}
}

func TestEgressDiscoveryDisabledIsPresenceOnly(t *testing.T) {
	for _, value := range []string{"", "true", "false", "no"} {
		obj := &metav1.ObjectMeta{Annotations: map[string]string{DisableEgressDiscoveryAnnotation: value}}
		if !EgressDiscoveryDisabled(obj) {
			t.Errorf("annotation with value %q should disable", value)
		}
	}
	if EgressDiscoveryDisabled(&metav1.ObjectMeta{}) {
		t.Error("no annotation should not disable")
	}
}
