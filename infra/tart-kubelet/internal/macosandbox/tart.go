package macosandbox

import (
	"bufio"
	"context"
	"crypto/sha256"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/google/uuid"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

//go:embed runtime/*
var runtimeAssets embed.FS

// BuildRuntime builds at background QoS in a content-addressed directory. Old
// builds remain available to checkpoints made before a kubelet upgrade.
func BuildRuntime(ctx context.Context, root string) (string, error) {
	var content []byte
	for _, name := range []string{"build.sh", "ResidentControl.swift", "tart.patch"} {
		data, err := runtimeAssets.ReadFile("runtime/" + name)
		if err != nil {
			return "", err
		}
		content = append(content, data...)
	}
	sum := sha256.Sum256(content)
	directory := filepath.Join(root, fmt.Sprintf("%x", sum[:12]))
	binary := filepath.Join(directory, "tart.app", "Contents", "MacOS", "tart")
	if _, err := os.Stat(filepath.Join(directory, "ready")); err == nil {
		return binary, nil
	}
	assets := filepath.Join(directory, "assets")
	if err := os.MkdirAll(assets, 0700); err != nil {
		return "", err
	}
	for _, name := range []string{"build.sh", "ResidentControl.swift", "tart.patch"} {
		data, _ := runtimeAssets.ReadFile("runtime/" + name)
		if err := os.WriteFile(filepath.Join(assets, name), data, 0600); err != nil {
			return "", err
		}
	}
	cmd := exec.CommandContext(ctx, "/usr/sbin/taskpolicy", "-b", "/bin/sh", filepath.Join(assets, "build.sh"), directory, assets)
	cmd.Stdout = os.Stderr
	cmd.Stderr = os.Stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("build sandbox runtime: %w", err)
	}
	return binary, nil
}

type TartRuntime struct {
	Client                 *tart.Client
	Image, Template, Tools string
}

func (t *TartRuntime) client(r *Record) *tart.Client {
	c := *t.Client
	if r.RuntimePath != "" {
		c.Binary = r.RuntimePath
	}
	c.LaunchGuard = nil
	c.ExtraEnv = append(append([]string{}, c.ExtraEnv...), "TUIST_SANDBOX_RUNTIME=1", "TART_NO_AUTO_PRUNE=1")
	return &c
}
func (t *TartRuntime) directory(r *Record) string {
	return filepath.Join(t.Client.HomeDir, "vms", r.VMName())
}
func (t *TartRuntime) options(r *Record) tart.RunOptions {
	return tart.RunOptions{Suspendable: true, DetachedLogs: true, SharedDirs: []string{"env:" + filepath.Join(t.Client.HomeDir, "env", r.SandboxID) + ":ro", "sandbox-tools:" + r.ToolsPath + ":ro"}}
}
func (t *TartRuntime) Create(ctx context.Context, r *Record) error {
	if r.Template != t.Template {
		return errors.New("unknown macOS template")
	}
	if r.RuntimePath == "" {
		return errors.New("runtime must be pinned before create")
	}
	c := t.client(r)
	if err := c.Clone(ctx, t.Image, r.VMName()); err != nil {
		return err
	}
	if err := c.Set(ctx, r.VMName(), r.VCPUs, r.MemoryMB); err != nil {
		return err
	}
	if err := t.checkDisk(ctx, r); err != nil {
		return err
	}
	if err := c.RegenerateIdentity(ctx, r.VMName()); err != nil {
		return err
	}
	env := filepath.Join(c.HomeDir, "env", r.SandboxID)
	if err := os.MkdirAll(env, 0700); err != nil {
		return err
	}
	if err := os.WriteFile(filepath.Join(env, "tuist.env"), []byte("TUIST_SANDBOX=1\n"), 0600); err != nil {
		return err
	}
	h, err := c.StartWithOptions(ctx, r.VMName(), t.options(r))
	if err != nil {
		return err
	}
	if err = t.waitGuestReady(ctx, r, h); err != nil {
		return err
	}
	// The image's sandbox boot mode disables runner dispatch before its halt
	// trap is armed. No runner service-account credential is shared with it.
	if _, err = c.Exec(ctx, r.VMName(), "/bin/sh", "-c", fmt.Sprintf(`set -eu
container=$(/usr/sbin/diskutil info -plist / | /usr/bin/plutil -extract APFSContainerReference raw -o - -)
/usr/bin/sudo -n /usr/sbin/diskutil apfs addVolume "$container" APFS TuistSandboxWorkspace -quota %dg -mountpoint /Users/runner/work
/usr/bin/sudo -n /usr/sbin/chown runner:staff /Users/runner/work`, r.WorkspaceGB)); err != nil {
		return err
	}
	_, err = t.control(ctx, r, "status")
	return err
}
func (t *TartRuntime) Resume(ctx context.Context, r *Record) error {
	if r.Resident {
		if _, err := t.control(ctx, r, "resume"); err != nil {
			return err
		}
		_, err := t.guest(ctx, r, map[string]string{"op": "ping"}, nil)
		return err
	}
	if err := t.checkDisk(ctx, r); err != nil {
		return err
	}
	c := t.client(r)
	r.Instance = ""
	r.PID = 0
	h, err := c.Resume(ctx, r.VMName(), t.options(r))
	if err != nil {
		return err
	}
	if err = t.waitGuestReady(ctx, r, h); err != nil {
		return err
	}
	_, err = t.control(ctx, r, "status")
	return err
}

// After checkpoint restoration, the guest can execute built-in commands before
// the shared bridge executable is usable. Readiness must exercise the same path
// as the first user command, while retaining the VM's capacity reservation.
func (t *TartRuntime) waitGuestReady(ctx context.Context, r *Record, h *tart.RunHandle) error {
	return h.WaitReady(ctx, func(ctx context.Context) error {
		reply, err := t.guest(ctx, r, map[string]string{"op": "ping"}, nil)
		if err == nil && reply.Type != "pong" {
			return errors.New("guest readiness returned no pong")
		}
		return err
	})
}

func (t *TartRuntime) Pause(ctx context.Context, r *Record) error {
	if busy, err := t.Busy(ctx, r); err != nil {
		return err
	} else if busy {
		return errors.New("sandbox has active guest work")
	}

	_, err := t.control(ctx, r, "pause")
	return err
}
func (t *TartRuntime) Save(ctx context.Context, r *Record) error {
	if err := t.checkDisk(ctx, r); err != nil {
		return err
	}
	if r.State != "paused" {
		if busy, err := t.Busy(ctx, r); err != nil {
			return err
		} else if busy {
			return errors.New("sandbox has active guest work")
		}
	}

	if _, err := t.control(ctx, r, "pause"); err != nil {
		return err
	}
	if _, err := t.control(ctx, r, "save"); err != nil {
		return err
	}
	return t.fence(ctx, r)
}
func (t *TartRuntime) fence(ctx context.Context, r *Record) error {
	c := t.client(r)
	// Stop deletes an already-suspended checkpoint. The private runtime exits
	// only after verifying the checkpoint belongs to this paused instance.
	if _, err := t.control(ctx, r, "fence"); err != nil {
		return err
	}
	for {
		running, err := c.IsRunning(ctx, r.VMName())
		if err != nil {
			return err
		}
		if !running {
			break
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(50 * time.Millisecond):
		}
	}
	vm, err := c.Get(ctx, r.VMName())
	if err != nil {
		return err
	}
	if vm == nil || !strings.EqualFold(vm.State, "suspended") {
		return errors.New("VM exited without a restorable checkpoint")
	}
	marker, err := os.ReadFile(filepath.Join(t.directory(r), "checkpoint-instance"))
	if err != nil {
		return err
	}
	if !strings.EqualFold(string(marker), r.Instance) || r.Instance == "" {
		return errors.New("checkpoint does not belong to owned runtime instance")
	}
	return nil
}
func (t *TartRuntime) Delete(ctx context.Context, r *Record) error {
	c := t.client(r)
	vm, err := c.Get(ctx, r.VMName())
	if err != nil {
		return err
	}
	if vm != nil {
		running, err := c.IsRunning(ctx, r.VMName())
		if err != nil {
			return err
		}
		if running {
			if err = c.Stop(ctx, r.VMName(), time.Second); err != nil {
				return err
			}
		}
		for {
			running, err = c.IsRunning(ctx, r.VMName())
			if err != nil {
				return err
			}
			if !running {
				break
			}
			select {
			case <-ctx.Done():
				return ctx.Err()
			case <-time.After(50 * time.Millisecond):
			}
		}
		if err = c.Delete(ctx, r.VMName()); err != nil {
			return err
		}
	}
	if err := os.RemoveAll(filepath.Join(c.HomeDir, "env", r.SandboxID)); err != nil {
		return err
	}
	if err := os.Remove(filepath.Join(c.LogDir, r.VMName()+".log")); err != nil && !os.IsNotExist(err) {
		return err
	}
	return nil
}
func (t *TartRuntime) Recover(ctx context.Context, r *Record) error {
	c := t.client(r)
	vm, err := c.Get(ctx, r.VMName())
	if err != nil {
		return err
	}
	if r.Operation == "create" {
		return errors.New("creation did not finish; delete the incomplete environment before retrying")
	}
	if r.Operation == "delete" {
		return errors.New("deletion must be retried")
	}
	if vm == nil {
		return errors.New("sandbox VM is missing; cold-boot fallback refused")
	}
	running, err := c.IsRunning(ctx, r.VMName())
	if err != nil {
		return err
	}
	if running {
		reply, err := t.control(ctx, r, "status")
		if err != nil {
			return err
		}
		r.Resident = true
		r.State = reply.State
		if r.Operation == "evict" {
			if err = t.Save(ctx, r); err != nil {
				return err
			}
			r.Resident = false
			r.State = "paused"
		}
		return nil
	}
	if !strings.EqualFold(vm.State, "suspended") {
		return errors.New("sandbox process lost without a checkpoint; cold-boot fallback refused")
	}
	marker, err := os.ReadFile(filepath.Join(t.directory(r), "checkpoint-instance"))
	if err != nil {
		return err
	}
	if r.Instance != "" && !strings.EqualFold(string(marker), r.Instance) {
		return errors.New("checkpoint instance mismatch")
	}
	if len(marker) == 0 {
		return errors.New("checkpoint proof is missing")
	}
	r.Resident = false
	r.State = "paused"
	r.PID = 0
	r.Instance = ""
	return nil
}

type controlReply struct {
	ID       string `json:"id"`
	Action   string `json:"action"`
	Instance string `json:"instance"`
	PID      int    `json:"pid"`
	State    string `json:"state"`
	Error    string `json:"error"`
}

func (t *TartRuntime) control(ctx context.Context, r *Record, action string) (controlReply, error) {
	var reply controlReply
	id := uuid.NewString()
	data, _ := json.Marshal(map[string]string{"id": id, "action": action, "instance": r.Instance})
	// status needs no instance; an empty UUID would be rejected by Swift decoding.
	if r.Instance == "" {
		data, _ = json.Marshal(map[string]string{"id": id, "action": action})
	}
	path := filepath.Join(t.directory(r), "sandbox-request.json")
	if err := atomicFile(path, data); err != nil {
		return reply, err
	}
	ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	for {
		data, err := os.ReadFile(filepath.Join(t.directory(r), "sandbox-reply.json"))
		if err == nil {
			if len(data) > 4096 {
				return reply, errors.New("oversized runtime reply")
			}
			if err = json.Unmarshal(data, &reply); err != nil {
				return reply, err
			}
			if strings.EqualFold(reply.ID, id) {
				if reply.Action != action || reply.PID <= 0 || reply.Instance == "" || reply.Error != "" {
					return reply, errors.New("runtime rejected transition")
				}
				if r.Instance != "" && !strings.EqualFold(reply.Instance, r.Instance) {
					return reply, errors.New("runtime process changed")
				}
				if r.PID != 0 && r.PID != reply.PID {
					return reply, errors.New("runtime PID changed")
				}
				if action == "resume" && reply.State != "running" || (action == "pause" || action == "save" || action == "fence") && reply.State != "paused" {
					return reply, errors.New("unexpected runtime state")
				}
				r.Instance = reply.Instance
				r.PID = reply.PID
				return reply, nil
			}
		} else if !os.IsNotExist(err) {
			return reply, err
		}
		select {
		case <-ctx.Done():
			return reply, ctx.Err()
		case <-time.After(5 * time.Millisecond):
		}
	}
}

type guestReply struct {
	Type     string `json:"type"`
	ID       string `json:"id"`
	Running  bool   `json:"running"`
	ExitCode int    `json:"exit_code"`
	DataB64  string `json:"data_b64"`
	Error    string `json:"error"`
}

func (t *TartRuntime) guest(ctx context.Context, r *Record, request any, out func(protocol.Stream)) (guestReply, error) {
	var result guestReply
	data, err := json.Marshal(request)
	if err != nil {
		return result, err
	}
	c := t.client(r)
	cmd := exec.CommandContext(ctx, c.Binary, "exec", "-i", r.VMName(), "/usr/bin/sudo", "-n", "-H", "-u", "runner", "/usr/bin/env", "PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin", "/Volumes/My Shared Files/sandbox-tools/sbx-macos")
	cmd.Env = append(os.Environ(), "TART_HOME="+c.HomeDir)
	cmd.Stdin = strings.NewReader(string(data) + "\n")
	cmd.WaitDelay = time.Second
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		return result, err
	}
	// Do not include guest output or command credentials in host errors.
	if err = cmd.Start(); err != nil {
		return result, err
	}
	scanner := bufio.NewScanner(stdout)
	scanner.Buffer(make([]byte, 65536), 1<<20)
	var total int
	for scanner.Scan() {
		var line guestReply
		if err = json.Unmarshal(scanner.Bytes(), &line); err != nil {
			break
		}
		if line.Error != "" {
			err = errors.New("guest operation failed")
			break
		}
		if line.Type == "stdout" || line.Type == "stderr" {
			if out != nil && total < 2<<20 {
				out(protocol.Stream{Stream: line.Type, DataB64: line.DataB64})
				total += len(line.DataB64)
			}
		} else {
			result = line
		}
	}
	if err == nil {
		err = scanner.Err()
	}
	if err != nil {
		_ = cmd.Process.Kill()
	}
	waitErr := cmd.Wait()
	if result.Type == "" && err == nil {
		err = errors.New("guest returned no completion proof")
	}
	return result, errors.Join(err, waitErr)
}
func (t *TartRuntime) Exec(ctx context.Context, r *Record, a protocol.ExecArgs, out func(protocol.Stream)) (protocol.ExecResult, error) {
	timeout := a.TimeoutMs
	if timeout <= 0 {
		timeout = 60000
	}
	if timeout > 3600000 {
		return protocol.ExecResult{}, errors.New("exec timeout exceeds one hour")
	}
	// Let the guest kill and reap its process group before the transport expires.
	ctx, cancel := context.WithTimeout(context.WithoutCancel(ctx), time.Duration(timeout)*time.Millisecond+5*time.Second)
	defer cancel()
	started := time.Now()
	result, err := t.guest(ctx, r, map[string]any{"op": "exec", "cmd": a.Cmd, "env": a.Env, "cwd": a.Cwd, "timeout_ms": timeout}, out)
	return protocol.ExecResult{ExitCode: result.ExitCode, DurationMs: time.Since(started).Milliseconds()}, err
}
func (t *TartRuntime) Worker(ctx context.Context, r *Record, action string, env map[string]string) (WorkerStatus, error) {
	result, err := t.guest(ctx, r, map[string]any{"op": action, "id": r.WorkerID, "env": env}, nil)
	return WorkerStatus{ID: result.ID, Running: result.Running, ExitCode: result.ExitCode}, err
}

func (t *TartRuntime) Busy(ctx context.Context, r *Record) (bool, error) {
	result, err := t.guest(ctx, r, map[string]string{"op": "busy"}, nil)
	if err == nil && result.Type != "busy" {
		err = errors.New("invalid busy response")
	}
	return result.Running, err
}
