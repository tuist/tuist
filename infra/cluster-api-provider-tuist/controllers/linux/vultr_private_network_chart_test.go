package linux

import (
	"bytes"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"

	corev1 "k8s.io/api/core/v1"
	yamlutil "k8s.io/apimachinery/pkg/util/yaml"
)

func TestManagedVultrCanonicalPolicies(t *testing.T) {
	helm := os.Getenv("TUIST_TEST_HELM")
	if helm == "" {
		var err error
		helm, err = exec.LookPath("helm")
		if err != nil {
			t.Skip("Helm is required for chart render checks")
		}
	}
	_, file, _, _ := runtime.Caller(0)
	source := filepath.Join(filepath.Dir(file), "..", "..", "..", "helm", "tuist")
	chart := t.TempDir()
	if err := os.Mkdir(filepath.Join(chart, "templates"), 0755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(chart, "Chart.yaml"), []byte("apiVersion: v2\nname: network-policy-test\nversion: 0.1.0\n"), 0644); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"values.yaml", "templates/_helpers.tpl", "templates/vultr-private-network.yaml"} {
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
			output, err := exec.Command(helm, "template", "test", chart, "--namespace", "tuist", "--values", filepath.Join(source, "values-managed-common.yaml"), "--values", filepath.Join(source, "values-managed-"+env+".yaml")).CombinedOutput()
			if err != nil {
				t.Fatalf("helm template: %v\n%s", err, output)
			}
			decoder := yamlutil.NewYAMLOrJSONDecoder(bytes.NewReader(output), 4096)
			for {
				var cm corev1.ConfigMap
				if err := decoder.Decode(&cm); err == io.EOF {
					break
				} else if err != nil {
					t.Fatal(err)
				}
				raw, ok := cm.Data["regions.json"]
				if !ok {
					continue
				}
				var regions map[string]vultrPrivateRegion
				if err := json.Unmarshal([]byte(raw), &regions); err != nil {
					t.Fatal(err)
				}
				if err := validateVultrCanonicalPeers(regions); err != nil {
					t.Fatal(err)
				}
			}
		})
	}
}
