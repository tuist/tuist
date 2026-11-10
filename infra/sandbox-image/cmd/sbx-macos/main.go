//go:build darwin

// sbx-macos is a stdin-only bridge over Tart's host-local vsock transport.
// Credentials travel through stdin and process environments, never argv or journals.
package main

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
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
	// CPUPermille answers the cpu op.
	CPUPermille int64 `json:"cpu_permille,omitempty"`
}

var outputMu sync.Mutex

func emit(r response) {
	outputMu.Lock()
	defer outputMu.Unlock()
	_ = json.NewEncoder(os.Stdout).Encode(r)
}
func main() {
	// Invoked through an exec with the credentials in its environment. The
	// exec's process group is fenced when it returns; Amp's bootstrap runs
	// in its own session so it outlives it, as `amp orb bootstrap` must.
	if len(os.Args) == 2 && os.Args[1] == "--orb-bootstrap" {
		if err := orbBootstrap(); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
		return
	}
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
	case "cpu":
		permille, err := cpuPermille()
		if err == nil {
			emit(response{Type: "cpu", CPUPermille: permille})
		}
		return err
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
		// A retried start finds its own worker running. Managed Agents reuse
		// the session ID as the work ID on every turn, so a finished worker
		// with the same ID is an earlier turn, and this turn starts a new one.
		if prior.ID == req.ID && prior.Running {
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

// cpuPermille is the recent CPU use of this user's processes, in thousandths
// of one core: the sum of ps's decaying %cpu, which the host integrates.
func cpuPermille() (int64, error) {
	out, err := exec.Command("/bin/ps", "-U", fmt.Sprint(os.Getuid()), "-o", "%cpu=").Output()
	if err != nil {
		return 0, err
	}
	var total float64
	for _, field := range strings.Fields(string(out)) {
		var value float64
		if _, err := fmt.Sscanf(field, "%g", &value); err == nil {
			total += value
		}
	}
	return int64(total * 10), nil
}

// orbBootstrap starts `amp orb bootstrap` once per credential, like the Linux
// guest's sbx-orb-bootstrap: a retried spawn with the same token keeps the
// running process; a resumed Orb's fresh token replaces only that process.
// The token is fingerprinted, never stored.
func orbBootstrap() error {
	token, ampURL := os.Getenv("ORB_TOKEN"), os.Getenv("AMP_URL")
	if token == "" {
		return errors.New("ORB_TOKEN is required")
	}
	if ampURL == "" {
		ampURL = "https://ampcode.com"
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	if err = os.MkdirAll(root(), 0700); err != nil {
		return err
	}
	lock, err := os.OpenFile(filepath.Join(root(), "orb.lock"), os.O_CREATE|os.O_RDWR, 0600)
	if err != nil {
		return err
	}
	defer lock.Close()
	if err = syscall.Flock(int(lock.Fd()), syscall.LOCK_EX); err != nil {
		return err
	}
	sum := sha256.Sum256([]byte(token + "\x00" + ampURL))
	fingerprint := hex.EncodeToString(sum[:])
	statePath := filepath.Join(root(), "orb.json")
	var prior struct {
		PID         int    `json:"pid"`
		Started     string `json:"started"`
		Fingerprint string `json:"fingerprint"`
	}
	if data, err := os.ReadFile(statePath); err == nil && json.Unmarshal(data, &prior) == nil && prior.PID > 0 {
		// The start time fences PID reuse across a cold boot of the disk.
		if processStarted(prior.PID) == prior.Started {
			if prior.Fingerprint == fingerprint {
				return nil
			}
			_ = syscall.Kill(prior.PID, syscall.SIGTERM)
			for i := 0; i < 30 && processStarted(prior.PID) == prior.Started; i++ {
				time.Sleep(100 * time.Millisecond)
			}
			if processStarted(prior.PID) == prior.Started {
				_ = syscall.Kill(prior.PID, syscall.SIGKILL)
			}
		}
	}
	amp, err := ampBinary(home)
	if err != nil {
		return err
	}
	// Amp's repository lives under ~/workspace; keep it on the separately
	// budgeted APFS workspace volume.
	workspace := filepath.Join(home, "work", "amp")
	if err = os.MkdirAll(workspace, 0755); err != nil {
		return err
	}
	if _, err = os.Lstat(filepath.Join(home, "workspace")); os.IsNotExist(err) {
		if err = os.Symlink(workspace, filepath.Join(home, "workspace")); err != nil {
			return err
		}
	}
	logFile, err := os.OpenFile(filepath.Join(home, ".amp-bootstrap.log"), os.O_CREATE|os.O_WRONLY|os.O_TRUNC, 0600)
	if err != nil {
		return err
	}
	defer logFile.Close()
	cmd := exec.Command(amp, "orb", "bootstrap")
	cmd.Dir = home
	cmd.Stdout, cmd.Stderr = logFile, logFile
	cmd.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	cmd.Env = []string{"PATH=" + filepath.Dir(amp) + ":/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
		"HOME=" + home, "USER=" + os.Getenv("USER"), "LANG=en_US.UTF-8", "ORB_TOKEN=" + token, "AMP_URL=" + ampURL,
		// macOS Orbs are not qualified yet: a project thread's first setup
		// fails without a trace at the default level. Debug records each
		// bootstrap request in ~/.cache/amp/logs/cli.log.
		"AMP_LOG_LEVEL=debug"}
	// No Tuist credential reaches Amp: Tuist clients in the guest sign in with the Orb's Amp identity.
	for _, name := range []string{"TUIST_URL", "TUIST_CACHE_ENDPOINT"} {
		if value := os.Getenv(name); value != "" {
			cmd.Env = append(cmd.Env, name+"="+value)
		}
	}
	// The CLI does not log what a bootstrap request runs, even at debug. Until
	// macOS Orbs are qualified, record every exec and exit for ten minutes,
	// which covers the first setup and Amp's restart attempts. Arguments may
	// hold credentials, so the file is root-only. Best effort: a missing trace
	// must not fail the spawn, and a running trace is kept.
	trace := exec.Command("/usr/bin/sudo", "-n", "/bin/sh", "-c",
		`/usr/bin/pgrep -x eslogger >/dev/null && exit 0
umask 077
/usr/bin/eslogger exec exit >"$1" 2>&1 &
sleep 600
kill $!`, "sh", filepath.Join(home, ".amp-exec-trace.jsonl"))
	trace.SysProcAttr = &syscall.SysProcAttr{Setsid: true}
	if trace.Start() == nil {
		_ = trace.Process.Release()
	}
	if err = cmd.Start(); err != nil {
		return err
	}
	pid := cmd.Process.Pid
	_ = cmd.Process.Release()
	prior.PID, prior.Started, prior.Fingerprint = pid, processStarted(pid), fingerprint
	data, _ := json.Marshal(prior)
	if err = os.WriteFile(statePath+".new", data, 0600); err != nil {
		return err
	}
	if err = os.Rename(statePath+".new", statePath); err != nil {
		return err
	}
	time.Sleep(200 * time.Millisecond)
	if syscall.Kill(pid, 0) != nil {
		return errors.New("Amp bootstrap exited during startup")
	}
	return nil
}

// The guest can read, but not execute, the share after a resume, so the CLI
// runs from a copy in the place Amp's installer uses.
var sharedAmp = "/Volumes/My Shared Files/sandbox-tools/amp"

func copyAmpBinary(home, source string) (string, error) {
	in, err := os.Open(source)
	if err != nil {
		return "", err
	}
	defer in.Close()
	dir := filepath.Join(home, ".amp", "bin")
	if err = os.MkdirAll(dir, 0755); err != nil {
		return "", err
	}
	out, err := os.CreateTemp(dir, "tmp.")
	if err != nil {
		return "", err
	}
	defer os.Remove(out.Name())
	if _, err = io.Copy(out, in); err == nil {
		err = out.Chmod(0755)
	}
	if closeErr := out.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return "", err
	}
	path := filepath.Join(dir, "amp")
	if err = os.Rename(out.Name(), path); err != nil {
		return "", err
	}
	// As Amp's installer does, so a shell in the Orb finds `amp` too.
	if err = os.MkdirAll(filepath.Join(home, ".local", "bin"), 0755); err == nil {
		link := filepath.Join(home, ".local", "bin", "amp")
		if _, statErr := os.Lstat(link); os.IsNotExist(statErr) {
			_ = os.Symlink(path, link)
		}
	}
	return path, nil
}

func processStarted(pid int) string {
	out, err := exec.Command("/bin/ps", "-p", fmt.Sprint(pid), "-o", "lstart=").Output()
	if err != nil {
		return ""
	}
	return strings.TrimSpace(string(out))
}

// The Amp CLI updates itself, so the first Orb on a guest installs it and
// later ones reuse it. The host shares a checksum-verified copy next to the
// guest tools; only a host that has not fetched it yet leaves the guest to
// download it with Amp's installer.
func ampBinary(home string) (string, error) {
	for _, path := range []string{filepath.Join(home, ".amp", "bin", "amp"), "/opt/homebrew/bin/amp", "/usr/local/bin/amp"} {
		if info, err := os.Stat(path); err == nil && info.Mode()&0111 != 0 {
			return path, nil
		}
	}
	if path, err := copyAmpBinary(home, sharedAmp); err == nil {
		return path, nil
	}
	install := exec.Command("/bin/bash", "-c", "curl -fsSL https://ampcode.com/install.sh | bash")
	install.Env = []string{"HOME=" + home, "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"}
	if err := install.Run(); err != nil {
		return "", errors.New("installing the Amp CLI failed")
	}
	path := filepath.Join(home, ".amp", "bin", "amp")
	if _, err := os.Stat(path); err != nil {
		return "", errors.New("the Amp CLI installer left no binary")
	}
	return path, nil
}
