package driver

import (
	"bytes"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"runtime"
	"testing"

	appsv1 "k8s.io/api/apps/v1"
	yamlutil "k8s.io/apimachinery/pkg/util/yaml"
)

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
	a, b := main[0], rack[0]
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
