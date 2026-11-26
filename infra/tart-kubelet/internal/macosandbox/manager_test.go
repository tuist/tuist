package macosandbox

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	"k8s.io/apimachinery/pkg/types"
)

type fakeRuntime struct {
	states                   map[string]string
	memory                   map[string]string
	busy                     bool
	worker                   WorkerStatus
	workerEnv                map[string]string
	saveErr, errorRecovery   error
	createErr                error
	saveStarted, saveRelease chan struct{}
	shutdowns                int
	creates, warms, recovers int
	claimedVolumeGB          int
	// unflushed fails the guest flush before a pause; archiveStarted, when
	// set, holds an archive until its context ends.
	unflushed      bool
	archiveStarted chan struct{}
	// Warm VMs boot in the background.
	mu          sync.Mutex
	cpuPermille int64
	snapshots   map[string]protocol.DiskSnapshotInfo
}

func (f *fakeRuntime) Create(_ context.Context, r *Record) error {
	f.creates++
	if f.createErr != nil {
		f.states[r.SandboxID] = "booting" // A VM that never became ready.
		return f.createErr
	}
	f.states[r.SandboxID] = "running"
	f.memory[r.SandboxID] = "in-memory-session"
	return nil
}

// A warm VM is keyed by its VM name until a claim moves it to its sandbox.
func (f *fakeRuntime) Warm(_ context.Context, r *Record) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.warms++
	f.states[r.VMName()] = "warm"
	r.WorkspaceVolumeGB = r.WorkspaceGB
	return nil
}
func (f *fakeRuntime) Claim(_ context.Context, r *Record) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.states[r.VMName()] != "warm" {
		return errors.New("not warm")
	}
	f.claimedVolumeGB = r.WorkspaceVolumeGB
	delete(f.states, r.VMName())
	f.states[r.SandboxID] = "running"
	f.memory[r.SandboxID] = "in-memory-session"
	return nil
}
func (f *fakeRuntime) Resume(_ context.Context, r *Record) error {
	r.DisksSynced = false
	if f.states[r.SandboxID] != "paused" && f.states[r.SandboxID] != "evicted" {
		return errors.New("not paused")
	}
	f.states[r.SandboxID] = "running"
	return nil
}
func (f *fakeRuntime) Pause(_ context.Context, r *Record) error {
	if f.busy {
		return errors.New("busy")
	}
	r.DisksSynced = !f.unflushed
	f.states[r.SandboxID] = "paused"
	return nil
}
func (f *fakeRuntime) Save(ctx context.Context, r *Record) error {
	if f.saveStarted != nil {
		close(f.saveStarted)
		select {
		case <-f.saveRelease:
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	if f.saveErr != nil {
		return f.saveErr
	}
	if r.State == "running" {
		r.DisksSynced = !f.unflushed
	}
	f.states[r.SandboxID] = "evicted"
	return nil
}

// A shut-down VM is stopped like an evicted one, but keeps no checkpoint.
func (f *fakeRuntime) Shutdown(_ context.Context, r *Record) error {
	if f.states[r.SandboxID] != "paused" {
		return errors.New("not paused")
	}
	f.states[r.SandboxID] = "evicted"
	f.shutdowns++
	return nil
}
func (f *fakeRuntime) Delete(_ context.Context, r *Record) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	delete(f.states, r.VMName())
	delete(f.states, r.SandboxID)
	delete(f.memory, r.SandboxID)
	return nil
}
func (f *fakeRuntime) Recover(_ context.Context, r *Record) error {
	f.recovers++
	if f.errorRecovery != nil {
		return f.errorRecovery
	}
	state, ok := f.states[r.SandboxID]
	if !ok {
		return errors.New("missing VM")
	}
	r.State = state
	r.Resident = true
	if state == "evicted" {
		r.State = "paused"
		r.Resident = false
	}
	return nil
}
func (f *fakeRuntime) Archive(ctx context.Context, r *Record, _ protocol.ArchiveArgs) (protocol.ArchiveResult, error) {
	if f.archiveStarted != nil {
		close(f.archiveStarted)
		<-ctx.Done()
		return protocol.ArchiveResult{}, ctx.Err()
	}
	return protocol.ArchiveResult{Bytes: 1, SHA256: "sum", DisksSynced: true}, nil
}
func (f *fakeRuntime) Busy(context.Context, *Record) (bool, error)      { return f.busy, nil }
func (f *fakeRuntime) GuestCPU(context.Context, *Record) (int64, error) { return f.cpuPermille, nil }
func (f *fakeRuntime) Exec(_ context.Context, r *Record, a protocol.ExecArgs, _ func(protocol.Stream)) (protocol.ExecResult, error) {
	if f.memory[r.SandboxID] != "in-memory-session" {
		return protocol.ExecResult{}, errors.New("memory lost")
	}
	return protocol.ExecResult{}, nil
}

// Only a fenced VM's disks can be saved.
func (f *fakeRuntime) SaveDisks(_ context.Context, r *Record, id string) (protocol.DiskSnapshotInfo, error) {
	if f.states[r.SandboxID] != "evicted" {
		return protocol.DiskSnapshotInfo{}, errors.New("VM still running")
	}
	if f.snapshots == nil {
		f.snapshots = map[string]protocol.DiskSnapshotInfo{}
	}
	f.snapshots[id] = protocol.DiskSnapshotInfo{ID: id, Template: r.Template, WorkspaceGB: r.WorkspaceGB, Bytes: 1}
	return f.snapshots[id], nil
}
func (f *fakeRuntime) DeleteDisks(_ context.Context, id string) error {
	delete(f.snapshots, id)
	return nil
}
func (f *fakeRuntime) ArchiveDisks(context.Context, protocol.ArchiveDisksArgs) (protocol.ArchiveResult, error) {
	return protocol.ArchiveResult{}, errors.New("not archived in tests")
}
func (f *fakeRuntime) CopyDisks(context.Context, protocol.CopyDisksArgs) (protocol.DiskSnapshotInfo, error) {
	return protocol.DiskSnapshotInfo{}, errors.New("not copied in tests")
}
func (f *fakeRuntime) DiskSnapshots() ([]protocol.DiskSnapshotInfo, error) {
	out := []protocol.DiskSnapshotInfo{}
	for _, s := range f.snapshots {
		out = append(out, s)
	}
	return out, nil
}
func (f *fakeRuntime) Worker(_ context.Context, r *Record, action string, env map[string]string) (WorkerStatus, error) {
	if action == "start" {
		f.worker = WorkerStatus{Running: true, ID: r.WorkerID}
		f.workerEnv = env
	}
	if action == "stop" {
		f.worker.Running = false
	}
	return f.worker, nil
}

type fakeCapacity struct {
	allow      bool
	held       map[string]bool
	releaseErr error
	onReserve  func()
}

func (f *fakeCapacity) Reserve(ctx context.Context, r *Record) error {
	if f.onReserve != nil {
		f.onReserve()
	}
	if err := f.Allow(ctx, r); err != nil {
		return err
	}
	if len(f.held) >= 1 && !f.held[r.SandboxID] {
		return ErrCapacity
	}
	f.held[r.SandboxID] = true
	return nil
}
func (f *fakeCapacity) Allow(context.Context, *Record) error {
	if !f.allow {
		return ErrCapacity
	}
	return nil
}
func (f *fakeCapacity) Release(_ context.Context, r *Record) error {
	if f.releaseErr != nil {
		return f.releaseErr
	}
	delete(f.held, r.SandboxID)
	return nil
}
func (f *fakeCapacity) Transfer(_ context.Context, r *Record, _, _ string, _ types.UID) error {
	f.held[r.SandboxID] = true
	return nil
}
func harness(t *testing.T) (*Manager, *fakeRuntime, *fakeCapacity, protocol.CreateArgs) {
	t.Helper()
	runtime := &fakeRuntime{states: map[string]string{}, memory: map[string]string{}}
	capacity := &fakeCapacity{allow: true, held: map[string]bool{}}
	manager := &Manager{Root: t.TempDir(), NodeUID: "node-1", RuntimePath: "/runtime/pinned", ToolsPath: "/tools/pinned", Runtime: runtime, Capacity: capacity}
	if err := manager.Load(context.Background()); err != nil {
		t.Fatal(err)
	}
	return manager, runtime, capacity, protocol.CreateArgs{SandboxID: uuid.NewString(), Template: "macos", VCPUs: 8, MemoryMB: 8192, WorkspaceGB: 10}
}
func TestResidentPauseRetainsCapacityAndMemoryAcrossRecovery(t *testing.T) {
	m, r, c, a := harness(t)
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	if err := m.Pause(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
	if !c.held[a.SandboxID] || !m.Snapshot()[0].Resident {
		t.Fatal("pause released resident charge")
	}
	recovered := &Manager{Root: m.Root, NodeUID: m.NodeUID, Runtime: r, Capacity: c}
	if err := recovered.Load(ctx); err != nil {
		t.Fatal(err)
	}
	if err := recovered.Resume(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
	if _, err := recovered.Exec(ctx, protocol.ExecArgs{SandboxID: a.SandboxID}, nil); err != nil {
		t.Fatal(err)
	}
	if r.creates != 1 {
		t.Fatal("recovery cold booted the sandbox")
	}
	if err := recovered.Delete(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
	if len(c.held) != 0 || len(recovered.Snapshot()) != 0 {
		t.Fatal("delete leaked ownership")
	}
}

// A create can wait for CI to give up a slot. Reports sent meanwhile must
// list the sandbox, or the server reads it as missing once the create ends.
func TestReportsListASandboxWhileItsCreateWaitsForCapacity(t *testing.T) {
	m, _, c, a := harness(t)
	var during []protocol.SandboxInfo
	c.onReserve = func() { during = m.Snapshot() }
	if err := m.Create(context.Background(), a); err != nil {
		t.Fatal(err)
	}
	if len(during) != 1 || during[0].ID != a.SandboxID || during[0].State != "creating" {
		t.Fatalf("report during the reservation wait: %+v", during)
	}
}

// The server places a create the host refused for capacity again after a
// short wait, under the same sandbox id and often on the same host. Once CI
// frees the slot, that create boots instead of failing as a duplicate.
func TestCreateRefusedForCapacitySucceedsWhenRetriedOnTheSameHost(t *testing.T) {
	m, r, c, a := harness(t)
	ctx := context.Background()
	c.allow = false
	if err := m.Create(ctx, a); !errors.Is(err, ErrCapacity) {
		t.Fatalf("refused create: %v", err)
	}
	c.allow = true
	if err := m.Create(ctx, a); err != nil {
		t.Fatalf("retried create: %v", err)
	}
	if r.creates != 1 || len(m.Snapshot()) != 1 || m.Snapshot()[0].State != "running" {
		t.Fatalf("retried create did not boot: creates=%d %+v", r.creates, m.Snapshot())
	}
	// The retried sandbox survives a host restart like any other.
	recovered := &Manager{Root: m.Root, NodeUID: m.NodeUID, Runtime: r, Capacity: c}
	if err := recovered.Load(ctx); err != nil {
		t.Fatal(err)
	}
	if s := recovered.Snapshot(); len(s) != 1 || s[0].State != "running" {
		t.Fatalf("after restart: %+v", s)
	}
}

func TestResidencyHoldOutlivesIdleGraceAndCIUntilItsOwnerEndsIt(t *testing.T) {
	m, r, c, a := harness(t)
	m.Grace = time.Nanosecond
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	if err := m.Hold(ctx, a.SandboxID, "amp:amp-thread", 0); err != nil {
		t.Fatal(err)
	}
	// The hold survives a host restart, CI demand and the idle grace.
	recovered := &Manager{Root: m.Root, NodeUID: m.NodeUID, Runtime: r, Capacity: c, Grace: time.Nanosecond}
	if err := recovered.Load(ctx); err != nil {
		t.Fatal(err)
	}
	c.allow = false
	time.Sleep(time.Millisecond)
	if err := recovered.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if r.states[a.SandboxID] != "running" || !c.held[a.SandboxID] {
		t.Fatal("idle eviction interrupted held guest work")
	}
	// A late release from an earlier turn leaves the current hold alone.
	if err := recovered.Release(a.SandboxID, "older-turn"); err != nil {
		t.Fatal(err)
	}
	if err := recovered.Reconcile(ctx); err != nil || r.states[a.SandboxID] != "running" {
		t.Fatal("a stale release ended the hold", err)
	}
	c.allow = true
	if err := recovered.Pause(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
	time.Sleep(time.Millisecond)
	if err := recovered.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if r.states[a.SandboxID] != "evicted" || c.held[a.SandboxID] {
		t.Fatal("the pause did not end the hold")
	}
	// A new turn resumes the evicted VM; releasing it makes it evictable again.
	if err := recovered.Hold(ctx, a.SandboxID, "amp:amp-thread", 0); err != nil || r.states[a.SandboxID] != "running" {
		t.Fatal("hold did not resume the sandbox", err)
	}
	if err := recovered.Release(a.SandboxID, "amp:amp-thread"); err != nil {
		t.Fatal(err)
	}
	time.Sleep(time.Millisecond)
	if err := recovered.Reconcile(ctx); err != nil || r.states[a.SandboxID] != "evicted" {
		t.Fatal("a released sandbox stayed resident", err)
	}
}

// A running VM already holds its charge, so holds on it, new or renewed, need
// no grant while CI holds it. A hold nobody renews expires, and the idle VM is
// checkpointed once its idle grace is up, not when CI asks for the room.
func TestHoldsOnARunningVMNeedNoGrantAndExpire(t *testing.T) {
	m, r, c, a := harness(t)
	m.Grace = time.Minute
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	if err := m.Hold(ctx, a.SandboxID, "commands", 0); err != nil {
		t.Fatal(err)
	}
	c.allow = false
	if err := m.Hold(ctx, a.SandboxID, "commands", 100*time.Millisecond); err != nil {
		t.Fatalf("renewing the current hold needed the grant: %v", err)
	}
	if err := m.Hold(ctx, a.SandboxID, "amp:other", 100*time.Millisecond); err != nil {
		t.Fatalf("a new hold on a running VM needed the grant: %v", err)
	}
	if err := m.Reconcile(ctx); err != nil || r.states[a.SandboxID] != "running" {
		t.Fatal("CI evicted a sandbox under a live hold", err)
	}
	time.Sleep(150 * time.Millisecond)
	if err := m.Reconcile(ctx); err != nil || r.states[a.SandboxID] != "running" {
		t.Fatal("CI demand evicted an idle VM before its grace was up", err)
	}
	m.Grace = time.Nanosecond
	if err := m.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if r.states[a.SandboxID] != "evicted" || c.held[a.SandboxID] {
		t.Fatal("an expired hold kept the VM past its idle grace")
	}
}

func TestGuestCPUIntegratesIntoMonotonicReportedTime(t *testing.T) {
	m, r, _, a := harness(t)
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	r.cpuPermille = 500
	m.SampleCPU(ctx)
	time.Sleep(200 * time.Millisecond)
	m.SampleCPU(ctx)
	// Half a core for at least 200 ms is at least 100 ms of CPU time.
	if got := m.Snapshot()[0].CPUMs; got < 100 || got > 400 {
		t.Fatalf("cpu_ms = %d", got)
	}
	if err := m.Pause(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
	if m.Snapshot()[0].CPUMs != 0 {
		t.Fatal("a paused sandbox reported guest CPU")
	}
}
func TestIdleEvictionSparesWorkAndRetainsFailedFence(t *testing.T) {
	m, r, c, a := harness(t)
	m.Grace = time.Nanosecond
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	if _, err := m.Worker(ctx, a.SandboxID, "start", map[string]string{"ANTHROPIC_WORK_ID": "work-1"}); err != nil {
		t.Fatal(err)
	}
	c.allow = false
	if err := m.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if !c.held[a.SandboxID] {
		t.Fatal("idle eviction interrupted active work")
	}
	r.worker.Running = false
	r.saveErr = errors.New("checkpoint failed")
	if err := m.Reconcile(ctx); err == nil {
		t.Fatal("expected save failure")
	}
	if !c.held[a.SandboxID] {
		t.Fatal("failed checkpoint freed capacity")
	}
	r.saveErr = nil
	if err := m.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if c.held[a.SandboxID] || m.Snapshot()[0].Resident {
		t.Fatal("successful eviction kept charge")
	}
	if err := m.Resume(ctx, a.SandboxID); !errors.Is(err, ErrCapacity) {
		t.Fatalf("resume admitted while CI holds the grant: %v", err)
	}
}

// A running VM already holds its charge, so commands into it (log reads,
// stdin, cancel) work while CI holds the grant. Resuming one still needs it.
func TestExecIntoRunningSandboxNeedsNoGrantButResumeDoes(t *testing.T) {
	m, _, c, a := harness(t)
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	if err := m.Hold(ctx, a.SandboxID, "commands", 0); err != nil {
		t.Fatal(err)
	}
	c.allow = false
	if _, err := m.Exec(ctx, protocol.ExecArgs{SandboxID: a.SandboxID}, nil); err != nil {
		t.Fatalf("exec into a running sandbox needed the grant: %v", err)
	}
	if err := m.Release(a.SandboxID, "commands"); err != nil {
		t.Fatal(err)
	}
	c.allow = true
	if err := m.Pause(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
	c.allow = false
	if _, err := m.Exec(ctx, protocol.ExecArgs{SandboxID: a.SandboxID}, nil); !errors.Is(err, ErrCapacity) {
		t.Fatalf("exec resumed a paused sandbox without the grant: %v", err)
	}
	if m.Snapshot()[0].State != "paused" {
		t.Fatal("refused exec changed the sandbox's state")
	}
}
func TestConcurrentCreatesCannotOverbookLastSlot(t *testing.T) {
	m, r, c, a := harness(t)
	var wg sync.WaitGroup
	success := make(chan string, 2)
	for i := 0; i < 2; i++ {
		a := a
		a.SandboxID = uuid.NewString()
		wg.Add(1)
		go func() {
			defer wg.Done()
			if m.Create(context.Background(), a) == nil {
				success <- a.SandboxID
			}
		}()
	}
	wg.Wait()
	if len(success) != 1 || r.creates != 1 || len(c.held) != 1 {
		t.Fatalf("overbooked: successes %d creates %d charges %d", len(success), r.creates, len(c.held))
	}
}
func TestReportsAndCILaunchDoNotWaitForCheckpoint(t *testing.T) {
	m, r, c, a := harness(t)
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	c.allow = false
	m.Grace = time.Nanosecond
	r.saveStarted = make(chan struct{})
	r.saveRelease = make(chan struct{})
	done := make(chan error, 1)
	go func() { done <- m.Reconcile(ctx) }()
	<-r.saveStarted
	s := &Service{manager: m, ready: true}
	started := time.Now()
	if _, err := s.LaunchGuard(ctx, "ci"); !errors.Is(err, ErrCapacity) {
		t.Fatal(err)
	}
	if len(m.Snapshot()) != 1 || time.Since(started) > 100*time.Millisecond {
		t.Fatal("slow checkpoint blocked CI worker or heartbeat")
	}
	close(r.saveRelease)
	if err := <-done; err != nil {
		t.Fatal(err)
	}
}
func TestRecoveryRefusesWrongOwnerAndNeverFreesUnknownVM(t *testing.T) {
	m, r, c, a := harness(t)
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	wrong := &Manager{Root: m.Root, NodeUID: "replacement", Runtime: r, Capacity: c}
	if wrong.Load(ctx) == nil {
		t.Fatal("accepted previous Node incarnation")
	}
	r.errorRecovery = errors.New("runtime unreachable")
	recovered := &Manager{Root: m.Root, NodeUID: m.NodeUID, Runtime: r, Capacity: c}
	if err := recovered.Load(ctx); err != nil {
		t.Fatal(err)
	}
	if !c.held[a.SandboxID] || recovered.Snapshot()[0].State != "error" {
		t.Fatal("unknown VM became free capacity")
	}
}

// A VM found with no process and no checkpoint holds no CPU or memory: it
// gives its slot back once, without being retried every reconcile, and stays
// listed in error until the server deletes it.
func TestLostVMReleasesItsReservationOnceUntilDeleted(t *testing.T) {
	m, r, c, a := harness(t)
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	r.errorRecovery = fmt.Errorf("sandbox process lost without a checkpoint; %w", ErrVMLost)
	c.releaseErr = errors.New("API unavailable")
	recovered := &Manager{Root: m.Root, NodeUID: m.NodeUID, Runtime: r, Capacity: c}
	if err := recovered.Load(ctx); err != nil {
		t.Fatal(err)
	}
	if !c.held[a.SandboxID] || !recovered.Snapshot()[0].Resident {
		t.Fatal("a failed release dropped the reservation")
	}
	c.releaseErr = nil
	if err := recovered.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	info := recovered.Snapshot()[0]
	if c.held[a.SandboxID] || info.Resident || info.State != "error" {
		t.Fatalf("lost VM kept its slot: held %v, %+v", c.held[a.SandboxID], info)
	}
	// The release is journaled, so neither a reconcile nor a restart retries it.
	again := &Manager{Root: m.Root, NodeUID: m.NodeUID, Runtime: r, Capacity: c}
	if err := again.Load(ctx); err != nil {
		t.Fatal(err)
	}
	before := r.recovers
	for i := 0; i < 3; i++ {
		if err := again.Reconcile(ctx); err != nil {
			t.Fatal(err)
		}
	}
	if r.recovers != before {
		t.Fatalf("lost VM was recovered %d more times", r.recovers-before)
	}
	if err := again.Delete(ctx, a.SandboxID); err != nil || len(again.Snapshot()) != 0 {
		t.Fatal("lost VM could not be deleted", err)
	}
}
func TestInterruptedDeleteIsRetriedAfterRestart(t *testing.T) {
	m, r, c, a := harness(t)
	ctx := context.Background()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	c.releaseErr = errors.New("API unavailable")
	if m.Delete(ctx, a.SandboxID) == nil {
		t.Fatal("expected failure")
	}
	c.releaseErr = nil
	recovered := &Manager{Root: m.Root, NodeUID: m.NodeUID, Runtime: r, Capacity: c}
	if err := recovered.Load(ctx); err != nil {
		t.Fatal(err)
	}
	if err := recovered.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if len(c.held) != 0 {
		t.Fatal("reservation leaked")
	}
	if _, err := os.Stat(filepath.Join(m.Root, a.SandboxID+".json")); !os.IsNotExist(err) {
		t.Fatal("journal leaked")
	}
}

// A host that cannot reach the server never receives a delete for a create
// that failed there, so recovery must free the slot itself.
func TestFailedCreateIsDeletedAndReleasedAfterRestart(t *testing.T) {
	m, r, c, a := harness(t)
	ctx := context.Background()
	r.createErr = errors.New("VM exited before guest readiness")
	if m.Create(ctx, a) == nil {
		t.Fatal("expected create failure")
	}
	if !c.held[a.SandboxID] {
		t.Fatal("uncertain start released its reservation before the VM was deleted")
	}
	r.createErr = nil
	r.errorRecovery = errors.New("creation did not finish")
	recovered := &Manager{Root: m.Root, NodeUID: m.NodeUID, Runtime: r, Capacity: c}
	if err := recovered.Load(ctx); err != nil {
		t.Fatal(err)
	}
	if err := recovered.Reconcile(ctx); err != nil {
		t.Fatal(err)
	}
	if len(c.held) != 0 || len(r.states) != 0 || len(recovered.Snapshot()) != 0 {
		t.Fatalf("failed create kept its slot: held=%v vms=%v reported=%v", c.held, r.states, recovered.Snapshot())
	}
	if _, err := os.Stat(filepath.Join(m.Root, a.SandboxID+".json")); !os.IsNotExist(err) {
		t.Fatal("journal leaked")
	}
	r.errorRecovery = nil
	if err := recovered.Create(ctx, a); err != nil {
		t.Fatalf("retrying the create: %v", err)
	}
}
func TestDispatchFencesOwnerAndKeepsCredentialsOutOfJournal(t *testing.T) {
	m, _, _, a := harness(t)
	ctx := context.Background()
	data, _ := json.Marshal(a)
	result := m.Dispatch(ctx, protocol.Command{Op: protocol.OpCreate, Args: data}, nil)
	if result.OK {
		t.Fatal("missing generation accepted")
	}
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	if _, err := m.Worker(ctx, a.SandboxID, "start", map[string]string{"ANTHROPIC_WORK_ID": "work-1", "ANTHROPIC_WORK_SECRET": "never-store-me"}); err != nil {
		t.Fatal(err)
	}
	data, err := os.ReadFile(filepath.Join(m.Root, a.SandboxID+".json"))
	if err != nil {
		t.Fatal(err)
	}
	var journal map[string]any
	if err = json.Unmarshal(data, &journal); err != nil {
		t.Fatal(err)
	}
	if journal["env"] != nil {
		t.Fatal("credentials persisted")
	}
	if journal["runtime_path"] != "/runtime/pinned" || journal["tools_path"] != "/tools/pinned" {
		t.Fatal("runtime compatibility was not pinned")
	}
}

func TestFailedPrelaunchReservationReleaseRetriesWithoutVM(t *testing.T) {
	m, r, c, a := harness(t)
	c.allow = false
	c.releaseErr = errors.New("API unavailable")
	if m.Create(context.Background(), a) == nil {
		t.Fatal("expected admission failure")
	}
	if r.creates != 0 || !m.Snapshot()[0].Resident {
		t.Fatal("unresolved reservation not retained")
	}
	c.releaseErr = nil
	recovered := &Manager{Root: m.Root, NodeUID: m.NodeUID, Runtime: r, Capacity: c}
	if err := recovered.Load(context.Background()); err != nil {
		t.Fatal(err)
	}
	if err := recovered.Reconcile(context.Background()); err != nil {
		t.Fatal(err)
	}
	if recovered.Snapshot()[0].Resident || recovered.records[a.SandboxID].Operation != "" {
		t.Fatal("release did not settle")
	}
}
func TestEmptyReportIsAnArraySoMissingVMsAreReconciled(t *testing.T) {
	m, _, _, _ := harness(t)
	data, err := json.Marshal(m.Snapshot())
	if err != nil || string(data) != "[]" {
		t.Fatalf("missing ownership report: %s %v", data, err)
	}
}

// A restore the server stopped waiting for is retried with a newly presigned
// URL; it is the same archive.
func TestRetriedRestoreMatchesItsJournalWhateverItsURL(t *testing.T) {
	m, runtime, _, a := harness(t)
	ctx := context.Background()
	a.FromArchive = &protocol.ArchiveSource{URL: "https://store/archive?sig=1", Bytes: 1024, SHA256: "abc"}
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	retry := a
	retry.FromArchive = &protocol.ArchiveSource{URL: "https://store/archive?sig=2", Bytes: 1024, SHA256: "abc"}
	if err := m.Create(ctx, retry); err != nil || runtime.creates != 1 {
		t.Fatalf("retried restore not matched: %v, creates %d", err, runtime.creates)
	}
	other := a
	other.FromArchive = &protocol.ArchiveSource{URL: "https://store/archive?sig=1", Bytes: 1024, SHA256: "def"}
	if m.Create(ctx, other) == nil {
		t.Fatal("a different archive matched")
	}
}

// A disk snapshot needs a pause that synced the guest's disks and no resume
// since. Saving evicts a resident VM first, which gives its slot back.
func TestSaveDisksRequiresSyncedPauseAndEvictsFirst(t *testing.T) {
	m, r, c, a := harness(t)
	ctx := t.Context()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	snapshot := uuid.NewString()
	r.unflushed = true
	if err := m.Pause(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
	if _, err := m.SaveDisks(ctx, a.SandboxID, snapshot, false); err == nil {
		t.Fatal("saved the disks of a pause that did not sync them")
	}
	if err := m.Resume(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
	r.unflushed = false
	if err := m.Pause(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
	info, err := m.SaveDisks(ctx, a.SandboxID, snapshot, false)
	if err != nil || info.ID != snapshot {
		t.Fatalf("save: %+v %v", info, err)
	}
	if rec := m.records[a.SandboxID]; rec.Resident || rec.State != "paused" || c.held[a.SandboxID] {
		t.Fatalf("saved without giving the slot back: %+v held=%v", rec, c.held)
	}
	if got := m.DiskSnapshots(); len(got) != 1 || got[0].ID != snapshot {
		t.Fatalf("reported snapshots %+v", got)
	}
	// A sandbox from the snapshot runs the image it was saved from, and one
	// from a snapshot the host lacks fails before reserving anything.
	r.snapshots[snapshot] = protocol.DiskSnapshotInfo{ID: snapshot, Template: "macos", TemplateTag: "image@sha256:old", WorkspaceGB: 10}
	cloned := a
	cloned.SandboxID = uuid.NewString()
	cloned.FromDiskSnapshot = snapshot
	c.held = map[string]bool{}
	if err := m.Create(ctx, cloned); err != nil {
		t.Fatal(err)
	}
	if tag := m.records[cloned.SandboxID].TemplateTag; tag != "image@sha256:old" {
		t.Fatalf("snapshot sandbox reports tag %q", tag)
	}
	missing := a
	missing.SandboxID = uuid.NewString()
	missing.FromDiskSnapshot = uuid.NewString()
	if err := m.Create(ctx, missing); !errors.Is(err, errSnapshotNotFound) || m.records[missing.SandboxID] != nil {
		t.Fatalf("create from a missing snapshot: %v", err)
	}
	for range 2 {
		if err := m.DeleteDisks(ctx, snapshot); err != nil {
			t.Fatal(err)
		}
	}
	if got := m.DiskSnapshots(); len(got) != 0 {
		t.Fatalf("deleted snapshot still reported: %+v", got)
	}
}

// A save that asks for a shutdown stops the guest cleanly instead of
// checkpointing it, gives the slot back, and the sandbox never resumes.
func TestSaveDisksWithShutdownStopsTheGuestAndRefusesResume(t *testing.T) {
	m, r, c, a := harness(t)
	ctx := t.Context()
	if err := m.Create(ctx, a); err != nil {
		t.Fatal(err)
	}
	if err := m.Pause(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
	snapshot := uuid.NewString()
	if info, err := m.SaveDisks(ctx, a.SandboxID, snapshot, true); err != nil || info.ID != snapshot {
		t.Fatalf("save: %+v %v", info, err)
	}
	if r.shutdowns != 1 {
		t.Fatalf("saved without shutting the guest down: %d shutdowns", r.shutdowns)
	}
	if rec := m.records[a.SandboxID]; rec.Resident || !rec.ShutDown || c.held[a.SandboxID] {
		t.Fatalf("saved without giving the slot back: %+v held=%v", rec, c.held)
	}
	if err := m.Resume(ctx, a.SandboxID); err == nil {
		t.Fatal("resumed a sandbox whose guest was shut down")
	}
	if err := m.Delete(ctx, a.SandboxID); err != nil {
		t.Fatal(err)
	}
}
