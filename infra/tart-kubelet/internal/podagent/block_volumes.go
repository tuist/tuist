package podagent

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"

	cachevolumes "github.com/tuist/tuist/infra/runner-cache"
	corev1 "k8s.io/api/core/v1"
	"sigs.k8s.io/controller-runtime/pkg/log"
)

// BlockVolumes serves custom cache volumes as USB disks that Tart hot-plugs
// into the running VM (`tart run --usb-disk-requests`, infra/tart-build), in
// place of sparse images in the guest's virtio-fs share: a macOS 27 guest's
// disk image driver loses writes to an image whose file is on the share.
//
// A volume is one ASIF image on this host. Each job gets an APFS clone of it
// (`cp -c`, copy-on-write, no data copied), attached read-write on its own, and
// the clone replaces the volume once the guest detached it cleanly, Tart let go
// of it and no other job's clone replaced the volume first. DiskImageKit stacks
// (read-only layers under a job overlay) were tried and dropped: on macOS 27.2 a
// VM did not read a stack's middle layers. Nothing is uploaded yet, so a volume
// is warm only on the host whose jobs wrote it, and each use is ended on the
// server as a cold one.
type BlockVolumes struct {
	// Root is host-only: guests never see it.
	Root string
	// Run runs a host tool; nil runs it directly.
	Run  func(ctx context.Context, name string, args ...string) error
	mu   sync.Mutex
	uses map[string]*blockUse
}

type blockManifest struct {
	Volume string `json:"volume"`
	// Generation counts the jobs whose writes the volume image holds; 0 is the
	// empty volume.
	Generation int `json:"generation"`
}

type blockUse struct {
	ID, PodName, PodUID, Scope, Clone, Share string
	// Generation is the volume's the clone was made from; the clone replaces
	// the volume only while it is still that generation.
	Generation int
	Clean      bool
	// Released is Tart's word that it detached the disk and let go of the
	// clone. Tart exits as soon as its VM stops, so a clone still attached then
	// can be missing writes: only a released one is kept.
	Released bool
}

func (b *BlockVolumes) run(ctx context.Context, name string, args ...string) error {
	if b.Run != nil {
		return b.Run(ctx, name, args...)
	}
	out, err := exec.CommandContext(ctx, name, args...).CombinedOutput()
	if err != nil {
		return fmt.Errorf("%s: %w (%s)", name, err, strings.TrimSpace(string(out)))
	}
	return nil
}

// RequestDir is the directory Tart reads the pod's USB disk requests from.
func (b *BlockVolumes) RequestDir(pod *corev1.Pod) (string, error) {
	dir := filepath.Join(b.Root, "requests", string(pod.UID))
	return dir, os.MkdirAll(dir, 0700)
}

func (b *BlockVolumes) volumeDir(scope string) string {
	return filepath.Join(b.Root, "volumes", scope)
}

func volumeImage(dir string) string {
	return filepath.Join(dir, "volume.asif")
}

func readBlockManifest(dir string) (blockManifest, error) {
	var manifest blockManifest
	data, err := os.ReadFile(filepath.Join(dir, "manifest.json"))
	if err != nil {
		return manifest, err
	}
	return manifest, json.Unmarshal(data, &manifest)
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

// Acquire hot-plugs the volume into the pod's VM and returns the guest's
// response: the volume name the guest mounts, and whether earlier jobs left
// content in it.
func (b *BlockVolumes) Acquire(ctx context.Context, pod *corev1.Pod, share string, identity cachevolumes.Identity) (map[string]any, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	if b.uses == nil {
		b.uses = map[string]*blockUse{}
	}
	if len(identity.Scope) != 64 || strings.ContainsAny(identity.Scope, "./") || identity.ID == "" || strings.ContainsAny(identity.ID, "./") {
		return nil, errors.New("invalid volume identity")
	}
	dir := b.volumeDir(identity.Scope)
	manifest, err := readBlockManifest(dir)
	if _, statErr := os.Stat(volumeImage(dir)); os.IsNotExist(err) || os.IsNotExist(statErr) {
		manifest, err = b.create(ctx, dir, identity)
	}
	if err != nil {
		return nil, err
	}
	requests, err := b.RequestDir(pod)
	if err != nil {
		return nil, err
	}
	if err := os.MkdirAll(filepath.Join(dir, "jobs"), 0700); err != nil {
		return nil, err
	}
	clone := filepath.Join(dir, "jobs", identity.ID+".asif")
	_ = os.Remove(clone)
	if err := b.run(ctx, "cp", "-c", volumeImage(dir), clone); err != nil {
		return nil, err
	}
	if err := writeJSONAtomically(filepath.Join(requests, identity.ID+".attach"), map[string]any{"image": clone}); err != nil {
		_ = os.Remove(clone)
		return nil, err
	}
	if err := waitForTartReply(ctx, requests, identity.ID, "attached"); err != nil {
		_ = os.Remove(clone)
		return nil, err
	}
	// The guest records its clean detach beside the volume, as for share volumes.
	markers := filepath.Join(share, identity.Scope)
	if err := os.MkdirAll(markers, 0777); err != nil {
		return nil, err
	}
	_ = os.Chmod(markers, 0777)
	_ = os.Remove(filepath.Join(markers, ".detached"))
	_ = os.Remove(filepath.Join(markers, ".released"))
	// Tells the guest's detach there is no image in the share to flush.
	if err := os.WriteFile(filepath.Join(markers, ".block"), nil, 0644); err != nil {
		return nil, err
	}
	b.uses[identity.ID] = &blockUse{ID: identity.ID, PodName: pod.Name, PodUID: string(pod.UID), Scope: identity.Scope, Clone: clone, Share: markers, Generation: manifest.Generation}
	return map[string]any{"id": identity.ID, "directory": identity.Scope, "warm": manifest.Generation > 0, "volume": manifest.Volume}, nil
}

// create makes the empty volume: an APFS volume in an ASIF image of the
// capacity the server chose. The host formats it and never mounts it again.
func (b *BlockVolumes) create(ctx context.Context, dir string, identity cachevolumes.Identity) (blockManifest, error) {
	capacity := identity.VolumeBytes
	if capacity <= 0 {
		capacity = 20_000_000_000
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		return blockManifest{}, err
	}
	manifest := blockManifest{Volume: "TuistCache-" + identity.Scope[:12]}
	_ = os.Remove(volumeImage(dir))
	size := fmt.Sprintf("%dG", (capacity+999_999_999)/1_000_000_000)
	if err := b.run(ctx, "diskutil", "image", "create", "blank", "--fs", "APFS", "--format", "ASIF", "--size", size, "--volumeName", manifest.Volume, volumeImage(dir)); err != nil {
		return blockManifest{}, err
	}
	return manifest, writeJSONAtomically(filepath.Join(dir, "manifest.json"), manifest)
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

// Settle asks Tart to detach each disk the guest has cleanly detached, and
// tells the guest (`.released` beside its marker) once Tart has, so the guest
// keeps its VM running until then. It runs every second beside the mailboxes
// and skips a round while an attach holds the lock.
func (b *BlockVolumes) Settle() {
	if !b.mu.TryLock() {
		return
	}
	defer b.mu.Unlock()
	b.settle()
}

func (b *BlockVolumes) settle() {
	for id, use := range b.uses {
		requests := filepath.Join(b.Root, "requests", use.PodUID)
		if !use.Clean {
			if marker, err := os.ReadFile(filepath.Join(use.Share, ".detached")); err == nil && string(marker) == id {
				use.Clean = true
				_ = writeJSONAtomically(filepath.Join(requests, id+".detach"), map[string]any{})
			}
		}
		if use.Clean && !use.Released {
			if _, err := os.Stat(filepath.Join(requests, id+".detached")); err == nil {
				use.Released = true
				_ = os.WriteFile(filepath.Join(use.Share, ".released"), []byte(id), 0644)
			}
		}
	}
}

// Reconcile settles every use, and once a pod's VM is gone makes its clone the
// volume, or deletes it when the guest did not detach it cleanly, Tart did not
// release it, or another job's clone replaced the volume first.
func (b *BlockVolumes) Reconcile(ctx context.Context, gone func(name, uid string) (bool, error), end func(context.Context, string)) {
	b.mu.Lock()
	defer b.mu.Unlock()
	logger := log.FromContext(ctx).WithName("block-cache-volumes")
	b.settle()
	for id, use := range b.uses {
		requests := filepath.Join(b.Root, "requests", use.PodUID)
		done, err := gone(use.PodName, use.PodUID)
		if err != nil || !done {
			continue
		}
		kept := b.keep(use)
		logger.Info("block cache volume use ended", "use", id, "scope", use.Scope, "clean", use.Clean, "released", use.Released, "kept", kept)
		end(ctx, id)
		delete(b.uses, id)
		if !slices.ContainsFunc(valuesOf(b.uses), func(other *blockUse) bool { return other.PodUID == use.PodUID }) {
			_ = os.RemoveAll(requests)
		}
	}
}

func (b *BlockVolumes) keep(use *blockUse) bool {
	dir := b.volumeDir(use.Scope)
	manifest, err := readBlockManifest(dir)
	if err != nil || !use.Clean || !use.Released || manifest.Generation != use.Generation {
		_ = os.Remove(use.Clone)
		return false
	}
	if err := os.Rename(use.Clone, volumeImage(dir)); err != nil {
		_ = os.Remove(use.Clone)
		return false
	}
	manifest.Generation++
	return writeJSONAtomically(filepath.Join(dir, "manifest.json"), manifest) == nil
}

func valuesOf(uses map[string]*blockUse) []*blockUse {
	values := make([]*blockUse, 0, len(uses))
	for _, use := range uses {
		values = append(values, use)
	}
	return values
}
