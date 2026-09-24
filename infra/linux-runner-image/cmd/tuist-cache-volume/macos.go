package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
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
	return acquireMacAt(key, macShare, macMountRoot, macCommand)
}
func macCommand(args ...string) error {
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Minute)
	defer cancel()
	if out, err := exec.CommandContext(ctx, "hdiutil", args...).CombinedOutput(); err != nil {
		return fmt.Errorf("hdiutil: %w (%s)", err, out)
	}
	return nil
}
func acquireMacAt(key, share, mountRoot string, command func(...string) error) (string, string, bool, error) {
	if _, err := os.Stat(share); err != nil {
		return "", "", false, err
	}
	name := digest(key) + ".request"
	data, _ := json.Marshal(map[string]any{"key": key, "uid": os.Getuid()})
	temp, err := os.CreateTemp(share, ".request-")
	if err != nil {
		return "", "", false, err
	}
	_, err = temp.Write(data)
	temp.Close()
	if err != nil {
		os.Remove(temp.Name())
		return "", "", false, err
	}
	if err = os.Rename(temp.Name(), filepath.Join(share, name)); err != nil {
		return "", "", false, err
	}
	deadline := time.Now().Add(6 * time.Minute)
	var response macResponse
	for {
		data, err = os.ReadFile(filepath.Join(share, name+".response"))
		if err == nil && json.Unmarshal(data, &response) == nil {
			break
		}
		if time.Now().After(deadline) {
			return "", "", false, errors.New("cache attachment timed out")
		}
		time.Sleep(250 * time.Millisecond)
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
func detachMac() error { return detachMacAt(macShare, macMountRoot, macCommand) }
func detachMacAt(share, mountRoot string, command func(...string) error) error {
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
		if err = command("detach", base, "-quiet"); err != nil {
			failures = append(failures, err)
			continue
		}
		if err = os.WriteFile(filepath.Join(share, dir.Name(), ".detached"), id, 0644); err != nil {
			failures = append(failures, err)
		}
	}
	return errors.Join(failures...)
}
