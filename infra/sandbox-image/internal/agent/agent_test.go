package agent

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/sandbox-image/internal/exec"
	"github.com/tuist/tuist/infra/sandbox-image/internal/protocol"
)

type fakeSystem struct {
	mu         sync.Mutex
	uptime     time.Duration
	times      []time.Time
	configured []ConfigureSpec
	err        error
}

func (f *fakeSystem) Uptime() (time.Duration, error) { return f.uptime, nil }

func (f *fakeSystem) SetTime(t time.Time) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.times = append(f.times, t)
	return f.err
}

func (f *fakeSystem) Configure(_ context.Context, spec ConfigureSpec) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.configured = append(f.configured, spec)
	return f.err
}

// client drives one request over a net.Pipe against the handler, the way the
// host does over one vsock connection.
type client struct {
	t    *testing.T
	conn net.Conn
	r    *bufio.Reader
}

func dial(t *testing.T, h *Handler) *client {
	t.Helper()
	server, conn := net.Pipe()
	go h.HandleConn(context.Background(), server)
	t.Cleanup(func() { conn.Close() })
	return &client{t: t, conn: conn, r: bufio.NewReader(conn)}
}

func (c *client) send(req protocol.Request) {
	c.t.Helper()
	line, err := json.Marshal(req)
	if err != nil {
		c.t.Fatal(err)
	}
	go func() {
		c.conn.Write(append(line, '\n'))
	}()
}

func (c *client) next() protocol.Response {
	c.t.Helper()
	c.conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	resp, err := protocol.ReadResponse(c.r)
	if err != nil {
		c.t.Fatalf("read response: %v", err)
	}
	return *resp
}

// rest drains every remaining frame until the handler closes the connection.
func (c *client) rest() []protocol.Response {
	c.t.Helper()
	var frames []protocol.Response
	c.conn.SetReadDeadline(time.Now().Add(10 * time.Second))
	for {
		resp, err := protocol.ReadResponse(c.r)
		if errors.Is(err, io.EOF) {
			return frames
		}
		if err != nil {
			c.t.Fatalf("read response: %v", err)
		}
		frames = append(frames, *resp)
	}
}

func roundTrip(t *testing.T, h *Handler, req protocol.Request) []protocol.Response {
	t.Helper()
	c := dial(t, h)
	c.send(req)
	return c.rest()
}

func newHandler(sys *fakeSystem, cwd string) *Handler {
	return &Handler{Version: "test", System: sys, Execs: exec.NewRegistry(cwd)}
}

func collect(t *testing.T, frames []protocol.Response) (stdout, stderr string, exit *int, kinds []string) {
	t.Helper()
	for _, f := range frames {
		kinds = append(kinds, f.Type)
		switch f.Type {
		case protocol.TypeStdout, protocol.TypeStderr:
			data, err := f.Data()
			if err != nil {
				t.Fatal(err)
			}
			if f.Type == protocol.TypeStdout {
				stdout += string(data)
			} else {
				stderr += string(data)
			}
		case protocol.TypeExit:
			exit = f.Code
		}
	}
	return stdout, stderr, exit, kinds
}

func TestPing(t *testing.T) {
	h := newHandler(&fakeSystem{uptime: 90 * time.Second}, t.TempDir())
	frames := roundTrip(t, h, protocol.Request{ID: "r1", Op: protocol.OpPing})
	if len(frames) != 1 || frames[0].Type != protocol.TypePong {
		t.Fatalf("unexpected frames: %+v", frames)
	}
	if frames[0].ID != "r1" || frames[0].UptimeS != 90 || frames[0].AgentVersion != "test" {
		t.Fatalf("unexpected pong: %+v", frames[0])
	}
}

func TestUnknownOp(t *testing.T) {
	h := newHandler(&fakeSystem{}, t.TempDir())
	frames := roundTrip(t, h, protocol.Request{ID: "r1", Op: "reboot"})
	if len(frames) != 1 || frames[0].Type != protocol.TypeError || !strings.Contains(frames[0].Message, "unknown op") {
		t.Fatalf("unexpected frames: %+v", frames)
	}
}

func TestMalformedRequest(t *testing.T) {
	h := newHandler(&fakeSystem{}, t.TempDir())
	server, conn := net.Pipe()
	go h.HandleConn(context.Background(), server)
	go conn.Write([]byte("{nope\n"))
	conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	resp, err := protocol.ReadResponse(bufio.NewReader(conn))
	if err != nil {
		t.Fatal(err)
	}
	if resp.Type != protocol.TypeError {
		t.Fatalf("expected an error frame, got %+v", resp)
	}
}

func TestSetTime(t *testing.T) {
	sys := &fakeSystem{}
	h := newHandler(sys, t.TempDir())
	frames := roundTrip(t, h, protocol.Request{ID: "r1", Op: protocol.OpSetTime, UnixNanos: 1757000000000000000})
	if len(frames) != 1 || frames[0].Type != protocol.TypeOK {
		t.Fatalf("unexpected frames: %+v", frames)
	}
	if len(sys.times) != 1 || sys.times[0].UnixNano() != 1757000000000000000 {
		t.Fatalf("clock not set: %+v", sys.times)
	}

	frames = roundTrip(t, h, protocol.Request{ID: "r2", Op: protocol.OpSetTime})
	if len(frames) != 1 || frames[0].Type != protocol.TypeError {
		t.Fatalf("expected an error without unix_nanos, got %+v", frames)
	}
}

func TestConfigure(t *testing.T) {
	sys := &fakeSystem{}
	h := newHandler(sys, t.TempDir())
	frames := roundTrip(t, h, protocol.Request{
		ID: "r1", Op: protocol.OpConfigure, Hostname: "sbx-abc", DNS: []string{"10.128.0.10"}, FormatWorkspace: true,
	})
	if len(frames) != 1 || frames[0].Type != protocol.TypeOK {
		t.Fatalf("unexpected frames: %+v", frames)
	}
	want := ConfigureSpec{Hostname: "sbx-abc", DNS: []string{"10.128.0.10"}, FormatWorkspace: true}
	if len(sys.configured) != 1 || sys.configured[0].Hostname != want.Hostname || !sys.configured[0].FormatWorkspace || sys.configured[0].DNS[0] != want.DNS[0] {
		t.Fatalf("unexpected configure call: %+v", sys.configured)
	}

	sys.err = errors.New("mkfs failed")
	frames = roundTrip(t, h, protocol.Request{ID: "r2", Op: protocol.OpConfigure, Hostname: "x"})
	if len(frames) != 1 || frames[0].Type != protocol.TypeError || !strings.Contains(frames[0].Message, "mkfs failed") {
		t.Fatalf("expected the system error to surface, got %+v", frames)
	}
}

func TestWriteFile(t *testing.T) {
	dir := t.TempDir()
	h := newHandler(&fakeSystem{}, dir)
	path := filepath.Join(dir, "nested", "deeper", "x.sh")
	frames := roundTrip(t, h, protocol.Request{
		ID: "r1", Op: protocol.OpWriteFile, Path: path, Mode: 0o755,
		DataB64: base64.StdEncoding.EncodeToString([]byte("#!/bin/sh\necho hi\n")),
	})
	if len(frames) != 1 || frames[0].Type != protocol.TypeOK {
		t.Fatalf("unexpected frames: %+v", frames)
	}
	data, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	if string(data) != "#!/bin/sh\necho hi\n" {
		t.Fatalf("unexpected content %q", data)
	}
	info, _ := os.Stat(path)
	if info.Mode().Perm() != 0o755 {
		t.Fatalf("unexpected mode %o", info.Mode().Perm())
	}

	frames = roundTrip(t, h, protocol.Request{ID: "r2", Op: protocol.OpWriteFile, Path: "relative/x", DataB64: ""})
	if len(frames) != 1 || frames[0].Type != protocol.TypeError {
		t.Fatalf("expected relative paths to be rejected, got %+v", frames)
	}
}

func TestExecStreamsOutputAndExitCode(t *testing.T) {
	h := newHandler(&fakeSystem{}, t.TempDir())
	frames := roundTrip(t, h, protocol.Request{
		ID: "r1", Op: protocol.OpExec, Cmd: []string{"/bin/sh", "-c", "printf out; printf err >&2; exit 3"},
	})
	stdout, stderr, exit, kinds := collect(t, frames)
	if kinds[0] != protocol.TypeStarted || frames[0].ExecID == "" {
		t.Fatalf("expected a started frame first, got %v", kinds)
	}
	if kinds[len(kinds)-1] != protocol.TypeExit {
		t.Fatalf("expected an exit frame last, got %v", kinds)
	}
	if stdout != "out" || stderr != "err" {
		t.Fatalf("unexpected output stdout=%q stderr=%q", stdout, stderr)
	}
	if exit == nil || *exit != 3 {
		t.Fatalf("unexpected exit code %v", exit)
	}
	for _, f := range frames {
		if f.ID != "r1" {
			t.Fatalf("frame lost its request id: %+v", f)
		}
	}
}

func TestExecEnvAndCwd(t *testing.T) {
	dir := t.TempDir()
	real, err := filepath.EvalSymlinks(dir)
	if err != nil {
		t.Fatal(err)
	}
	h := newHandler(&fakeSystem{}, t.TempDir())
	frames := roundTrip(t, h, protocol.Request{
		ID: "r1", Op: protocol.OpExec, Cwd: dir, Env: map[string]string{"FOO": "bar"},
		Cmd: []string{"/bin/sh", "-c", "echo $FOO; echo $HOME; echo $LANG; pwd -P"},
	})
	stdout, _, exit, _ := collect(t, frames)
	if exit == nil || *exit != 0 {
		t.Fatalf("unexpected exit %v (frames %+v)", exit, frames)
	}
	if stdout != "bar\n/root\nC.UTF-8\n"+real+"\n" {
		t.Fatalf("unexpected stdout %q", stdout)
	}
}

func TestExecDefaultCwdAndPathLookup(t *testing.T) {
	dir := t.TempDir()
	real, _ := filepath.EvalSymlinks(dir)
	h := newHandler(&fakeSystem{}, dir)
	frames := roundTrip(t, h, protocol.Request{ID: "r1", Op: protocol.OpExec, Cmd: []string{"sh", "-c", "pwd -P"}})
	stdout, _, exit, _ := collect(t, frames)
	if exit == nil || *exit != 0 || strings.TrimSpace(stdout) != real {
		t.Fatalf("unexpected result stdout=%q exit=%v", stdout, exit)
	}
}

func TestExecFailsToStart(t *testing.T) {
	h := newHandler(&fakeSystem{}, t.TempDir())
	frames := roundTrip(t, h, protocol.Request{ID: "r1", Op: protocol.OpExec, Cmd: []string{"/definitely/not/here"}})
	if len(frames) != 1 || frames[0].Type != protocol.TypeError {
		t.Fatalf("expected a single error frame, got %+v", frames)
	}
	frames = roundTrip(t, h, protocol.Request{ID: "r2", Op: protocol.OpExec, Cmd: []string{"/bin/sh", "-c", "true"}, Cwd: "/definitely/not/here"})
	if len(frames) != 1 || frames[0].Type != protocol.TypeError || !strings.Contains(frames[0].Message, "cwd") {
		t.Fatalf("expected a cwd error, got %+v", frames)
	}
	frames = roundTrip(t, h, protocol.Request{ID: "r3", Op: protocol.OpExec})
	if len(frames) != 1 || frames[0].Type != protocol.TypeError {
		t.Fatalf("expected an empty-cmd error, got %+v", frames)
	}
}

func TestExecTimeout(t *testing.T) {
	h := newHandler(&fakeSystem{}, t.TempDir())
	start := time.Now()
	frames := roundTrip(t, h, protocol.Request{
		ID: "r1", Op: protocol.OpExec, Cmd: []string{"/bin/sh", "-c", "echo before; sleep 20; echo after"}, TimeoutMs: 200,
	})
	stdout, _, exit, _ := collect(t, frames)
	if exit == nil || *exit != exec.ExitTimeout {
		t.Fatalf("expected exit %d, got %v", exec.ExitTimeout, exit)
	}
	if stdout != "before\n" {
		t.Fatalf("unexpected stdout %q", stdout)
	}
	if elapsed := time.Since(start); elapsed > 5*time.Second {
		t.Fatalf("timeout took %s", elapsed)
	}
	if running := h.Execs.Running(); len(running) != 0 {
		t.Fatalf("exec still registered: %v", running)
	}
}

func TestKillByExecID(t *testing.T) {
	h := newHandler(&fakeSystem{}, t.TempDir())
	running := dial(t, h)
	running.send(protocol.Request{ID: "r1", Op: protocol.OpExec, Cmd: []string{"/bin/sh", "-c", "sleep 20"}})
	started := running.next()
	if started.Type != protocol.TypeStarted || started.ExecID == "" {
		t.Fatalf("expected a started frame, got %+v", started)
	}
	if ids := h.Execs.Running(); len(ids) != 1 || ids[0] != started.ExecID {
		t.Fatalf("registry does not list the exec: %v", ids)
	}

	killed := roundTrip(t, h, protocol.Request{ID: "r2", Op: protocol.OpKill, Target: started.ExecID, Signal: 15})
	if len(killed) != 1 || killed[0].Type != protocol.TypeOK {
		t.Fatalf("unexpected kill response %+v", killed)
	}
	_, _, exit, _ := collect(t, running.rest())
	if exit == nil || *exit != 128+15 {
		t.Fatalf("expected exit 143 after SIGTERM, got %v", exit)
	}

	missing := roundTrip(t, h, protocol.Request{ID: "r3", Op: protocol.OpKill, Target: started.ExecID})
	if len(missing) != 1 || missing[0].Type != protocol.TypeError {
		t.Fatalf("expected an error for a finished exec, got %+v", missing)
	}
}

func TestExecDoesNotWaitForBackgroundedChildren(t *testing.T) {
	h := newHandler(&fakeSystem{}, t.TempDir())
	start := time.Now()
	frames := roundTrip(t, h, protocol.Request{
		ID: "r1", Op: protocol.OpExec, Cmd: []string{"/bin/sh", "-c", "sleep 30 & echo started"},
	})
	stdout, _, exit, _ := collect(t, frames)
	if exit == nil || *exit != 0 || stdout != "started\n" {
		t.Fatalf("unexpected result stdout=%q exit=%v", stdout, exit)
	}
	if elapsed := time.Since(start); elapsed > 10*time.Second {
		t.Fatalf("exec waited on the backgrounded child: %s", elapsed)
	}
}
