// Package vsock is the host side of the sbx-agent protocol: one connection
// per request through Firecracker's vsock unix socket (CONNECT handshake),
// then newline-delimited JSON as described in infra/sandboxd/AGENTS.md.
package vsock

import (
	"bufio"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"time"
)

// Agent is what the sandbox manager needs from the guest agent. The real
// implementation is *Client; tests substitute their own.
type Agent interface {
	Ping(ctx context.Context) (Pong, error)
	SetTime(ctx context.Context, now time.Time) error
	Configure(ctx context.Context, req ConfigureRequest) error
	WriteFile(ctx context.Context, path string, mode uint32, data []byte) error
	Start(ctx context.Context, req ExecRequest, out OutputFunc) (Process, error)
	Kill(ctx context.Context, execID string, signal int) error
}

// Process is a running exec inside the guest.
type Process interface {
	ID() string
	// Wait blocks until the exec exits and returns its exit code. A context
	// cancellation returns ctx.Err() but leaves the guest process alone;
	// use Signal to stop it.
	Wait(ctx context.Context) (int, error)
	Signal(ctx context.Context, signal int) error
}

// OutputFunc receives stdout/stderr chunks as they stream in. stream is
// "stdout" or "stderr".
type OutputFunc func(stream string, data []byte)

type Pong struct {
	UptimeS      float64
	AgentVersion string
}

type ConfigureRequest struct {
	Hostname        string
	DNS             []string
	FormatWorkspace bool
}

type ExecRequest struct {
	Cmd       []string
	Env       map[string]string
	Cwd       string
	TimeoutMs int64
}

// Dialer opens a raw connection to the guest agent.
type Dialer func(ctx context.Context) (net.Conn, error)

type request struct {
	ID              string            `json:"id"`
	Op              string            `json:"op"`
	UnixNanos       int64             `json:"unix_nanos,omitempty"`
	Hostname        string            `json:"hostname,omitempty"`
	DNS             []string          `json:"dns,omitempty"`
	FormatWorkspace bool              `json:"format_workspace,omitempty"`
	Path            string            `json:"path,omitempty"`
	Mode            uint32            `json:"mode,omitempty"`
	DataB64         string            `json:"data_b64,omitempty"`
	Cmd             []string          `json:"cmd,omitempty"`
	Env             map[string]string `json:"env,omitempty"`
	Cwd             string            `json:"cwd,omitempty"`
	TimeoutMs       int64             `json:"timeout_ms,omitempty"`
	Target          string            `json:"target,omitempty"`
	Signal          int               `json:"signal,omitempty"`
}

type response struct {
	ID           string  `json:"id"`
	Type         string  `json:"type"`
	UptimeS      float64 `json:"uptime_s"`
	AgentVersion string  `json:"agent_version"`
	ExecID       string  `json:"exec_id"`
	DataB64      string  `json:"data_b64"`
	Code         int     `json:"code"`
	Message      string  `json:"message"`
}

// AgentError is an error frame from the guest.
type AgentError struct {
	Op      string
	Message string
}

func (e *AgentError) Error() string { return fmt.Sprintf("agent %s: %s", e.Op, e.Message) }

// Client speaks the agent protocol over connections from a Dialer.
type Client struct {
	dial Dialer
	seq  atomic.Uint64
}

func NewClient(dial Dialer) *Client { return &Client{dial: dial} }

// NewUDSClient targets Firecracker's vsock UDS on the host and the agent
// port inside the guest.
func NewUDSClient(path string, port uint32) *Client {
	return NewClient(func(ctx context.Context) (net.Conn, error) { return DialUDS(ctx, path, port) })
}

// DialUDS connects to Firecracker's vsock unix socket and performs the
// "CONNECT <port>" / "OK <hostport>" handshake.
func DialUDS(ctx context.Context, path string, port uint32) (net.Conn, error) {
	var d net.Dialer
	conn, err := d.DialContext(ctx, "unix", path)
	if err != nil {
		return nil, err
	}
	if err := Handshake(ctx, conn, port); err != nil {
		conn.Close()
		return nil, err
	}
	return conn, nil
}

// Handshake runs the Firecracker host-initiated vsock handshake on conn.
func Handshake(ctx context.Context, conn net.Conn, port uint32) error {
	if deadline, ok := ctx.Deadline(); ok {
		_ = conn.SetDeadline(deadline)
		defer conn.SetDeadline(time.Time{})
	}
	if _, err := fmt.Fprintf(conn, "CONNECT %d\n", port); err != nil {
		return fmt.Errorf("vsock handshake: %w", err)
	}
	line, err := readLine(conn, 64)
	if err != nil {
		return fmt.Errorf("vsock handshake: %w", err)
	}
	if !strings.HasPrefix(line, "OK ") {
		return fmt.Errorf("vsock handshake: unexpected reply %q", line)
	}
	if _, err := strconv.Atoi(strings.TrimSpace(strings.TrimPrefix(line, "OK "))); err != nil {
		return fmt.Errorf("vsock handshake: bad port in reply %q", line)
	}
	return nil
}

// readLine reads up to '\n' one byte at a time so nothing past the handshake
// line is consumed from the stream.
func readLine(r io.Reader, max int) (string, error) {
	var buf []byte
	one := make([]byte, 1)
	for len(buf) < max {
		if _, err := io.ReadFull(r, one); err != nil {
			return "", err
		}
		if one[0] == '\n' {
			return string(buf), nil
		}
		buf = append(buf, one[0])
	}
	return "", errors.New("line too long")
}

func (c *Client) nextID() string {
	return "r" + strconv.FormatUint(c.seq.Add(1), 10)
}

type conn struct {
	net.Conn
	reader *bufio.Reader
}

func (c *Client) open(ctx context.Context) (*conn, error) {
	raw, err := c.dial(ctx)
	if err != nil {
		return nil, err
	}
	return &conn{Conn: raw, reader: bufio.NewReaderSize(raw, 256*1024)}, nil
}

func (c *conn) send(req request) error {
	data, err := json.Marshal(req)
	if err != nil {
		return err
	}
	data = append(data, '\n')
	_, err = c.Write(data)
	return err
}

func (c *conn) recv() (response, error) {
	line, err := c.reader.ReadBytes('\n')
	if err != nil {
		return response{}, err
	}
	var resp response
	if err := json.Unmarshal(line, &resp); err != nil {
		return response{}, fmt.Errorf("decoding agent frame: %w", err)
	}
	return resp, nil
}

// call sends one request and reads exactly one response, applying the
// context deadline to the connection.
func (c *Client) call(ctx context.Context, req request) (response, error) {
	req.ID = c.nextID()
	cn, err := c.open(ctx)
	if err != nil {
		return response{}, err
	}
	defer cn.Close()
	stop := watchContext(ctx, cn)
	defer stop()
	if err := cn.send(req); err != nil {
		return response{}, fmt.Errorf("agent %s: %w", req.Op, err)
	}
	resp, err := cn.recv()
	if err != nil {
		if ctx.Err() != nil {
			return response{}, ctx.Err()
		}
		return response{}, fmt.Errorf("agent %s: %w", req.Op, err)
	}
	if resp.Type == "error" {
		return resp, &AgentError{Op: req.Op, Message: resp.Message}
	}
	return resp, nil
}

// watchContext closes the connection when ctx ends, which unblocks reads.
func watchContext(ctx context.Context, cn net.Conn) func() {
	done := make(chan struct{})
	go func() {
		select {
		case <-ctx.Done():
			cn.Close()
		case <-done:
		}
	}()
	return func() { close(done) }
}

func (c *Client) Ping(ctx context.Context) (Pong, error) {
	resp, err := c.call(ctx, request{Op: "ping"})
	if err != nil {
		return Pong{}, err
	}
	if resp.Type != "pong" {
		return Pong{}, fmt.Errorf("agent ping: unexpected reply type %q", resp.Type)
	}
	return Pong{UptimeS: resp.UptimeS, AgentVersion: resp.AgentVersion}, nil
}

// WaitReady pings until the agent answers or the timeout passes.
func (c *Client) WaitReady(ctx context.Context, timeout time.Duration) (Pong, error) {
	return WaitReady(ctx, c, timeout)
}

// WaitReady pings any Agent until it answers or the timeout passes.
func WaitReady(ctx context.Context, agent Agent, timeout time.Duration) (Pong, error) {
	deadline := time.Now().Add(timeout)
	var last error
	for {
		attempt, cancel := context.WithTimeout(ctx, 2*time.Second)
		pong, err := agent.Ping(attempt)
		cancel()
		if err == nil {
			return pong, nil
		}
		last = err
		if ctx.Err() != nil {
			return Pong{}, ctx.Err()
		}
		if time.Now().After(deadline) {
			return Pong{}, fmt.Errorf("agent not ready after %s: %w", timeout, last)
		}
		select {
		case <-ctx.Done():
			return Pong{}, ctx.Err()
		case <-time.After(25 * time.Millisecond):
		}
	}
}

func (c *Client) SetTime(ctx context.Context, now time.Time) error {
	return expectOK(c.call(ctx, request{Op: "set_time", UnixNanos: now.UnixNano()}))
}

func (c *Client) Configure(ctx context.Context, req ConfigureRequest) error {
	return expectOK(c.call(ctx, request{Op: "configure", Hostname: req.Hostname, DNS: req.DNS, FormatWorkspace: req.FormatWorkspace}))
}

func (c *Client) WriteFile(ctx context.Context, path string, mode uint32, data []byte) error {
	return expectOK(c.call(ctx, request{Op: "write_file", Path: path, Mode: mode, DataB64: base64.StdEncoding.EncodeToString(data)}))
}

func (c *Client) Kill(ctx context.Context, execID string, signal int) error {
	return expectOK(c.call(ctx, request{Op: "kill", Target: execID, Signal: signal}))
}

func expectOK(resp response, err error) error {
	if err != nil {
		return err
	}
	if resp.Type != "ok" {
		return fmt.Errorf("agent: unexpected reply type %q", resp.Type)
	}
	return nil
}

type process struct {
	client *Client
	id     string
	cn     *conn
	out    OutputFunc
	done   chan struct{}
	code   int
	err    error
	once   sync.Once
}

func (p *process) ID() string { return p.id }

func (p *process) Wait(ctx context.Context) (int, error) {
	select {
	case <-p.done:
		return p.code, p.err
	case <-ctx.Done():
		return -1, ctx.Err()
	}
}

func (p *process) Signal(ctx context.Context, signal int) error {
	return p.client.Kill(ctx, p.id, signal)
}

// pump reads stream frames until exit or error and then closes the
// connection.
func (p *process) pump() {
	defer close(p.done)
	defer p.cn.Close()
	for {
		resp, err := p.cn.recv()
		if err != nil {
			p.err = fmt.Errorf("agent exec %s: stream ended: %w", p.id, err)
			p.code = -1
			return
		}
		switch resp.Type {
		case "stdout", "stderr":
			if p.out != nil {
				data, decErr := base64.StdEncoding.DecodeString(resp.DataB64)
				if decErr != nil {
					p.err = fmt.Errorf("agent exec %s: bad %s frame: %w", p.id, resp.Type, decErr)
					p.code = -1
					return
				}
				p.out(resp.Type, data)
			}
		case "exit":
			p.code = resp.Code
			return
		case "error":
			p.err = &AgentError{Op: "exec", Message: resp.Message}
			p.code = -1
			return
		}
	}
}

// Start launches a command and returns once the agent reports it started.
// The connection stays open to stream output until exit; the request ctx
// only bounds the start handshake.
func (c *Client) Start(ctx context.Context, req ExecRequest, out OutputFunc) (Process, error) {
	cn, err := c.open(ctx)
	if err != nil {
		return nil, err
	}
	stop := watchContext(ctx, cn)
	if err := cn.send(request{ID: c.nextID(), Op: "exec", Cmd: req.Cmd, Env: req.Env, Cwd: req.Cwd, TimeoutMs: req.TimeoutMs}); err != nil {
		stop()
		cn.Close()
		return nil, fmt.Errorf("agent exec: %w", err)
	}
	resp, err := cn.recv()
	stop()
	if err != nil {
		cn.Close()
		if ctx.Err() != nil {
			return nil, ctx.Err()
		}
		return nil, fmt.Errorf("agent exec: %w", err)
	}
	switch resp.Type {
	case "started":
	case "error":
		cn.Close()
		return nil, &AgentError{Op: "exec", Message: resp.Message}
	default:
		cn.Close()
		return nil, fmt.Errorf("agent exec: unexpected reply type %q", resp.Type)
	}
	p := &process{client: c, id: resp.ExecID, cn: cn, out: out, done: make(chan struct{})}
	go p.pump()
	return p, nil
}

// Exec runs a command to completion. Cancelling ctx kills the guest process
// (SIGKILL) and returns ctx.Err().
func (c *Client) Exec(ctx context.Context, req ExecRequest, out OutputFunc) (int, error) {
	return RunProcess(ctx, c, req, out)
}

// RunProcess is Exec over any Agent.
func RunProcess(ctx context.Context, agent Agent, req ExecRequest, out OutputFunc) (int, error) {
	proc, err := agent.Start(ctx, req, out)
	if err != nil {
		return -1, err
	}
	code, err := proc.Wait(ctx)
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		killCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = proc.Signal(killCtx, 9)
		return -1, err
	}
	return code, err
}

// RunProcessWait waits on an already started process with the same
// cancellation semantics as RunProcess.
func RunProcessWait(ctx context.Context, proc Process) (int, error) {
	code, err := proc.Wait(ctx)
	if errors.Is(err, context.Canceled) || errors.Is(err, context.DeadlineExceeded) {
		killCtx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_ = proc.Signal(killCtx, 9)
		return -1, err
	}
	return code, err
}
