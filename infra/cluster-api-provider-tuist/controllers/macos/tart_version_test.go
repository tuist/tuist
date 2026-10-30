package macos

import (
	"strings"
	"testing"

	"k8s.io/client-go/tools/record"

	infrav1 "github.com/tuist/tuist/infra/cluster-api-provider-tuist/api/v1alpha1"
	"github.com/tuist/tuist/infra/macos-host-bootstrap"
)

var testTartReleases = map[string][]byte{
	"2.32.1": []byte("tart 2.32.1 tarball"),
	"2.41.1": []byte("tart 2.41.1 tarball"),
}

func tartFleet() bootstrap.Config {
	return bootstrap.Config{
		TartKubeletBinary: []byte("tart-kubelet"),
		TartVersion:       "2.32.1",
		TartTarball:       testTartReleases["2.32.1"],
		HostCPU:           8,
		HostMemoryMB:      14336,
		MaxPods:           3,
	}
}

func pinTart(version string) func(*infrav1.RackAppleSiliconMachine) {
	return func(m *infrav1.RackAppleSiliconMachine) {
		m.Annotations = map[string]string{TartVersionAnnotation: version}
	}
}

func TestHostTart_PinnedMachineGetsThePinnedRelease(t *testing.T) {
	r := &RackAppleSiliconMachineReconciler{FleetConfig: tartFleet(), TartReleases: testTartReleases, DefaultGuestCapacity: 1}
	host := rackHost("mini-01")
	for _, tc := range []struct {
		name    string
		machine *infrav1.RackAppleSiliconMachine
		version string
	}{
		{"unpinned", rackMachine("m"), "2.32.1"},
		{"pinned", rackMachine("m", pinTart("2.41.1")), "2.41.1"},
		{"pinned to a release the image lacks", rackMachine("m", pinTart("2.99.0")), "2.32.1"},
	} {
		t.Run(tc.name, func(t *testing.T) {
			pushed := r.hostConfig(tc.machine, host, bootstrap.PerHost{NodeName: "m"})
			if pushed.TartVersion != tc.version || string(pushed.TartTarball) != string(testTartReleases[tc.version]) {
				t.Fatalf("pushed Tart %s with tarball %q, want %s", pushed.TartVersion, pushed.TartTarball, tc.version)
			}
			if want, have := r.desiredHostConfigHash(tc.machine, host), bootstrap.HostConfigHash(pushed); want != have {
				t.Fatalf("stamped hash %s != hash of what was pushed %s", want, have)
			}
		})
	}
}

// Pinning is how a new Tart reaches one host before the fleet, so it has to
// drift that host and only that host.
func TestHostTart_PinDriftsOnlyThePinnedMachine(t *testing.T) {
	r := &ScalewayAppleSiliconMachineReconciler{FleetConfig: tartFleet(), TartReleases: testTartReleases, DefaultGuestCapacity: 1}
	unpinned := &infrav1.ScalewayAppleSiliconMachine{}
	pinned := &infrav1.ScalewayAppleSiliconMachine{}
	pinned.Annotations = map[string]string{TartVersionAnnotation: "2.41.1"}
	pinnedToFleet := &infrav1.ScalewayAppleSiliconMachine{}
	pinnedToFleet.Annotations = map[string]string{TartVersionAnnotation: "2.32.1"}

	if r.desiredHostConfigHash(unpinned) == r.desiredHostConfigHash(pinned) {
		t.Fatal("pinning a machine to another Tart does not move its fingerprint, so the pin never reaches the host")
	}
	if r.desiredHostConfigHash(unpinned) != r.desiredHostConfigHash(pinnedToFleet) {
		t.Fatal("pinning a machine to the fleet's own Tart drifted it")
	}
	if got := r.hostConfig(pinned, bootstrap.PerHost{}).TartVersion; got != "2.41.1" {
		t.Fatalf("pinned machine pushes Tart %s, want 2.41.1", got)
	}
}

func TestReportUnavailableTartPin(t *testing.T) {
	for _, tc := range []struct {
		name        string
		annotations map[string]string
		wantEvent   bool
	}{
		{"unpinned", nil, false},
		{"pinned to a carried release", map[string]string{TartVersionAnnotation: "2.41.1"}, false},
		{"pinned to a missing release", map[string]string{TartVersionAnnotation: "2.41"}, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			recorder := record.NewFakeRecorder(10)
			machine := rackMachine("m")
			machine.Annotations = tc.annotations
			reportUnavailableTartPin(machine, tartFleet(), testTartReleases, recorder)
			select {
			case event := <-recorder.Events:
				if !tc.wantEvent {
					t.Fatalf("unexpected event %q", event)
				}
				for _, want := range []string{"TartVersionUnavailable", "2.41", "2.32.1, 2.41.1", "stays on 2.32.1"} {
					if !strings.Contains(event, want) {
						t.Errorf("event %q does not mention %q", event, want)
					}
				}
			default:
				if tc.wantEvent {
					t.Fatal("no event for a pin the image cannot honour")
				}
			}
		})
	}
}
