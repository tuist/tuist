package driver

import (
	"bytes"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	corev1 "k8s.io/api/core/v1"
	yamlutil "k8s.io/apimachinery/pkg/util/yaml"
)

func TestManagedStoragePrerequisitesStayOptIn(t *testing.T) {
	_, file, _, _ := runtime.Caller(0)
	chart := filepath.Clean(filepath.Join(filepath.Dir(file), "../../../helm/tuist"))
	for _, env := range []string{"production", "canary", "staging"} {
		t.Run(env, func(t *testing.T) {
			out, err := exec.Command("helm", "template", "tuist", chart,
				"-f", filepath.Join(chart, "values-managed-common.yaml"),
				"-f", filepath.Join(chart, "values-managed-"+env+".yaml"),
				"-f", filepath.Join(chart, "values-ci.yaml")).CombinedOutput()
			if err != nil {
				t.Fatalf("render: %v\n%s", err, out)
			}
			dec := yamlutil.NewYAMLOrJSONDecoder(bytes.NewReader(out), 4096)
			drivers, roots := 0, 0
			for {
				var obj struct {
					Kind     string
					Metadata struct{ Name string }
					Spec     json.RawMessage
				}
				if err := dec.Decode(&obj); err == io.EOF {
					break
				} else if err != nil {
					t.Fatal(err)
				}
				if obj.Kind == "CSIDriver" && obj.Metadata.Name == Name {
					drivers++
				}
				if obj.Kind == "ExternalSecret" && bytes.Contains(obj.Spec, []byte(`"KURA_VOLUME_ROOT_KEYS/value"`)) {
					roots++
				}
			}
			want := 0
			if env == "staging" {
				want = 1
			} // Keep the already-qualified staging dependency.
			if drivers != want || roots != want {
				t.Fatalf("drivers=%d roots=%d want=%d", drivers, roots, want)
			}
		})
	}
}

// renderDaemonSets renders a chart and returns its DaemonSets by name.
func renderDaemonSets(t *testing.T, args ...string) map[string]appsv1.DaemonSet {
	t.Helper()
	out, err := exec.Command("helm", args...).CombinedOutput()
	if err != nil {
		t.Fatalf("helm: %v\n%s", err, out)
	}
	dec := yamlutil.NewYAMLOrJSONDecoder(bytes.NewReader(out), 4096)
	sets := map[string]appsv1.DaemonSet{}
	for {
		var raw json.RawMessage
		if err := dec.Decode(&raw); err == io.EOF {
			break
		} else if err != nil {
			t.Fatal(err)
		}
		var kind struct{ Kind string }
		if json.Unmarshal(raw, &kind) != nil || kind.Kind != "DaemonSet" {
			continue
		}
		// Callers assert the DaemonSets they need; others may not fit the typed API.
		var ds appsv1.DaemonSet
		if json.Unmarshal(raw, &ds) == nil {
			sets[ds.Name] = ds
		}
	}
	return sets
}

func poolsOf(ds appsv1.DaemonSet) []string {
	return ds.Spec.Template.Spec.Affinity.NodeAffinity.RequiredDuringSchedulingIgnoredDuringExecution.NodeSelectorTerms[0].MatchExpressions[0].Values
}

func TestNodePluginsLiveInTheUnwaitedReleaseWithOneHostContract(t *testing.T) {
	if _, err := exec.LookPath("helm"); err != nil {
		t.Fatal("helm required for node plugin release regression")
	}
	_, file, _, _ := runtime.Caller(0)
	root := filepath.Clean(filepath.Join(filepath.Dir(file), "../../../helm"))
	isolated := t.TempDir()
	if err := os.Mkdir(filepath.Join(isolated, "templates"), 0755); err != nil {
		t.Fatal(err)
	}
	for _, name := range []string{"Chart.yaml", "values.yaml", "templates/_helpers.tpl", "templates/kura-volumes-csi.yaml"} {
		data, err := os.ReadFile(filepath.Join(root, "tuist", name))
		if err != nil {
			t.Fatal(err)
		}
		if name == "Chart.yaml" {
			data = []byte("apiVersion: v2\nname: tuist\nversion: 0.1.0\n")
		}
		if err := os.WriteFile(filepath.Join(isolated, name), data, 0600); err != nil {
			t.Fatal(err)
		}
	}
	rackNodes := filepath.Join(root, "rack-nodes")
	render := func(chart, release string, extra ...string) map[string]appsv1.DaemonSet {
		args := []string{"template", release, chart, "-f", filepath.Join(root, "tuist/values.yaml"), "--set", "kuraFleet.enabled=true", "--set", "kuraVolumesCSI.enabled=true", "--set", "kuraVolumesCSI.image.tag=test-pinned", "--set", "kuraVolumesCSI.rackPools[0]=rack-storage-ber1", "--set", "server.appUrl=https://staging.tuist.dev"}
		return renderDaemonSets(t, append(args, extra...)...)
	}
	out, err := exec.Command("helm", "template", "tuist", isolated, "-f", filepath.Join(root, "tuist/values.yaml"), "--set", "kuraFleet.enabled=true", "--set", "kuraVolumesCSI.enabled=true").CombinedOutput()
	if err != nil {
		t.Fatalf("helm: %v\n%s", err, out)
	}
	if !strings.Contains(string(out), "podInfoOnMount: true") || !strings.Contains(string(out), "name: kura-thin-encrypted-nvme") || !strings.Contains(string(out), "topology.kura-volumes.tuist.dev/node-layout") {
		t.Fatal("thin class or pod UID contract missing")
	}
	if main := render(isolated, "tuist"); len(main) != 0 {
		t.Fatalf("the waited tuist release still renders node plugins: %d", len(main))
	}

	sets := render(rackNodes, "tuist-rack-nodes", "--set", "tuistRelease=tuist")
	rented, rack := sets["kura-volumes-csi-node"], sets["kura-volumes-csi-rack"]
	if len(sets) != 2 || rented.Name == "" || rack.Name == "" {
		t.Fatalf("rack-nodes plugins = %d", len(sets))
	}
	// The rented plugin is adopted from the tuist release, so its selector,
	// which Kubernetes never lets change, stays the one that release created.
	if want := map[string]string{"app.kubernetes.io/name": "kura-volumes-csi-node", "app.kubernetes.io/instance": "tuist"}; !reflect.DeepEqual(rented.Spec.Selector.MatchLabels, want) {
		t.Fatalf("rented selector = %v, want %v", rented.Spec.Selector.MatchLabels, want)
	}
	if rack.Spec.Selector.MatchLabels["app.kubernetes.io/instance"] != "tuist-rack-nodes" {
		t.Fatal("rack plugin selector moved")
	}

	thin := render(rackNodes, "tuist-rack-nodes", "--set", "kuraVolumesCSI.thin.pool=tenants")
	if !reflect.DeepEqual(thin["kura-volumes-csi-node"].Spec.Template.Spec.Containers, thin["kura-volumes-csi-rack"].Spec.Template.Spec.Containers) {
		t.Fatal("thin rack args drift")
	}
	if !strings.Contains(strings.Join(thin["kura-volumes-csi-node"].Spec.Template.Spec.Containers[0].Args, " "), "--thin-pool=tenants") {
		t.Fatal("thin configuration missing")
	}
	digest := "sha256:" + strings.Repeat("a", 64)
	for _, ds := range render(rackNodes, "tuist-rack-nodes", "--set", "kuraVolumesCSI.image.digest="+digest) {
		if ds.Spec.Template.Spec.Containers[0].Image != "ghcr.io/tuist/kura-volumes-csi@"+digest {
			t.Fatal("digest must take precedence over legacy tag on every plugin")
		}
	}

	pa, pb := rented.Spec.Template.Spec, rack.Spec.Template.Spec
	if pa.ServiceAccountName != pb.ServiceAccountName || pa.ServiceAccountName != "kura-volumes-csi-node" {
		t.Fatal("rack key identity differs")
	}
	if !reflect.DeepEqual(pa.Containers, pb.Containers) || !reflect.DeepEqual(pa.Volumes, pb.Volumes) {
		t.Fatal("rack storage/key/mount contract drifted from rented plugin")
	}
	if !reflect.DeepEqual(poolsOf(rack), []string{"rack-storage-ber1"}) || !reflect.DeepEqual(poolsOf(rented), []string{"kura-scw-fr-par"}) {
		t.Fatal("wrong pool ownership")
	}
	tolerates := func(tolerations []corev1.Toleration) bool {
		for _, v := range tolerations {
			if v.Key == "tuist.dev/rack-storage" {
				return true
			}
		}
		return false
	}
	if !tolerates(pb.Tolerations) || tolerates(pa.Tolerations) {
		t.Fatal("only the rack plugin tolerates rack storage")
	}
	// Moving the last rented pool to a rack must never leave two plugins on one node.
	moved := render(rackNodes, "tuist-rack-nodes", "--set", "kuraVolumesCSI.rackPools[1]=kura-scw-fr-par")
	if _, ok := moved["kura-volumes-csi-node"]; ok || len(moved) != 1 {
		t.Fatal("rented plugin still schedules on a delegated pool")
	}
}

// rackNodes.kuraCachePools copies tuist.kuraCachePools; every managed fleet
// must resolve to the same pools in both charts.
func TestRentedPluginPoolsMatchTheTuistCachePools(t *testing.T) {
	_, file, _, _ := runtime.Caller(0)
	root := filepath.Clean(filepath.Join(filepath.Dir(file), "../../../helm"))
	for _, env := range []string{"staging", "canary", "production"} {
		t.Run(env, func(t *testing.T) {
			values := []string{"-f", filepath.Join(root, "tuist/values-managed-common.yaml"), "-f", filepath.Join(root, "tuist/values-managed-"+env+".yaml"), "-f", filepath.Join(root, "tuist/values-ci.yaml")}
			exporter, ok := renderDaemonSets(t, append([]string{"template", "tuist", filepath.Join(root, "tuist")}, values...)...)["kura-volume-quota-exporter"]
			if !ok {
				t.Fatal("cache pool exporter missing")
			}
			args := []string{"template", "tuist-rack-nodes", filepath.Join(root, "rack-nodes"), "-f", filepath.Join(root, "tuist/values.yaml")}
			args = append(append(args, values...), "--set", "kuraVolumesCSI.enabled=true", "--set", "kuraVolumesCSI.image.tag=test-pinned", "--set", "kuraVolumesCSI.rackPools=null")
			plugin, ok := renderDaemonSets(t, args...)["kura-volumes-csi-node"]
			if !ok {
				t.Fatal("rented plugin missing")
			}
			if !reflect.DeepEqual(poolsOf(exporter), poolsOf(plugin)) {
				t.Fatalf("cache pools differ: tuist %v, rack-nodes %v", poolsOf(exporter), poolsOf(plugin))
			}
		})
	}
}
