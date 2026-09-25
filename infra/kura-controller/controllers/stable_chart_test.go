package controllers

import (
	"bytes"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"strings"
	"testing"

	"k8s.io/apimachinery/pkg/apis/meta/v1/unstructured"
	yamlutil "k8s.io/apimachinery/pkg/util/yaml"
)

// Render the owned templates in isolation: upstream subcharts are deliberately
// outside this test. No cluster, Helm repository, AWS or Cloudflare is contacted.
func renderStableChart(t *testing.T, chart string, templates []string, settings ...string) []map[string]interface{} {
	return renderStableChartWithValues(t, chart, templates, nil, settings...)
}

func renderStableChartWithValues(t *testing.T, chart string, templates, values []string, settings ...string) []map[string]interface{} {
	t.Helper()
	helm := os.Getenv("TUIST_TEST_HELM")
	if helm == "" {
		var err error
		helm, err = exec.LookPath("helm")
		if err != nil {
			t.Skip("Helm is required for chart render checks")
		}
	}
	_, file, _, _ := runtime.Caller(0)
	source := filepath.Join(filepath.Dir(file), "..", "..", "helm", chart)
	destination := t.TempDir()
	if err := os.Mkdir(filepath.Join(destination, "templates"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(destination, "Chart.yaml"), []byte("apiVersion: v2\nname: test-cache-dns\nversion: 0.1.0\n"), 0644); err != nil {
		t.Fatal(err)
	}
	for _, file := range append([]string{"values.yaml"}, templates...) {
		data, err := os.ReadFile(filepath.Join(source, file))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(destination, file), data, 0644); err != nil {
			t.Fatal(err)
		}
	}
	args := []string{"template", "test", destination, "--namespace", "platform"}
	for _, file := range values {
		args = append(args, "--values", filepath.Join(source, file))
	}
	for _, setting := range settings {
		args = append(args, "--set", setting)
	}
	output, err := exec.Command(helm, args...).CombinedOutput()
	if err != nil {
		t.Fatalf("helm template: %v\n%s", err, output)
	}
	decoder := yamlutil.NewYAMLOrJSONDecoder(bytes.NewReader(output), 4096)
	var docs []map[string]interface{}
	for {
		doc := map[string]interface{}{}
		if err := decoder.Decode(&doc); err == io.EOF {
			break
		} else if err != nil {
			t.Fatal(err)
		}
		if len(doc) != 0 {
			docs = append(docs, doc)
		}
	}
	return docs
}

func TestStableDNSCanaryAndProductionInfrastructure(t *testing.T) {
	for _, env := range []string{"canary", "production"} {
		t.Run(env, func(t *testing.T) {
			platformValues := "values-tuist-canary.yaml"
			if env == "production" {
				platformValues = "values-tuist.yaml"
			}
			docs := renderStableChartWithValues(t, "platform", []string{"templates/cache-dns.yaml", "templates/cluster-issuer.yaml"}, []string{platformValues})
			writer, secrets := false, 0
			for _, doc := range docs {
				if doc["kind"] == "ExternalSecret" {
					secrets++
				}
				if doc["kind"] == "Deployment" {
					containers, _, _ := unstructured.NestedSlice(doc, "spec", "template", "spec", "containers")
					args, _, _ := unstructured.NestedStringSlice(containers[0].(map[string]interface{}), "args")
					joined := strings.Join(args, " ")
					writer = strings.Contains(joined, "--txt-owner-id=tuist-"+env+"-cache") && strings.Contains(joined, "--zone-id-filter=Z046862130S1WUMPV7Z3P")
				}
			}
			if !writer || secrets != 2 {
				t.Fatalf("missing isolated writer/solver: writer=%v secrets=%d", writer, secrets)
			}
			docs = renderStableChartWithValues(t, "tuist", []string{"templates/_helpers.tpl", "templates/kura-controller.yaml", "templates/kura-cache-dns-secret.yaml"}, []string{"values-managed-common.yaml", "values-managed-" + env + ".yaml"}, "kuraController.image.tag=test")
			controller, secret := false, false
			for _, doc := range docs {
				if doc["kind"] == "ExternalSecret" {
					secret = true
				}
				if doc["kind"] != "Deployment" {
					continue
				}
				containers, _, _ := unstructured.NestedSlice(doc, "spec", "template", "spec", "containers")
				args, _, _ := unstructured.NestedStringSlice(containers[0].(map[string]interface{}), "args")
				joined := strings.Join(args, " ")
				for _, value := range []string{"--stable-dns-owner=tuist-" + env + "-cache", "*.cache.tuist.dev", "*.kura.tuist.dev", "--stable-dns-drain=3720s"} {
					if !strings.Contains(joined, value) {
						t.Fatalf("missing controller argument %q: %s", value, joined)
					}
				}
				controller = true
			}
			if !controller || !secret {
				t.Fatalf("controller=%v secret=%v", controller, secret)
			}
		})
	}
}

func TestStableDNSPlatformChartIsInertByDefaultAndIsolatesWriter(t *testing.T) {
	templates := []string{"templates/cache-dns.yaml", "templates/cluster-issuer.yaml"}
	for _, doc := range renderStableChart(t, "platform", templates) {
		if doc["kind"] == "Deployment" || doc["kind"] == "ExternalSecret" {
			t.Fatalf("stable DNS enabled by default: %v", doc["kind"])
		}
	}
	docs := renderStableChart(t, "platform", templates, "cacheDNS.enabled=true", "cacheDNS.hostedZoneId=ZCACHE", "cacheDNS.ownerId=staging-cache", "cacheDNS.externalSecret.enabled=true", "cacheDNS.externalSecret.writerItem=writer", "cacheDNS.externalSecret.solverItem=solver")
	writer, issuer, secrets := false, false, 0
	for _, doc := range docs {
		switch doc["kind"] {
		case "Deployment":
			containers, _, _ := unstructured.NestedSlice(doc, "spec", "template", "spec", "containers")
			args, _, _ := unstructured.NestedStringSlice(containers[0].(map[string]interface{}), "args")
			joined := strings.Join(args, " ")
			for _, required := range []string{"--source=crd", "--domain-filter=cache.tuist.dev", "--zone-id-filter=ZCACHE", "--txt-owner-id=staging-cache", "--policy=sync"} {
				if !strings.Contains(joined, required) {
					t.Errorf("missing %s", required)
				}
			}
			if strings.Contains(joined, "--source=ingress") || strings.Contains(joined, "--source=service") {
				t.Fatal("writer consumes ambiguous sources")
			}
			writer = true
		case "ClusterIssuer":
			solvers, _, _ := unstructured.NestedSlice(doc, "spec", "acme", "solvers")
			if len(solvers) != 2 {
				t.Fatalf("expected isolated AWS solver alongside Cloudflare: %v", solvers)
			}
			zone, _, _ := unstructured.NestedString(solvers[0].(map[string]interface{}), "dns01", "route53", "hostedZoneID")
			if zone != "ZCACHE" {
				t.Fatal("solver not scoped to delegated zone")
			}
			issuer = true
		case "ExternalSecret":
			secrets++
		}
	}
	if !writer || !issuer || secrets != 2 {
		t.Fatalf("incomplete platform plumbing: writer=%v issuer=%v secrets=%d", writer, issuer, secrets)
	}
}

func TestStableDNSControllerChartUsesSeparateSecretAndDrain(t *testing.T) {
	templates := []string{"templates/_helpers.tpl", "templates/kura-controller.yaml", "templates/kura-cache-dns-secret.yaml"}
	settings := []string{"kuraController.enabled=true", "kuraController.image.tag=test", "kuraController.stableDNS.enabled=true", "kuraController.stableDNS.hostedZoneId=ZCACHE", "kuraController.stableDNS.ownerId=staging-cache", "kuraController.stableDNS.externalSecret.enabled=true", "kuraController.stableDNS.externalSecret.item=controller"}
	docs := renderStableChart(t, "tuist", templates, settings...)
	found := false
	for _, doc := range docs {
		if doc["kind"] != "Deployment" {
			continue
		}
		containers, _, _ := unstructured.NestedSlice(doc, "spec", "template", "spec", "containers")
		container := containers[0].(map[string]interface{})
		args, _, _ := unstructured.NestedStringSlice(container, "args")
		if !strings.Contains(strings.Join(args, " "), "--stable-dns-drain=3720s") {
			t.Fatal("missing default withdrawal drain")
		}
		env, _, _ := unstructured.NestedSlice(container, "envFrom")
		secret, _, _ := unstructured.NestedString(env[0].(map[string]interface{}), "secretRef", "name")
		if secret != "kura-cache-dns" {
			t.Fatal("controller did not receive its separate scoped credential")
		}
		found = true
	}
	if !found {
		t.Fatal("controller deployment missing")
	}
}
