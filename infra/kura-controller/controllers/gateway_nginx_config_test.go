package controllers

import (
	"encoding/json"
	"os"
	"strings"
	"testing"

	"sigs.k8s.io/yaml"
)

// chartValuesPath is the platform Helm chart that renders the regional Kura
// gateway ingress-nginx ConfigMaps, relative to this package.
const chartValuesPath = "../../helm/platform/values.yaml"

// expectedGatewayRegions is the number of kura-*-ingress-nginx blocks the chart
// is expected to define (kura-eu-central / kura-ca-east / kura-us-east /
// kura-us-west). It is asserted so that accidentally removing or renaming a
// regional gateway block — which would otherwise silently shrink the drift
// check's coverage — fails the test. Update this when a regional gateway is
// intentionally added or removed.
const expectedGatewayRegions = 4

// requiredGatewayConfigKeys are the nginx settings every regional Kura gateway
// must carry and keep equal to the dedicated-gateway ConfigMap
// (gatewayNginxConfigData): the client-IP / proxy-protocol base plus the HTTP/2
// upload-window keys. A region missing any of these — or setting a different
// value — fails the test, because such a gateway mishandles client IPs or
// throttles large gRPC uploads. Keys gatewayNginxConfigData also produces but
// that are NOT listed here are optional for the regional path (a region need
// not set them), yet still must match wherever a region does set one, so no
// value can silently diverge between the two render paths.
var requiredGatewayConfigKeys = []string{
	"use-forwarded-headers",
	"use-proxy-protocol",
	"compute-full-forwarded-for",
	"upstream-keepalive-timeout",
	"client-body-buffer-size",
	"http2-max-concurrent-streams",
	"http-snippet",
}

// TestGatewayNginxConfigMatchesChart guards the two gateway render paths against
// drift: the dedicated gateway (gatewayNginxConfigData here) and the regional
// gateways (the kura-*-ingress-nginx blocks in infra/helm/platform/values.yaml).
// For every regional block it asserts the required keys are present with the
// controller's value, and that any other controller key matches wherever the
// region also sets it. It checks every regional block (not a single sampled
// region), so a future de-anchoring that diverges one region is caught. A block
// that exists but carries no controller.config is treated as a failure rather
// than skipped (a de-anchored region emptied of its config would otherwise pass
// unchecked), and the block count is asserted against expectedGatewayRegions so
// removing or renaming a region cannot silently shrink coverage.
func TestGatewayNginxConfigMatchesChart(t *testing.T) {
	raw, err := os.ReadFile(chartValuesPath)
	if err != nil {
		t.Fatalf("read chart values %s: %v", chartValuesPath, err)
	}

	// values.yaml is heterogeneous at the top level, so decode each entry as
	// raw JSON and only parse the gateway blocks. sigs.k8s.io/yaml resolves the
	// YAML anchor/aliases first, so every region carries its effective config
	// whether or not it still shares the anchored node.
	var top map[string]json.RawMessage
	if err := yaml.Unmarshal(raw, &top); err != nil {
		t.Fatalf("parse chart values: %v", err)
	}

	controller := gatewayNginxConfigData()

	// Guard the required list against drifting from the controller itself: a
	// required key the controller no longer produces is a test-maintenance bug.
	required := make(map[string]bool, len(requiredGatewayConfigKeys))
	for _, key := range requiredGatewayConfigKeys {
		if _, ok := controller[key]; !ok {
			t.Errorf("required key %q is not produced by gatewayNginxConfigData(); update the test", key)
		}
		required[key] = true
	}

	matched := 0
	for name, rawBlock := range top {
		if !strings.HasPrefix(name, "kura-") || !strings.HasSuffix(name, "-ingress-nginx") {
			continue
		}
		matched++

		var block struct {
			Controller struct {
				Config map[string]string `json:"config"`
			} `json:"controller"`
		}
		if err := json.Unmarshal(rawBlock, &block); err != nil {
			t.Errorf("%s: parse controller.config: %v", name, err)
			continue
		}

		chart := block.Controller.Config
		if len(chart) == 0 {
			t.Errorf("%s: controller.config is empty or absent; a regional gateway must carry the shared nginx config", name)
			continue
		}

		for key, want := range controller {
			got, present := chart[key]
			switch {
			case required[key] && !present:
				t.Errorf("%s: missing required gateway config key %q (controller=%q)", name, key, want)
			case present && got != want:
				t.Errorf("%s: gateway config key %q drifted: controller=%q chart=%q — update both render paths together", name, key, want, got)
			}
		}
	}

	if matched != expectedGatewayRegions {
		t.Fatalf("expected %d kura-*-ingress-nginx blocks, found %d; update expectedGatewayRegions if a regional gateway was intentionally added or removed", expectedGatewayRegions, matched)
	}
}
