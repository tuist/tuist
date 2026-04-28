// Package state holds the in-memory mapping between CRI primitives
// (PodSandbox, Container) and the underlying Tart VM names.
//
// CRI's model is two-layered: a Pod has a sandbox (typically a pause
// container reserving namespaces), and one or more containers run
// within it. tart-cri collapses this — one Pod ↔ one Tart VM. The
// "sandbox" is just a state record; the "container" is where the VM
// actually runs.
//
// State is persisted on disk (line-delimited JSON) so a tart-cri
// restart picks up where it left off without losing track of running
// VMs.
package state

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"time"

	runtimeapi "k8s.io/cri-api/pkg/apis/runtime/v1"
)

// Store is the persistent state of all sandboxes + containers tart-cri
// has been told to manage. Methods are safe for concurrent use.
type Store struct {
	mu         sync.RWMutex
	sandboxes  map[string]*Sandbox  // keyed by SandboxID
	containers map[string]*Container // keyed by ContainerID

	path string
}

// Sandbox is the CRI Pod sandbox state.
type Sandbox struct {
	ID         string                          `json:"id"`
	Metadata   *runtimeapi.PodSandboxMetadata  `json:"metadata"`
	State      runtimeapi.PodSandboxState      `json:"state"`
	CreatedAt  time.Time                       `json:"created_at"`
	Labels     map[string]string               `json:"labels"`
	Annotations map[string]string              `json:"annotations"`
	Hostname   string                          `json:"hostname"`
	LogDir     string                          `json:"log_dir"`
	IP         string                          `json:"ip,omitempty"`
}

// Container is the CRI container state. With our one-VM-per-Pod model,
// there's exactly one Container per Sandbox, and ContainerID identifies
// the underlying Tart VM (we use the container ID as the VM name).
type Container struct {
	ID          string                         `json:"id"`
	SandboxID   string                         `json:"sandbox_id"`
	Metadata    *runtimeapi.ContainerMetadata  `json:"metadata"`
	Image       string                         `json:"image"`
	State       runtimeapi.ContainerState      `json:"state"`
	CreatedAt   time.Time                      `json:"created_at"`
	StartedAt   time.Time                      `json:"started_at,omitempty"`
	FinishedAt  time.Time                      `json:"finished_at,omitempty"`
	ExitCode    int32                          `json:"exit_code,omitempty"`
	Reason      string                         `json:"reason,omitempty"`
	Message     string                         `json:"message,omitempty"`
	Labels      map[string]string              `json:"labels"`
	Annotations map[string]string              `json:"annotations"`
	LogPath     string                         `json:"log_path"`
	Envs        []string                       `json:"envs"`
	CPU         int                            `json:"cpu"`
	MemoryMB    int                            `json:"memory_mb"`
}

// New opens (or creates) a Store backed by a state file at path.
func New(path string) (*Store, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, fmt.Errorf("mkdir state dir: %w", err)
	}
	s := &Store{
		sandboxes:  make(map[string]*Sandbox),
		containers: make(map[string]*Container),
		path:       path,
	}
	if err := s.load(); err != nil {
		return nil, err
	}
	return s, nil
}

// PutSandbox inserts or replaces a sandbox.
func (s *Store) PutSandbox(sb *Sandbox) error {
	s.mu.Lock()
	s.sandboxes[sb.ID] = sb
	s.mu.Unlock()
	return s.persist()
}

// GetSandbox returns the sandbox by ID, or nil if not found.
func (s *Store) GetSandbox(id string) *Sandbox {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if sb, ok := s.sandboxes[id]; ok {
		cp := *sb
		return &cp
	}
	return nil
}

// ListSandboxes returns every sandbox.
func (s *Store) ListSandboxes() []*Sandbox {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]*Sandbox, 0, len(s.sandboxes))
	for _, sb := range s.sandboxes {
		cp := *sb
		out = append(out, &cp)
	}
	return out
}

// DeleteSandbox removes a sandbox and any associated containers.
func (s *Store) DeleteSandbox(id string) error {
	s.mu.Lock()
	delete(s.sandboxes, id)
	for cid, c := range s.containers {
		if c.SandboxID == id {
			delete(s.containers, cid)
		}
	}
	s.mu.Unlock()
	return s.persist()
}

// PutContainer inserts or replaces a container.
func (s *Store) PutContainer(c *Container) error {
	s.mu.Lock()
	s.containers[c.ID] = c
	s.mu.Unlock()
	return s.persist()
}

// GetContainer returns the container by ID, or nil if not found.
func (s *Store) GetContainer(id string) *Container {
	s.mu.RLock()
	defer s.mu.RUnlock()
	if c, ok := s.containers[id]; ok {
		cp := *c
		return &cp
	}
	return nil
}

// ListContainers returns every container, optionally filtered by
// sandbox ID.
func (s *Store) ListContainers(sandboxID string) []*Container {
	s.mu.RLock()
	defer s.mu.RUnlock()
	out := make([]*Container, 0, len(s.containers))
	for _, c := range s.containers {
		if sandboxID != "" && c.SandboxID != sandboxID {
			continue
		}
		cp := *c
		out = append(out, &cp)
	}
	return out
}

// DeleteContainer removes a container.
func (s *Store) DeleteContainer(id string) error {
	s.mu.Lock()
	delete(s.containers, id)
	s.mu.Unlock()
	return s.persist()
}

func (s *Store) persist() error {
	s.mu.RLock()
	defer s.mu.RUnlock()

	tmp, err := os.CreateTemp(filepath.Dir(s.path), ".tart-cri.state.*.tmp")
	if err != nil {
		return err
	}
	defer os.Remove(tmp.Name())

	enc := json.NewEncoder(tmp)
	for _, sb := range s.sandboxes {
		if err := enc.Encode(record{Kind: "sandbox", Sandbox: sb}); err != nil {
			tmp.Close()
			return err
		}
	}
	for _, c := range s.containers {
		if err := enc.Encode(record{Kind: "container", Container: c}); err != nil {
			tmp.Close()
			return err
		}
	}
	if err := tmp.Close(); err != nil {
		return err
	}
	return os.Rename(tmp.Name(), s.path)
}

func (s *Store) load() error {
	f, err := os.Open(s.path)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	defer f.Close()

	dec := json.NewDecoder(f)
	for {
		var r record
		if err := dec.Decode(&r); err != nil {
			if err == io.EOF {
				return nil
			}
			return err
		}
		switch r.Kind {
		case "sandbox":
			if r.Sandbox != nil {
				s.sandboxes[r.Sandbox.ID] = r.Sandbox
			}
		case "container":
			if r.Container != nil {
				s.containers[r.Container.ID] = r.Container
			}
		}
	}
}

type record struct {
	Kind      string     `json:"kind"`
	Sandbox   *Sandbox   `json:"sandbox,omitempty"`
	Container *Container `json:"container,omitempty"`
}
