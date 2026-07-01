package podagent

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"time"

	corev1 "k8s.io/api/core/v1"
)

// RunnerCacheEndpointFile is the marker tart-kubelet writes into the per-VM
// share once the account's host Kura is up. dispatch-poll.sh reads it and
// exports it as TUIST_CACHE_ENDPOINT, so the job's cache client talks to the
// host Kura over the vmnet bridge. This replaces #11580's cache clone-in: the
// share carries an endpoint, not a copy of the cache.
const RunnerCacheEndpointFile = ".tuist-cache-endpoint"

// WriteEndpoint writes http://<hostAddr>:<port> into the per-VM share. hostAddr
// is the host's vmnet-bridge IP (the VM's gateway), resolved by the reconciler
// from the VM IP; port is the account's host Kura cache port.
func WriteEndpoint(shareDir, hostAddr string, port int) error {
	url := fmt.Sprintf("http://%s:%d", hostAddr, port)
	if err := os.WriteFile(filepath.Join(shareDir, RunnerCacheEndpointFile), []byte(url+"\n"), 0o644); err != nil {
		return fmt.Errorf("write cache endpoint marker: %w", err)
	}
	return nil
}

// HostKuraManager runs one persistent Kura process per account on the Mac host
// (Option A). Each process serves that account's cache volume
// (<root>/accounts/<id>/current) to the account's runner VMs over the vmnet
// bridge, and replicates with the account's EM peer over the PN. Unlike the
// ephemeral in-VM Kura, these processes survive across one-shot job VMs, which is
// what lets idle freshen/push work.
//
// The manager owns process lifecycle and port allocation only; it is deliberately
// host-address-agnostic. The reconciler maps an account's port to the VM-facing
// endpoint (host vmnet IP : port), because only it knows the bridge address.
//
// Peering is plaintext (http) for now — see the plan's §3.2: the PN link carries
// no cert yet, so KuraSpec.PeerURL is an http URL and no TLS material is set.
type HostKuraManager struct {
	// Root is the runner cache root; accounts/<id>/current lives under it.
	Root string
	// KuraBinary is the path to the kura executable on the host.
	KuraBinary string
	// BasePort is the first host port handed to a Kura process; subsequent
	// accounts get the next free port at or above it.
	BasePort int
	// PeerURLFor returns the account's EM peer URL (plaintext http) to set as
	// KURA_PEERS, or "" to run islanded (no peer). Optional.
	PeerURLFor func(accountID string) string
	// Start launches a Kura process from a spec. Injected so tests do not exec
	// a real binary; defaults to startHostKuraProcess when nil.
	Start ProcessStarter

	// nowFn is an optional clock override for tests.
	nowFn func() time.Time

	mu    sync.Mutex
	procs map[string]*managedKura
	ports map[int]string // port -> accountID, for allocation
}

type managedKura struct {
	spec     KuraSpec
	proc     KuraProcess
	lastUsed time.Time
}

// KuraSpec is the resolved configuration for one account's host Kura process.
type KuraSpec struct {
	AccountID string
	DataDir   string
	Port      int
	// PeerURL is the account's EM peer (plaintext http) or "" for none.
	PeerURL string
}

// KuraProcess is a running host Kura, abstracted so the manager is testable
// without execing a real binary.
type KuraProcess interface {
	// Ready reports whether the process is serving (HTTP /ready == 200).
	Ready(ctx context.Context) bool
	// Stop terminates the process and releases its resources.
	Stop() error
}

// ProcessStarter launches a Kura process for the given spec.
type ProcessStarter func(ctx context.Context, binary string, spec KuraSpec) (KuraProcess, error)

// EnabledForPod reports whether the host-Kura path applies to a Pod: the manager
// is configured (Root set) and the Pod opts into the runner cache volume (same
// annotation #11580 uses). Mirrors CacheVolumeManager.EnabledForPod.
func (m *HostKuraManager) EnabledForPod(pod *corev1.Pod) bool {
	return m != nil &&
		m.Root != "" &&
		pod.Annotations[RunnerCacheVolumeAnnotation] == "true"
}

// Ensure guarantees a host Kura for accountID is running against its cache
// volume, starting one if needed. It returns the host port the process listens
// on and whether it is serving yet. Ensure is idempotent: a second call for an
// account that is already running returns the same port without restarting.
func (m *HostKuraManager) Ensure(ctx context.Context, accountID string) (port int, ready bool, err error) {
	if _, err := safePathElement(accountID, "runner account label"); err != nil {
		return 0, false, err
	}

	m.mu.Lock()
	defer m.mu.Unlock()
	if m.procs == nil {
		m.procs = map[string]*managedKura{}
		m.ports = map[int]string{}
	}

	if existing, ok := m.procs[accountID]; ok {
		existing.lastUsed = m.now()
		return existing.spec.Port, existing.proc.Ready(ctx), nil
	}

	spec := KuraSpec{
		AccountID: accountID,
		DataDir:   filepath.Join(m.Root, "accounts", accountID, "current"),
		Port:      m.allocatePortLocked(accountID),
	}
	if m.PeerURLFor != nil {
		spec.PeerURL = m.PeerURLFor(accountID)
	}

	start := m.Start
	if start == nil {
		start = startHostKuraProcess
	}
	proc, err := start(ctx, m.KuraBinary, spec)
	if err != nil {
		for off := 0; off < portsPerNode; off++ {
			delete(m.ports, spec.Port+off)
		}
		return 0, false, fmt.Errorf("start host kura for account %s: %w", accountID, err)
	}
	m.procs[accountID] = &managedKura{spec: spec, proc: proc, lastUsed: m.now()}
	return spec.Port, proc.Ready(ctx), nil
}

// Touch updates an account's last-used time (called on each dispatch to the
// account) so LRU eviction can pick the coldest one. No-op if not running.
func (m *HostKuraManager) Touch(accountID string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if p, ok := m.procs[accountID]; ok {
		p.lastUsed = m.now()
	}
}

// Stop terminates and forgets an account's host Kura (called on eviction). It
// releases the port. Stopping an account that is not running is a no-op.
func (m *HostKuraManager) Stop(accountID string) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	p, ok := m.procs[accountID]
	if !ok {
		return nil
	}
	delete(m.procs, accountID)
	for off := 0; off < portsPerNode; off++ {
		delete(m.ports, p.spec.Port+off)
	}
	if err := p.proc.Stop(); err != nil {
		return fmt.Errorf("stop host kura for account %s: %w", accountID, err)
	}
	return nil
}

// Running reports whether an account currently has a host Kura process.
func (m *HostKuraManager) Running(accountID string) bool {
	m.mu.Lock()
	defer m.mu.Unlock()
	_, ok := m.procs[accountID]
	return ok
}

// LeastRecentlyUsed returns the accountID of the coldest running process, or ""
// when none are running. Used by the per-Mac disk-watermark eviction to pick a
// victim (evict the whole trio: volume + this node + presence label).
func (m *HostKuraManager) LeastRecentlyUsed() string {
	m.mu.Lock()
	defer m.mu.Unlock()
	var victim string
	var oldest time.Time
	for id, p := range m.procs {
		if victim == "" || p.lastUsed.Before(oldest) {
			victim, oldest = id, p.lastUsed
		}
	}
	return victim
}

// portsPerNode is the contiguous block each host Kura reserves: the cache HTTP
// port (base), gRPC (base+1), and the internal/peer port (base+2). Blocks are
// spaced so processes on the same host never collide.
const portsPerNode = 3

// allocatePortLocked returns the base of the lowest free portsPerNode-sized block
// at or above BasePort, marking every port in the block taken. Caller holds m.mu.
func (m *HostKuraManager) allocatePortLocked(accountID string) int {
	for base := m.BasePort; ; base += portsPerNode {
		free := true
		for off := 0; off < portsPerNode; off++ {
			if _, taken := m.ports[base+off]; taken {
				free = false
				break
			}
		}
		if free {
			for off := 0; off < portsPerNode; off++ {
				m.ports[base+off] = accountID
			}
			return base
		}
	}
}

func (m *HostKuraManager) now() time.Time {
	if m.nowFn != nil {
		return m.nowFn()
	}
	return time.Now()
}

