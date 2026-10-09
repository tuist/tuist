package linux

import (
	"bytes"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"reflect"
	"runtime"
	"strings"
	"testing"

	yamlutil "k8s.io/apimachinery/pkg/util/yaml"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
)

// rackLinuxFleetChart copies the chart's rack-linux-fleet template, with what
// it reads, into a chart of its own, and returns it and the source chart.
func rackLinuxFleetChart(t *testing.T) (chart, source string) {
	t.Helper()
	_, file, _, _ := runtime.Caller(0)
	source = filepath.Join(filepath.Dir(file), "..", "..", "..", "helm", "tuist")
	chart = t.TempDir()
	for _, dir := range []string{"templates", "rack-sites"} {
		if err := os.Mkdir(filepath.Join(chart, dir), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(chart, "Chart.yaml"), []byte("apiVersion: v2\nname: tuist\nversion: 0.1.0\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	sites, err := filepath.Glob(filepath.Join(source, "rack-sites", "*.yaml"))
	if err != nil || len(sites) == 0 {
		t.Fatalf("no rendered rack sites in %s: %v", source, err)
	}
	names := []string{"values.yaml", "templates/_helpers.tpl", "templates/rack-linux-fleet.yaml"}
	for _, site := range sites {
		names = append(names, filepath.Join("rack-sites", filepath.Base(site)))
	}
	for _, name := range names {
		data, err := os.ReadFile(filepath.Join(source, name))
		if err != nil {
			t.Fatal(err)
		}
		if err := os.WriteFile(filepath.Join(chart, name), data, 0o644); err != nil {
			t.Fatal(err)
		}
	}
	return chart, source
}

func helmBinary(t *testing.T) string {
	t.Helper()
	if helm := os.Getenv("TUIST_TEST_HELM"); helm != "" {
		return helm
	}
	helm, err := exec.LookPath("helm")
	if err != nil {
		t.Skip("Helm is required for chart render checks")
	}
	return helm
}

func renderRackLinuxHosts(t *testing.T, chart, source string, extra ...string) (map[string]infrav1.RackLinuxHost, string, error) {
	t.Helper()
	args := append([]string{"template", "test", chart, "--namespace", "tuist",
		"--values", filepath.Join(source, "values-managed-common.yaml"),
		"--values", filepath.Join(source, "values-managed-staging.yaml")}, extra...)
	output, err := exec.Command(helmBinary(t), args...).CombinedOutput()
	if err != nil {
		return nil, string(output), err
	}
	hosts := map[string]infrav1.RackLinuxHost{}
	decoder := yamlutil.NewYAMLOrJSONDecoder(bytes.NewReader(output), 4096)
	for {
		var host infrav1.RackLinuxHost
		if err := decoder.Decode(&host); err == io.EOF {
			break
		} else if err != nil {
			t.Fatal(err)
		}
		if host.Kind == "RackLinuxHost" {
			hosts[host.Spec.Hostname] = host
		}
	}
	return hosts, string(output), nil
}

// The edges' RackLinuxHosts carry their way out from the site definition, as
// rack:fleet render wrote it into the chart: each edge's VRRP address, the
// other edge's as its peer, and its uplinks in the order the rack-edge pod
// stacks the VRRP VLAN on them.
func TestStagingRackLinuxEdgesCarryTheirWayOut(t *testing.T) {
	chart, source := rackLinuxFleetChart(t)
	hosts, output, err := renderRackLinuxHosts(t, chart, source)
	if err != nil {
		t.Fatalf("helm template: %v\n%s", err, output)
	}
	uplinks := []string{"enp2s0f1np1", "enp2s0f0np0"}
	for name, want := range map[string]infrav1.RackLinuxHostEdgeVRRP{
		"ber1-edge-a": {VLAN: 4000, Address: "10.255.255.1/29", Peer: "10.255.255.2"},
		"ber1-edge-b": {VLAN: 4000, Address: "10.255.255.2/29", Peer: "10.255.255.1"},
	} {
		host, ok := hosts[name]
		if !ok {
			t.Fatalf("no RackLinuxHost %s in:\n%s", name, output)
		}
		if host.Spec.Edge == nil || !reflect.DeepEqual(host.Spec.Edge.Uplinks, uplinks) || host.Spec.Edge.VRRP != want {
			t.Errorf("%s: edge %+v", name, host.Spec.Edge)
		}
		if host.Spec.Edge != nil {
			if _, err := edgeInstallUserData(host.Spec.Edge); err != nil {
				t.Errorf("%s: the install would refuse its edge network: %v", name, err)
			}
		}
	}
	for name, host := range hosts {
		if host.Spec.Role != "edge" && host.Spec.Edge != nil {
			t.Errorf("%s is a %s host with an edge network", name, host.Spec.Role)
		}
	}
}

// An edge the site definition does not know is a mistake in one of the two,
// and the chart says so rather than installing it without a way out.
func TestRackLinuxFleetRefusesAnEdgeTheSiteDoesNotKnow(t *testing.T) {
	chart, source := rackLinuxFleetChart(t)
	values := filepath.Join(t.TempDir(), "edge-c.yaml")
	if err := os.WriteFile(values, []byte("rackLinuxFleet:\n  hosts:\n    - uuid: 04450c00-63f4-11f1-81f4-3582298d5c00\n      hostname: ber1-edge-c\n      role: edge\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	_, output, err := renderRackLinuxHosts(t, chart, source, "--values", values)
	if err == nil || !strings.Contains(output, "rackLinuxFleet.hosts[ber1-edge-c] is an edge of ber1, whose site definition has no VRRP member by that name") {
		t.Fatalf("rendered an edge the site does not know: %v\n%s", err, output)
	}
}
