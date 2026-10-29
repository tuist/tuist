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

func TestRackPluginHasIndependentReleaseAndSameHostContract(t *testing.T) {
	helm, err := exec.LookPath("helm")
	if err != nil {
		t.Fatal("helm required for rack release regression")
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
	render := func(chart, release string, extra ...string) []appsv1.DaemonSet {
		args := []string{"template", release, chart, "-f", filepath.Join(root, "tuist/values.yaml"), "--set", "kuraFleet.enabled=true", "--set", "kuraVolumesCSI.enabled=true", "--set", "kuraVolumesCSI.image.tag=test-pinned", "--set", "kuraVolumesCSI.rackPools[0]=rack-storage-ber1", "--set", "server.appUrl=https://staging.tuist.dev"}
		args = append(args, extra...)
		out, err := exec.Command(helm, args...).CombinedOutput()
		if err != nil {
			t.Fatalf("helm: %v\n%s", err, out)
		}
		if chart == isolated && (!strings.Contains(string(out), "podInfoOnMount: true") || !strings.Contains(string(out), "name: kura-thin-encrypted-nvme") || !strings.Contains(string(out), "topology.kura-volumes.tuist.dev/node-layout")) {
			t.Fatal("thin class or pod UID contract missing")
		}
		dec := yamlutil.NewYAMLOrJSONDecoder(bytes.NewReader(out), 4096)
		var sets []appsv1.DaemonSet
		for {
			var ds appsv1.DaemonSet
			err := dec.Decode(&ds)
			if err == io.EOF {
				break
			}
			if err != nil {
				t.Fatal(err)
			}
			if ds.Kind == "DaemonSet" {
				sets = append(sets, ds)
			}
		}
		return sets
	}
	main := render(isolated, "tuist")
	rack := render(filepath.Join(root, "rack-nodes"), "tuist-rack-nodes")
	if len(main) != 1 || len(rack) != 1 {
		t.Fatalf("main=%d rack=%d", len(main), len(rack))
	}
	thinArgs := []string{"--set", "kuraVolumesCSI.thin.pool=tenants"}
	tm := render(isolated, "tuist", thinArgs...)
	tr := render(filepath.Join(root, "rack-nodes"), "tuist-rack-nodes", thinArgs...)
	if !reflect.DeepEqual(tm[0].Spec.Template.Spec.Containers, tr[0].Spec.Template.Spec.Containers) {
		t.Fatal("thin rack args drift")
	}
	if !strings.Contains(strings.Join(tm[0].Spec.Template.Spec.Containers[0].Args, " "), "--thin-pool=tenants") {
		t.Fatal("thin configuration missing")
	}
	a, b := main[0], rack[0]
	digest := "sha256:" + strings.Repeat("a", 64)
	for _, chart := range []string{isolated, filepath.Join(root, "rack-nodes")} {
		sets := render(chart, "tuist", "--set", "kuraVolumesCSI.image.digest="+digest)
		if sets[0].Spec.Template.Spec.Containers[0].Image != "ghcr.io/tuist/kura-volumes-csi@"+digest {
			t.Fatal("digest must take precedence over legacy tag on both releases")
		}
	}
	if a.Name == b.Name || a.Spec.Selector.MatchLabels["app.kubernetes.io/instance"] == b.Spec.Selector.MatchLabels["app.kubernetes.io/instance"] {
		t.Fatal("releases overlap")
	}
	pa, pb := a.Spec.Template.Spec, b.Spec.Template.Spec
	if pa.ServiceAccountName != pb.ServiceAccountName || pa.ServiceAccountName != "kura-volumes-csi-node" {
		t.Fatal("rack key identity differs")
	}
	if !reflect.DeepEqual(pa.Containers, pb.Containers) || !reflect.DeepEqual(pa.Volumes, pb.Volumes) {
		t.Fatal("rack storage/key/mount contract drifted from rented plugin")
	}
	pools := func(ds appsv1.DaemonSet) []string {
		return ds.Spec.Template.Spec.Affinity.NodeAffinity.RequiredDuringSchedulingIgnoredDuringExecution.NodeSelectorTerms[0].MatchExpressions[0].Values
	}
	if !reflect.DeepEqual(pools(b), []string{"rack-storage-ber1"}) || !reflect.DeepEqual(pools(a), []string{"kura-scw-fr-par"}) {
		t.Fatal("wrong pool ownership")
	}
	hasTaint := false
	for _, v := range pb.Tolerations {
		if v.Key == "tuist.dev/rack-storage" {
			hasTaint = true
		}
	}
	if !hasTaint {
		t.Fatal("rack taint not tolerated")
	}
	// Moving the last rented pool into the independent release must retain the
	// shared CSI identity and classes, but never leave two plugins on one node.
	none := render(isolated, "tuist", "--set", "kuraVolumesCSI.rackPools[1]=kura-scw-fr-par")
	if len(none) != 0 {
		t.Fatal("waited release still schedules on delegated pool")
	}
}
