package cachevolumes

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strings"
	"time"
)

// RBD uses one image per job. Only a sealed, protected snapshot is a parent.
// Ceph credentials and block devices remain in this trusted host agent.
type RBD struct {
	Pool, Namespace, Client string
	SizeGB                  int
	Run                     func(context.Context, string, ...string) ([]byte, error)
	Mount                   func(string, string) error
	Unmount                 func(string, string) error
	MeasureFS               func(string) (int64, int64, error)
}

func (r *RBD) command(name string, args ...string) ([]byte, error) {
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Minute)
	defer cancel()
	run := r.Run
	if run == nil {
		run = func(ctx context.Context, name string, args ...string) ([]byte, error) {
			return exec.CommandContext(ctx, name, args...).CombinedOutput()
		}
	}
	out, err := run(ctx, name, args...)
	// Do not return command output: Ceph errors may include infrastructure details.
	if err != nil {
		return nil, fmt.Errorf("%s operation failed: %w", name, err)
	}
	return out, nil
}
func (r *RBD) rbd(args ...string) ([]byte, error) {
	prefix := []string{"--pool", r.Pool, "--namespace", r.Namespace, "--id", r.Client}
	return r.command("rbd", append(prefix, args...)...)
}

// Probe checks that the configured namespace can be reached before scheduling.
func (r *RBD) Probe() error {
	_, err := r.exists("tuist-probe")
	return err
}
func imageName(slot Slot) string { return "tuist-" + slot.ID }
func (r *RBD) exists(name string) (bool, error) {
	out, err := r.rbd("ls", "--format", "json")
	if err != nil {
		return false, err
	}
	var names []string
	if err = json.Unmarshal(out, &names); err != nil {
		return false, err
	}
	for _, n := range names {
		if n == name {
			return true, nil
		}
	}
	return false, nil
}
func (r *RBD) device(name string) (string, error) {
	out, err := r.rbd("device", "list", "--format", "json")
	if err != nil {
		return "", err
	}
	var mappings []struct {
		Pool      string `json:"pool"`
		Namespace string `json:"namespace"`
		Name      string `json:"name"`
		Device    string `json:"device"`
	}
	if err = json.Unmarshal(out, &mappings); err != nil {
		return "", err
	}
	for _, mapping := range mappings {
		if mapping.Pool == r.Pool && mapping.Namespace == r.Namespace && mapping.Name == name {
			if !regexp.MustCompile(`^/dev/rbd[0-9]+$`).MatchString(mapping.Device) {
				return "", errors.New("invalid mapped device")
			}
			return mapping.Device, nil
		}
	}
	return "", nil
}
func (r *RBD) Attach(slot Slot, path string) error {
	name := imageName(slot)
	exists, err := r.exists(name)
	if err != nil {
		return err
	}
	if !exists {
		if slot.ParentID != "" {
			_, err = r.rbd("clone", r.Pool+"/"+r.Namespace+"/tuist-"+slot.ParentID+"@cache", r.Pool+"/"+r.Namespace+"/"+name)
		} else {
			// RBD size units are binary; round decimal GB up to the next MiB.
			_, err = r.rbd("create", name, "--size", fmt.Sprintf("%dM", (int64(r.SizeGB)*1_000_000_000+(1<<20)-1)/(1<<20)), "--image-feature", "layering,exclusive-lock,object-map,fast-diff,deep-flatten")
		}
		if err != nil {
			return err
		}
	}
	device, err := r.device(name)
	if err != nil {
		return err
	}
	if device == "" {
		out, err := r.rbd("device", "map", name)
		if err != nil {
			return err
		}
		device = strings.TrimSpace(string(out))
		if !regexp.MustCompile(`^/dev/rbd[0-9]+$`).MatchString(device) {
			return errors.New("invalid mapped device")
		}
	}
	if slot.ParentID == "" {
		// The metadata bit is persisted before exposure. A crash before this bit can
		// only reformat an unexposed image, never a filesystem a job has written to.
		out, err := r.rbd("image-meta", "list", name, "--format", "json")
		if err != nil {
			return err
		}
		var metadata map[string]string
		if len(strings.TrimSpace(string(out))) > 0 {
			if err = json.Unmarshal(out, &metadata); err != nil {
				return err
			}
		}
		if metadata["tuist.formatted"] != "true" {
			if _, err = r.command("mkfs.ext4", "-F", "-m", "0", device); err != nil {
				return err
			}
			if _, err = r.rbd("image-meta", "set", name, "tuist.formatted", "true"); err != nil {
				return err
			}
		}
	}
	if err = r.Mount(device, path); err != nil {
		return err
	}
	// The mounted volume is private to this job. All execution UIDs get separate
	// identities; the action creates its data directory with its own ownership.
	root, err := os.OpenRoot(path)
	if err != nil {
		return err
	}
	defer root.Close()
	if err := root.Remove(".tuist-volume"); err != nil && !os.IsNotExist(err) {
		return err
	}
	marker, err := root.OpenFile(".tuist-volume", os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0644)
	if err != nil {
		return err
	}
	_, err = marker.WriteString(slot.ID)
	closeErr := marker.Close()
	if err != nil {
		return err
	}
	return closeErr
}
func (r *RBD) Measure(_ Slot, path string) (int64, int64, error) { return r.MeasureFS(path) }
func (r *RBD) detach(slot Slot, path string) error {
	device, err := r.device(imageName(slot))
	if err != nil {
		return err
	}
	if device != "" {
		if err = r.Unmount(device, path); err != nil {
			return err
		}
		_, err = r.rbd("device", "unmap", device)
	}
	return err
}
func (r *RBD) snapshots(name string) ([]struct {
	Name      string `json:"name"`
	Protected string `json:"protected"`
}, error) {
	out, err := r.rbd("snap", "ls", name, "--format", "json")
	if err != nil {
		return nil, err
	}
	var snapshots []struct {
		Name      string `json:"name"`
		Protected string `json:"protected"`
	}
	err = json.Unmarshal(out, &snapshots)
	return snapshots, err
}
func (r *RBD) Seal(slot Slot, path string) error {
	if err := r.detach(slot, path); err != nil {
		return err
	}
	name := imageName(slot)
	out, err := r.rbd("info", name, "--format", "json")
	if err != nil {
		return err
	}
	var info struct {
		Parent json.RawMessage `json:"parent"`
	}
	if err = json.Unmarshal(out, &info); err != nil {
		return err
	}
	// Flatten after job teardown, away from the attachment path. This bounds
	// clone ancestry and lets old parents be reclaimed after all readers finish.
	if len(info.Parent) > 0 && string(info.Parent) != "null" {
		if _, err = r.rbd("flatten", name); err != nil {
			return err
		}
	}
	snapshots, err := r.snapshots(name)
	if err != nil {
		return err
	}
	found, protected := false, false
	for _, snap := range snapshots {
		if snap.Name == "cache" {
			found = true
			protected = snap.Protected == "true"
		}
	}
	if !found {
		if _, err = r.rbd("snap", "create", name+"@cache"); err != nil {
			return err
		}
	}
	if !protected {
		_, err = r.rbd("snap", "protect", name+"@cache")
	}
	return err
}
func (r *RBD) Delete(slot Slot, path string) error {
	if err := r.detach(slot, path); err != nil {
		return err
	}
	name := imageName(slot)
	exists, err := r.exists(name)
	if err != nil {
		return err
	}
	if !exists {
		return removeMountpoint(path)
	}
	snapshots, err := r.snapshots(name)
	if err != nil {
		return err
	}
	for _, snap := range snapshots {
		if snap.Name != "cache" {
			return errors.New("unexpected snapshot")
		}
		if snap.Protected == "true" {
			if _, err = r.rbd("snap", "unprotect", name+"@cache"); err != nil {
				return err
			}
		}
		if _, err = r.rbd("snap", "rm", name+"@cache"); err != nil {
			return err
		}
	}
	if _, err = r.rbd("rm", name); err != nil {
		return err
	}
	return removeMountpoint(path)
}
func removeMountpoint(path string) error {
	// Writers are fenced; remove only the mountpoint and empty pod directory.
	if err := os.Remove(path); err != nil && !os.IsNotExist(err) {
		return err
	}
	_ = os.Remove(filepath.Dir(path))
	return nil
}
