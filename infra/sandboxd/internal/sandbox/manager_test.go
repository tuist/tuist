package sandbox

import (
	"context"
	"encoding/json"
	"errors"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/fakevm"
	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
	"github.com/tuist/tuist/infra/sandboxd/internal/network"
	"github.com/tuist/tuist/infra/sandboxd/internal/protocol"
	"github.com/tuist/tuist/infra/sandboxd/internal/template"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
	"github.com/tuist/tuist/infra/sandboxd/internal/vsock"
)

type eventSink struct {
	mu     sync.Mutex
	events []protocol.Event
	cond   *sync.Cond
}

func newEventSink() *eventSink {
	s := &eventSink{}
	s.cond = sync.NewCond(&s.mu)
	return s
}

func (s *eventSink) add(e protocol.Event) {
	s.mu.Lock()
	s.events = append(s.events, e)
	s.cond.Broadcast()
	s.mu.Unlock()
}

func (s *eventSink) wait(t *testing.T, name string, timeout time.Duration) protocol.Event {
	t.Helper()
	deadline := time.Now().Add(timeout)
	s.mu.Lock()
	defer s.mu.Unlock()
	for {
		for _, e := range s.events {
			if e.Event == name {
				return e
			}
		}
		if time.Now().After(deadline) {
			t.Fatalf("event %s not emitted; have %+v", name, s.events)
		}
		timer := time.AfterFunc(20*time.Millisecond, s.cond.Broadcast)
		s.cond.Wait()
		timer.Stop()
	}
}

type harness struct {
	m        *Manager
	launcher *fakevm.Launcher
	net      *fakevm.Network
	slots    *network.Slots
	events   *eventSink
	dataDir  string
	jailBase string
	tmplDir  string
}

func seedTemplate(t *testing.T, dataDir string) string {
	t.Helper()
	dir := filepath.Join(dataDir, "templates", "default", "t1")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, template.KernelFile), []byte("kernel"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, template.RootfsFile), []byte("pristine rootfs"), 0o644); err != nil {
		t.Fatal(err)
	}
	return dir
}

func newHarness(t *testing.T) *harness {
	t.Helper()
	dataDir := t.TempDir()
	tmplDir := seedTemplate(t, dataDir)
	jailBase := filepath.Join(dataDir, "jail")
	launcher := &fakevm.Launcher{}
	net := &fakevm.Network{}
	slots := network.NewSlots(8)
	events := newEventSink()
	store := &template.Store{Dir: filepath.Join(dataDir, "templates")}
	agent := func(path string) vsock.Agent { return vsock.NewUDSClient(path, firecracker.AgentPort) }
	builder := &template.Builder{
		Store: store, Launcher: launcher, Network: net, Slots: slots, Agent: agent, JailBase: jailBase,
		JailerEnabled: true, UIDBase: 10000, DNS: []string{"10.128.0.10"}, FirecrackerVersion: "v1.16.1",
		WorkspaceGB: 10, BootTimeout: 5 * time.Second, Events: events.add,
	}
	m := New(Config{
		JailBase: jailBase, FirecrackerBin: "/fc", JailerBin: "/jailer", JailerEnabled: true, UIDBase: 10000,
		DNS: []string{"10.128.0.10"}, DefaultTemplate: "default", BootTimeout: 5 * time.Second, StopWorkerGrace: 2 * time.Second,
	}, Deps{
		Store: store, Builder: builder, Launcher: launcher, Network: net, Slots: slots, Agent: agent,
		Metrics: NewMetrics(nil), Events: events.add,
	})
	return &harness{m: m, launcher: launcher, net: net, slots: slots, events: events, dataDir: dataDir, jailBase: jailBase, tmplDir: tmplDir}
}

const testID = "abc123def456xyz"

func (h *harness) create(t *testing.T, id string, workspaceGB int) protocol.CreateResult {
	t.Helper()
	res, err := h.m.Create(context.Background(), protocol.CreateArgs{SandboxID: id, Template: "default", VCPUs: 2, MemoryMB: 4096, WorkspaceGB: workspaceGB})
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	return res
}

func callPaths(inst *fakevm.Instance) []string {
	var out []string
	for _, c := range inst.Calls() {
		if c.Method == "GET" {
			continue
		}
		out = append(out, c.Method+" "+c.Path)
	}
	return out
}

func TestLifecycle(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	res := h.create(t, testID, 20)
	if res.BootMs < 0 {
		t.Fatalf("boot_ms %d", res.BootMs)
	}
	root := vm.RootDir(h.jailBase, testID)
	for _, name := range []string{"vmlinux", "mem", "snapshot", "rootfs.ext4", "workspace.ext4", MetadataFile} {
		if !vm.Exists(filepath.Join(root, name)) {
			t.Fatalf("missing %s in jail root", name)
		}
	}
	if size := vm.FileSize(filepath.Join(root, "workspace.ext4")); size != 20<<30 {
		t.Fatalf("workspace size %d", size)
	}
	meta, err := LoadMetadata(root)
	if err != nil {
		t.Fatal(err)
	}
	if meta.State != protocol.StateRunning || meta.Slot != 0 || meta.Generation != 0 || meta.Hostname != "sbx-abc123def456" || meta.Template != "default" || meta.Tag != "t1" || meta.WorkspaceGB != 20 {
		t.Fatalf("metadata %+v", meta)
	}
	// Instance 0 was the template build; instance 1 is the sandbox.
	instances := h.launcher.Instances()
	if len(instances) != 2 {
		t.Fatalf("expected 2 vms (template build + sandbox), got %d", len(instances))
	}
	inst := instances[1]
	paths := callPaths(inst)
	if strings.Join(paths, ",") != "PUT /snapshot/load,PATCH /drives/workspace" {
		t.Fatalf("create api calls %v", paths)
	}
	load := inst.Calls()[len(inst.Calls())-2]
	for _, c := range inst.Calls() {
		if c.Path == "/snapshot/load" {
			load = c
		}
	}
	backend, _ := load.Body["mem_backend"].(map[string]any)
	if load.Body["snapshot_path"] != "/snapshot" || backend["backend_path"] != "/mem" || backend["backend_type"] != "File" || load.Body["resume_vm"] != true {
		t.Fatalf("snapshot load body %v", load.Body)
	}
	configures := inst.Agent.RequestsOf("configure")
	if len(configures) != 1 || configures[0]["hostname"] != "sbx-abc123def456" || configures[0]["format_workspace"] != true {
		t.Fatalf("configure requests %v", configures)
	}
	if dns, _ := configures[0]["dns"].([]any); len(dns) != 1 || dns[0] != "10.128.0.10" {
		t.Fatalf("configure dns %v", configures[0]["dns"])
	}
	if len(inst.Agent.RequestsOf("set_time")) != 1 {
		t.Fatal("expected one set_time")
	}
	ns := network.NamespaceName(testID)
	if calls := h.net.Snapshot(); calls[len(calls)-1] != "setup "+ns+" 0" {
		t.Fatalf("network calls %v", calls)
	}

	info, err := h.m.Status(ctx, testID)
	if err != nil || info.State != protocol.StateRunning || info.WorkerRunning || info.VCPUs != 2 || info.MemoryMB != 4096 {
		t.Fatalf("status %+v %v", info, err)
	}

	var mu sync.Mutex
	var output []string
	execRes, err := h.m.Exec(ctx, protocol.ExecArgs{SandboxID: testID, Cmd: []string{"echo", "hi"}}, func(stream string, data []byte) {
		mu.Lock()
		output = append(output, stream+":"+string(data))
		mu.Unlock()
	})
	if err != nil || execRes.ExitCode != 0 {
		t.Fatalf("exec %+v %v", execRes, err)
	}
	if strings.Join(output, "") != "stdout:echo hi\n" {
		t.Fatalf("exec output %q", output)
	}
	execs := inst.Agent.RequestsOf("exec")
	if execs[0]["cwd"] != "/workspace" {
		t.Fatalf("exec should default cwd to /workspace: %v", execs[0])
	}

	worker, err := h.m.StartWorker(ctx, protocol.StartWorkerArgs{SandboxID: testID, Env: map[string]string{"ANTHROPIC_WORK_SECRET": "s3cret", "SBX_MAX_IDLE": "30s"}})
	if err != nil || worker.ExecID == "" {
		t.Fatalf("start worker %+v %v", worker, err)
	}
	if _, err := h.m.StartWorker(ctx, protocol.StartWorkerArgs{SandboxID: testID}); !errors.Is(err, ErrWorkerRunning) {
		t.Fatalf("second worker should be refused, got %v", err)
	}
	info, _ = h.m.Status(ctx, testID)
	if !info.WorkerRunning {
		t.Fatal("worker_running should be true")
	}
	if _, err := h.m.Pause(ctx, testID); !errors.Is(err, ErrBusy) {
		t.Fatalf("pause with worker should be refused, got %v", err)
	}
	workerExec := inst.Agent.RequestsOf("exec")[1]
	if cmd, _ := workerExec["cmd"].([]any); len(cmd) != 1 || cmd[0] != "/usr/local/bin/sbx-worker" {
		t.Fatalf("worker cmd %v", workerExec["cmd"])
	}
	if env, _ := workerExec["env"].(map[string]any); env["ANTHROPIC_WORK_SECRET"] != "s3cret" {
		t.Fatalf("worker env not passed: %v", workerExec["env"])
	}
	if err := h.m.StopWorker(ctx, testID); err != nil {
		t.Fatalf("stop worker: %v", err)
	}
	exited := h.events.wait(t, protocol.EventWorkerExited, 5*time.Second)
	if exited.SandboxID != testID || exited.ExitCode == nil || *exited.ExitCode != 143 || exited.DurationMs < 0 {
		t.Fatalf("worker_exited %+v", exited)
	}
	if err := h.m.StopWorker(ctx, testID); !errors.Is(err, ErrNoWorker) {
		t.Fatalf("stop without worker should fail, got %v", err)
	}

	pauseRes, err := h.m.Pause(ctx, testID)
	if err != nil {
		t.Fatalf("pause: %v", err)
	}
	if pauseRes.MemBytes <= 0 {
		t.Fatalf("pause result %+v", pauseRes)
	}
	paths = callPaths(inst)
	if strings.Join(paths[2:], ",") != "PATCH /vm,PUT /snapshot/create" {
		t.Fatalf("pause api calls %v", paths)
	}
	var create fakevm.Call
	for _, c := range inst.Calls() {
		if c.Path == "/snapshot/create" {
			create = c
		}
	}
	if create.Body["snapshot_path"] != "/snapshot.new" || create.Body["mem_file_path"] != "/mem.new" || create.Body["snapshot_type"] != "Full" {
		t.Fatalf("snapshot create body %v", create.Body)
	}
	if !inst.Killed() {
		t.Fatal("pause must kill firecracker")
	}
	if vm.Exists(filepath.Join(root, "mem.new")) || vm.Exists(filepath.Join(root, "snapshot.new")) {
		t.Fatal("pause must rename the new snapshot files over the old ones")
	}
	memData, _ := os.ReadFile(filepath.Join(root, "mem"))
	if !strings.HasPrefix(string(memData), "mem_file_path "+testID) {
		t.Fatalf("mem should be the sandbox's own snapshot, got %q", memData)
	}
	templateMem, _ := os.ReadFile(filepath.Join(h.tmplDir, "shapes", "2x4096", template.MemFile))
	if !strings.HasPrefix(string(templateMem), "mem_file_path tmpl-") {
		t.Fatalf("template memfile must be untouched by a sandbox pause, got %q", templateMem)
	}
	meta, _ = LoadMetadata(root)
	if meta.State != protocol.StatePaused || meta.Generation != 1 {
		t.Fatalf("metadata after pause %+v", meta)
	}
	if calls := h.net.Snapshot(); calls[len(calls)-1] != "teardown "+ns+" 0" {
		t.Fatalf("network calls after pause %v", calls)
	}
	if _, err := h.m.Pause(ctx, testID); !errors.Is(err, ErrNotRunning) {
		t.Fatalf("double pause should fail, got %v", err)
	}
	if _, err := h.m.Exec(ctx, protocol.ExecArgs{SandboxID: testID, Cmd: []string{"true"}}, nil); !errors.Is(err, ErrNotRunning) {
		t.Fatalf("exec on paused should fail, got %v", err)
	}

	resumeRes, err := h.m.Resume(ctx, testID)
	if err != nil {
		t.Fatalf("resume: %v", err)
	}
	if resumeRes.RestoreMs < 0 {
		t.Fatalf("resume result %+v", resumeRes)
	}
	resumed := h.launcher.Last()
	if resumed == inst {
		t.Fatal("resume must spawn a new firecracker")
	}
	if paths := callPaths(resumed); strings.Join(paths, ",") != "PUT /snapshot/load" {
		t.Fatalf("resume api calls %v", paths)
	}
	configures = resumed.Agent.RequestsOf("configure")
	if len(configures) != 1 || configures[0]["format_workspace"] != nil {
		t.Fatalf("resume configure must not format: %v", configures)
	}
	meta, _ = LoadMetadata(root)
	if meta.State != protocol.StateRunning || meta.Generation != 1 || meta.Slot != 0 {
		t.Fatalf("metadata after resume %+v", meta)
	}
	if _, err := h.m.Resume(ctx, testID); !errors.Is(err, ErrNotPaused) {
		t.Fatalf("resume of running should fail, got %v", err)
	}

	if err := h.m.Delete(ctx, testID); err != nil {
		t.Fatalf("delete: %v", err)
	}
	if !resumed.Killed() {
		t.Fatal("delete must kill the vm")
	}
	if vm.Exists(vm.JailDir(h.jailBase, testID)) {
		t.Fatal("delete must remove the jail dir")
	}
	if len(h.m.List()) != 0 {
		t.Fatalf("list after delete %v", h.m.List())
	}
	if slot, _ := h.slots.Allocate(); slot != 0 {
		t.Fatalf("slot should be released, got %d", slot)
	}
	if _, err := h.m.Status(ctx, testID); !errors.Is(err, ErrNotFound) {
		t.Fatalf("status after delete %v", err)
	}
}

func TestCreateValidation(t *testing.T) {
	h := newHarness(t)
	ctx := context.Background()
	if _, err := h.m.Create(ctx, protocol.CreateArgs{SandboxID: "bad/id", VCPUs: 2, MemoryMB: 4096}); err == nil {
		t.Fatal("bad id accepted")
	}
	if _, err := h.m.Create(ctx, protocol.CreateArgs{SandboxID: "ok", VCPUs: 0, MemoryMB: 4096}); err == nil {
		t.Fatal("zero vcpus accepted")
	}
	if _, err := h.m.Create(ctx, protocol.CreateArgs{SandboxID: "ok", Template: "nope", VCPUs: 2, MemoryMB: 4096}); err == nil {
		t.Fatal("unknown template accepted")
	}
	h.create(t, "dup", 0)
	if _, err := h.m.Create(ctx, protocol.CreateArgs{SandboxID: "dup", VCPUs: 2, MemoryMB: 4096}); !errors.Is(err, ErrAlreadyExists) {
		t.Fatalf("duplicate should fail, got %v", err)
	}
	meta, _ := LoadMetadata(vm.RootDir(h.jailBase, "dup"))
	if meta.WorkspaceGB != DefaultWorkspaceGB {
		t.Fatalf("default workspace %+v", meta)
	}
	// Same workspace size as the template: no drive patch.
	inst := h.launcher.Last()
	if paths := callPaths(inst); strings.Join(paths, ",") != "PUT /snapshot/load" {
		t.Fatalf("api calls %v", paths)
	}
}

func TestCreateFailureCleansUp(t *testing.T) {
	h := newHarness(t)
	// Build the template first so the failure hits the sandbox launch.
	h.create(t, "warm", 0)
	if err := h.m.Delete(context.Background(), "warm"); err != nil {
		t.Fatal(err)
	}
	h.launcher.FailLaunch = errors.New("no kvm")
	_, err := h.m.Create(context.Background(), protocol.CreateArgs{SandboxID: "fails", VCPUs: 2, MemoryMB: 4096})
	if err == nil || !strings.Contains(err.Error(), "no kvm") {
		t.Fatalf("expected launch failure, got %v", err)
	}
	if len(h.m.List()) != 0 {
		t.Fatalf("failed create left a registry entry: %v", h.m.List())
	}
	if vm.Exists(vm.JailDir(h.jailBase, "fails")) {
		t.Fatal("failed create left its jail dir")
	}
	calls := h.net.Snapshot()
	if calls[len(calls)-1] != "teardown "+network.NamespaceName("fails")+" 0" {
		t.Fatalf("network calls %v", calls)
	}
	if h.slots.InUse() != 0 {
		t.Fatal("slot leaked")
	}
}

func TestSandboxDeathIsReported(t *testing.T) {
	h := newHarness(t)
	h.create(t, testID, 0)
	inst := h.launcher.Last()
	inst.Crash()
	event := h.events.wait(t, protocol.EventSandboxDied, 5*time.Second)
	if event.SandboxID != testID || event.Reason == "" {
		t.Fatalf("sandbox_died %+v", event)
	}
	deadline := time.Now().Add(2 * time.Second)
	for {
		info, _ := h.m.Status(context.Background(), testID)
		if info.State == protocol.StateError {
			if info.Error == "" {
				t.Fatal("error state without reason")
			}
			break
		}
		if time.Now().After(deadline) {
			t.Fatalf("state %+v", info)
		}
		time.Sleep(10 * time.Millisecond)
	}
	if _, err := h.m.Exec(context.Background(), protocol.ExecArgs{SandboxID: testID, Cmd: []string{"true"}}, nil); !errors.Is(err, ErrNotRunning) {
		t.Fatalf("exec on dead sandbox: %v", err)
	}
	if err := h.m.Delete(context.Background(), testID); err != nil {
		t.Fatalf("delete dead sandbox: %v", err)
	}
}

func TestPauseSnapshotFailureKeepsRunning(t *testing.T) {
	h := newHarness(t)
	h.create(t, testID, 0)
	inst := h.launcher.Last()
	inst.FailSnapshotCreate = true
	_, err := h.m.Pause(context.Background(), testID)
	if err == nil {
		t.Fatal("expected snapshot failure")
	}
	info, _ := h.m.Status(context.Background(), testID)
	if info.State != protocol.StateRunning {
		t.Fatalf("state after failed pause %+v", info)
	}
	if inst.Killed() {
		t.Fatal("vm must survive a failed snapshot")
	}
	paths := callPaths(inst)
	if paths[len(paths)-1] != "PATCH /vm" {
		t.Fatalf("expected a resume after the failed snapshot: %v", paths)
	}
	if _, err := h.m.Exec(context.Background(), protocol.ExecArgs{SandboxID: testID, Cmd: []string{"true"}}, nil); err != nil {
		t.Fatalf("exec after failed pause: %v", err)
	}
}

func TestRecover(t *testing.T) {
	h := newHarness(t)
	base := filepath.Join(h.jailBase, "firecracker")
	write := func(id string, meta Metadata, files ...string) {
		root := vm.RootDir(h.jailBase, id)
		if err := os.MkdirAll(root, 0o755); err != nil {
			t.Fatal(err)
		}
		for _, f := range files {
			if err := os.WriteFile(filepath.Join(root, f), []byte("x"), 0o644); err != nil {
				t.Fatal(err)
			}
		}
		if meta.ID != "" {
			if err := meta.Save(root); err != nil {
				t.Fatal(err)
			}
		}
	}
	write("wasrunning", Metadata{ID: "wasrunning", Template: "default", Tag: "t1", VCPUs: 2, MemoryMB: 4096, State: protocol.StateRunning, Slot: 3, Generation: 2}, "mem", "snapshot", "mem.new")
	write("nosnapshot", Metadata{ID: "nosnapshot", Template: "default", Tag: "t1", VCPUs: 2, MemoryMB: 4096, State: protocol.StateRunning, Slot: 1})
	write("waspaused", Metadata{ID: "waspaused", Template: "default", Tag: "t1", VCPUs: 2, MemoryMB: 4096, State: protocol.StatePaused, Slot: 0, Generation: 1}, "mem", "snapshot")
	write("tmpl-default-t1-2x4096", Metadata{}, "mem")
	h.net.Existing = []string{"sbx-stale", "sbx-tmpl-deadbeef"}

	if err := h.m.Recover(context.Background()); err != nil {
		t.Fatal(err)
	}
	byID := map[string]protocol.SandboxInfo{}
	for _, info := range h.m.List() {
		byID[info.ID] = info
	}
	if len(byID) != 3 {
		t.Fatalf("recovered %v", byID)
	}
	if byID["wasrunning"].State != protocol.StatePaused || byID["wasrunning"].Generation != 2 {
		t.Fatalf("wasrunning %+v", byID["wasrunning"])
	}
	if byID["nosnapshot"].State != protocol.StateError || byID["nosnapshot"].Error == "" {
		t.Fatalf("nosnapshot %+v", byID["nosnapshot"])
	}
	if byID["waspaused"].State != protocol.StatePaused {
		t.Fatalf("waspaused %+v", byID["waspaused"])
	}
	if vm.Exists(filepath.Join(base, "tmpl-default-t1-2x4096")) {
		t.Fatal("jail dir without metadata should be removed")
	}
	if vm.Exists(filepath.Join(vm.RootDir(h.jailBase, "wasrunning"), "mem.new")) {
		t.Fatal("stale mem.new should be removed")
	}
	meta, _ := LoadMetadata(vm.RootDir(h.jailBase, "wasrunning"))
	if meta.State != protocol.StatePaused {
		t.Fatalf("recovered state must be persisted: %+v", meta)
	}
	calls := strings.Join(h.net.Snapshot(), "\n")
	for _, want := range []string{"teardown sbx-stale -1", "teardown sbx-tmpl-deadbeef -1"} {
		if !strings.Contains(calls, want) {
			t.Fatalf("missing %q in network calls:\n%s", want, calls)
		}
	}
	for _, slot := range []int{0, 1, 3} {
		if err := h.slots.Reserve(slot); err == nil {
			t.Fatalf("slot %d should have been reserved by recovery", slot)
		}
	}
	if slot, _ := h.slots.Allocate(); slot != 2 {
		t.Fatalf("next free slot should be 2, got %d", slot)
	}
	// The recovered sandbox resumes from its own snapshot.
	if _, err := h.m.Resume(context.Background(), "waspaused"); err == nil {
		t.Fatal("resume without rootfs/workspace/vmlinux should fail")
	}
	write("waspaused", Metadata{}, "rootfs.ext4", "workspace.ext4", "vmlinux")
	if _, err := h.m.Resume(context.Background(), "waspaused"); err != nil {
		t.Fatalf("resume recovered sandbox: %v", err)
	}
}

func TestShutdownPausesIdleSandboxes(t *testing.T) {
	h := newHarness(t)
	h.create(t, "idle", 0)
	h.create(t, "busy", 0)
	if _, err := h.m.StartWorker(context.Background(), protocol.StartWorkerArgs{SandboxID: "busy"}); err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	h.m.Shutdown(ctx)
	idle, _ := h.m.Status(ctx, "idle")
	busy, _ := h.m.Status(ctx, "busy")
	if idle.State != protocol.StatePaused {
		t.Fatalf("idle sandbox should be paused: %+v", idle)
	}
	if busy.State != protocol.StateRunning || !busy.WorkerRunning {
		t.Fatalf("busy sandbox should keep running: %+v", busy)
	}
}

func TestTemplatesAdvertiseReadyShapes(t *testing.T) {
	h := newHarness(t)
	infos := h.m.Templates()
	if len(infos) != 1 || !infos[0].Ready || len(infos[0].Shapes) != 0 || infos[0].Name != "default" || infos[0].Tag != "t1" {
		t.Fatalf("templates before build %+v", infos)
	}
	if err := h.m.BuildTemplate(context.Background(), "default", "", template.Shape{VCPUs: 4, MemoryMB: 8192}); err != nil {
		t.Fatal(err)
	}
	infos = h.m.Templates()
	if len(infos[0].Shapes) != 1 || infos[0].Shapes[0] != "4x8192" {
		t.Fatalf("templates after build %+v", infos)
	}
}

func TestMetadataRoundTrip(t *testing.T) {
	root := t.TempDir()
	meta := Metadata{ID: "s1", Template: "default", Tag: "t1", VCPUs: 2, MemoryMB: 4096, WorkspaceGB: 10, Hostname: "sbx-s1", State: protocol.StatePaused, Slot: 4, Generation: 3, CreatedAt: time.Now().UTC().Truncate(time.Second)}
	if err := meta.Save(root); err != nil {
		t.Fatal(err)
	}
	loaded, err := LoadMetadata(root)
	if err != nil {
		t.Fatal(err)
	}
	if loaded.ID != "s1" || loaded.Slot != 4 || loaded.Generation != 3 || loaded.State != protocol.StatePaused || !loaded.CreatedAt.Equal(meta.CreatedAt) || loaded.UpdatedAt.IsZero() {
		t.Fatalf("loaded %+v", loaded)
	}
	if loaded.Shape().String() != "2x4096" {
		t.Fatal("shape")
	}
	info := loaded.Info(true)
	if info.TemplateTag != "t1" || !info.WorkerRunning || info.State != protocol.StatePaused {
		t.Fatalf("info %+v", info)
	}
	if _, err := LoadMetadata(t.TempDir()); err == nil {
		t.Fatal("missing metadata should error")
	}
	if err := os.WriteFile(filepath.Join(root, MetadataFile), []byte(`{"state":"paused"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	if _, err := LoadMetadata(root); err == nil {
		t.Fatal("metadata without id should error")
	}
}

type fakeOps struct {
	calls []string
}

func (f *fakeOps) Create(ctx context.Context, args protocol.CreateArgs) (protocol.CreateResult, error) {
	f.calls = append(f.calls, "create "+args.SandboxID)
	if args.VCPUs != 2 || args.MemoryMB != 4096 || args.WorkspaceGB != 10 || args.Hostname != "sbx-abc" {
		return protocol.CreateResult{}, errors.New("args not decoded")
	}
	return protocol.CreateResult{BootMs: 42}, nil
}
func (f *fakeOps) Resume(ctx context.Context, id string) (protocol.ResumeResult, error) {
	f.calls = append(f.calls, "resume "+id)
	return protocol.ResumeResult{RestoreMs: 7}, nil
}
func (f *fakeOps) Pause(ctx context.Context, id string) (protocol.PauseResult, error) {
	f.calls = append(f.calls, "pause "+id)
	return protocol.PauseResult{}, ErrBusy
}
func (f *fakeOps) Delete(ctx context.Context, id string) error {
	f.calls = append(f.calls, "delete "+id)
	return nil
}
func (f *fakeOps) Exec(ctx context.Context, args protocol.ExecArgs, out vsock.OutputFunc) (protocol.ExecResult, error) {
	f.calls = append(f.calls, "exec "+args.SandboxID)
	if ctx.Err() != nil {
		return protocol.ExecResult{}, ctx.Err()
	}
	out("stdout", []byte("hello\n"))
	out("stderr", []byte("warn\n"))
	return protocol.ExecResult{ExitCode: 3, DurationMs: 5}, nil
}
func (f *fakeOps) StartWorker(ctx context.Context, args protocol.StartWorkerArgs) (protocol.StartWorkerResult, error) {
	f.calls = append(f.calls, "start_worker "+args.SandboxID)
	if args.Env["ANTHROPIC_WORK_ID"] != "w1" {
		return protocol.StartWorkerResult{}, errors.New("env not decoded")
	}
	return protocol.StartWorkerResult{ExecID: "e1"}, nil
}
func (f *fakeOps) StopWorker(ctx context.Context, id string) error {
	f.calls = append(f.calls, "stop_worker "+id)
	return nil
}
func (f *fakeOps) Status(ctx context.Context, id string) (protocol.SandboxInfo, error) {
	f.calls = append(f.calls, "status "+id)
	return protocol.SandboxInfo{ID: id, State: protocol.StateRunning}, nil
}

func TestDispatch(t *testing.T) {
	ops := &fakeOps{}
	run := func(op, args string) (protocol.Result, []protocol.Stream) {
		var streams []protocol.Stream
		cmd := protocol.Command{Type: protocol.FrameCommand, ID: "c-" + op, Op: op, Args: json.RawMessage(args)}
		res := Dispatch(context.Background(), ops, cmd, func(s protocol.Stream) { streams = append(streams, s) })
		return res, streams
	}
	res, _ := run("create", `{"sandbox_id":"s1","template":"default","vcpus":2,"memory_mb":4096,"workspace_gb":10,"hostname":"sbx-abc"}`)
	if !res.OK || res.ID != "c-create" || res.Data.(protocol.CreateResult).BootMs != 42 {
		t.Fatalf("create result %+v", res)
	}
	res, _ = run("resume", `{"sandbox_id":"s1"}`)
	if !res.OK || res.Data.(protocol.ResumeResult).RestoreMs != 7 {
		t.Fatalf("resume result %+v", res)
	}
	res, _ = run("pause", `{"sandbox_id":"s1"}`)
	if res.OK || !strings.Contains(res.Error, "worker or exec running") {
		t.Fatalf("pause result %+v", res)
	}
	res, streams := run("exec", `{"sandbox_id":"s1","cmd":["ls"],"cwd":"/workspace","timeout_ms":1000}`)
	if !res.OK || res.Data.(protocol.ExecResult).ExitCode != 3 {
		t.Fatalf("exec result %+v", res)
	}
	if len(streams) != 2 || streams[0].Stream != "stdout" || streams[0].ID != "c-exec" || streams[0].Type != protocol.FrameStream || streams[0].DataB64 != "aGVsbG8K" || streams[1].Stream != "stderr" {
		t.Fatalf("streams %+v", streams)
	}
	res, _ = run("start_worker", `{"sandbox_id":"s1","env":{"ANTHROPIC_WORK_ID":"w1"}}`)
	if !res.OK || res.Data.(protocol.StartWorkerResult).ExecID != "e1" {
		t.Fatalf("start_worker result %+v", res)
	}
	res, _ = run("stop_worker", `{"sandbox_id":"s1"}`)
	if !res.OK {
		t.Fatalf("stop_worker result %+v", res)
	}
	res, _ = run("status", `{"sandbox_id":"s1"}`)
	if !res.OK || res.Data.(protocol.SandboxInfo).State != protocol.StateRunning {
		t.Fatalf("status result %+v", res)
	}
	res, _ = run("delete", `{"sandbox_id":"s1"}`)
	if !res.OK {
		t.Fatalf("delete result %+v", res)
	}
	res, _ = run("explode", `{}`)
	if res.OK || !strings.Contains(res.Error, "unknown op") {
		t.Fatalf("unknown op result %+v", res)
	}
	res, _ = run("create", ``)
	if res.OK || !strings.Contains(res.Error, "missing args") {
		t.Fatalf("missing args result %+v", res)
	}
	res, _ = run("create", `{"vcpus":"two"}`)
	if res.OK || !strings.Contains(res.Error, "decoding args") {
		t.Fatalf("bad args result %+v", res)
	}
	if strings.Join(ops.calls, ",") != "create s1,resume s1,pause s1,exec s1,start_worker s1,stop_worker s1,status s1,delete s1" {
		t.Fatalf("calls %v", ops.calls)
	}
	data, _ := json.Marshal(Dispatch(context.Background(), ops, protocol.Command{ID: "x", Op: "delete", Args: json.RawMessage(`{"sandbox_id":"s1"}`)}, nil))
	if string(data) != `{"type":"result","id":"x","ok":true,"data":{}}` {
		t.Fatalf("delete result encoding %s", data)
	}
}

func TestLifecycleOpsRunDetachedFromCommandContext(t *testing.T) {
	ops := &fakeOps{}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	res := Dispatch(ctx, ops, protocol.Command{ID: "c", Op: "resume", Args: json.RawMessage(`{"sandbox_id":"s1"}`)}, nil)
	if !res.OK {
		t.Fatalf("lifecycle op should not see the cancelled context: %+v", res)
	}
	res = Dispatch(ctx, ops, protocol.Command{ID: "c", Op: "exec", Args: json.RawMessage(`{"sandbox_id":"s1","cmd":["ls"]}`)}, nil)
	if res.OK {
		t.Fatalf("exec should see the cancelled context: %+v", res)
	}
}
