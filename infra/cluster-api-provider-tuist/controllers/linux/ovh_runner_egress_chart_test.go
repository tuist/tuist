package linux

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

func TestRunnerEgressChart(t *testing.T) {
	helm := os.Getenv("TUIST_TEST_HELM")
	if helm == "" {
		var err error
		helm, err = exec.LookPath("helm")
		if err != nil {
			t.Skip("Helm required")
		}
	}
	_, file, _, _ := runtime.Caller(0)
	source := filepath.Join(filepath.Dir(file), "..", "..", "..", "helm", "tuist")
	chart := t.TempDir()
	if err := os.Mkdir(filepath.Join(chart, "templates"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(chart, "Chart.yaml"), []byte("apiVersion: v2\nname: runner-egress-test\nversion: 0.1.0\n"), 0644); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"values.yaml", "templates/_helpers.tpl", "templates/ovh-runner-egress.yaml", "templates/capi-scaleway-applesilicon.yaml"} {
		data, err := os.ReadFile(filepath.Join(source, name))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(chart, name), data, 0644); err != nil {
			t.Fatal(err)
		}
	}
	for _, env := range []string{"staging", "canary", "production"} {
		t.Run(env, func(t *testing.T) {
			base := []string{"template", "test", chart, "--namespace", "tuist-" + env, "--values", filepath.Join(source, "values-managed-common.yaml"), "--values", filepath.Join(source, "values-managed-"+env+".yaml")}
			for _, enabled := range []bool{false, true} {
				args := append([]string{}, base...)
				if enabled {
					args = append(args, "--set", "capi.ovhRunnerEgress.enabled=true")
				}
				output, err := exec.Command(helm, args...).CombinedOutput()
				if err != nil {
					t.Fatalf("helm: %v\n%s", err, output)
				}
				decoder := yamlutil.NewYAMLOrJSONDecoder(bytes.NewReader(output), 4096)
				configFound, argumentFound, rbacFound := false, false, false
				for {
					obj := &unstructured.Unstructured{}
					err := decoder.Decode(&obj.Object)
					if err == io.EOF {
						break
					}
					if err != nil {
						t.Fatal(err)
					}
					if obj.GetKind() == "ConfigMap" && strings.HasSuffix(obj.GetName(), "ovh-runner-egress") {
						configFound = true
						data, _, _ := unstructured.NestedStringMap(obj.Object, "data")
						if (data["enabled"] == "true") != enabled {
							t.Fatalf("wrong enabled: %v", data)
						}
						if _, _, err := runnerEgressPrefix(data["vrackID"], data["cidr"]); err != nil {
							t.Fatalf("invalid delivered block: %v", err)
						}
					}
					if obj.GetKind() == "Deployment" && strings.Contains(string(output), "--ovh-runner-egress-config=") {
						argumentFound = true
					}
					if obj.GetKind() == "ClusterRole" && strings.HasSuffix(obj.GetName(), "ovh-runner-egress") {
						rbacFound = true
					}
				}
				if !configFound || !argumentFound || !rbacFound {
					t.Fatalf("missing config/argument/RBAC: %v %v %v", configFound, argumentFound, rbacFound)
				}
			}
			output, err := exec.Command(helm, append(base, "--set", "capi.ovhRunnerEgress.enabled=true,capi.ovhRunnerEgress.cidr=")...).CombinedOutput()
			if err == nil || !strings.Contains(string(output), "cidr is required") {
				t.Fatalf("missing block accepted: %v %s", err, output)
			}
		})
	}
}
