package kvmnri

import (
	"os"
	"testing"

	"github.com/containerd/nri/pkg/api"
)

const namespace = "tuist-runners"

func runnerPod() *api.PodSandbox {
	return &api.PodSandbox{
		Name:           "linux-2x-abc",
		Namespace:      namespace,
		RuntimeHandler: "kata-qemu",
		Annotations:    map[string]string{KVMContainersAnnotation: "poller,runner"},
	}
}

func TestAdjust_AddsKVMToNamedContainer(t *testing.T) {
	for _, name := range []string{"poller", "runner"} {
		adjustment := Adjust(namespace, runnerPod(), &api.Container{Name: name})
		if adjustment == nil {
			t.Fatalf("%s: got no adjustment", name)
		}
		devices := adjustment.GetLinux().GetDevices()
		if len(devices) != 1 {
			t.Fatalf("%s: got %d devices, want 1", name, len(devices))
		}
		device := devices[0]
		if device.Path != "/dev/kvm" || device.Type != "c" || device.Major != 10 || device.Minor != 232 {
			t.Errorf("%s: device = %s %s %d:%d, want /dev/kvm c 10:232", name, device.Path, device.Type, device.Major, device.Minor)
		}
		if device.FileMode == nil || os.FileMode(device.FileMode.Value) != 0o666 {
			t.Errorf("%s: file mode = %v, want 0666", name, device.FileMode)
		}
		if device.Uid == nil || device.Uid.Value != 0 || device.Gid == nil || device.Gid.Value != 0 {
			t.Errorf("%s: owner = %v:%v, want 0:0", name, device.Uid, device.Gid)
		}
		rules := adjustment.GetLinux().GetResources().GetDevices()
		if len(rules) != 1 {
			t.Fatalf("%s: got %d cgroup rules, want 1", name, len(rules))
		}
		rule := rules[0]
		if !rule.Allow || rule.Type != "c" || rule.Major.GetValue() != 10 || rule.Minor.GetValue() != 232 || rule.Access != "rwm" {
			t.Errorf("%s: cgroup rule = %+v, want allow c 10:232 rwm", name, rule)
		}
	}
}

func TestAdjust_LeavesOtherContainersAlone(t *testing.T) {
	otherNamespace := runnerPod()
	otherNamespace.Namespace = "default"
	runc := runnerPod()
	runc.RuntimeHandler = "runc"
	unannotated := runnerPod()
	unannotated.Annotations = nil

	cases := map[string]struct {
		pod       *api.PodSandbox
		container string
	}{
		"wrong namespace":       {otherNamespace, "runner"},
		"runc":                  {runc, "runner"},
		"missing annotation":    {unannotated, "runner"},
		"container not named":   {runnerPod(), "dind"},
		"container name prefix": {runnerPod(), "run"},
	}
	for name, tc := range cases {
		if adjustment := Adjust(namespace, tc.pod, &api.Container{Name: tc.container}); adjustment != nil {
			t.Errorf("%s: got %v, want no adjustment", name, adjustment)
		}
	}
}
