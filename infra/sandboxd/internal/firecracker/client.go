// Package firecracker is a minimal client for the Firecracker v1.16 HTTP API
// over its unix socket. Field names follow src/firecracker/swagger at that
// tag; only the endpoints sandboxd uses are wrapped.
package firecracker

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os/exec"
	"strings"
	"time"
)

// In-jail paths and identifiers. Every sandbox and template build uses the
// same ones so a snapshot restores into any jail directory.
const (
	KernelPath    = "/vmlinux"
	RootfsPath    = "/rootfs.ext4"
	WorkspacePath = "/workspace.ext4"
	MemPath       = "/mem"
	SnapshotPath  = "/snapshot"
	VsockPath     = "/v.sock"
	APISocketPath = "/run/firecracker.socket"

	RootDriveID      = "rootfs"
	WorkspaceDriveID = "workspace"
	IfaceID          = "eth0"
	TapName          = "tap0"
	GuestMAC         = "06:00:AC:10:00:02"
	GuestCID         = 3
	AgentPort        = 5000
)

// BootArgs builds the kernel command line for a template boot. The serial
// console stays on (loglevel 4) so boot problems show up in firecracker.log.
func BootArgs(dns []string, hostname string) string {
	args := "console=ttyS0 reboot=k panic=1 pci=off root=/dev/vda rw rootfstype=ext4 init=/sbin/sbx-init loglevel=4"
	if len(dns) > 0 {
		args += " sbx.dns=" + strings.Join(dns, ",")
	}
	if hostname != "" {
		args += " sbx.hostname=" + hostname
	}
	return args
}

type MachineConfig struct {
	VCPUCount       int  `json:"vcpu_count"`
	MemSizeMiB      int  `json:"mem_size_mib"`
	SMT             bool `json:"smt"`
	TrackDirtyPages bool `json:"track_dirty_pages"`
}

type BootSource struct {
	KernelImagePath string `json:"kernel_image_path"`
	BootArgs        string `json:"boot_args,omitempty"`
	InitrdPath      string `json:"initrd_path,omitempty"`
}

type Drive struct {
	DriveID      string `json:"drive_id"`
	PathOnHost   string `json:"path_on_host"`
	IsRootDevice bool   `json:"is_root_device"`
	IsReadOnly   bool   `json:"is_read_only"`
	CacheType    string `json:"cache_type,omitempty"`
	IOEngine     string `json:"io_engine,omitempty"`
}

// DrivePatch is the body of PATCH /drives/{id}: re-pointing (or re-reading)
// the backing file makes Firecracker notify the guest of the new capacity.
type DrivePatch struct {
	DriveID    string `json:"drive_id"`
	PathOnHost string `json:"path_on_host"`
}

type NetworkInterface struct {
	IfaceID     string `json:"iface_id"`
	GuestMAC    string `json:"guest_mac,omitempty"`
	HostDevName string `json:"host_dev_name"`
}

type Vsock struct {
	GuestCID int    `json:"guest_cid"`
	UDSPath  string `json:"uds_path"`
}

type Balloon struct {
	AmountMiB             int  `json:"amount_mib"`
	DeflateOnOOM          bool `json:"deflate_on_oom"`
	StatsPollingIntervalS int  `json:"stats_polling_interval_s"`
}

type Logger struct {
	LogPath       string `json:"log_path"`
	Level         string `json:"level,omitempty"`
	ShowLevel     bool   `json:"show_level"`
	ShowLogOrigin bool   `json:"show_log_origin"`
}

type Metrics struct {
	MetricsPath string `json:"metrics_path"`
}

type VMState string

const (
	VMPaused  VMState = "Paused"
	VMResumed VMState = "Resumed"
)

type SnapshotType string

const (
	SnapshotFull SnapshotType = "Full"
	SnapshotDiff SnapshotType = "Diff"
)

type SnapshotCreateParams struct {
	SnapshotType SnapshotType `json:"snapshot_type"`
	SnapshotPath string       `json:"snapshot_path"`
	MemFilePath  string       `json:"mem_file_path"`
}

type MemoryBackend struct {
	BackendType string `json:"backend_type"`
	BackendPath string `json:"backend_path"`
}

type NetworkOverride struct {
	IfaceID     string `json:"iface_id"`
	HostDevName string `json:"host_dev_name"`
}

type VsockOverride struct {
	UDSPath string `json:"uds_path"`
}

type SnapshotLoadParams struct {
	SnapshotPath     string            `json:"snapshot_path"`
	MemBackend       MemoryBackend     `json:"mem_backend"`
	ResumeVM         bool              `json:"resume_vm"`
	TrackDirtyPages  bool              `json:"track_dirty_pages,omitempty"`
	NetworkOverrides []NetworkOverride `json:"network_overrides,omitempty"`
	VsockOverride    *VsockOverride    `json:"vsock_override,omitempty"`
}

type InstanceInfo struct {
	AppName    string `json:"app_name"`
	ID         string `json:"id"`
	State      string `json:"state"`
	VMMVersion string `json:"vmm_version"`
}

// APIError is a non-2xx answer from the API, carrying Firecracker's
// fault_message.
type APIError struct {
	Status  int
	Method  string
	Path    string
	Message string
}

func (e *APIError) Error() string {
	return fmt.Sprintf("firecracker %s %s: %d %s", e.Method, e.Path, e.Status, e.Message)
}

type Client struct {
	http *http.Client
	sock string
}

func NewClient(socketPath string) *Client {
	dialer := &net.Dialer{}
	return &Client{
		sock: socketPath,
		http: &http.Client{
			Transport: &http.Transport{
				DialContext: func(ctx context.Context, _, _ string) (net.Conn, error) {
					return dialer.DialContext(ctx, "unix", socketPath)
				},
				DisableKeepAlives: true,
			},
		},
	}
}

func (c *Client) SocketPath() string { return c.sock }

func (c *Client) do(ctx context.Context, method, path string, body any, out any) error {
	var reader io.Reader
	if body != nil {
		data, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("encoding %s %s body: %w", method, path, err)
		}
		reader = bytes.NewReader(data)
	}
	req, err := http.NewRequestWithContext(ctx, method, "http://firecracker"+path, reader)
	if err != nil {
		return err
	}
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := c.http.Do(req)
	if err != nil {
		return fmt.Errorf("firecracker %s %s: %w", method, path, err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return fmt.Errorf("firecracker %s %s: reading response: %w", method, path, err)
	}
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		var fault struct {
			FaultMessage string `json:"fault_message"`
		}
		_ = json.Unmarshal(data, &fault)
		msg := fault.FaultMessage
		if msg == "" {
			msg = strings.TrimSpace(string(data))
		}
		return &APIError{Status: resp.StatusCode, Method: method, Path: path, Message: msg}
	}
	if out != nil && len(data) > 0 {
		if err := json.Unmarshal(data, out); err != nil {
			return fmt.Errorf("firecracker %s %s: decoding response: %w", method, path, err)
		}
	}
	return nil
}

func (c *Client) Info(ctx context.Context) (InstanceInfo, error) {
	var info InstanceInfo
	err := c.do(ctx, http.MethodGet, "/", nil, &info)
	return info, err
}

func (c *Client) Version(ctx context.Context) (string, error) {
	var out struct {
		FirecrackerVersion string `json:"firecracker_version"`
	}
	if err := c.do(ctx, http.MethodGet, "/version", nil, &out); err != nil {
		return "", err
	}
	return out.FirecrackerVersion, nil
}

// WaitReady polls GET / until the API socket answers or the timeout passes.
func (c *Client) WaitReady(ctx context.Context, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	var last error
	for {
		attempt, cancel := context.WithTimeout(ctx, 2*time.Second)
		_, last = c.Info(attempt)
		cancel()
		if last == nil {
			return nil
		}
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if time.Now().After(deadline) {
			return fmt.Errorf("firecracker API socket %s not ready after %s: %w", c.sock, timeout, last)
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(20 * time.Millisecond):
		}
	}
}

func (c *Client) PutMachineConfig(ctx context.Context, cfg MachineConfig) error {
	return c.do(ctx, http.MethodPut, "/machine-config", cfg, nil)
}

func (c *Client) PutBootSource(ctx context.Context, src BootSource) error {
	return c.do(ctx, http.MethodPut, "/boot-source", src, nil)
}

func (c *Client) PutDrive(ctx context.Context, drive Drive) error {
	return c.do(ctx, http.MethodPut, "/drives/"+drive.DriveID, drive, nil)
}

func (c *Client) PatchDrive(ctx context.Context, patch DrivePatch) error {
	return c.do(ctx, http.MethodPatch, "/drives/"+patch.DriveID, patch, nil)
}

func (c *Client) PutNetworkInterface(ctx context.Context, iface NetworkInterface) error {
	return c.do(ctx, http.MethodPut, "/network-interfaces/"+iface.IfaceID, iface, nil)
}

func (c *Client) PutVsock(ctx context.Context, vsock Vsock) error {
	return c.do(ctx, http.MethodPut, "/vsock", vsock, nil)
}

func (c *Client) PutBalloon(ctx context.Context, balloon Balloon) error {
	return c.do(ctx, http.MethodPut, "/balloon", balloon, nil)
}

func (c *Client) PutLogger(ctx context.Context, logger Logger) error {
	return c.do(ctx, http.MethodPut, "/logger", logger, nil)
}

func (c *Client) PutMetrics(ctx context.Context, metrics Metrics) error {
	return c.do(ctx, http.MethodPut, "/metrics", metrics, nil)
}

func (c *Client) InstanceStart(ctx context.Context) error {
	return c.do(ctx, http.MethodPut, "/actions", map[string]string{"action_type": "InstanceStart"}, nil)
}

func (c *Client) PatchVMState(ctx context.Context, state VMState) error {
	return c.do(ctx, http.MethodPatch, "/vm", map[string]VMState{"state": state}, nil)
}

func (c *Client) CreateSnapshot(ctx context.Context, params SnapshotCreateParams) error {
	if params.SnapshotType == "" {
		params.SnapshotType = SnapshotFull
	}
	return c.do(ctx, http.MethodPut, "/snapshot/create", params, nil)
}

func (c *Client) LoadSnapshot(ctx context.Context, params SnapshotLoadParams) error {
	if params.MemBackend.BackendType == "" {
		params.MemBackend.BackendType = "File"
	}
	return c.do(ctx, http.MethodPut, "/snapshot/load", params, nil)
}

// BinaryVersion runs `firecracker --version` and returns the "vX.Y.Z" token
// from its first line.
func BinaryVersion(ctx context.Context, bin string) (string, error) {
	out, err := exec.CommandContext(ctx, bin, "--version").Output()
	if err != nil {
		return "", fmt.Errorf("%s --version: %w", bin, err)
	}
	return ParseVersionOutput(string(out)), nil
}

func ParseVersionOutput(out string) string {
	first, _, _ := strings.Cut(out, "\n")
	for _, field := range strings.Fields(first) {
		if strings.HasPrefix(field, "v") && strings.Count(field, ".") >= 2 {
			return field
		}
	}
	return strings.TrimSpace(first)
}

var ErrNotReady = errors.New("firecracker API not ready")
