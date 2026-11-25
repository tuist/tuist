package vm

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
)

// sleepLauncher stands in for Firecracker with a sleep process, so the
// daemon side's SIGKILL backstop only ever reaches a process the test owns.
type sleepLauncher struct {
	mu     sync.Mutex
	specs  []Spec
	cgroup []string
	last   *sleepInstance
}

func (l *sleepLauncher) Launch(_ context.Context, spec Spec) (Instance, error) {
	if spec.MountNS == nil {
		return nil, errors.New("no mount namespace fd")
	}
	cgroupTarget := ""
	if spec.Cgroup != nil {
		// The fd vmm received names the same directory the daemon opened.
		target, err := os.Readlink("/proc/self/fd/" + strconv.Itoa(int(spec.Cgroup.Fd())))
		if err != nil {
			return nil, err
		}
		cgroupTarget = target
	}
	cmd := exec.Command("sleep", "60")
	if err := cmd.Start(); err != nil {
		return nil, err
	}
	inst := &sleepInstance{cmd: cmd, done: make(chan struct{})}
	go func() {
		inst.err = cmd.Wait()
		close(inst.done)
	}()
	l.mu.Lock()
	l.specs = append(l.specs, spec)
	l.cgroup = append(l.cgroup, cgroupTarget)
	l.last = inst
	l.mu.Unlock()
	return inst, nil
}

type sleepInstance struct {
	cmd  *exec.Cmd
	done chan struct{}
	err  error
}

func (i *sleepInstance) ID() string                     { return "" }
func (i *sleepInstance) Root() string                   { return "" }
func (i *sleepInstance) HostPath(string) string         { return "" }
func (i *sleepInstance) GuestPath(string) string        { return "" }
func (i *sleepInstance) API() *firecracker.Client       { return nil }
func (i *sleepInstance) VsockPath() string              { return "" }
func (i *sleepInstance) PID() int                       { return i.cmd.Process.Pid }
func (i *sleepInstance) CPUTime() (time.Duration, bool) { return 0, false }
func (i *sleepInstance) ResidentMemory() (Memory, bool) { return Memory{}, false }
func (i *sleepInstance) Done() <-chan struct{}          { return i.done }
func (i *sleepInstance) ExitError() error               { <-i.done; return i.err }
func (i *sleepInstance) Kill(context.Context) error {
	_ = i.cmd.Process.Kill()
	<-i.done
	return nil
}

func startVMM(t *testing.T, configure ...func(*VMMServer)) (*VMMServer, *sleepLauncher, string) {
	t.Helper()
	socket := filepath.Join(t.TempDir(), "vmm.sock")
	ln, err := net.ListenUnix("unix", &net.UnixAddr{Name: socket, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	launcher := &sleepLauncher{}
	server := &VMMServer{Launcher: launcher, Cgroup: "/kubepods/pod1/vmm", FirecrackerVersion: "v1.16.2", Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
	for _, f := range configure {
		f(server)
	}
	go func() { _ = server.Serve(ln) }()
	t.Cleanup(func() { _ = ln.Close() })
	return server, launcher, socket
}

func waitFor(t *testing.T, what string, ok func() bool) {
	t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for !ok() {
		if time.Now().After(deadline) {
			t.Fatalf("timed out waiting for %s", what)
		}
		time.Sleep(10 * time.Millisecond)
	}
}

func TestVMMHello(t *testing.T) {
	_, _, socket := startVMM(t)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	got, gone, err := VMMHello(ctx, socket)
	if err != nil || got != (VMMInfo{Cgroup: "/kubepods/pod1/vmm", FirecrackerVersion: "v1.16.2"}) {
		t.Fatalf("VMMHello = %+v, %v", got, err)
	}
	select {
	case <-gone:
		t.Fatal("gone closed while vmm runs")
	case <-time.After(100 * time.Millisecond):
	}
}

// The daemon learns that vmm stopped: its VMs went with it.
func TestVMMHelloGoneWhenVMMStops(t *testing.T) {
	socket := filepath.Join(t.TempDir(), "vmm.sock")
	ln, err := net.ListenUnix("unix", &net.UnixAddr{Name: socket, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	type result struct {
		gone <-chan struct{}
		err  error
	}
	got := make(chan result, 1)
	go func() {
		_, gone, err := VMMHello(ctx, socket)
		got <- result{gone, err}
	}()
	conn, err := ln.AcceptUnix()
	if err != nil {
		t.Fatal(err)
	}
	if _, _, _, err := readVMMRequest(conn); err != nil {
		t.Fatal(err)
	}
	if err := writeVMM(conn, vmmReply{Cgroup: "/c"}); err != nil {
		t.Fatal(err)
	}
	r := <-got
	if r.err != nil {
		t.Fatal(r.err)
	}
	_ = conn.Close()
	_ = ln.Close()
	select {
	case <-r.gone:
	case <-time.After(5 * time.Second):
		t.Fatal("gone never closed after vmm went away")
	}
}

func TestVMMLaunchPassesSpecAndFdsAndKills(t *testing.T) {
	server, launcher, socket := startVMM(t)
	cgroupDir := t.TempDir()
	cgroup, err := os.Open(cgroupDir)
	if err != nil {
		t.Fatal(err)
	}
	defer cgroup.Close()
	daemon := &VMMLauncher{Socket: socket}
	inst, err := daemon.Launch(context.Background(), Spec{ID: "sbx-1", JailBase: "/j", NetNS: "sbx-1", UID: 10003, Cgroup: cgroup})
	if err != nil {
		t.Fatal(err)
	}
	launcher.mu.Lock()
	spec, gotCgroup, sleeper := launcher.specs[0], launcher.cgroup[0], launcher.last
	launcher.mu.Unlock()
	if spec.ID != "sbx-1" || spec.NetNS != "sbx-1" || spec.UID != 10003 {
		t.Fatalf("vmm got spec %+v", spec)
	}
	if gotCgroup != cgroupDir {
		t.Fatalf("vmm's cgroup fd names %q, want %q", gotCgroup, cgroupDir)
	}
	if inst.PID() != sleeper.PID() || inst.Root() != RootDir("/j", "sbx-1") {
		t.Fatalf("pid %d root %s, want %d %s", inst.PID(), inst.Root(), sleeper.PID(), RootDir("/j", "sbx-1"))
	}
	if server.Active() != 1 {
		t.Fatalf("Active = %d while the VM runs", server.Active())
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := inst.Kill(ctx); err != nil {
		t.Fatal(err)
	}
	select {
	case <-sleeper.done:
	default:
		t.Fatal("Kill returned before vmm killed the VM")
	}
	if err := inst.ExitError(); err == nil || !strings.Contains(err.Error(), "killed") {
		t.Fatalf("ExitError = %v, want the kill's exit", err)
	}
	waitFor(t, "Active to reach 0", func() bool { return server.Active() == 0 })
}

// A daemon that goes away without pausing a VM treats it as dead, so vmm
// must not leave it running.
func TestVMMKillsVMWhenDaemonConnectionCloses(t *testing.T) {
	server, launcher, socket := startVMM(t)
	inst, err := (&VMMLauncher{Socket: socket}).Launch(context.Background(), Spec{ID: "sbx-2", JailBase: "/j"})
	if err != nil {
		t.Fatal(err)
	}
	launcher.mu.Lock()
	sleeper := launcher.last
	launcher.mu.Unlock()
	_ = inst.(*remoteMachine).conn.Close()
	select {
	case <-sleeper.done:
	case <-time.After(5 * time.Second):
		t.Fatal("vmm kept the VM after the daemon's connection closed")
	}
	waitFor(t, "Active to reach 0", func() bool { return server.Active() == 0 })
}

func TestVMMReportsAnExitTheDaemonDidNotAskFor(t *testing.T) {
	_, launcher, socket := startVMM(t)
	inst, err := (&VMMLauncher{Socket: socket}).Launch(context.Background(), Spec{ID: "sbx-3", JailBase: "/j"})
	if err != nil {
		t.Fatal(err)
	}
	launcher.mu.Lock()
	sleeper := launcher.last
	launcher.mu.Unlock()
	_ = sleeper.cmd.Process.Kill()
	select {
	case <-inst.Done():
	case <-time.After(5 * time.Second):
		t.Fatal("the daemon never heard of the exit")
	}
	err = inst.ExitError()
	if err == nil || strings.Contains(err.Error(), "sandboxd") || strings.Contains(err.Error(), "lost vmm") {
		t.Fatalf("ExitError = %v, want the VM's own exit", err)
	}
}

func TestVMMLaunchError(t *testing.T) {
	_, _, socket := startVMM(t)
	_, err := (&VMMLauncher{Socket: socket}).Launch(context.Background(), Spec{ID: "../escape", JailBase: "/j"})
	if err == nil {
		t.Fatal("an invalid id launched")
	}
}

func launchSleeper(t *testing.T, socket string, launcher *sleepLauncher, id string) (Instance, *sleepInstance) {
	t.Helper()
	inst, err := (&VMMLauncher{Socket: socket}).Launch(context.Background(), Spec{ID: id, JailBase: "/j"})
	if err != nil {
		t.Fatal(err)
	}
	launcher.mu.Lock()
	defer launcher.mu.Unlock()
	return inst, launcher.last
}

func alive(s *sleepInstance) bool {
	select {
	case <-s.done:
		return false
	default:
		return true
	}
}

// Step 2b: a detached VM outlives the daemon's connection, and the next
// daemon attaches it by id and pid and owns it from then on.
func TestVMMDetachedVMOutlivesTheDaemonAndAttaches(t *testing.T) {
	server, launcher, socket := startVMM(t)
	inst, sleeper := launchSleeper(t, socket, launcher, "sbx-4")
	start := inst.(Handoff).Start()
	if start == 0 || start != ProcessStart(sleeper.PID()) {
		t.Fatalf("Start = %d, want the process's start %d", start, ProcessStart(sleeper.PID()))
	}
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := inst.(Handoff).Detach(ctx); err != nil {
		t.Fatal(err)
	}
	<-inst.Done()
	time.Sleep(100 * time.Millisecond)
	if !alive(sleeper) {
		t.Fatal("vmm killed the VM the daemon detached")
	}

	next := &VMMLauncher{Socket: socket}
	vms, err := next.List(ctx)
	if err != nil || len(vms) != 1 || vms[0] != (VMMVM{ID: "sbx-4", PID: sleeper.PID(), Start: start, Detached: true}) {
		t.Fatalf("List = %+v, %v", vms, err)
	}
	if _, err := next.Attach(ctx, Spec{ID: "sbx-4", JailBase: "/j"}, sleeper.PID()+1); err == nil {
		t.Fatal("attached with another pid")
	}
	attached, err := next.Attach(ctx, Spec{ID: "sbx-4", JailBase: "/j"}, sleeper.PID())
	if err != nil {
		t.Fatal(err)
	}
	if attached.PID() != sleeper.PID() || attached.(Handoff).Start() != start || attached.Root() != RootDir("/j", "sbx-4") {
		t.Fatalf("attached pid %d start %d root %s", attached.PID(), attached.(Handoff).Start(), attached.Root())
	}
	if _, err := next.Attach(ctx, Spec{ID: "sbx-4", JailBase: "/j"}, sleeper.PID()); err == nil {
		t.Fatal("a second daemon connection attached a VM another holds")
	}
	// The new connection now decides: closing it kills the VM again.
	_ = attached.(*remoteMachine).conn.Close()
	select {
	case <-sleeper.done:
	case <-time.After(5 * time.Second):
		t.Fatal("vmm kept the attached VM after its new connection closed")
	}
	waitFor(t, "Active to reach 0", func() bool { return server.Active() == 0 })
}

// The next daemon learns of a VM that exited while nobody held it.
func TestVMMReportsAnExitWhileDetached(t *testing.T) {
	_, launcher, socket := startVMM(t)
	inst, sleeper := launchSleeper(t, socket, launcher, "sbx-5")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := inst.(Handoff).Detach(ctx); err != nil {
		t.Fatal(err)
	}
	_ = sleeper.cmd.Process.Kill()
	<-sleeper.done
	next := &VMMLauncher{Socket: socket}
	waitFor(t, "the exit to be listed", func() bool {
		vms, err := next.List(ctx)
		return err == nil && len(vms) == 1 && vms[0].Exited
	})
	if _, err := next.Attach(ctx, Spec{ID: "sbx-5", JailBase: "/j"}, sleeper.PID()); !errors.Is(err, ErrExited) {
		t.Fatalf("Attach = %v, want ErrExited", err)
	}
	if vms, err := next.List(ctx); err != nil || len(vms) != 0 {
		t.Fatalf("List after the exit was collected = %+v, %v", vms, err)
	}
}

// A VM no daemon comes back for must not run on: that daemon's successor
// cold boots it.
func TestVMMKillsADetachedVMNobodyAttaches(t *testing.T) {
	server, launcher, socket := startVMM(t, func(s *VMMServer) { s.DetachTTL = 200 * time.Millisecond })
	inst, sleeper := launchSleeper(t, socket, launcher, "sbx-6")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := inst.(Handoff).Detach(ctx); err != nil {
		t.Fatal(err)
	}
	select {
	case <-sleeper.done:
	case <-time.After(5 * time.Second):
		t.Fatal("the detached VM outlived its TTL")
	}
	waitFor(t, "Active to reach 0", func() bool { return server.Active() == 0 })
}

// While the Pod stops, vmm refuses detaches (the daemon then pauses its
// VMs) and kills detached VMs nobody attaches within the grace.
func TestVMMDrainRefusesDetachesAndExpiresDetachedVMs(t *testing.T) {
	server, launcher, socket := startVMM(t)
	detached, detachedSleeper := launchSleeper(t, socket, launcher, "sbx-7")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := detached.(Handoff).Detach(ctx); err != nil {
		t.Fatal(err)
	}
	held, heldSleeper := launchSleeper(t, socket, launcher, "sbx-8")
	server.Drain(200 * time.Millisecond)
	if err := held.(Handoff).Detach(ctx); err == nil {
		t.Fatal("vmm detached a VM while draining")
	}
	select {
	case <-held.Done():
		t.Fatal("a refused detach ended the instance")
	default:
	}
	select {
	case <-detachedSleeper.done:
	case <-time.After(5 * time.Second):
		t.Fatal("the detached VM outlived the drain grace")
	}
	if !alive(heldSleeper) {
		t.Fatal("the drain killed a VM a daemon still holds")
	}
	if err := held.Kill(ctx); err != nil {
		t.Fatal(err)
	}
	waitFor(t, "Active to reach 0", func() bool { return server.Active() == 0 })
}

// vmm spawns its own binaries, whatever the daemon's spec names.
func TestVMMPinsItsBinaries(t *testing.T) {
	server, launcher, socket := startVMM(t, func(s *VMMServer) {
		s.FirecrackerBin, s.JailerBin = "/proc/7/root/usr/local/bin/firecracker", "/proc/7/root/usr/local/bin/jailer"
	})
	inst, err := (&VMMLauncher{Socket: socket}).Launch(context.Background(), Spec{ID: "sbx-9", JailBase: "/j", FirecrackerBin: "/usr/local/bin/firecracker", JailerBin: "/usr/local/bin/jailer"})
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = inst.Kill(context.Background()) }()
	launcher.mu.Lock()
	spec := launcher.specs[0]
	launcher.mu.Unlock()
	if spec.FirecrackerBin != server.FirecrackerBin || spec.JailerBin != server.JailerBin {
		t.Fatalf("vmm spawned %s and %s", spec.FirecrackerBin, spec.JailerBin)
	}
}

// A detached VM keeps its id: another launch of it is refused until the
// daemon attached and killed it.
func TestVMMRefusesALaunchOverADetachedVM(t *testing.T) {
	_, launcher, socket := startVMM(t)
	inst, sleeper := launchSleeper(t, socket, launcher, "sbx-10")
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := inst.(Handoff).Detach(ctx); err != nil {
		t.Fatal(err)
	}
	if _, err := (&VMMLauncher{Socket: socket}).Launch(ctx, Spec{ID: "sbx-10", JailBase: "/j"}); err == nil || !strings.Contains(err.Error(), "still running") {
		t.Fatalf("Launch over a detached VM = %v", err)
	}
	attached, err := (&VMMLauncher{Socket: socket}).Attach(ctx, Spec{ID: "sbx-10", JailBase: "/j"}, sleeper.PID())
	if err != nil {
		t.Fatal(err)
	}
	if err := attached.Kill(ctx); err != nil {
		t.Fatal(err)
	}
	again, err := (&VMMLauncher{Socket: socket}).Launch(ctx, Spec{ID: "sbx-10", JailBase: "/j"})
	if err != nil {
		t.Fatalf("Launch after the kill = %v", err)
	}
	_ = again.Kill(ctx)
}
