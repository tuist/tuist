// Package fakevm is a test double for vm.Launcher: a Firecracker-shaped HTTP
// API on the jail's API socket and an sbx-agent-shaped vsock server on
// v.sock, so the sandbox manager and template builder run end to end
// without KVM.
package fakevm

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/firecracker"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
)

// Launcher records every instance it creates.
type Launcher struct {
	mu        sync.Mutex
	instances []*Instance
	// FailLaunch makes the next Launch fail with this error.
	FailLaunch error
	// Jailed mirrors vm.Spec.JailerEnabled for GuestPath.
	Jailed bool
	// AgentBootDelay delays the first successful ping after a boot or
	// restore.
	AgentBootDelay time.Duration
}

func (l *Launcher) Launch(ctx context.Context, spec vm.Spec) (vm.Instance, error) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if l.FailLaunch != nil {
		err := l.FailLaunch
		l.FailLaunch = nil
		return nil, err
	}
	if err := vm.ValidateID(spec.ID); err != nil {
		return nil, err
	}
	root := vm.RootDir(spec.JailBase, spec.ID)
	if err := vm.Prepare(root, -1, -1); err != nil {
		return nil, err
	}
	inst := &Instance{
		spec:      spec,
		root:      root,
		done:      make(chan struct{}),
		Agent:     &Agent{delay: l.AgentBootDelay, started: time.Now()},
		jailed:    spec.JailerEnabled,
		bootedNow: time.Now(),
	}
	if err := inst.start(); err != nil {
		return nil, err
	}
	l.instances = append(l.instances, inst)
	return inst, nil
}

func (l *Launcher) Instances() []*Instance {
	l.mu.Lock()
	defer l.mu.Unlock()
	return append([]*Instance(nil), l.instances...)
}

func (l *Launcher) Last() *Instance {
	all := l.Instances()
	if len(all) == 0 {
		return nil
	}
	return all[len(all)-1]
}

// Call is one recorded API request.
type Call struct {
	Method string
	Path   string
	Body   map[string]any
}

type Instance struct {
	spec      vm.Spec
	root      string
	jailed    bool
	bootedNow time.Time

	sockDir     string
	apiServer   *http.Server
	apiListener net.Listener
	agentLn     net.Listener
	client      *firecracker.Client
	Agent       *Agent

	mu     sync.Mutex
	calls  []Call
	state  string
	killed atomic.Bool
	done   chan struct{}
	once   sync.Once
	// FailSnapshotCreate makes PUT /snapshot/create answer 400.
	FailSnapshotCreate bool
}

// start binds the fake API and agent sockets. They live in a short
// directory under the platform temp dir rather than in the jail root:
// unix socket paths are capped at 104 bytes on macOS and test jail roots
// are longer than that. The manager only ever learns socket paths from the
// instance, so this is invisible to it.
func (i *Instance) start() error {
	sockDir, err := os.MkdirTemp("", "sbxfake")
	if err != nil {
		return err
	}
	i.sockDir = sockDir
	apiPath := filepath.Join(sockDir, "api.sock")
	ln, err := net.Listen("unix", apiPath)
	if err != nil {
		return err
	}
	i.apiListener = ln
	i.client = firecracker.NewClient(apiPath)
	i.state = "Not started"
	i.apiServer = &http.Server{Handler: http.HandlerFunc(i.handle)}
	go func() { _ = i.apiServer.Serve(ln) }()

	agentLn, err := net.Listen("unix", filepath.Join(sockDir, "v.sock"))
	if err != nil {
		return err
	}
	i.agentLn = agentLn
	go i.Agent.serve(agentLn)
	return nil
}

func (i *Instance) handle(w http.ResponseWriter, r *http.Request) {
	call := Call{Method: r.Method, Path: r.URL.Path}
	data, _ := io.ReadAll(r.Body)
	if len(data) > 0 {
		_ = json.Unmarshal(data, &call.Body)
	}
	i.mu.Lock()
	i.calls = append(i.calls, call)
	i.mu.Unlock()

	fault := func(status int, msg string) {
		w.WriteHeader(status)
		fmt.Fprintf(w, `{"fault_message":%q}`, msg)
	}
	switch {
	case r.Method == http.MethodGet && r.URL.Path == "/":
		i.mu.Lock()
		state := i.state
		i.mu.Unlock()
		fmt.Fprintf(w, `{"app_name":"Firecracker","id":%q,"state":%q,"vmm_version":"1.16.1"}`, i.spec.ID, state)
	case r.Method == http.MethodGet && r.URL.Path == "/version":
		_, _ = w.Write([]byte(`{"firecracker_version":"v1.16.1"}`))
	case r.Method == http.MethodPut && r.URL.Path == "/actions":
		i.setState("Running")
		i.Agent.boot()
		w.WriteHeader(http.StatusNoContent)
	case r.Method == http.MethodPatch && r.URL.Path == "/vm":
		if call.Body["state"] == "Paused" {
			i.setState("Paused")
		} else {
			i.setState("Running")
		}
		w.WriteHeader(http.StatusNoContent)
	case r.Method == http.MethodPut && r.URL.Path == "/snapshot/create":
		if i.FailSnapshotCreate {
			fault(400, "snapshot creation failed (test)")
			return
		}
		if i.getState() != "Paused" {
			fault(400, "vm must be paused")
			return
		}
		for _, key := range []string{"snapshot_path", "mem_file_path"} {
			p, _ := call.Body[key].(string)
			if err := os.WriteFile(i.HostPath(p), []byte(key+" "+i.spec.ID+" "+strconv.FormatInt(time.Now().UnixNano(), 10)), 0o644); err != nil {
				fault(500, err.Error())
				return
			}
		}
		w.WriteHeader(http.StatusNoContent)
	case r.Method == http.MethodPut && r.URL.Path == "/snapshot/load":
		snap, _ := call.Body["snapshot_path"].(string)
		backend, _ := call.Body["mem_backend"].(map[string]any)
		mem, _ := backend["backend_path"].(string)
		if !vm.Exists(i.HostPath(snap)) || !vm.Exists(i.HostPath(mem)) {
			fault(400, "Load snapshot error: missing snapshot or memory file")
			return
		}
		if resume, _ := call.Body["resume_vm"].(bool); resume {
			i.setState("Running")
			i.Agent.boot()
		} else {
			i.setState("Paused")
		}
		w.WriteHeader(http.StatusNoContent)
	default:
		w.WriteHeader(http.StatusNoContent)
	}
}

func (i *Instance) setState(s string) {
	i.mu.Lock()
	i.state = s
	i.mu.Unlock()
}

func (i *Instance) getState() string {
	i.mu.Lock()
	defer i.mu.Unlock()
	return i.state
}

func (i *Instance) Calls() []Call {
	i.mu.Lock()
	defer i.mu.Unlock()
	return append([]Call(nil), i.calls...)
}

func (i *Instance) CallPaths() []string {
	var out []string
	for _, c := range i.Calls() {
		out = append(out, c.Method+" "+c.Path)
	}
	return out
}

func (i *Instance) ID() string                    { return i.spec.ID }
func (i *Instance) Root() string                  { return i.root }
func (i *Instance) HostPath(inJail string) string { return filepath.Join(i.root, inJail) }
func (i *Instance) API() *firecracker.Client      { return i.client }
func (i *Instance) VsockPath() string             { return filepath.Join(i.sockDir, "v.sock") }
func (i *Instance) PID() int                      { return 4242 }
func (i *Instance) Done() <-chan struct{}         { return i.done }
func (i *Instance) Killed() bool                  { return i.killed.Load() }

func (i *Instance) GuestPath(inJail string) string {
	if i.jailed {
		return inJail
	}
	return i.HostPath(inJail)
}

func (i *Instance) ExitError() error {
	select {
	case <-i.done:
		if i.killed.Load() {
			return nil
		}
		return errors.New("firecracker crashed (test)")
	default:
		return nil
	}
}

func (i *Instance) Kill(ctx context.Context) error {
	i.killed.Store(true)
	i.stop()
	return nil
}

// Crash simulates Firecracker dying on its own.
func (i *Instance) Crash() { i.stop() }

func (i *Instance) stop() {
	i.once.Do(func() {
		_ = i.apiServer.Close()
		_ = i.agentLn.Close()
		i.Agent.stop()
		_ = os.RemoveAll(i.sockDir)
		close(i.done)
	})
}

// Agent emulates sbx-agent over the vsock UDS.
type Agent struct {
	mu       sync.Mutex
	delay    time.Duration
	started  time.Time
	readyAt  time.Time
	booted   bool
	Requests []map[string]any
	execs    map[string]*fakeExec
	seq      int
	stopped  bool
	// ExecHook, when set, controls exec behaviour; return false to fall
	// through to the default (echo cmd, exit 0).
	ExecHook func(req map[string]any, out func(stream string, data []byte)) (exitCode int, handled bool)
}

type fakeExec struct {
	kill chan int
}

func (a *Agent) boot() {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.booted = true
	a.readyAt = time.Now().Add(a.delay)
}

func (a *Agent) stop() {
	a.mu.Lock()
	defer a.mu.Unlock()
	a.stopped = true
	for _, e := range a.execs {
		select {
		case e.kill <- 9:
		default:
		}
	}
}

func (a *Agent) RequestsOf(op string) []map[string]any {
	a.mu.Lock()
	defer a.mu.Unlock()
	var out []map[string]any
	for _, r := range a.Requests {
		if r["op"] == op {
			out = append(out, r)
		}
	}
	return out
}

func (a *Agent) serve(ln net.Listener) {
	for {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		go a.handle(conn)
	}
}

func (a *Agent) handle(conn net.Conn) {
	defer conn.Close()
	reader := bufio.NewReader(conn)
	line, err := reader.ReadString('\n')
	if err != nil {
		return
	}
	if !strings.HasPrefix(line, "CONNECT 5000\n") {
		return
	}
	a.mu.Lock()
	ready := a.booted && !a.stopped && time.Now().After(a.readyAt)
	a.mu.Unlock()
	if !ready {
		// Firecracker drops the host connection when nothing listens.
		return
	}
	if _, err := conn.Write([]byte("OK 1024\n")); err != nil {
		return
	}
	line, err = reader.ReadString('\n')
	if err != nil {
		return
	}
	var req map[string]any
	if err := json.Unmarshal([]byte(line), &req); err != nil {
		return
	}
	a.mu.Lock()
	a.Requests = append(a.Requests, req)
	a.mu.Unlock()
	id, _ := req["id"].(string)
	write := func(frame map[string]any) {
		frame["id"] = id
		data, _ := json.Marshal(frame)
		_, _ = conn.Write(append(data, '\n'))
	}
	switch req["op"] {
	case "ping":
		write(map[string]any{"type": "pong", "uptime_s": time.Since(a.started).Seconds(), "agent_version": "fake"})
	case "set_time", "configure", "write_file":
		write(map[string]any{"type": "ok"})
	case "kill":
		target, _ := req["target"].(string)
		sig, _ := req["signal"].(float64)
		a.mu.Lock()
		e := a.execs[target]
		a.mu.Unlock()
		if e == nil {
			write(map[string]any{"type": "error", "message": "no such exec"})
			return
		}
		select {
		case e.kill <- int(sig):
		default:
		}
		write(map[string]any{"type": "ok"})
	case "exec":
		a.exec(req, write)
	default:
		write(map[string]any{"type": "error", "message": "unknown op"})
	}
}

func (a *Agent) exec(req map[string]any, write func(map[string]any)) {
	a.mu.Lock()
	a.seq++
	execID := "e" + strconv.Itoa(a.seq)
	e := &fakeExec{kill: make(chan int, 1)}
	if a.execs == nil {
		a.execs = map[string]*fakeExec{}
	}
	a.execs[execID] = e
	hook := a.ExecHook
	a.mu.Unlock()
	defer func() {
		a.mu.Lock()
		delete(a.execs, execID)
		a.mu.Unlock()
	}()
	write(map[string]any{"type": "started", "exec_id": execID})
	out := func(stream string, data []byte) {
		write(map[string]any{"type": stream, "data_b64": base64.StdEncoding.EncodeToString(data)})
	}
	var cmd []string
	if raw, ok := req["cmd"].([]any); ok {
		for _, c := range raw {
			cmd = append(cmd, fmt.Sprint(c))
		}
	}
	if hook != nil {
		if code, handled := hook(req, out); handled {
			write(map[string]any{"type": "exit", "code": code})
			return
		}
	}
	if len(cmd) > 0 && cmd[0] == "/usr/local/bin/sbx-worker" {
		out("stdout", []byte("worker started\n"))
		sig := <-e.kill
		out("stderr", []byte(fmt.Sprintf("worker got signal %d\n", sig)))
		write(map[string]any{"type": "exit", "code": 128 + sig})
		return
	}
	if len(cmd) > 0 && cmd[0] == "sleep" {
		select {
		case sig := <-e.kill:
			write(map[string]any{"type": "exit", "code": 128 + sig})
		case <-time.After(10 * time.Second):
			write(map[string]any{"type": "exit", "code": 0})
		}
		return
	}
	out("stdout", []byte(strings.Join(cmd, " ")+"\n"))
	write(map[string]any{"type": "exit", "code": 0})
}
