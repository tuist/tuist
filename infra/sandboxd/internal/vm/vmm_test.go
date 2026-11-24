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

func startVMM(t *testing.T) (*VMMServer, *sleepLauncher, string) {
	t.Helper()
	socket := filepath.Join(t.TempDir(), "vmm.sock")
	ln, err := net.ListenUnix("unix", &net.UnixAddr{Name: socket, Net: "unix"})
	if err != nil {
		t.Fatal(err)
	}
	launcher := &sleepLauncher{}
	server := &VMMServer{Launcher: launcher, Cgroup: "/kubepods/pod1/vmm", Log: slog.New(slog.NewTextHandler(io.Discard, nil))}
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

func TestVMMCgroup(t *testing.T) {
	_, _, socket := startVMM(t)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	got, gone, err := VMMCgroup(ctx, socket)
	if err != nil || got != "/kubepods/pod1/vmm" {
		t.Fatalf("VMMCgroup = %q, %v", got, err)
	}
	select {
	case <-gone:
		t.Fatal("gone closed while vmm runs")
	case <-time.After(100 * time.Millisecond):
	}
}

// The daemon learns that vmm stopped: its VMs went with it.
func TestVMMCgroupGoneWhenVMMStops(t *testing.T) {
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
		_, gone, err := VMMCgroup(ctx, socket)
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
