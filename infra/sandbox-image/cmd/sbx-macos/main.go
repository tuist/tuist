// sbx-macos is a stdin-only bridge over Tart's host-local vsock transport.
// Credentials travel through stdin and process environments, never argv or journals.
package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"
)

type request struct {
	Op        string            `json:"op"`
	ID        string            `json:"id"`
	Cmd       []string          `json:"cmd"`
	Env       map[string]string `json:"env"`
	Cwd       string            `json:"cwd"`
	TimeoutMS int64             `json:"timeout_ms"`
}
type response struct {
	Type     string `json:"type,omitempty"`
	ID       string `json:"id,omitempty"`
	Running  bool   `json:"running"`
	ExitCode int    `json:"exit_code"`
	DataB64  string `json:"data_b64,omitempty"`
	Error    string `json:"error,omitempty"`
	PID      int    `json:"pid,omitempty"`
	PGID     int    `json:"pgid,omitempty"`
}

var outputMu sync.Mutex

func emit(r response) {
	outputMu.Lock()
	defer outputMu.Unlock()
	_ = json.NewEncoder(os.Stdout).Encode(r)
}
func main() {
	var req request
	if err := json.NewDecoder(io.LimitReader(os.Stdin, 1<<20)).Decode(&req); err != nil {
		emit(response{Error: "invalid request"})
		os.Exit(1)
	}
	if len(os.Args) == 2 && strings.HasPrefix(os.Args[1], "--worker=") {
		if req.ID != strings.TrimPrefix(os.Args[1], "--worker=") {
			os.Exit(1)
		}
		worker(req)
		return
	}
	if err := dispatch(req); err != nil {
		emit(response{Error: err.Error()})
		os.Exit(1)
	}
}
func root() string {
	home, _ := os.UserHomeDir()
	return filepath.Join(home, "Library", "Application Support", "TuistSandbox")
}
func statePath() string { return filepath.Join(root(), "worker.json") }
func save(r response) error {
	data, err := json.Marshal(r)
	if err != nil {
		return err
	}
	f, err := os.CreateTemp(root(), ".worker-")
	if err != nil {
		return err
	}
	defer os.Remove(f.Name())
	if _, err = f.Write(data); err == nil {
		err = f.Sync()
	}
	closeErr := f.Close()
	if err != nil {
		return err
	}
	if closeErr != nil {
		return closeErr
	}
	return os.Rename(f.Name(), statePath())
}

// Missing completion proof remains busy; status never signals a possibly reused PID.
func status() (response, error) {
	data, err := os.ReadFile(statePath())
	if os.IsNotExist(err) {
		return response{Type: "status"}, nil
	}
	if err != nil {
		return response{}, err
	}
	var r response
	if err = json.Unmarshal(data, &r); err != nil {
		return r, err
	}
	r.Type = "status"
	if r.PGID > 0 && syscall.Kill(-r.PGID, 0) != syscall.ESRCH {
		r.Running = true
	}
	return r, nil
}
func busy() (bool, error) {
	entries, err := os.ReadDir(root())
	if err != nil {
		return true, err
	}
	for _, entry := range entries {
		if strings.HasPrefix(entry.Name(), "exec-") {
			return true, nil
		}
	}
	s, err := status()
	return s.Running, err
}
func validID(id string) bool {
	if len(id) < 1 || len(id) > 255 {
		return false
	}
	for _, r := range id {
		if !(r >= 'a' && r <= 'z' || r >= 'A' && r <= 'Z' || r >= '0' && r <= '9' || r == '-' || r == '_') {
			return false
		}
	}
	return true
}
func dispatch(req request) error {
	if err := os.MkdirAll(root(), 0700); err != nil {
		return err
	}
	switch req.Op {
	case "ping":
		emit(response{Type: "pong"})
		return nil
	case "busy":
		running, err := busy()
		if err == nil {
			emit(response{Type: "busy", Running: running})
		}
		return err
	case "exec":
		if len(req.Cmd) == 0 || req.TimeoutMS < 1 || req.TimeoutMS > 3600000 {
			return errors.New("invalid exec request")
		}
		cmd, err := command(req)
		if err != nil {
			return err
		}
		marker, err := os.CreateTemp(root(), "exec-")
		if err != nil {
			return err
		}
		marker.Close()
		ctx, cancel := context.WithTimeout(context.Background(), time.Duration(req.TimeoutMS)*time.Millisecond)
		defer cancel()
		cmd.Stdout = &streamWriter{kind: "stdout"}
		cmd.Stderr = &streamWriter{kind: "stderr"}
		code, err := run(ctx, cmd)
		if err != nil {
			if cmd.Process == nil {
				_ = os.Remove(marker.Name())
			}
			return err
		}
		if err = os.Remove(marker.Name()); err != nil {
			return err
		}
		emit(response{Type: "exit", ExitCode: code})
		return nil
	case "status":
		s, err := status()
		if err == nil {
			emit(s)
		}
		return err
	case "stop":
		s, err := status()
		if err != nil {
			return err
		}
		if req.ID != "" && req.ID != s.ID {
			return errors.New("worker identity changed")
		}
		if s.Running {
			text, err := exec.Command("/bin/ps", "-p", fmt.Sprint(s.PID), "-o", "command=").Output()
			if err != nil || !strings.HasSuffix(strings.TrimSpace(string(text)), "--worker="+s.ID) {
				return errors.New("worker owner cannot be verified")
			}
			if err = syscall.Kill(s.PID, syscall.SIGTERM); err != nil {
				return err
			}
			until := time.Now().Add(10 * time.Second)
			for s.Running && time.Now().Before(until) {
				time.Sleep(50 * time.Millisecond)
				s, err = status()
				if err != nil {
					return err
				}
			}
			if s.Running {
				return errors.New("worker did not stop")
			}
		}
		emit(s)
		return nil
	case "start":
		if !validID(req.ID) {
			return errors.New("invalid work id")
		}
		lock, err := os.OpenFile(filepath.Join(root(), "worker.lock"), os.O_CREATE|os.O_RDWR, 0600)
		if err != nil {
			return err
		}
		defer lock.Close()
		if err = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
			return err
		}
		defer syscall.Flock(int(lock.Fd()), syscall.LOCK_UN)
		prior, err := status()
		if err != nil {
			return err
		}
		if prior.ID == req.ID {
			emit(prior)
			return nil
		}
		if prior.Running {
			return errors.New("another worker is running")
		}
		executable, err := os.Executable()
		if err != nil {
			return err
		}
		child := exec.Command(executable, "--worker="+req.ID)
		child.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
		input, err := child.StdinPipe()
		if err != nil {
			return err
		}
		null, err := os.OpenFile(os.DevNull, os.O_RDWR, 0)
		if err != nil {
			input.Close()
			return err
		}
		defer null.Close()
		child.Stdout = null
		child.Stderr = null
		if err = child.Start(); err != nil {
			input.Close()
			return err
		}
		current := response{Type: "status", ID: req.ID, Running: true, PID: child.Process.Pid}
		if err = save(current); err != nil {
			input.Close()
			_ = child.Process.Kill()
			_ = child.Wait()
			return err
		}
		err = json.NewEncoder(input).Encode(req)
		input.Close()
		_ = child.Process.Release()
		if err != nil {
			return err
		}
		emit(current)
		return nil
	default:
		return errors.New("unknown operation")
	}
}
func command(req request) (*exec.Cmd, error) {
	if len(req.Cmd) == 0 {
		return nil, errors.New("empty command")
	}
	cmd := exec.Command(req.Cmd[0], req.Cmd[1:]...)
	cmd.Dir = req.Cwd
	if cmd.Dir == "" {
		home, _ := os.UserHomeDir()
		cmd.Dir = filepath.Join(home, "work")
	}
	env := map[string]string{}
	for _, item := range os.Environ() {
		k, v, ok := strings.Cut(item, "=")
		if ok {
			env[k] = v
		}
	}
	for k, v := range req.Env {
		if k == "" || strings.ContainsAny(k, "=\x00") || strings.ContainsRune(v, 0) {
			return nil, errors.New("invalid environment")
		}
		env[k] = v
	}
	for k, v := range env {
		cmd.Env = append(cmd.Env, k+"="+v)
	}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}
	cmd.WaitDelay = 2 * time.Second
	return cmd, nil
}
func run(ctx context.Context, cmd *exec.Cmd) (int, error) {
	if err := cmd.Start(); err != nil {
		return 0, err
	}
	return waitGroup(ctx, cmd)
}
func waitGroup(ctx context.Context, cmd *exec.Cmd) (int, error) {
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	var err error
	code := 0
	select {
	case err = <-done:
	case <-ctx.Done():
		code = 124
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		err = <-done
	}
	// A background command cannot escape its exec or worker lifetime.
	if killErr := syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL); killErr != nil && killErr != syscall.ESRCH {
		return code, killErr
	}
	deadline := time.Now().Add(5 * time.Second)
	for syscall.Kill(-cmd.Process.Pid, 0) != syscall.ESRCH {
		if time.Now().After(deadline) {
			return code, errors.New("command group not fenced")
		}
		time.Sleep(20 * time.Millisecond)
	}
	if code == 124 {
		return code, nil
	}
	var exit *exec.ExitError
	if errors.As(err, &exit) {
		return exit.ExitCode(), nil
	}
	return 0, err
}
func worker(req request) {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, syscall.SIGINT)
	defer stop()
	executable, _ := os.Executable()
	req.Cmd = []string{filepath.Join(filepath.Dir(executable), "sbx-worker")}
	cmd, err := command(req)
	if err != nil {
		return
	}
	if err = cmd.Start(); err != nil {
		_ = save(response{ID: req.ID, ExitCode: 1, PID: os.Getpid()})
		return
	}
	current := response{ID: req.ID, Running: true, PID: os.Getpid(), PGID: cmd.Process.Pid}
	if err = save(current); err != nil {
		_ = syscall.Kill(-cmd.Process.Pid, syscall.SIGKILL)
		_ = cmd.Wait()
		return
	}
	code, err := waitGroup(ctx, cmd)
	if err != nil {
		return
	}
	current.Running = false
	current.ExitCode = code
	current.PGID = 0
	_ = save(current)
}

type streamWriter struct{ kind string }

func (w *streamWriter) Write(p []byte) (int, error) {
	n := len(p)
	for len(p) > 0 {
		size := min(len(p), 32768)
		emit(response{Type: w.kind, DataB64: base64.StdEncoding.EncodeToString(p[:size])})
		p = p[size:]
	}
	return n, nil
}
