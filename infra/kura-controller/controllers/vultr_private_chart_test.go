package controllers

import (
	"encoding/json"
	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	"strings"
	"testing"
)

func TestVultrPrivateNetworkChartOwnershipAndQualification(t *testing.T) {
	templates := []string{"templates/_helpers.tpl", "templates/vultr-private-network.yaml", "templates/capi-scaleway-applesilicon.yaml"}
	for _, env := range []string{"default", "staging", "canary", "production"} {
		t.Run(env, func(t *testing.T) {
			var values []string
			if env != "default" {
				values = []string{"values-managed-common.yaml", "values-managed-" + env + ".yaml"}
			}
			docs := renderStableChartWithValues(t, "tuist", templates, values)
			config, flag := false, false
			for _, doc := range docs {
				if doc["kind"] == "ConfigMap" {
					raw, found, _ := unstructured.NestedString(doc, "data", "regions.json")
					if found {
						config = true
						var regions map[string]struct {
							Description string `json:"description"`
							CIDR        string `json:"cidr"`
							Qualified   bool   `json:"qualified"`
						}
						if err := json.Unmarshal([]byte(raw), &regions); err != nil {
							t.Fatal(err)
						}
						if len(regions) != 2 || !regions["ord"].Qualified || !regions["scl"].Qualified || regions["ord"].CIDR != "172.30.244.0/24" || regions["scl"].CIDR != "172.30.245.0/24" {
							t.Fatalf("unsafe qualification configuration: %+v", regions)
						}
					}
				}
				if doc["kind"] == "Deployment" {
					containers, _, _ := unstructured.NestedSlice(doc, "spec", "template", "spec", "containers")
					for _, c := range containers {
						args, _, _ := unstructured.NestedStringSlice(c.(map[string]interface{}), "args")
						for _, arg := range args {
							if strings.HasPrefix(arg, "--vultr-private-network-config=") {
								flag = true
							}
						}
					}
				}
			}
			want := env == "production"
			if config != want || flag != want {
				t.Fatalf("config=%t flag=%t want=%t", config, flag, want)
			}
		})
	}
}
