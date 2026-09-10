// Package agent implements the guest side of the sandboxd vsock protocol: it
// accepts one request per connection, dispatches it and streams the response
// frames back. Everything Linux-specific sits behind the System interface so
// the handler is testable over net.Pipe on any platform.
package agent

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"os"
	"path/filepath"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandbox-image/internal/exec"
	"github.com/tuist/tuist/infra/sandbox-image/internal/protocol"
)

// ConfigureSpec is what a configure request asks the guest to become. Empty
// Hostname or DNS leave the current value alone.
type ConfigureSpec struct {
	Hostname        string
	DNS             []string
	FormatWorkspace bool
}

// System is the platform surface the handler needs.
type System interface {
	Uptime() (time.Duration, error)
	SetTime(t time.Time) error
	Configure(ctx context.Context, spec ConfigureSpec) error
}

type Handler struct {
	Version string
	System  System
	Execs   *exec.Registry
	Logger  *slog.Logger
}

// Serve accepts connections until ctx is cancelled or the listener fails.
func (h *Handler) Serve(ctx context.Context, l net.Listener) error {
	for {
		conn, err := l.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			var netErr net.Error
			if errors.As(err, &netErr) && netErr.Timeout() {
				time.Sleep(100 * time.Millisecond)
				continue
			}
			return err
		}
		go h.HandleConn(ctx, conn)
	}
}

// HandleConn serves exactly one request and closes the connection.
func (h *Handler) HandleConn(ctx context.Context, conn net.Conn) {
	defer conn.Close()
	w := protocol.NewWriter(conn)
	req, err := protocol.ReadRequest(conn)
	if err != nil {
		if errors.Is(err, io.EOF) {
			return
		}
		h.logger().Warn("bad request", slog.Any("error", err))
		_ = w.Send(protocol.Error("", err.Error()))
		return
	}
	h.handle(ctx, req, w)
}

func (h *Handler) handle(ctx context.Context, req *protocol.Request, w *protocol.Writer) {
	var err error
	switch req.Op {
	case protocol.OpPing:
		err = h.ping(req, w)
	case protocol.OpSetTime:
		err = h.setTime(req, w)
	case protocol.OpConfigure:
		err = h.configure(ctx, req, w)
	case protocol.OpWriteFile:
		err = h.writeFile(req, w)
	case protocol.OpExec:
		err = h.exec(ctx, req, w)
	case protocol.OpKill:
		err = h.kill(req, w)
	default:
		err = fmt.Errorf("unknown op %q", req.Op)
	}
	if err != nil {
		h.logger().Warn("request failed", slog.String("id", req.ID), slog.String("op", req.Op), slog.Any("error", err))
		_ = w.Send(protocol.Error(req.ID, err.Error()))
	}
}

func (h *Handler) ping(req *protocol.Request, w *protocol.Writer) error {
	uptime, err := h.System.Uptime()
	if err != nil {
		h.logger().Warn("uptime unavailable", slog.Any("error", err))
	}
	return w.Send(protocol.Pong(req.ID, uptime.Seconds(), h.Version))
}

func (h *Handler) setTime(req *protocol.Request, w *protocol.Writer) error {
	if req.UnixNanos <= 0 {
		return errors.New("set_time: unix_nanos is required")
	}
	if err := h.System.SetTime(time.Unix(0, req.UnixNanos)); err != nil {
		return fmt.Errorf("set_time: %w", err)
	}
	return w.Send(protocol.OK(req.ID))
}

func (h *Handler) configure(ctx context.Context, req *protocol.Request, w *protocol.Writer) error {
	spec := ConfigureSpec{Hostname: req.Hostname, DNS: req.DNS, FormatWorkspace: req.FormatWorkspace}
	if err := h.System.Configure(ctx, spec); err != nil {
		return fmt.Errorf("configure: %w", err)
	}
	return w.Send(protocol.OK(req.ID))
}

func (h *Handler) writeFile(req *protocol.Request, w *protocol.Writer) error {
	if !filepath.IsAbs(req.Path) {
		return fmt.Errorf("write_file: path must be absolute, got %q", req.Path)
	}
	data, err := base64.StdEncoding.DecodeString(req.DataB64)
	if err != nil {
		return fmt.Errorf("write_file: decode data_b64: %w", err)
	}
	mode := os.FileMode(req.Mode)
	if mode == 0 {
		mode = 0o644
	}
	if err := os.MkdirAll(filepath.Dir(req.Path), 0o755); err != nil {
		return fmt.Errorf("write_file: %w", err)
	}
	if err := os.WriteFile(req.Path, data, mode); err != nil {
		return fmt.Errorf("write_file: %w", err)
	}
	// WriteFile only applies the mode on creation and through the umask.
	if err := os.Chmod(req.Path, mode); err != nil {
		return fmt.Errorf("write_file: %w", err)
	}
	return w.Send(protocol.OK(req.ID))
}

func (h *Handler) exec(ctx context.Context, req *protocol.Request, w *protocol.Writer) error {
	spec := exec.Spec{
		Cmd:     req.Cmd,
		Env:     req.Env,
		Cwd:     req.Cwd,
		Timeout: time.Duration(req.TimeoutMs) * time.Millisecond,
	}
	started := func(id string) {
		_ = w.Send(protocol.Started(req.ID, id))
	}
	code, err := h.Execs.Run(ctx, spec, started, &sink{id: req.ID, w: w})
	if err != nil {
		return fmt.Errorf("exec: %w", err)
	}
	return w.Send(protocol.Exit(req.ID, code))
}

func (h *Handler) kill(req *protocol.Request, w *protocol.Writer) error {
	if req.Target == "" {
		return errors.New("kill: target is required")
	}
	sig := syscall.Signal(req.Signal)
	if sig == 0 {
		sig = syscall.SIGTERM
	}
	if err := h.Execs.Kill(req.Target, sig); err != nil {
		return fmt.Errorf("kill %s: %w", req.Target, err)
	}
	return w.Send(protocol.OK(req.ID))
}

func (h *Handler) logger() *slog.Logger {
	if h.Logger != nil {
		return h.Logger
	}
	return slog.Default()
}

type sink struct {
	id string
	w  *protocol.Writer
}

func (s *sink) Write(stream exec.Stream, data []byte) error {
	typ := protocol.TypeStdout
	if stream == exec.Stderr {
		typ = protocol.TypeStderr
	}
	return s.w.Send(protocol.Stream(s.id, typ, data))
}
