package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"golang.org/x/sys/unix"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

const macShare = "/Volumes/My Shared Files/custom-cache"
const macMountRoot = "/Users/runner/.tuist-custom-cache"

type macResponse struct {
	Directory string `json:"directory"`
	ID        string `json:"id"`
	Warm      bool   `json:"warm"`
	Error     string `json:"error"`
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
	if _, err := os.Stat(share); err != nil {
		return "", "", false, err
	}
	data, _ := json.Marshal(map[string]any{"key": key, "uid": os.Getuid()})
	temp, err := os.CreateTemp(share, ".request-")
	if err != nil {
		return "", "", false, err
	}
	name := filepath.Base(temp.Name()) + ".request"
	defer os.Remove(temp.Name())
	defer os.Remove(filepath.Join(share, name+".response"))
	defer os.Remove(filepath.Join(share, name))
	_, err = temp.Write(data)
	temp.Close()
	if err != nil {
		os.Remove(temp.Name())
		return "", "", false, err
	}
	if err = os.Rename(temp.Name(), filepath.Join(share, name)); err != nil {
		return "", "", false, err
	}
	var response macResponse
	for {
		data, err = os.ReadFile(filepath.Join(share, name+".response"))
		if err == nil && json.Unmarshal(data, &response) == nil {
			break
		}
		select {
		case <-ctx.Done():
			return "", "", false, ctx.Err()
		case <-time.After(250 * time.Millisecond):
		}
	}
	if err := ctx.Err(); err != nil {
		return "", "", false, err
	}
	if response.Error != "" || !directoryPattern.MatchString(response.Directory) || response.ID == "" {
		return "", "", false, errors.New("cache unavailable")
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
	return detachMacAt(macShare, macMountRoot, func(args ...string) error { return macCommandContext(ctx, args...) }, measureMac, func() {
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
func detachMacAt(share, mountRoot string, command func(...string) error, measure func(string) (int64, int64, error), pause func()) error {
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
		var used, capacity int64
		for attempt := 0; attempt < 5; attempt++ {
			used, capacity, err = measure(base)
			if err != nil {
				break
			}
			err = command("detach", base, "-quiet")
			if err == nil {
				break
			}
			if attempt < 4 {
				pause()
			}
		}
		if err != nil {
			failures = append(failures, err)
			continue
		}
		usage, _ := json.Marshal(map[string]any{"id": string(id), "used_bytes": used, "capacity_bytes": capacity})
		if err = os.WriteFile(filepath.Join(share, dir.Name(), ".usage"), usage, 0644); err != nil {
			failures = append(failures, err)
			continue
		}
		if err = os.WriteFile(filepath.Join(share, dir.Name(), ".detached"), id, 0644); err != nil {
			failures = append(failures, err)
		}
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
