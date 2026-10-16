package kvmdeviceplugin

import (
	"context"
	"encoding/json"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	pluginapi "k8s.io/kubelet/pkg/apis/deviceplugin/v1beta1"

	"github.com/tuist/tuist/infra/runners-controller/internal/podtemplate"
)

type fakeKubelet struct {
	pluginapi.UnimplementedRegistrationServer
	requests chan *pluginapi.RegisterRequest
}

func (k *fakeKubelet) Register(_ context.Context, req *pluginapi.RegisterRequest) (*pluginapi.Empty, error) {
	k.requests <- req
	return &pluginapi.Empty{}, nil
}

// Unix socket paths are capped near 100 bytes, which t.TempDir() exceeds on macOS.
func shortTempDir(t *testing.T) string {
	t.Helper()
	dir, err := os.MkdirTemp("/tmp", "kvmdp")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	return dir
}

func startFakeKubelet(t *testing.T, dir string) *fakeKubelet {
	t.Helper()
	listener, err := net.Listen("unix", filepath.Join(dir, "kubelet.sock"))
	if err != nil {
		t.Fatal(err)
	}
	kubelet := &fakeKubelet{requests: make(chan *pluginapi.RegisterRequest, 4)}
	server := grpc.NewServer()
	pluginapi.RegisterRegistrationServer(server, kubelet)
	go func() { _ = server.Serve(listener) }()
	t.Cleanup(server.Stop)
	return kubelet
}

func dialPlugin(t *testing.T, path string) pluginapi.DevicePluginClient {
	t.Helper()
	conn, err := grpc.NewClient("unix://"+path, grpc.WithTransportCredentials(insecure.NewCredentials()))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	return pluginapi.NewDevicePluginClient(conn)
}

func awaitRegistration(t *testing.T, kubelet *fakeKubelet) *pluginapi.RegisterRequest {
	t.Helper()
	select {
	case req := <-kubelet.requests:
		return req
	case <-time.After(5 * time.Second):
		t.Fatal("plugin never registered with kubelet")
		return nil
	}
}

func TestResourceNameMatchesWhatRunnerPodsRequest(t *testing.T) {
	if ResourceName != string(podtemplate.KVMResourceName) {
		t.Fatalf("plugin advertises %q but runner Pods request %q", ResourceName, podtemplate.KVMResourceName)
	}
}

func TestPluginRegistersAndAllocatesKVM(t *testing.T) {
	dir := shortTempDir(t)
	kubelet := startFakeKubelet(t, dir)
	// /dev/null stands in for /dev/kvm: what health checks is a character device.
	plugin := &Plugin{SocketDir: dir, SocketName: "tuist-kvm.sock", CDIDir: filepath.Join(dir, "cdi"), DevicePath: "/dev/null", Devices: 3, PollInterval: 50 * time.Millisecond}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go func() { _ = plugin.Run(ctx) }()

	req := awaitRegistration(t, kubelet)
	if req.ResourceName != ResourceName || req.Endpoint != "tuist-kvm.sock" || req.Version != pluginapi.Version {
		t.Fatalf("Register request = %+v", req)
	}

	client := dialPlugin(t, filepath.Join(dir, "tuist-kvm.sock"))
	stream, err := client.ListAndWatch(ctx, &pluginapi.Empty{})
	if err != nil {
		t.Fatal(err)
	}
	list, err := stream.Recv()
	if err != nil {
		t.Fatal(err)
	}
	if len(list.Devices) != 3 {
		t.Fatalf("advertised %d devices, want 3", len(list.Devices))
	}
	for _, d := range list.Devices {
		if d.Health != pluginapi.Healthy {
			t.Fatalf("device %s health = %s, want Healthy", d.ID, d.Health)
		}
	}

	resp, err := client.Allocate(ctx, &pluginapi.AllocateRequest{ContainerRequests: []*pluginapi.ContainerAllocateRequest{{DevicesIDs: []string{"kvm-0"}}}})
	if err != nil {
		t.Fatal(err)
	}
	if len(resp.ContainerResponses) != 1 {
		t.Fatalf("Allocate response = %+v, want one response for one container", resp)
	}
	container := resp.ContainerResponses[0]
	if len(container.CDIDevices) != 1 || container.CDIDevices[0].Name != CDIDeviceName {
		t.Fatalf("allocated CDI devices = %+v, want [%s]", container.CDIDevices, CDIDeviceName)
	}
	// A plain device spec would make containerd copy the host node's
	// 0660 mode, which the runner user cannot open.
	if len(container.Devices) != 0 {
		t.Fatalf("allocated device specs = %+v, want none beside the CDI device", container.Devices)
	}
}

func TestCDISpecGivesTheContainerAnOpenableKVMNode(t *testing.T) {
	dir := shortTempDir(t)
	kubelet := startFakeKubelet(t, dir)
	cdiDir := filepath.Join(dir, "cdi")
	plugin := &Plugin{SocketDir: dir, SocketName: "tuist-kvm.sock", CDIDir: cdiDir, DevicePath: "/dev/null", Devices: 1, PollInterval: 50 * time.Millisecond}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go func() { _ = plugin.Run(ctx) }()
	awaitRegistration(t, kubelet)

	data, err := os.ReadFile(filepath.Join(cdiDir, "tuist.dev-kvm.json"))
	if err != nil {
		t.Fatalf("CDI spec not written before registration: %v", err)
	}
	var spec struct {
		Kind    string `json:"kind"`
		Devices []struct {
			Name           string `json:"name"`
			ContainerEdits struct {
				DeviceNodes []struct {
					Path        string `json:"path"`
					Type        string `json:"type"`
					Major       int64  `json:"major"`
					Minor       int64  `json:"minor"`
					FileMode    uint32 `json:"fileMode"`
					Permissions string `json:"permissions"`
				} `json:"deviceNodes"`
			} `json:"containerEdits"`
		} `json:"devices"`
	}
	if err := json.Unmarshal(data, &spec); err != nil {
		t.Fatalf("CDI spec is not valid JSON: %v", err)
	}
	if spec.Kind+"="+spec.Devices[0].Name != CDIDeviceName {
		t.Fatalf("CDI spec names %s=%s, Allocate returns %s", spec.Kind, spec.Devices[0].Name, CDIDeviceName)
	}
	node := spec.Devices[0].ContainerEdits.DeviceNodes[0]
	if node.Path != "/dev/kvm" || node.Type != "c" || node.Major != 10 || node.Minor != 232 || node.FileMode != 0o666 || node.Permissions != "rw" {
		t.Fatalf("CDI device node = %+v, want /dev/kvm c 10:232 0666 rw", node)
	}
}

func TestPluginReportsUnhealthyWithoutAHostDevice(t *testing.T) {
	dir := shortTempDir(t)
	notADevice := filepath.Join(dir, "kvm")
	if err := os.WriteFile(notADevice, nil, 0o600); err != nil {
		t.Fatal(err)
	}
	plugin := &Plugin{DevicePath: notADevice, Devices: 2}
	for _, d := range plugin.devices() {
		if d.Health != pluginapi.Unhealthy {
			t.Fatalf("device %s health = %s on a host without KVM, want Unhealthy", d.ID, d.Health)
		}
	}
}

// kubelet deletes every plugin socket when it restarts and only knows about
// plugins that register again afterwards.
func TestPluginRegistersAgainAfterKubeletRestart(t *testing.T) {
	dir := shortTempDir(t)
	kubelet := startFakeKubelet(t, dir)
	plugin := &Plugin{SocketDir: dir, SocketName: "tuist-kvm.sock", CDIDir: filepath.Join(dir, "cdi"), DevicePath: "/dev/null", Devices: 1, PollInterval: 50 * time.Millisecond}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go func() { _ = plugin.Run(ctx) }()

	awaitRegistration(t, kubelet)
	if err := os.Remove(filepath.Join(dir, "tuist-kvm.sock")); err != nil {
		t.Fatal(err)
	}
	awaitRegistration(t, kubelet)
	if _, err := os.Stat(filepath.Join(dir, "tuist-kvm.sock")); err != nil {
		t.Fatalf("plugin socket not served again: %v", err)
	}
}
