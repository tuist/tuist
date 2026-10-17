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

	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
	"github.com/tuist/tuist/infra/sandboxd/internal/template"
)

const MetadataFile = "metadata.json"

// Metadata is the on-disk record of one sandbox, kept in its jail root.
type Metadata struct {
	ID          string    `json:"id"`
	Template    string    `json:"template"`
	Tag         string    `json:"tag"`
	VCPUs       int       `json:"vcpus"`
	MemoryMB    int       `json:"memory_mb"`
	WorkspaceGB int       `json:"workspace_gb"`
	Hostname    string    `json:"hostname"`
	State       string    `json:"state"`
	Slot        int       `json:"slot"`
	Generation  int       `json:"generation"`
	ColdBoot    bool      `json:"cold_boot,omitempty"`
	CreatedAt   time.Time `json:"created_at"`
	UpdatedAt   time.Time `json:"updated_at"`
	Error       string    `json:"error,omitempty"`
}

func (m Metadata) Shape() template.Shape {
	return template.Shape{VCPUs: m.VCPUs, MemoryMB: m.MemoryMB}
}

func (m Metadata) Info(workerRunning bool) protocol.SandboxInfo {
	return protocol.SandboxInfo{
		ID: m.ID, State: m.State, Template: m.Template, TemplateTag: m.Tag,
		VCPUs: m.VCPUs, MemoryMB: m.MemoryMB, WorkspaceGB: m.WorkspaceGB, Hostname: m.Hostname,
		WorkerRunning: workerRunning, ColdBoot: m.ColdBoot, Generation: m.Generation, CreatedAt: m.CreatedAt, Error: m.Error,
	}
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
