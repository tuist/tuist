// Package kvmnri gives runner containers /dev/kvm from a containerd NRI
// plugin instead of the devices.tuist.dev/kvm device plugin.
//
// Pools with exclusive CPUs carry a Pod-level resource budget, and the
// kubelet panics when such a Pod also requests a device-plugin resource
// (https://github.com/kubernetes/kubernetes/issues/143490). Those Pods name
// the containers that need /dev/kvm in the KVMContainersAnnotation, and the
// plugin adds the device when containerd creates each one.
package kvmnri

import (
	"os"
	"strings"

	"github.com/containerd/nri/pkg/api"
)

const (
	// KVMContainersAnnotation lists, comma-separated, the containers of a
	// Pod that get /dev/kvm. podtemplate sets it.
	KVMContainersAnnotation = "tuist.dev/kvm-containers"
	// RuntimeHandler is the only runtime whose Pods get /dev/kvm: the device
	// reaches the Kata guest, never the host's runc containers.
	RuntimeHandler = "kata-qemu"

	DevicePath  = "/dev/kvm"
	DeviceMajor = 10
	DeviceMinor = 232
)

// Adjust returns the adjustment that adds /dev/kvm to ctr, or nil when the
// container should not get it: its Pod is outside namespace, does not run
// under kata-qemu, or does not name ctr in KVMContainersAnnotation.
func Adjust(namespace string, pod *api.PodSandbox, ctr *api.Container) *api.ContainerAdjustment {
	if pod.GetNamespace() != namespace || pod.GetRuntimeHandler() != RuntimeHandler {
		return nil
	}
	named := false
	for _, name := range strings.Split(pod.GetAnnotations()[KVMContainersAnnotation], ",") {
		if strings.TrimSpace(name) == ctr.GetName() && ctr.GetName() != "" {
			named = true
			break
		}
	}
	if !named {
		return nil
	}

	adjustment := &api.ContainerAdjustment{}
	// The api helpers take interface{} and return nil for any type they do
	// not expect, so an untyped constant would silently drop the mode or
	// owner: pass typed values.
	adjustment.AddDevice(&api.LinuxDevice{
		Path:     DevicePath,
		Type:     "c",
		Major:    DeviceMajor,
		Minor:    DeviceMinor,
		FileMode: api.FileMode(os.FileMode(0o666)),
		Uid:      api.UInt32(uint32(0)),
		Gid:      api.UInt32(uint32(0)),
	})
	adjustment.Linux.Resources = &api.LinuxResources{
		Devices: []*api.LinuxDeviceCgroup{{
			Allow:  true,
			Type:   "c",
			Major:  api.Int64(int64(DeviceMajor)),
			Minor:  api.Int64(int64(DeviceMinor)),
			Access: "rwm",
		}},
	}
	return adjustment
}
