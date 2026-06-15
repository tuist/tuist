package controllers

import (
	"os"
	"testing"

	"sigs.k8s.io/yaml"
)

// chartValuesPath is the platform Helm chart that renders the regional Kura
// gateway ingress-nginx ConfigMaps, relative to this package.
const chartValuesPath = "../../helm/platform/values.yaml"

// windowKeys are the HTTP/2 upload-window settings that must be identical
// between the dedicated-gateway ConfigMap (this controller) and the regional
// gateway config (the platform chart). If they diverge, large gRPC uploads
// regress on one path but not the other.
var windowKeys = []string{
	"client-body-buffer-size",
	"http2-max-concurrent-streams",
	"http-snippet",
}

// TestGatewayNginxConfigMatchesChart guards against the two gateway render
// paths drifting: the dedicated gateway (gatewayNginxConfigData here) and the
// regional gateways (infra/helm/platform/values.yaml) must agree on the
// HTTP/2 upload-window keys. The chart's three regional blocks share one
// anchored config node, so checking any one of them covers all three.
func TestGatewayNginxConfigMatchesChart(t *testing.T) {
	raw, err := os.ReadFile(chartValuesPath)
	if err != nil {
		t.Fatalf("read chart values %s: %v", chartValuesPath, err)
	}

	var values struct {
		Gateway struct {
			Controller struct {
				Config map[string]string `json:"config"`
			} `json:"controller"`
		} `json:"kura-us-west-ingress-nginx"`
	}
	if err := yaml.Unmarshal(raw, &values); err != nil {
		t.Fatalf("parse chart values: %v", err)
	}

	chart := values.Gateway.Controller.Config
	if len(chart) == 0 {
		t.Fatal("no controller.config found for kura-us-west-ingress-nginx; chart layout changed")
	}

	controller := gatewayNginxConfigData()
	for _, key := range windowKeys {
		got, ok := chart[key]
		if !ok {
			t.Errorf("chart regional gateway config is missing window key %q", key)
			continue
		}
		if want := controller[key]; got != want {
			t.Errorf("window key %q drifted: controller=%q chart=%q — update both render paths together", key, want, got)
		}
	}
}
