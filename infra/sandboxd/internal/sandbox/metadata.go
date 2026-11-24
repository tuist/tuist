package sandbox

import (
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	"github.com/tuist/tuist/infra/sandboxd/internal/template"
)

const MetadataFile = "metadata.json"

// Metadata is the on-disk record of one sandbox, kept in its jail root.
type Metadata struct {
	ID          string `json:"id"`
	Template    string `json:"template"`
	Tag         string `json:"tag"`
	VCPUs       int    `json:"vcpus"`
	MemoryMB    int    `json:"memory_mb"`
	WorkspaceGB int    `json:"workspace_gb"`
	Hostname    string `json:"hostname"`
	State       string `json:"state"`
	Slot        int    `json:"slot"`
	Generation  int    `json:"generation"`
	ColdBoot    bool   `json:"cold_boot,omitempty"`
	// CPUGuaranteeMilli weighs the VM's cgroup; zero, as in metadata from
	// before guarantees, is protocol.DefaultCPUGuaranteeMilli.
	CPUGuaranteeMilli uint64 `json:"cpu_guarantee_milli,omitempty"`
	// FirecrackerVersion wrote the memory image beside the disks; another
	// version cannot load it, so recovery turns a mismatch into a cold boot.
	FirecrackerVersion string `json:"firecracker_version,omitempty"`
	// DisksSynced records that the last pause flushed the guest page cache
	// to the disks, so they can be saved without the memory image.
	DisksSynced bool `json:"disks_synced,omitempty"`
	// PausedCPUMs is the VM's CPU time at its last pause, which reports
	// carry while it stays paused so the server bills a pause it learns of
	// from a report (a daemon shutdown's) up to it. Zero when unread.
	PausedCPUMs int64 `json:"paused_cpu_ms,omitempty"`
	// RootfsGrowPending records that the rootfs file was grown to its
	// template's size and the guest has not grown its filesystem yet.
	RootfsGrowPending bool      `json:"rootfs_grow_pending,omitempty"`
	CreatedAt         time.Time `json:"created_at"`
	UpdatedAt         time.Time `json:"updated_at"`
	Error             string    `json:"error,omitempty"`

	// CacheImage names the cache image cloned into the jail at create. Its
	// clone is never archived, so a memory image that has it mounted must
	// not travel either. Empty for no cache or the template's placeholder.
	CacheImage string `json:"cache_image,omitempty"`

	// Handover names the Firecracker process a daemon left running in the
	// vmm container for the next daemon to attach (step 2b), with State
	// still running. Without it, or when vmm no longer holds exactly that
	// process, a running sandbox lost its VM.
	Handover *Handover `json:"handover,omitempty"`
}

// Handover is a process by pid and start time, which together name one
// process: a reused pid starts later.
type Handover struct {
	PID   int    `json:"pid"`
	Start uint64 `json:"start"`
}

func (m Metadata) Shape() template.Shape {
	return template.Shape{VCPUs: m.VCPUs, MemoryMB: m.MemoryMB}
}

func (m Metadata) Info(workerRunning bool) protocol.SandboxInfo {
	info := protocol.SandboxInfo{
		ID: m.ID, State: m.State, Template: m.Template, TemplateTag: m.Tag,
		VCPUs: m.VCPUs, MemoryMB: m.MemoryMB, WorkspaceGB: m.WorkspaceGB, Hostname: m.Hostname,
		WorkerRunning: workerRunning, ColdBoot: m.ColdBoot, Generation: m.Generation, CreatedAt: m.CreatedAt, Error: m.Error,
	}
	if m.State == protocol.StatePaused {
		info.CPUMs = m.PausedCPUMs
	}
	return info
}

func LoadMetadata(root string) (Metadata, error) {
	data, err := readNoFollow(filepath.Join(root, MetadataFile))
	if err != nil {
		return Metadata{}, err
	}
	var m Metadata
	if err := json.Unmarshal(data, &m); err != nil {
		return Metadata{}, fmt.Errorf("decoding %s: %w", filepath.Join(root, MetadataFile), err)
	}
	if m.ID == "" {
		return Metadata{}, fmt.Errorf("%s has no id", filepath.Join(root, MetadataFile))
	}
	return m, nil
}

// Save writes the metadata atomically (temp file + rename). The jail root
// belongs to the jailed Firecracker's uid, so neither the temp file nor the
// metadata file is ever opened through a symlink; rename replaces a planted
// link rather than following it.
func (m *Metadata) Save(root string) error {
	m.UpdatedAt = time.Now().UTC()
	data, err := json.MarshalIndent(m, "", "  ")
	if err != nil {
		return err
	}
	path := filepath.Join(root, MetadataFile)
	tmp := path + ".tmp"
	if err := os.Remove(tmp); err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	file, err := os.OpenFile(tmp, os.O_CREATE|os.O_EXCL|os.O_WRONLY|syscall.O_NOFOLLOW, 0o644)
	if err != nil {
		return err
	}
	if _, err := file.Write(append(data, '\n')); err != nil {
		file.Close()
		return err
	}
	if err := file.Close(); err != nil {
		return err
	}
	return os.Rename(tmp, path)
}

func readNoFollow(path string) ([]byte, error) {
	file, err := os.OpenFile(path, os.O_RDONLY|syscall.O_NOFOLLOW, 0)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	return io.ReadAll(file)
}
