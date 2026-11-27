package macosandbox

import (
	"bufio"
	"context"
	"crypto/sha256"
	"embed"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
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
	Client *tart.Client
	// Templates maps each prepared template to the image its VMs clone.
	Templates *Templates
	Tools     string
	// CIStore is the CI VMs' TART_HOME, which an archived image a restore
	// needs is seeded from before it is pulled (ensureImage).
	CIStore string
	// Checkouts gives each VM its checkout share; nil without the runner cache.
	Checkouts Checkouts
	// rootfs is the root disk ceiling diskRoom reserves per sandbox, as
	// last seen on this host's sandbox VMs (see rootDisk). 0 until known.
	rootfs atomic.Int64
	// snapMu orders the renames and deletes of disk snapshot directories.
	snapMu sync.Mutex
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
	shares := []string{"env:" + filepath.Join(t.Client.HomeDir, "env", r.envName()) + ":ro", "sandbox-tools:" + r.ToolsPath + ":ro"}
	if r.CheckoutShare != "" {
		shares = append(shares, checkoutShareName+":"+r.CheckoutShare)
	}
	return tart.RunOptions{Suspendable: true, DetachedLogs: true, SharedDirs: shares}
}
func (t *TartRuntime) Create(ctx context.Context, r *Record) error {
	if r.FromArchive != nil {
		return t.restore(ctx, r)
	}
	if err := t.Warm(ctx, r); err != nil {
		return err
	}
	return t.Claim(ctx, r)
}

// Warm clones and boots a VM up to a ready guest bridge. Nothing in it
// belongs to a sandbox yet, so a warm VM can wait for one.
func (t *TartRuntime) Warm(ctx context.Context, r *Record) error {
	image, ok := t.Templates.Image(r.Template)
	if !ok {
		return errors.New("unknown macOS template")
	}
	if r.RuntimePath == "" {
		return errors.New("runtime must be pinned before create")
	}
	// Timed like a restore, so a slow cold create can be attributed.
	start, mark := time.Now(), time.Now()
	phases := []any{"vm", r.VMName(), "memory_mb", r.MemoryMB}
	lap := func(name string) {
		phases = append(phases, name+"_ms", time.Since(mark).Milliseconds())
		mark = time.Now()
	}
	defer func() {
		slog.Info("macOS sandbox boot phases", append(phases, "total_ms", time.Since(start).Milliseconds())...)
	}()
	c := t.client(r)
	// A VM from a disk snapshot clones the snapshot, a stopped VM in this
	// store, and keeps its workspace volume.
	source, snapshot := image, protocol.DiskSnapshotInfo{}
	if r.FromDiskSnapshot != "" {
		var err error
		if snapshot, err = t.DiskSnapshot(r.FromDiskSnapshot); err != nil {
			return err
		}
		if snapshot.Template != r.Template || snapshot.WorkspaceGB != r.WorkspaceGB {
			return errors.New("disk snapshot does not match the sandbox's template and workspace")
		}
		source = snapshotVMName(r.FromDiskSnapshot)
		phases = append(phases, "disk_snapshot", r.FromDiskSnapshot)
	}
	if err := t.roomForClone(ctx, c, r.MemoryMB); err != nil {
		return err
	}
	if err := c.Clone(ctx, source, r.VMName()); err != nil {
		return err
	}
	lap("clone")
	if err := c.Set(ctx, r.VMName(), r.VCPUs, r.MemoryMB); err != nil {
		return err
	}
	if err := t.checkDisk(ctx, r); err != nil {
		return err
	}
	if err := c.RegenerateIdentity(ctx, r.VMName()); err != nil {
		return err
	}
	if err := t.writeEnv(c.HomeDir, r); err != nil {
		return err
	}
	// Without the cache the VM boots without a share, and its sessions clone.
	if t.Checkouts != nil {
		if share, err := t.Checkouts.SandboxShare(r.envName()); err == nil {
			r.CheckoutShare = share
		} else {
			slog.Warn("macOS sandbox boots without a checkout share", "vm", r.VMName(), "error", err)
		}
	}
	lap("configure")
	h, err := c.StartWithOptions(ctx, r.VMName(), t.options(r))
	if err != nil {
		return err
	}
	lap("start")
	probes, err := t.waitGuestReady(ctx, r, h)
	lap("guest_ready")
	phases = append(phases, "probes", strings.Join(probes, ","))
	if err != nil {
		return err
	}
	if snapshot.ID != "" {
		err = t.mountWorkspace(ctx, r, snapshot.WorkspaceGB)
	} else {
		// Adding the volume takes 1 to 2 s, so it happens before a claim waits.
		err = t.addWorkspace(ctx, r)
	}
	lap("workspace")
	if err == nil && strings.HasPrefix(r.VMName(), warmVMPrefix) {
		err = t.primeVolumeDelete(ctx, r)
		lap("prime")
	}
	return err
}

// writeEnv writes the env share that boots the image in sandbox mode.
func (t *TartRuntime) writeEnv(home string, r *Record) error {
	env := filepath.Join(home, "env", r.envName())
	if err := os.MkdirAll(env, 0700); err != nil {
		return err
	}
	return os.WriteFile(filepath.Join(env, "tuist.env"), []byte("TUIST_SANDBOX=1\n"), 0600)
}

// primeVolumeDelete adds and deletes a scratch volume while a warm VM waits.
// A guest's first APFS volume delete takes 5 to 11 s and later ones under
// 1 s, so without it a claim of another workspace size paid the first one.
func (t *TartRuntime) primeVolumeDelete(ctx context.Context, r *Record) error {
	_, err := t.client(r).Exec(ctx, r.VMName(), "/bin/sh", "-c", `set -eu
/bin/mkdir -p /private/tmp/tuist-scratch
container=$(/usr/sbin/diskutil info -plist / | /usr/bin/plutil -extract APFSContainerReference raw -o - -)
/usr/bin/sudo -n /usr/sbin/diskutil apfs addVolume "$container" APFS TuistSandboxScratch -mountpoint /private/tmp/tuist-scratch >/dev/null
`+deleteVolumeAt("/private/tmp/tuist-scratch"))
	return err
}

// deleteVolumeAt deletes the volume mounted at a path. It is unmounted
// with umount -f first: Disk Arbitration's unmount waited up to 11 s on a
// newly booted guest, the forced one takes about 40 ms.
func deleteVolumeAt(path string) string {
	return fmt.Sprintf(`volume=$(/usr/sbin/diskutil info -plist %[1]s | /usr/bin/plutil -extract DeviceIdentifier raw -o - -)
/usr/bin/sudo -n /sbin/umount -f %[1]s
/usr/bin/sudo -n /usr/sbin/diskutil apfs deleteVolume "$volume" >/dev/null
`, path)
}

// Claim finishes a booted VM for its sandbox: the workspace quota is the
// sandbox's own, and the status call pins the runtime instance and PID.
func (t *TartRuntime) Claim(ctx context.Context, r *Record) error {
	start := time.Now()
	if r.WorkspaceVolumeGB != r.WorkspaceGB {
		if err := t.addWorkspace(ctx, r); err != nil {
			return err
		}
	}
	workspace := time.Since(start)
	t.selectXcode(ctx, r)
	xcode := time.Since(start) - workspace
	_, err := t.control(ctx, r, "status")
	slog.Info("macOS sandbox claim phases", "sandbox_id", r.SandboxID, "vm", r.VMName(), "workspace_ms", workspace.Milliseconds(), "xcode_ms", xcode.Milliseconds(), "status_ms", (time.Since(start) - workspace - xcode).Milliseconds())
	return err
}

// selectXcode points the guest's `xcode-select` and `/Applications/Xcode.app`
// at the Xcode the sandbox asked for, as a CI runner does at its claim
// (infra/runner-image/select-xcode.sh, about 50 ms). The selection lives on
// the VM's disk, so pauses, snapshots and archives keep it. An image without
// the script, or without that Xcode, keeps its own selection: the sandbox
// still works, so a failure is logged rather than failing the create.
func (t *TartRuntime) selectXcode(ctx context.Context, r *Record) {
	if r.XcodeVersion == "" {
		return
	}
	out, err := t.client(r).Exec(ctx, r.VMName(), "/bin/sh", "-c",
		`[ -x /opt/tuist/select-xcode.sh ] || exit 0; exec /opt/tuist/select-xcode.sh select "$1"`, "sh", r.XcodeVersion)
	if err != nil {
		slog.Warn("macOS sandbox Xcode not selected", "sandbox_id", r.SandboxID, "xcode_version", r.XcodeVersion, "error", err)
		return
	}
	slog.Info("macOS sandbox Xcode selected", "sandbox_id", r.SandboxID, "xcode_version", r.XcodeVersion, "output", strings.TrimSpace(string(out)))
}

// addWorkspace mounts a volume with the sandbox's quota at the workspace.
// APFS cannot change an existing volume's quota, so a VM that already has a
// volume of another size replaces it. Spotlight is off on the volume, as on
// the image's root, so it does not index the sandbox's work. `mdutil` fails
// with -407 ("unable to perform operation") while `mds` is not yet serving,
// as on a VM booted moments before, and that failed sandbox creates
// (2026-11). On a guest whose `mds` was restarted, the failed call took
// about 5 s and disabled indexing anyway: every later `-i off` failed with
// -403 and reported "Indexing and searching disabled". So a failed call
// counts once the volume reports indexing disabled, and is retried for up
// to about a minute until then.
func (t *TartRuntime) addWorkspace(ctx context.Context, r *Record) error {
	replace := ""
	if r.WorkspaceVolumeGB != 0 {
		replace = deleteVolumeAt("/Users/runner/work")
	}
	// The image's sandbox boot mode disables runner dispatch before its halt
	// trap is armed. No runner service-account credential is shared with it.
	// diskutil and mdutil report errors on stdout, of which a failed Exec
	// keeps only the tail, so the script sends everything to stderr and
	// traces each command: a failed create then says which step failed and why.
	if _, err := t.client(r).Exec(ctx, r.VMName(), "/bin/sh", "-c", fmt.Sprintf(`set -eux
exec 1>&2
%scontainer=$(/usr/sbin/diskutil info -plist / | /usr/bin/plutil -extract APFSContainerReference raw -o - -)
/usr/bin/sudo -n /usr/sbin/diskutil apfs addVolume "$container" APFS TuistSandboxWorkspace -quota %dg -mountpoint /Users/runner/work
/usr/bin/sudo -n /usr/bin/touch /Users/runner/work/.metadata_never_index
i=0
until /usr/bin/sudo -n /usr/bin/mdutil -i off /Users/runner/work; do
  /usr/bin/sudo -n /usr/bin/mdutil -s /Users/runner/work | /usr/bin/grep -q disabled && break
  i=$((i + 1)); [ "$i" -lt 10 ]; sleep 1
done
/usr/bin/sudo -n /usr/sbin/chown runner:staff /Users/runner/work`, replace, r.WorkspaceGB)); err != nil {
		return err
	}
	r.WorkspaceVolumeGB = r.WorkspaceGB
	return nil
}

func (t *TartRuntime) Resume(ctx context.Context, r *Record) error {
	r.DisksSynced = false
	if r.Resident {
		start := time.Now()
		if _, err := t.control(ctx, r, "resume"); err != nil {
			return err
		}
		resumed := time.Since(start)
		_, err := t.guest(ctx, r, map[string]string{"op": "ping"}, nil)
		slog.Info("macOS sandbox resident resume phases", "sandbox_id", r.SandboxID, "resume_ms", resumed.Milliseconds(), "ping_ms", (time.Since(start) - resumed).Milliseconds())
		return err
	}
	// Each phase is timed so a slow restore can be attributed: Apple's restore
	// alone is about 3 s at 8 GiB, and the rest is this path's own overhead.
	start, mark := time.Now(), time.Now()
	phases := []any{"sandbox_id", r.SandboxID, "memory_mb", r.MemoryMB}
	lap := func(name string) {
		phases = append(phases, name+"_ms", time.Since(mark).Milliseconds())
		mark = time.Now()
	}
	defer func() {
		slog.Info("macOS sandbox restore phases", append(phases, "total_ms", time.Since(start).Milliseconds())...)
	}()
	if err := t.checkDisk(ctx, r); err != nil {
		return err
	}
	lap("disk_check")
	c := t.client(r)
	r.Instance = ""
	r.PID = 0
	// A restore needs every share it was saved with.
	if r.CheckoutShare != "" {
		if err := os.MkdirAll(r.CheckoutShare, 0o777); err != nil {
			return err
		}
	}
	h, err := c.Resume(ctx, r.VMName(), t.options(r))
	if err != nil {
		return err
	}
	lap("start")
	probes, err := t.waitGuestReady(ctx, r, h)
	lap("guest_ready")
	phases = append(phases, "probes", strings.Join(probes, ","))
	if err != nil {
		return err
	}
	_, err = t.control(ctx, r, "status")
	lap("status")
	return err
}

// After checkpoint restoration, the guest can execute built-in commands before
// the shared bridge executable is usable. Readiness must exercise the same path
// as the first user command, while retaining the VM's capacity reservation.
//
// The runtime answers its control channel only once Apple's restore (or boot)
// has returned, so guest commands wait for that first: a `tart exec` started
// earlier only fails. The first command after a restore can take over a
// second, so a probe gets a budget that does not kill and restart it.
// The returned trace lists each probe's step, outcome and duration.
func (t *TartRuntime) waitGuestReady(ctx context.Context, r *Record, h *tart.RunHandle) ([]string, error) {
	var trace []string
	running := false
	err := h.WaitReady(ctx, 5*time.Second, func(ctx context.Context) error {
		start := time.Now()
		step := "ping"
		err := func() error {
			if !running {
				step = "status"
				if _, err := t.control(ctx, r, "status"); err != nil {
					return err
				}
				running = true
				trace = append(trace, fmt.Sprintf("status:ok:%d", time.Since(start).Milliseconds()))
				start, step = time.Now(), "ping"
			}
			reply, err := t.guest(ctx, r, map[string]string{"op": "ping"}, nil)
			if err == nil && reply.Type != "pong" {
				return errors.New("guest readiness returned no pong")
			}
			return err
		}()
		outcome := "ok"
		if errors.Is(err, context.DeadlineExceeded) {
			outcome = "timeout"
		} else if err != nil {
			outcome = "error"
		}
		trace = append(trace, fmt.Sprintf("%s:%s:%d", step, outcome, time.Since(start).Milliseconds()))
		return err
	})
	return trace, err
}

func (t *TartRuntime) Pause(ctx context.Context, r *Record) error {
	if busy, err := t.Busy(ctx, r); err != nil {
		return err
	} else if busy {
		return errors.New("sandbox has active guest work")
	}
	t.syncGuest(ctx, r)
	_, err := t.control(ctx, r, "pause")
	return err
}

// guestShutdownTimeout bounds a clean guest shutdown; save_disks has two
// minutes in all, and the clone after it takes seconds.
const guestShutdownTimeout = 75 * time.Second

// Shutdown shuts a resident paused VM's guest down from inside, which ends
// its processes and unmounts its file systems, and waits for the VM process
// to exit. It never forces the VM off: a forced stop leaves the disks as a
// crash would, so a guest that does not stop in time fails the shutdown and
// the caller saves nothing. The resume drops any stale checkpoint first.
func (t *TartRuntime) Shutdown(ctx context.Context, r *Record) error {
	if _, err := t.control(ctx, r, "resume"); err != nil {
		return err
	}
	ctx, cancel := context.WithTimeout(ctx, guestShutdownTimeout)
	defer cancel()
	c := t.client(r)
	// The guest agent usually goes away before it answers, so the command's
	// own result says nothing; the VM process exiting is the proof.
	execCtx, cancelExec := context.WithTimeout(ctx, 15*time.Second)
	_, execErr := c.Exec(execCtx, r.VMName(), "/usr/bin/sudo", "-n", "/sbin/shutdown", "-h", "now")
	cancelExec()
	for {
		running, err := c.IsRunning(ctx, r.VMName())
		if err == nil && !running {
			r.DisksSynced = true
			return nil
		}
		select {
		case <-ctx.Done():
			return errors.Join(errors.New("guest did not shut down"), execErr, err)
		case <-time.After(250 * time.Millisecond):
		}
	}
}

// syncGuest flushes the guest's file systems to its disk before the VM stops
// running, and records whether that worked: what the guest wrote but did
// not flush lives only in its memory, which an archive cannot carry.
func (t *TartRuntime) syncGuest(ctx context.Context, r *Record) {
	ctx, cancel := context.WithTimeout(ctx, 30*time.Second)
	defer cancel()
	_, err := t.client(r).Exec(ctx, r.VMName(), "/bin/sync")
	r.DisksSynced = err == nil
	if err != nil {
		slog.Warn("macOS sandbox pauses without flushing its disks", "sandbox_id", r.SandboxID, "error", err)
	}
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
		t.syncGuest(ctx, r)
	}

	if _, err := t.control(ctx, r, "pause"); err != nil {
		return err
	}
	if _, err := t.control(ctx, r, "save"); err != nil {
		return err
	}
	if err := t.fence(ctx, r); err != nil {
		return err
	}
	logStoredBytes(t.directory(r), r.SandboxID)
	return nil
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
	if err := os.RemoveAll(filepath.Join(c.HomeDir, "env", r.envName())); err != nil {
		return err
	}
	if t.Checkouts != nil {
		// The VM is gone, so the session's export can be taken.
		if r.Checkout != nil && r.CheckoutShare != "" {
			t.Checkouts.CollectSandbox(*r.Checkout, r.CheckoutShare)
		}
		if err := t.Checkouts.RemoveSandboxShare(r.envName()); err != nil {
			return err
		}
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
	if r.Operation == "create" || r.Operation == "claim" {
		return errors.New("creation did not finish; delete the incomplete environment before retrying")
	}
	if r.Operation == "delete" {
		return errors.New("deletion must be retried")
	}
	if vm == nil {
		return fmt.Errorf("sandbox VM is missing; %w", ErrVMLost)
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
		return fmt.Errorf("sandbox process lost without a checkpoint; %w", ErrVMLost)
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
	// CPUPermille answers the cpu op: recent CPU use of the sandbox user's
	// processes, in thousandths of one core.
	CPUPermille int64 `json:"cpu_permille"`
}

// guestBridge runs the bridge from a root-owned copy on the guest's disk.
// After a suspended VM resumes, the guest can still read the VirtioFS share
// but `runner` can no longer execute from it (EPERM), so the share only
// delivers the tools: a copy that differs from the share is replaced.
const guestBridge = `set -eu
s="/Volumes/My Shared Files/sandbox-tools"
l=/usr/local/libexec/tuist-sandbox
if ! /usr/bin/cmp -s "$s/sbx-macos" "$l/sbx-macos"; then
	/usr/bin/sudo -n /bin/sh -c 'set -eu; /bin/mkdir -p "$2"; for f in sbx-macos sbx-worker; do /bin/cp -X "$1/$f" "$2/.$f.$$"; /bin/chmod 0755 "$2/.$f.$$"; /bin/mv -f "$2/.$f.$$" "$2/$f"; done' sh "$s" "$l"
fi
exec /usr/bin/sudo -n -H -u runner /usr/bin/env PATH=/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin "$l/sbx-macos"`

func (t *TartRuntime) guest(ctx context.Context, r *Record, request any, out func(protocol.Stream)) (guestReply, error) {
	var result guestReply
	data, err := json.Marshal(request)
	if err != nil {
		return result, err
	}
	c := t.client(r)
	cmd := exec.CommandContext(ctx, c.Binary, "exec", "-i", r.VMName(), "/bin/sh", "-c", guestBridge)
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

func (t *TartRuntime) GuestCPU(ctx context.Context, r *Record) (int64, error) {
	result, err := t.guest(ctx, r, map[string]string{"op": "cpu"}, nil)
	if err == nil && result.Type != "cpu" {
		err = errors.New("invalid cpu response")
	}
	return result.CPUPermille, err
}

func (t *TartRuntime) Busy(ctx context.Context, r *Record) (bool, error) {
	result, err := t.guest(ctx, r, map[string]string{"op": "busy"}, nil)
	if err == nil && result.Type != "busy" {
		err = errors.New("invalid busy response")
	}
	return result.Running, err
}
