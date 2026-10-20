package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"golang.org/x/sys/unix"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"slices"
	"strconv"
	"strings"
	"time"
)

const macShare = "/Volumes/My Shared Files/custom-cache"
const macMountRoot = "/Users/runner/.tuist-custom-cache"

var reasonPattern = regexp.MustCompile(`^[a-z_]{1,32}$`)

type macResponse struct {
	Directory string `json:"directory"`
	ID        string `json:"id"`
	Warm      bool   `json:"warm"`
	Error     string `json:"error"`
	Reason    string `json:"reason"`
}

func macUnavailable(reason string) error {
	switch reason {
	case "timeout":
		return errors.New("the saved volume is still downloading to this runner host; later jobs on this host will use it")
	case "capacity":
		return errors.New("this runner host has no room for the volume right now")
	case "denied":
		return errors.New("the Tuist server did not authorize a volume for this job")
	case "execution_pending":
		return errExecutionPending
	default:
		return errors.New("cache unavailable")
	}
}

func acquireMac(key string) (string, string, bool, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	return acquireMacAt(ctx, key, macShare, macMountRoot, func(args ...string) error { return macCommandContext(ctx, args...) })
}
func macCommandContext(ctx context.Context, args ...string) error {
	ctx, cancel := context.WithTimeout(ctx, 2*time.Minute)
	defer cancel()
	command := exec.CommandContext(ctx, "hdiutil", args...)
	// The image helper must survive job cleanup until dispatch performs a clean detach.
	command.Env = slices.DeleteFunc(command.Environ(), func(variable string) bool {
		return strings.HasPrefix(variable, "RUNNER_TRACKING_ID=")
	})
	if out, err := command.CombinedOutput(); err != nil {
		return fmt.Errorf("hdiutil: %w (%s)", err, out)
	}
	return nil
}
func acquireMacAt(ctx context.Context, key, share, mountRoot string, command func(...string) error) (string, string, bool, error) {
	response, err := exchangeMac(ctx, share, map[string]any{"key": key, "uid": os.Getuid()})
	if err != nil {
		return "", "", false, err
	}
	if response.Error != "" || !directoryPattern.MatchString(response.Directory) || response.ID == "" {
		return "", "", false, macUnavailable(response.Reason)
	}
	base := filepath.Join(mountRoot, response.Directory)
	shared := filepath.Join(share, response.Directory)
	if proof, err := os.ReadFile(filepath.Join(base, ".tuist-volume")); err == nil && string(proof) == response.ID {
		return response.Directory, response.ID, response.Warm, nil
	}
	if err = os.MkdirAll(base, 0755); err != nil {
		return "", "", false, err
	}
	if err = os.Remove(filepath.Join(shared, ".detached")); err != nil && !os.IsNotExist(err) {
		return "", "", false, err
	}
	if err = command("attach", filepath.Join(shared, "cache.sparseimage"), "-owners", "off", "-nobrowse", "-quiet", "-mountpoint", base); err != nil {
		return "", "", false, err
	}
	if err = os.WriteFile(filepath.Join(base, ".tuist-volume"), []byte(response.ID), 0644); err != nil {
		return "", "", false, err
	}
	// Without a baseline the volume reports itself changed, so it is still saved.
	_ = os.Remove(baselinePath(mountRoot, response.Directory))
	if names, err := topLevelEntries(base); err == nil {
		_ = os.WriteFile(baselinePath(mountRoot, response.Directory), []byte(names), 0644)
	}
	if err = os.WriteFile(filepath.Join(shared, ".mounted"), []byte(response.ID), 0644); err != nil {
		return "", "", false, err
	}
	return response.Directory, response.ID, response.Warm, nil
}

// Only clean detach marks a branch eligible. A force-detach, failed job,
// cancellation or abrupt VM shutdown leaves it disposable.
func detachMac() error {
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	return detachMacAt(macShare, macMountRoot, func(args ...string) error { return macCommandContext(ctx, args...) }, measureMac, func(base string, kill bool) { releaseMac(ctx, base, kill) }, func() {
		select {
		case <-ctx.Done():
		case <-time.After(time.Second):
		}
	})
}
func measureMac(path string) (int64, int64, error) {
	var stat unix.Statfs_t
	if err := unix.Statfs(path, &stat); err != nil {
		return 0, 0, err
	}
	return int64(stat.Blocks-stat.Bfree) * int64(stat.Bsize), int64(stat.Blocks) * int64(stat.Bsize), nil
}

type macHolder struct {
	pid     int
	command string
}

// releaseMac ends this user's processes that still have files open on the
// volume mounted at base, so the next plain detach can succeed. Launch agents
// started during the job outlive the runner's own process cleanup, and a tool
// installed onto a volume runs from it. Ending them never permits publication
// by itself: only the clean detach that follows does.
func releaseMac(ctx context.Context, base string, kill bool) {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	// Naming the mount point lists every open file on that filesystem.
	out, _ := exec.CommandContext(ctx, "lsof", "-n", "-w", "-F", "pc", "--", base).Output()
	signal, verb := unix.SIGTERM, "terminating"
	if kill {
		signal, verb = unix.SIGKILL, "killing"
	}
	var names []string
	for _, holder := range parseMacHolders(out) {
		if holder.pid == os.Getpid() || holder.pid == os.Getppid() {
			continue
		}
		names = append(names, fmt.Sprintf("%s (pid %d)", holder.command, holder.pid))
		_ = unix.Kill(holder.pid, signal)
	}
	if len(names) == 0 {
		fmt.Fprintf(os.Stderr, "tuist-cache-volume: %s is busy; no process of this user holds it\n", filepath.Base(base))
		return
	}
	fmt.Fprintf(os.Stderr, "tuist-cache-volume: %s is busy; %s %s\n", filepath.Base(base), verb, strings.Join(names, ", "))
}
func parseMacHolders(out []byte) []macHolder {
	var holders []macHolder
	for _, line := range strings.Split(string(out), "\n") {
		if len(line) < 2 {
			continue
		}
		switch line[0] {
		case 'p':
			pid, err := strconv.Atoi(line[1:])
			if err != nil {
				continue
			}
			holders = append(holders, macHolder{pid: pid})
		case 'c':
			if len(holders) > 0 {
				holders[len(holders)-1].command = line[1:]
			}
		}
	}
	return holders
}
func detachMacAt(share, mountRoot string, command func(...string) error, measure func(string) (int64, int64, error), release func(string, bool), pause func()) error {
	dirs, err := os.ReadDir(mountRoot)
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	var failures []error
	for _, dir := range dirs {
		if !directoryPattern.MatchString(dir.Name()) {
			continue
		}
		base := filepath.Join(mountRoot, dir.Name())
		id, err := os.ReadFile(filepath.Join(base, ".tuist-volume"))
		if err != nil {
			failures = append(failures, err)
			continue
		}
		baseline, _ := os.ReadFile(baselinePath(mountRoot, dir.Name()))
		var used, capacity int64
		var changed bool
		for attempt := 0; attempt < 5; attempt++ {
			used, capacity, err = measure(base)
			if err != nil {
				break
			}
			changed = changed || changedSinceMount(base, baseline)
			err = command("detach", base, "-quiet")
			if err == nil {
				break
			}
			if attempt < 4 {
				release(base, attempt > 0)
				pause()
			}
		}
		if err != nil {
			failures = append(failures, err)
			continue
		}
		usage, _ := json.Marshal(map[string]any{"id": string(id), "used_bytes": used, "capacity_bytes": capacity, "changed": changed})
		if err = os.WriteFile(filepath.Join(share, dir.Name(), ".usage"), usage, 0644); err != nil {
			failures = append(failures, err)
			continue
		}
		if err = os.WriteFile(filepath.Join(share, dir.Name(), ".detached"), id, 0644); err != nil {
			failures = append(failures, err)
			continue
		}
		_ = os.Remove(baselinePath(mountRoot, dir.Name()))
	}
	return errors.Join(failures...)
}

func attachMac(key string, targets []string, root string) error {
	if err := validateMacTargets(targets); err != nil {
		return err
	}
	return attachUsing(key, targets, root, func() (string, string, bool, error) { return acquireMac(key) }, func(_ string, source, target string) error { return linkMacDirectory(root, source, target) })
}
func validateMacTargets(targets []string) error {
	for _, target := range targets {
		for _, part := range strings.Split(filepath.Clean(target), string(filepath.Separator)) {
			if part == "node_modules" {
				return fmt.Errorf("%w: macOS cache paths use symlinks; cache the package download directory (for example ~/.npm) instead of node_modules", errInvalidPath)
			}
		}
	}
	return nil
}
func linkMacDirectory(root, source, target string) error {
	if err := emptyTarget(target); err != nil {
		return err
	}
	if err := os.Remove(target); err != nil && !os.IsNotExist(err) {
		return err
	}
	return os.Symlink(filepath.Join(root, source), target)
}

// exchangeMac writes one request into the host mailbox and waits for its answer.
func exchangeMac(ctx context.Context, share string, request map[string]any) (macResponse, error) {
	var response macResponse
	if _, err := os.Stat(share); err != nil {
		return response, err
	}
	data, _ := json.Marshal(request)
	temp, err := os.CreateTemp(share, ".request-")
	if err != nil {
		return response, err
	}
	name := filepath.Base(temp.Name()) + ".request"
	defer os.Remove(temp.Name())
	defer os.Remove(filepath.Join(share, name+".response"))
	defer os.Remove(filepath.Join(share, name))
	_, err = temp.Write(data)
	temp.Close()
	if err != nil {
		os.Remove(temp.Name())
		return response, err
	}
	if err = os.Rename(temp.Name(), filepath.Join(share, name)); err != nil {
		return response, err
	}
	for {
		data, err = os.ReadFile(filepath.Join(share, name+".response"))
		if err == nil && json.Unmarshal(data, &response) == nil {
			break
		}
		select {
		case <-ctx.Done():
			return response, ctx.Err()
		case <-time.After(250 * time.Millisecond):
		}
	}
	return response, ctx.Err()
}

// checkoutMac mounts the job's cached checkout at its workspace before the first
// step. Every failure leaves the workspace untouched, so actions/checkout clones
// exactly as it does without a cached checkout.
func checkoutMac(workspace string) string {
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	return checkoutMacAt(ctx, workspace, macShare, checkoutStatePath, func(args ...string) error { return macCommandContext(ctx, args...) })
}

func checkoutMacAt(ctx context.Context, workspace, share, statePath string, command func(...string) error) string {
	if !filepath.IsAbs(workspace) || filepath.Clean(workspace) != workspace {
		return "skipped (workspace is not an absolute path)"
	}
	if err := emptyTarget(workspace); err != nil {
		return "skipped (workspace is not empty)"
	}
	response, err := exchangeMac(ctx, share, map[string]any{"checkout": true, "uid": os.Getuid()})
	if err != nil {
		return "unavailable (timeout)"
	}
	if response.Error != "" || !directoryPattern.MatchString(response.Directory) || response.ID == "" {
		reason := response.Reason
		if !reasonPattern.MatchString(reason) {
			reason = "error"
		}
		// These answers come with a grant: the host builds from what this job exports.
		if reason == "cold" || reason == "capacity" || reason == "timeout" {
			_ = recordCheckout(statePath, workspace, false)
		}
		return "unavailable (" + reason + ")"
	}
	if err := os.MkdirAll(workspace, 0755); err != nil {
		return "unavailable (workspace)"
	}
	shared := filepath.Join(share, response.Directory)
	if err := command("attach", filepath.Join(shared, "cache.sparseimage"), "-owners", "off", "-nobrowse", "-quiet", "-mountpoint", workspace); err != nil {
		return "unavailable (attach)"
	}
	_ = recordCheckout(statePath, workspace, true)
	// Mounted proves to the host that the guest holds the branch; nothing is
	// written into the workspace itself.
	if err := os.WriteFile(filepath.Join(shared, ".mounted"), []byte(response.ID), 0644); err != nil {
		return "reused (unreported)"
	}
	return "reused"
}

// baselinePath records a mounted volume's top-level entries outside the volume.
func baselinePath(mountRoot, dir string) string {
	return filepath.Join(mountRoot, "."+dir+".inventory")
}

// topLevelEntries lists the volume root. Entries that start with a dot belong
// to Tuist or macOS, which creates some of them lazily.
func topLevelEntries(base string) (string, error) {
	entries, err := os.ReadDir(base)
	if err != nil {
		return "", err
	}
	var names []string
	for _, entry := range entries {
		if !strings.HasPrefix(entry.Name(), ".") {
			names = append(names, entry.Name())
		}
	}
	return strings.Join(names, "\n"), nil
}

var errChangedSinceMount = errors.New("changed since mount")

// changedSinceMount reports whether anything in the volume changed after it was
// mounted. Writing, renaming, deleting or changing the metadata of an entry
// updates its ctime or its parent's, which no tool can set back, so the walk
// stops at the first entry newer than `.tuist-volume`, written at mount.
func changedSinceMount(base string, baseline []byte) bool {
	var mounted unix.Stat_t
	if len(baseline) == 0 || unix.Lstat(filepath.Join(base, ".tuist-volume"), &mounted) != nil {
		return true
	}
	if names, err := topLevelEntries(base); err != nil || names != string(baseline) {
		return true
	}
	return filepath.WalkDir(base, func(path string, entry fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if path == base {
			return nil
		}
		if filepath.Dir(path) == base && strings.HasPrefix(entry.Name(), ".") {
			if entry.IsDir() {
				return filepath.SkipDir
			}
			return nil
		}
		var stat unix.Stat_t
		if err := unix.Lstat(path, &stat); err != nil {
			return err
		}
		if stat.Ctim.Nano() > mounted.Ctim.Nano() {
			return errChangedSinceMount
		}
		return nil
	}) != nil
}
