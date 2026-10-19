package template

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
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
	"github.com/tuist/tuist/infra/sandboxd/internal/vsock"
)

func TestShapeParsing(t *testing.T) {
	shape, err := ParseShape("2x4096")
	if err != nil || shape.VCPUs != 2 || shape.MemoryMB != 4096 || shape.String() != "2x4096" {
		t.Fatalf("got %+v %v", shape, err)
	}
	for _, bad := range []string{"", "2", "x4096", "0x4096", "2x64", "2 x 4096", "33x4096"} {
		if _, err := ParseShape(bad); err == nil {
			t.Fatalf("%q should be rejected", bad)
		}
	}
	shapes, err := ParseShapes(" 2x4096, 4x8192 ,")
	if err != nil || len(shapes) != 2 || shapes[1].String() != "4x8192" {
		t.Fatalf("got %v %v", shapes, err)
	}
	if shapes, err := ParseShapes(""); err != nil || len(shapes) != 0 {
		t.Fatalf("empty list: %v %v", shapes, err)
	}
}

func seedTemplate(t *testing.T, dir, name, tag string) Template {
	t.Helper()
	tdir := filepath.Join(dir, name, tag)
	if err := os.MkdirAll(tdir, 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tdir, KernelFile), []byte("kernel"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tdir, RootfsFile), []byte("pristine rootfs"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(tdir, MetadataFile), []byte(`{"name":"default","tag":"t1","kernel":"vmlinux-6.1"}`), 0o644); err != nil {
		t.Fatal(err)
	}
	return Template{Name: name, Tag: tag, Dir: tdir}
}

func TestStoreDiscovery(t *testing.T) {
	dir := t.TempDir()
	store := &Store{Dir: dir}
	if list, err := store.List(); err != nil || len(list) != 0 {
		t.Fatalf("empty store: %v %v", list, err)
	}
	seedTemplate(t, dir, "default", "t1")
	if err := os.MkdirAll(filepath.Join(dir, "default", "broken"), 0o755); err != nil {
		t.Fatal(err)
	}
	list, err := store.List()
	if err != nil || len(list) != 1 || list[0].Tag != "t1" {
		t.Fatalf("list: %v %v", list, err)
	}
	if _, err := store.Get("default", "broken"); err == nil {
		t.Fatal("broken template should not resolve")
	}
	got, err := store.Resolve("default", "")
	if err != nil || got.Tag != "t1" {
		t.Fatalf("resolve single tag: %+v %v", got, err)
	}
	seedTemplate(t, dir, "default", "t2")
	if _, err := store.Resolve("default", ""); err == nil || !strings.Contains(err.Error(), "several tags") {
		t.Fatalf("expected ambiguity error, got %v", err)
	}
	if got, err := store.Resolve("default", "t2"); err != nil || got.Tag != "t2" {
		t.Fatalf("resolve explicit: %+v %v", got, err)
	}
	if _, err := store.Resolve("missing", ""); err == nil {
		t.Fatal("missing template should error")
	}
}

func TestBuildID(t *testing.T) {
	id := BuildID(Template{Name: "default", Tag: "sha-abc.1"}, Shape{VCPUs: 2, MemoryMB: 4096})
	if id != "tmpl-default-sha-abc-1-2x4096" {
		t.Fatalf("got %q", id)
	}
	if err := vm.ValidateID(BuildID(Template{Name: strings.Repeat("n", 40), Tag: strings.Repeat("t", 40)}, Shape{VCPUs: 2, MemoryMB: 4096})); err != nil {
		t.Fatal(err)
	}
}

type eventSink struct {
	mu     sync.Mutex
	events []protocol.Event
}

func (s *eventSink) add(e protocol.Event) {
	s.mu.Lock()
	s.events = append(s.events, e)
	s.mu.Unlock()
}

func (s *eventSink) all() []protocol.Event {
	s.mu.Lock()
	defer s.mu.Unlock()
	return append([]protocol.Event(nil), s.events...)
}

func newBuilder(t *testing.T, dataDir string, launcher *fakevm.Launcher, net *fakevm.Network, sink *eventSink) *Builder {
	t.Helper()
	return &Builder{
		Store:              &Store{Dir: filepath.Join(dataDir, "templates")},
		Launcher:           launcher,
		Network:            net,
		Slots:              network.NewSlots(16),
		Agent:              func(path string) vsock.Agent { return vsock.NewUDSClient(path, firecracker.AgentPort) },
		JailBase:           filepath.Join(dataDir, "jail"),
		FirecrackerBin:     "/usr/local/bin/firecracker",
		JailerBin:          "/usr/local/bin/jailer",
		JailerEnabled:      true,
		UIDBase:            10000,
		DNS:                []string{"10.128.0.10"},
		FirecrackerVersion: "v1.16.1",
		WorkspaceGB:        10,
		BootTimeout:        5 * time.Second,
		Events:             sink.add,
	}
}

func TestBuilderEnsureBuildsShapeSnapshot(t *testing.T) {
	dataDir := t.TempDir()
	tmpl := seedTemplate(t, filepath.Join(dataDir, "templates"), "default", "t1")
	launcher := &fakevm.Launcher{}
	net := &fakevm.Network{}
	sink := &eventSink{}
	var observed []string
	b := newBuilder(t, dataDir, launcher, net, sink)
	b.Observe = func(shape Shape, elapsed time.Duration, err error) {
		observed = append(observed, shape.String())
	}
	shape := Shape{VCPUs: 2, MemoryMB: 4096}

	artifacts, err := b.Ensure(context.Background(), tmpl, shape)
	if err != nil {
		t.Fatal(err)
	}
	shapeDir := tmpl.ShapeDir(shape)
	if artifacts.Dir != shapeDir {
		t.Fatalf("artifacts dir %s", artifacts.Dir)
	}
	for _, name := range []string{BootRootfs, MemFile, SnapshotFile, MetadataFile, ReadyFile} {
		if !vm.Exists(filepath.Join(shapeDir, name)) {
			t.Fatalf("missing %s in %s", name, shapeDir)
		}
	}
	if data, _ := os.ReadFile(artifacts.Rootfs); string(data) != "pristine rootfs" {
		t.Fatalf("boot rootfs content %q", data)
	}
	if !vm.Exists(tmpl.Rootfs()) {
		t.Fatal("pristine rootfs must be kept")
	}
	var meta Metadata
	data, _ := os.ReadFile(filepath.Join(shapeDir, MetadataFile))
	if err := json.Unmarshal(data, &meta); err != nil {
		t.Fatal(err)
	}
	if meta.Name != "default" || meta.Tag != "t1" || meta.VCPUs != 2 || meta.MemoryMB != 4096 || meta.WorkspaceGB != 10 || meta.FirecrackerVersion != "v1.16.1" || meta.Kernel != "vmlinux-6.1" || meta.BuiltAt.IsZero() {
		t.Fatalf("metadata %+v", meta)
	}
	if artifacts.Meta.WorkspaceGB != 10 {
		t.Fatalf("artifacts meta %+v", artifacts.Meta)
	}

	inst := launcher.Last()
	if inst == nil {
		t.Fatal("no vm launched")
	}
	calls := inst.Calls()
	var sequence []string
	byPath := map[string]map[string]any{}
	for _, c := range calls {
		if c.Method == "GET" {
			continue
		}
		sequence = append(sequence, c.Method+" "+c.Path)
		byPath[c.Method+" "+c.Path] = c.Body
	}
	want := []string{"PUT /machine-config", "PUT /boot-source", "PUT /drives/rootfs", "PUT /drives/workspace", "PUT /network-interfaces/eth0", "PUT /vsock", "PUT /actions", "PATCH /vm", "PUT /snapshot/create"}
	if strings.Join(sequence, ",") != strings.Join(want, ",") {
		t.Fatalf("api sequence\n got %v\nwant %v", sequence, want)
	}
	if byPath["PUT /machine-config"]["vcpu_count"] != float64(2) || byPath["PUT /machine-config"]["mem_size_mib"] != float64(4096) {
		t.Fatalf("machine config %v", byPath["PUT /machine-config"])
	}
	bootArgs, _ := byPath["PUT /boot-source"]["boot_args"].(string)
	if !strings.Contains(bootArgs, "sbx.dns=10.128.0.10") || !strings.Contains(bootArgs, "sbx.hostname=sandbox") || byPath["PUT /boot-source"]["kernel_image_path"] != "/vmlinux" {
		t.Fatalf("boot source %v", byPath["PUT /boot-source"])
	}
	if byPath["PUT /drives/workspace"]["path_on_host"] != "/workspace.ext4" || byPath["PUT /drives/rootfs"]["is_root_device"] != true {
		t.Fatalf("drives %v %v", byPath["PUT /drives/rootfs"], byPath["PUT /drives/workspace"])
	}
	if byPath["PUT /vsock"]["uds_path"] != "/v.sock" || byPath["PUT /vsock"]["guest_cid"] != float64(3) {
		t.Fatalf("vsock %v", byPath["PUT /vsock"])
	}
	if byPath["PATCH /vm"]["state"] != "Paused" {
		t.Fatalf("vm state %v", byPath["PATCH /vm"])
	}
	if byPath["PUT /snapshot/create"]["snapshot_path"] != "/snapshot" || byPath["PUT /snapshot/create"]["mem_file_path"] != "/mem" || byPath["PUT /snapshot/create"]["snapshot_type"] != "Full" {
		t.Fatalf("snapshot create %v", byPath["PUT /snapshot/create"])
	}
	if !inst.Killed() {
		t.Fatal("template vm must be killed, never resumed")
	}
	if pings := inst.Agent.RequestsOf("ping"); len(pings) == 0 {
		t.Fatal("expected ping before snapshot")
	}
	if len(inst.Agent.RequestsOf("configure")) != 0 {
		t.Fatal("template build must not configure the guest")
	}

	if vm.Exists(vm.JailDir(b.JailBase, BuildID(tmpl, shape))) {
		t.Fatal("build jail dir should be removed")
	}
	if vm.Exists(shapeDir + buildSuffix) {
		t.Fatal("staging dir should be renamed away")
	}
	netCalls := net.Snapshot()
	ns := network.BuildNamespaceName(BuildID(tmpl, shape))
	if len(netCalls) != 2 || netCalls[0] != "setup "+ns+" 0" || netCalls[1] != "teardown "+ns+" 0" {
		t.Fatalf("network calls %v", netCalls)
	}
	if b.Slots.InUse() != 0 {
		t.Fatal("build slot should be released")
	}
	events := sink.all()
	if len(events) != 1 || events[0].Event != protocol.EventTemplateReady || events[0].Name != "default" || events[0].Tag != "t1" || events[0].Shape != "2x4096" {
		t.Fatalf("events %+v", events)
	}
	if len(observed) != 1 {
		t.Fatalf("observed %v", observed)
	}
	if got := tmpl.ReadyShapes(); len(got) != 1 || got[0] != shape {
		t.Fatalf("ready shapes %v", got)
	}

	// A second Ensure is served from disk without another build.
	if _, err := b.Ensure(context.Background(), tmpl, shape); err != nil {
		t.Fatal(err)
	}
	if len(launcher.Instances()) != 1 {
		t.Fatal("ready shape must not rebuild")
	}
}

func TestBuilderSerializesConcurrentEnsures(t *testing.T) {
	dataDir := t.TempDir()
	tmpl := seedTemplate(t, filepath.Join(dataDir, "templates"), "default", "t1")
	launcher := &fakevm.Launcher{AgentBootDelay: 100 * time.Millisecond}
	b := newBuilder(t, dataDir, launcher, &fakevm.Network{}, &eventSink{})
	shape := Shape{VCPUs: 4, MemoryMB: 8192}
	var wg sync.WaitGroup
	errs := make(chan error, 5)
	for i := 0; i < 5; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := b.Ensure(context.Background(), tmpl, shape)
			errs <- err
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	if len(launcher.Instances()) != 1 {
		t.Fatalf("expected one build, got %d", len(launcher.Instances()))
	}
}

func TestBuilderFailureLeavesNoShape(t *testing.T) {
	dataDir := t.TempDir()
	tmpl := seedTemplate(t, filepath.Join(dataDir, "templates"), "default", "t1")
	launcher := &fakevm.Launcher{FailLaunch: errors.New("kvm unavailable")}
	net := &fakevm.Network{}
	b := newBuilder(t, dataDir, launcher, net, &eventSink{})
	shape := Shape{VCPUs: 2, MemoryMB: 4096}
	_, err := b.Ensure(context.Background(), tmpl, shape)
	if err == nil || !strings.Contains(err.Error(), "kvm unavailable") {
		t.Fatalf("expected launch failure, got %v", err)
	}
	if tmpl.ShapeReady(shape) {
		t.Fatal("failed build must not mark the shape ready")
	}
	if vm.Exists(vm.JailDir(b.JailBase, BuildID(tmpl, shape))) {
		t.Fatal("failed build must remove its jail dir")
	}
	calls := net.Snapshot()
	if len(calls) != 2 || !strings.HasPrefix(calls[1], "teardown ") {
		t.Fatalf("network calls %v", calls)
	}
	// The failure is not sticky: the next Ensure builds.
	if _, err := b.Ensure(context.Background(), tmpl, shape); err != nil {
		t.Fatal(err)
	}
}

func TestBuilderEnsureCallerCancellationDoesNotAbortBuild(t *testing.T) {
	dataDir := t.TempDir()
	tmpl := seedTemplate(t, filepath.Join(dataDir, "templates"), "default", "t1")
	launcher := &fakevm.Launcher{AgentBootDelay: 200 * time.Millisecond}
	b := newBuilder(t, dataDir, launcher, &fakevm.Network{}, &eventSink{})
	shape := Shape{VCPUs: 2, MemoryMB: 4096}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	if _, err := b.Ensure(ctx, tmpl, shape); !errors.Is(err, context.DeadlineExceeded) {
		t.Fatalf("expected deadline, got %v", err)
	}
	if _, err := b.Ensure(context.Background(), tmpl, shape); err != nil {
		t.Fatal(err)
	}
	if len(launcher.Instances()) != 1 {
		t.Fatalf("expected the first build to complete, got %d builds", len(launcher.Instances()))
	}
}

func TestCleanPartialBuilds(t *testing.T) {
	dataDir := t.TempDir()
	tmpl := seedTemplate(t, filepath.Join(dataDir, "templates"), "default", "t1")
	ready := tmpl.ShapeDir(Shape{VCPUs: 2, MemoryMB: 4096})
	partial := tmpl.ShapeDir(Shape{VCPUs: 4, MemoryMB: 8192})
	staging := partial + buildSuffix
	for _, d := range []string{ready, partial, staging} {
		if err := os.MkdirAll(d, 0o755); err != nil {
			t.Fatal(err)
		}
	}
	if err := os.WriteFile(filepath.Join(ready, ReadyFile), nil, 0o644); err != nil {
		t.Fatal(err)
	}
	store := &Store{Dir: filepath.Join(dataDir, "templates")}
	if err := store.CleanPartialBuilds(); err != nil {
		t.Fatal(err)
	}
	if !vm.Exists(ready) || vm.Exists(partial) || vm.Exists(staging) {
		t.Fatal("clean removed the wrong directories")
	}
}
