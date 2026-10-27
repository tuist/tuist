// Package kvmdeviceplugin is a kubelet device plugin that advertises
// `devices.tuist.dev/kvm` on Kata runner hosts and, on allocation, hands
// containerd a CDI device that adds /dev/kvm to the container's OCI spec.
//
// That spec entry is the only way to give an unprivileged container a
// device node in Kubernetes. Under Kata the shim passes it to the guest
// agent unchanged, and the agent creates the node with the spec's
// major:minor (10:232, fixed for KVM) and mode. Inside the guest that
// resolves to the guest kernel's own KVM device, so the container drives
// KVM in its microVM, never the host's.
//
// CDI rather than a plain device spec because of the mode: from a device
// spec, containerd copies the host node's mode and group (0660, the host's
// kvm gid), which the runner user cannot open. The CDI spec sets 0666 on
// the container's node only, so the host's /dev/kvm stays as the
// distribution set it.
//
// The devices are not exclusive: KVM is shared by every process that
// opens it, so the advertised count only bounds how many Pods per node
// may ask for it.
package kvmdeviceplugin

import (
	"context"
	"errors"
	"fmt"
	"net"
	"os"
	"path/filepath"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	pluginapi "k8s.io/kubelet/pkg/apis/deviceplugin/v1beta1"
)

const (
	ResourceName = "devices.tuist.dev/kvm"
	DevicePath   = "/dev/kvm"

	// CDIDeviceName is the fully qualified CDI name Allocate returns.
	CDIDeviceName = "tuist.dev/kvm=kvm"
	cdiSpecFile   = "tuist.dev-kvm.json"
)

// cdiSpec gives the container's /dev/kvm the fixed KVM major:minor and a
// mode its non-root user can open. Major and minor are explicit so the
// spec never depends on stat-ing the host node.
const cdiSpec = `{
  "cdiVersion": "0.6.0",
  "kind": "tuist.dev/kvm",
  "devices": [
    {
      "name": "kvm",
      "containerEdits": {
        "deviceNodes": [
          {"path": "/dev/kvm", "type": "c", "major": 10, "minor": 232, "fileMode": 438, "permissions": "rw"}
        ]
      }
    }
  ]
}
`

type Plugin struct {
	// SocketDir is kubelet's device-plugin directory, holding kubelet.sock.
	SocketDir string
	// SocketName is this plugin's socket inside SocketDir.
	SocketName string
	// CDIDir is one of containerd's CDI spec directories (cdi_spec_dirs).
	CDIDir string
	// DevicePath is where the host's /dev/kvm is visible to the plugin.
	DevicePath string
	// Devices is how many allocatable units the node advertises.
	Devices int
	// PollInterval paces the health check and the kubelet-restart watch.
	PollInterval time.Duration
	Logf         func(format string, args ...any)

	pluginapi.UnimplementedDevicePluginServer
}

func (p *Plugin) socketPath() string { return filepath.Join(p.SocketDir, p.SocketName) }

func (p *Plugin) logf(format string, args ...any) {
	if p.Logf != nil {
		p.Logf(format, args...)
	}
}

// Run serves and registers the plugin until ctx ends. kubelet wipes the
// device-plugin directory when it restarts and forgets every plugin, so
// when our socket disappears Run serves a fresh one and registers again.
func (p *Plugin) Run(ctx context.Context) error {
	if err := p.writeCDISpec(); err != nil {
		return err
	}
	for {
		server, err := p.serve()
		if err != nil {
			return err
		}
		if err := p.register(ctx); err != nil {
			server.Stop()
			p.logf("register with kubelet: %v; retrying", err)
			if !sleep(ctx, p.PollInterval) {
				return nil
			}
			continue
		}
		p.logf("registered %s with %d devices", ResourceName, p.Devices)
		p.waitForSocketRemoval(ctx)
		server.Stop()
		if ctx.Err() != nil {
			return nil
		}
		p.logf("plugin socket removed, kubelet restarted; registering again")
	}
}

// writeCDISpec publishes the spec before the plugin registers, so containerd
// can resolve the device the first time kubelet allocates it.
func (p *Plugin) writeCDISpec() error {
	if err := os.MkdirAll(p.CDIDir, 0o755); err != nil {
		return fmt.Errorf("create CDI directory: %w", err)
	}
	path := filepath.Join(p.CDIDir, cdiSpecFile)
	if err := os.WriteFile(path+".tmp", []byte(cdiSpec), 0o644); err != nil {
		return fmt.Errorf("write CDI spec: %w", err)
	}
	return os.Rename(path+".tmp", path)
}

func (p *Plugin) serve() (*grpc.Server, error) {
	if err := os.Remove(p.socketPath()); err != nil && !errors.Is(err, os.ErrNotExist) {
		return nil, fmt.Errorf("remove stale socket: %w", err)
	}
	listener, err := net.Listen("unix", p.socketPath())
	if err != nil {
		return nil, fmt.Errorf("listen on %s: %w", p.socketPath(), err)
	}
	server := grpc.NewServer()
	pluginapi.RegisterDevicePluginServer(server, p)
	go func() { _ = server.Serve(listener) }()
	return server, nil
}

func (p *Plugin) register(ctx context.Context) error {
	conn, err := grpc.NewClient("unix://"+filepath.Join(p.SocketDir, "kubelet.sock"), grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		return err
	}
	defer conn.Close()
	callCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	_, err = pluginapi.NewRegistrationClient(conn).Register(callCtx, &pluginapi.RegisterRequest{
		Version:      pluginapi.Version,
		Endpoint:     p.SocketName,
		ResourceName: ResourceName,
	})
	return err
}

func (p *Plugin) waitForSocketRemoval(ctx context.Context) {
	for sleep(ctx, p.PollInterval) {
		if _, err := os.Stat(p.socketPath()); errors.Is(err, os.ErrNotExist) {
			return
		}
	}
}

// healthy reports whether the host exposes KVM at all. Without it the
// guest kernel would still boot, but its KVM driver would find no
// virtualization extensions and expose no device.
func (p *Plugin) healthy() bool {
	info, err := os.Stat(p.DevicePath)
	return err == nil && info.Mode()&os.ModeCharDevice != 0
}

func (p *Plugin) devices() []*pluginapi.Device {
	health := pluginapi.Unhealthy
	if p.healthy() {
		health = pluginapi.Healthy
	}
	devices := make([]*pluginapi.Device, p.Devices)
	for i := range devices {
		devices[i] = &pluginapi.Device{ID: fmt.Sprintf("kvm-%d", i), Health: health}
	}
	return devices
}

func (p *Plugin) GetDevicePluginOptions(context.Context, *pluginapi.Empty) (*pluginapi.DevicePluginOptions, error) {
	return &pluginapi.DevicePluginOptions{}, nil
}

func (p *Plugin) ListAndWatch(_ *pluginapi.Empty, stream pluginapi.DevicePlugin_ListAndWatchServer) error {
	last := p.healthy()
	if err := stream.Send(&pluginapi.ListAndWatchResponse{Devices: p.devices()}); err != nil {
		return err
	}
	for sleep(stream.Context(), p.PollInterval) {
		if now := p.healthy(); now != last {
			last = now
			if err := stream.Send(&pluginapi.ListAndWatchResponse{Devices: p.devices()}); err != nil {
				return err
			}
		}
	}
	return nil
}

func (p *Plugin) Allocate(_ context.Context, req *pluginapi.AllocateRequest) (*pluginapi.AllocateResponse, error) {
	resp := &pluginapi.AllocateResponse{}
	for range req.ContainerRequests {
		resp.ContainerResponses = append(resp.ContainerResponses, &pluginapi.ContainerAllocateResponse{
			CDIDevices: []*pluginapi.CDIDevice{{Name: CDIDeviceName}},
		})
	}
	return resp, nil
}

func (p *Plugin) GetPreferredAllocation(context.Context, *pluginapi.PreferredAllocationRequest) (*pluginapi.PreferredAllocationResponse, error) {
	return &pluginapi.PreferredAllocationResponse{}, nil
}

func (p *Plugin) PreStartContainer(context.Context, *pluginapi.PreStartContainerRequest) (*pluginapi.PreStartContainerResponse, error) {
	return &pluginapi.PreStartContainerResponse{}, nil
}

func sleep(ctx context.Context, d time.Duration) bool {
	timer := time.NewTimer(d)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return false
	case <-timer.C:
		return true
	}
}
