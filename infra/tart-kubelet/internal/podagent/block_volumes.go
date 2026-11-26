package podagent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
)

// USBDisks hot-plugs custom cache volumes kept as ASIF images
// (cachevolumes.FormatASIF) into running VMs as USB disks, through Tart's
// `run --usb-disk-requests` (infra/tart-build). macOS 27 guests lose writes to
// a disk image whose file is on their virtio-fs share, so these volumes never
// go through it. Everything else, admission, eviction, publication and
// restores on other hosts, is the shared custom-volume Store's.
//
// All state is in host-only files under Root, so a restart neither loses a
// release nor trusts the guest: requests/<pod UID>/<use>.use names the use's
// share directory, Tart answers <use>.attached and, after the detach this
// asks for once the guest's clean detach marker names the use, <use>.detached.
type USBDisks struct {
	// Root is host-only: guests never see it.
	Root string
	// Shares is the custom volumes' root, whose pods/<pod UID>/<scope> the
	// guest writes its markers into.
	Shares string
}

type usbDiskUse struct {
	Scope string `json:"scope"`
}

// RequestDir is the directory Tart reads the pod's USB disk requests from.
func (d *USBDisks) RequestDir(pod *corev1.Pod) (string, error) {
	dir := filepath.Join(d.Root, "requests", string(pod.UID))
	return dir, os.MkdirAll(dir, 0700)
}

func (d *USBDisks) share(uid, scope string) string {
	return filepath.Join(d.Shares, "pods", uid, scope)
}

// Attach asks Tart to hot-plug image into the slot's VM and waits for its
// answer. A retried attach of the same use returns at once.
func (d *USBDisks) Attach(ctx context.Context, slot cachevolumes.Slot, image string) error {
	dir := filepath.Join(d.Root, "requests", slot.PodUID)
	if _, err := os.Stat(filepath.Join(dir, slot.ID+".attached")); err == nil {
		return nil
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		return err
	}
	share := d.share(slot.PodUID, slot.Scope)
	// Tells the guest's detach there is no image in the share to flush.
	if err := os.WriteFile(filepath.Join(share, ".block"), nil, 0644); err != nil {
		return err
	}
	_ = os.Remove(filepath.Join(share, ".released"))
	if err := writeJSONAtomically(filepath.Join(dir, slot.ID+".use"), usbDiskUse{Scope: slot.Scope}); err != nil {
		return err
	}
	_ = os.Remove(filepath.Join(dir, slot.ID+".error"))
	if err := writeJSONAtomically(filepath.Join(dir, slot.ID+".attach"), map[string]any{"image": image}); err != nil {
		return err
	}
	return waitForTartReply(ctx, dir, slot.ID, "attached")
}

// Released reports whether Tart detached the slot's disk at the host's request.
func (d *USBDisks) Released(slot cachevolumes.Slot) bool {
	_, err := os.Stat(filepath.Join(d.Root, "requests", slot.PodUID, slot.ID+".detached"))
	return err == nil
}

// Settle asks Tart to detach each disk whose guest wrote its clean detach
// marker, and tells the guest (`.released` beside its marker) once Tart has,
// so the guest keeps its VM running until then. It runs every second.
func (d *USBDisks) Settle() {
	uses, _ := filepath.Glob(filepath.Join(d.Root, "requests", "*", "*.use"))
	for _, path := range uses {
		dir, id := filepath.Dir(path), strings.TrimSuffix(filepath.Base(path), ".use")
		var use usbDiskUse
		if data, err := os.ReadFile(path); err != nil || json.Unmarshal(data, &use) != nil || use.Scope == "" {
			continue
		}
		share := d.share(filepath.Base(dir), use.Scope)
		if _, err := os.Stat(filepath.Join(dir, id+".attached")); err != nil {
			continue
		}
		if _, err := os.Stat(filepath.Join(dir, id+".detached")); err == nil {
			_ = os.WriteFile(filepath.Join(share, ".released"), []byte(id), 0644)
			continue
		}
		// Tart removes a request once it reads it, so the host keeps its own
		// record that it asked, and asks once.
		if _, err := os.Stat(filepath.Join(dir, id+".detach-requested")); err == nil {
			continue
		}
		if cachevolumes.APFSMarker(share, ".detached", id) {
			if os.WriteFile(filepath.Join(dir, id+".detach-requested"), nil, 0600) == nil {
				_ = writeJSONAtomically(filepath.Join(dir, id+".detach"), map[string]any{})
			}
		}
	}
}

// Clean removes the request directories of pods that hold no allocated or
// active volume and are gone, as Store.CleanPods does for their shares.
func (d *USBDisks) Clean(slots []cachevolumes.Slot, gone func(string) (bool, error)) error {
	held := map[string]bool{}
	for _, slot := range slots {
		if slot.State == "active" || slot.State == "allocated" {
			held[slot.PodUID] = true
		}
	}
	dirs, err := os.ReadDir(filepath.Join(d.Root, "requests"))
	if os.IsNotExist(err) {
		return nil
	}
	if err != nil {
		return err
	}
	var failures []error
	for _, dir := range dirs {
		if held[dir.Name()] {
			continue
		}
		if done, err := gone(dir.Name()); err != nil {
			failures = append(failures, err)
		} else if done {
			failures = append(failures, os.RemoveAll(filepath.Join(d.Root, "requests", dir.Name())))
		}
	}
	return errors.Join(failures...)
}

func writeJSONAtomically(path string, value any) error {
	data, err := json.Marshal(value)
	if err != nil {
		return err
	}
	temporary := filepath.Join(filepath.Dir(path), "."+filepath.Base(path)+".tmp")
	if err := os.WriteFile(temporary, data, 0600); err != nil {
		return err
	}
	return os.Rename(temporary, path)
}

// waitForTartReply waits for Tart's answer to request id.
func waitForTartReply(ctx context.Context, dir, id, reply string) error {
	for {
		if _, err := os.Stat(filepath.Join(dir, id+"."+reply)); err == nil {
			return nil
		}
		if data, err := os.ReadFile(filepath.Join(dir, id+".error")); err == nil {
			return fmt.Errorf("tart: %s", strings.TrimSpace(string(data)))
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(200 * time.Millisecond):
		}
	}
}
