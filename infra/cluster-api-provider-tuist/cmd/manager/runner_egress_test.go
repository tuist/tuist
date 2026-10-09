package main

import "testing"

func TestParseRunnerEgressGateways(t *testing.T) {
	gateways, err := parseRunnerEgressGateways(`[{"name":"dedicated-1","index":1,"endpoint":"203.0.113.10:51821","publicKey":"HIgo9xNzJMWLKASShiTqIybxZ0U3wGLiUeJ1PKf8ykw="}]`)
	if err != nil {
		t.Fatal(err)
	}
	if len(gateways) != 1 || gateways[0].Name != "dedicated-1" || gateways[0].Index != 1 {
		t.Fatalf("gateways = %+v", gateways)
	}
	if gateways, err := parseRunnerEgressGateways("  "); err != nil || gateways != nil {
		t.Fatalf("empty = %+v, %v", gateways, err)
	}
	for name, raw := range map[string]string{
		"not json":      `dedicated-1`,
		"unknown field": `[{"name":"dedicated-1","index":1,"endpoint":"203.0.113.10:51821","publicKey":"HIgo9xNzJMWLKASShiTqIybxZ0U3wGLiUeJ1PKf8ykw=","egressIP":"x"}]`,
		"invalid":       `[{"name":"dedicated-1","index":1,"endpoint":"gw:51821","publicKey":"HIgo9xNzJMWLKASShiTqIybxZ0U3wGLiUeJ1PKf8ykw="}]`,
	} {
		if _, err := parseRunnerEgressGateways(raw); err == nil {
			t.Fatalf("%s accepted", name)
		}
	}
}
