package firecracker

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"
)

type recorded struct {
	Method string
	Path   string
	Body   map[string]any
}

func startAPI(t *testing.T, handler func(rec recorded, w http.ResponseWriter)) (*Client, *[]recorded) {
	t.Helper()
	dir, err := os.MkdirTemp("", "fcapi")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	sock := filepath.Join(dir, "api.sock")
	listener, err := net.Listen("unix", sock)
	if err != nil {
		t.Fatal(err)
	}
	var mu sync.Mutex
	var calls []recorded
	server := httptest.NewUnstartedServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		rec := recorded{Method: r.Method, Path: r.URL.Path}
		data, _ := io.ReadAll(r.Body)
		if len(data) > 0 {
			_ = json.Unmarshal(data, &rec.Body)
		}
		mu.Lock()
		calls = append(calls, rec)
		mu.Unlock()
		handler(rec, w)
	}))
	server.Listener = listener
	server.Start()
	t.Cleanup(server.Close)
	return NewClient(sock), &calls
}

func TestSnapshotAndConfigRequests(t *testing.T) {
	client, calls := startAPI(t, func(rec recorded, w http.ResponseWriter) {
		if rec.Method == http.MethodGet && rec.Path == "/" {
			_, _ = w.Write([]byte(`{"app_name":"Firecracker","id":"x","state":"Running","vmm_version":"1.16.1"}`))
			return
		}
		w.WriteHeader(http.StatusNoContent)
	})
	ctx := context.Background()
	if err := client.WaitReady(ctx, time.Second); err != nil {
		t.Fatal(err)
	}
	if err := client.PutMachineConfig(ctx, MachineConfig{VCPUCount: 2, MemSizeMiB: 4096}); err != nil {
		t.Fatal(err)
	}
	if err := client.PutBootSource(ctx, BootSource{KernelImagePath: KernelPath, BootArgs: BootArgs([]string{"10.0.0.10"}, "sandbox")}); err != nil {
		t.Fatal(err)
	}
	if err := client.PutDrive(ctx, Drive{DriveID: RootDriveID, PathOnHost: RootfsPath, IsRootDevice: true}); err != nil {
		t.Fatal(err)
	}
	if err := client.PutNetworkInterface(ctx, NetworkInterface{IfaceID: IfaceID, GuestMAC: GuestMAC, HostDevName: TapName}); err != nil {
		t.Fatal(err)
	}
	if err := client.PutVsock(ctx, Vsock{GuestCID: GuestCID, UDSPath: VsockPath}); err != nil {
		t.Fatal(err)
	}
	if err := client.InstanceStart(ctx); err != nil {
		t.Fatal(err)
	}
	if err := client.PatchVMState(ctx, VMPaused); err != nil {
		t.Fatal(err)
	}
	if err := client.CreateSnapshot(ctx, SnapshotCreateParams{SnapshotPath: "/snapshot.new", MemFilePath: "/mem.new"}); err != nil {
		t.Fatal(err)
	}
	if err := client.LoadSnapshot(ctx, SnapshotLoadParams{SnapshotPath: SnapshotPath, MemBackend: MemoryBackend{BackendPath: MemPath}, ResumeVM: true,
		VsockOverride: &VsockOverride{UDSPath: VsockPath}, NetworkOverrides: []NetworkOverride{{IfaceID: IfaceID, HostDevName: TapName}}}); err != nil {
		t.Fatal(err)
	}
	if err := client.PatchDrive(ctx, DrivePatch{DriveID: WorkspaceDriveID, PathOnHost: WorkspacePath}); err != nil {
		t.Fatal(err)
	}

	byPath := map[string]recorded{}
	for _, call := range *calls {
		byPath[call.Method+" "+call.Path] = call
	}
	mc := byPath["PUT /machine-config"].Body
	if mc["vcpu_count"] != float64(2) || mc["mem_size_mib"] != float64(4096) || mc["smt"] != false || mc["track_dirty_pages"] != false {
		t.Fatalf("machine config body %v", mc)
	}
	boot := byPath["PUT /boot-source"].Body
	if boot["kernel_image_path"] != "/vmlinux" {
		t.Fatalf("boot source body %v", boot)
	}
	wantArgs := "console=ttyS0 reboot=k panic=1 pci=off root=/dev/vda rw rootfstype=ext4 init=/sbin/sbx-init loglevel=4 sbx.dns=10.0.0.10 sbx.hostname=sandbox"
	if boot["boot_args"] != wantArgs {
		t.Fatalf("boot args %q", boot["boot_args"])
	}
	drive := byPath["PUT /drives/rootfs"].Body
	if drive["path_on_host"] != "/rootfs.ext4" || drive["is_root_device"] != true || drive["is_read_only"] != false {
		t.Fatalf("drive body %v", drive)
	}
	iface := byPath["PUT /network-interfaces/eth0"].Body
	if iface["guest_mac"] != GuestMAC || iface["host_dev_name"] != "tap0" {
		t.Fatalf("iface body %v", iface)
	}
	vsock := byPath["PUT /vsock"].Body
	if vsock["guest_cid"] != float64(3) || vsock["uds_path"] != "/v.sock" {
		t.Fatalf("vsock body %v", vsock)
	}
	if byPath["PUT /actions"].Body["action_type"] != "InstanceStart" {
		t.Fatal("instance start body")
	}
	if byPath["PATCH /vm"].Body["state"] != "Paused" {
		t.Fatal("vm state body")
	}
	create := byPath["PUT /snapshot/create"].Body
	if create["snapshot_type"] != "Full" || create["snapshot_path"] != "/snapshot.new" || create["mem_file_path"] != "/mem.new" {
		t.Fatalf("snapshot create body %v", create)
	}
	load := byPath["PUT /snapshot/load"].Body
	backend := load["mem_backend"].(map[string]any)
	if load["snapshot_path"] != "/snapshot" || backend["backend_type"] != "File" || backend["backend_path"] != "/mem" || load["resume_vm"] != true {
		t.Fatalf("snapshot load body %v", load)
	}
	if _, present := load["track_dirty_pages"]; present {
		t.Fatalf("track_dirty_pages should be omitted when false: %v", load)
	}
	if load["vsock_override"].(map[string]any)["uds_path"] != "/v.sock" {
		t.Fatalf("vsock override %v", load)
	}
	overrides := load["network_overrides"].([]any)
	if overrides[0].(map[string]any)["host_dev_name"] != "tap0" {
		t.Fatalf("network overrides %v", load)
	}
	patch := byPath["PATCH /drives/workspace"].Body
	if patch["drive_id"] != "workspace" || patch["path_on_host"] != "/workspace.ext4" {
		t.Fatalf("drive patch %v", patch)
	}
}

func TestAPIErrorCarriesFaultMessage(t *testing.T) {
	client, _ := startAPI(t, func(rec recorded, w http.ResponseWriter) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = w.Write([]byte(`{"fault_message":"The requested operation is not supported after starting the microVM."}`))
	})
	err := client.InstanceStart(context.Background())
	var apiErr *APIError
	if !errors.As(err, &apiErr) {
		t.Fatalf("expected APIError, got %v", err)
	}
	if apiErr.Status != 400 || apiErr.Message != "The requested operation is not supported after starting the microVM." {
		t.Fatalf("unexpected error %+v", apiErr)
	}
}

func TestWaitReadyTimesOutWithoutSocket(t *testing.T) {
	client := NewClient(filepath.Join(t.TempDir(), "missing.sock"))
	start := time.Now()
	err := client.WaitReady(context.Background(), 150*time.Millisecond)
	if err == nil {
		t.Fatal("expected timeout")
	}
	if time.Since(start) > 2*time.Second {
		t.Fatalf("waited too long: %s", time.Since(start))
	}
}

func TestParseVersionOutput(t *testing.T) {
	if got := ParseVersionOutput("Firecracker v1.16.1\nTool to start..."); got != "v1.16.1" {
		t.Fatalf("got %q", got)
	}
	if got := ParseVersionOutput("garbage"); got != "garbage" {
		t.Fatalf("got %q", got)
	}
}
