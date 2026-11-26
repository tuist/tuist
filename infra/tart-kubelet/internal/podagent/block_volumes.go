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
// A volume is a DiskImageKit stack on this host: an empty ASIF base, the
// overlays earlier jobs left as read-only layers, and the job's own writable
// overlay, which Tart creates and which becomes the next layer once the guest
// detached it cleanly. Nothing is uploaded yet, so a volume is warm only on the
// host whose jobs wrote it, and each use is ended on the server as a cold one.
type BlockVolumes struct {
	// Root is host-only: guests never see it.
	Root string
	// Run runs a host tool; nil runs it directly.
	Run  func(ctx context.Context, name string, args ...string) error
	mu   sync.Mutex
	uses map[string]*blockUse
}

// blockMaxLayers bounds a stack's depth. A clean job past it is not kept:
// every layer is another file DiskImageKit validates at each attach.
const blockMaxLayers = 8

type blockManifest struct {
	Volume string   `json:"volume"`
	Layers []string `json:"layers"`
}

type blockUse struct {
	ID, PodName, PodUID, Scope, Overlay, Share string
	// Layers is the stack the overlay was created on; it is kept only on top of
	// the same stack.
	Layers []string
	Clean  bool
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
	if os.IsNotExist(err) {
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
	overlay := filepath.Join(dir, "jobs", identity.ID+".asif")
	if err := writeJSONAtomically(filepath.Join(requests, identity.ID+".attach"), map[string]any{"layers": manifest.Layers, "overlay": overlay}); err != nil {
		return nil, err
	}
	if err := waitForTartReply(ctx, requests, identity.ID, "attached"); err != nil {
		_ = os.Remove(overlay)
		return nil, err
	}
	// The guest records its clean detach beside the volume, as for share volumes.
	markers := filepath.Join(share, identity.Scope)
	if err := os.MkdirAll(markers, 0777); err != nil {
		return nil, err
	}
	_ = os.Chmod(markers, 0777)
	_ = os.Remove(filepath.Join(markers, ".detached"))
	// Tells the guest's detach there is no image in the share to flush.
	if err := os.WriteFile(filepath.Join(markers, ".block"), nil, 0644); err != nil {
		return nil, err
	}
	b.uses[identity.ID] = &blockUse{ID: identity.ID, PodName: pod.Name, PodUID: string(pod.UID), Scope: identity.Scope, Overlay: overlay, Share: markers, Layers: slices.Clone(manifest.Layers)}
	return map[string]any{"id": identity.ID, "directory": identity.Scope, "warm": len(manifest.Layers) > 1, "volume": manifest.Volume}, nil
}

// create makes the volume's empty base: an APFS volume in an ASIF image of the
// capacity the server chose. The host formats it and never mounts it again.
func (b *BlockVolumes) create(ctx context.Context, dir string, identity cachevolumes.Identity) (blockManifest, error) {
	capacity := identity.VolumeBytes
	if capacity <= 0 {
		capacity = 20_000_000_000
	}
	if err := os.MkdirAll(dir, 0700); err != nil {
		return blockManifest{}, err
	}
	manifest := blockManifest{Volume: "TuistCache-" + identity.Scope[:12], Layers: []string{filepath.Join(dir, "base.asif")}}
	_ = os.Remove(manifest.Layers[0])
	size := fmt.Sprintf("%dG", (capacity+999_999_999)/1_000_000_000)
	if err := b.run(ctx, "diskutil", "image", "create", "blank", "--fs", "APFS", "--format", "ASIF", "--size", size, "--volumeName", manifest.Volume, manifest.Layers[0]); err != nil {
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

// Reconcile detaches each disk the guest has cleanly detached, and once its
// pod's VM is gone keeps the overlay as the volume's next layer, or deletes it
// when the guest did not detach it cleanly or another job's layer came first.
func (b *BlockVolumes) Reconcile(ctx context.Context, gone func(name, uid string) (bool, error), end func(context.Context, string)) {
	b.mu.Lock()
	defer b.mu.Unlock()
	logger := log.FromContext(ctx).WithName("block-cache-volumes")
	for id, use := range b.uses {
		requests := filepath.Join(b.Root, "requests", use.PodUID)
		if !use.Clean {
			if marker, err := os.ReadFile(filepath.Join(use.Share, ".detached")); err == nil && string(marker) == id {
				use.Clean = true
				_ = writeJSONAtomically(filepath.Join(requests, id+".detach"), map[string]any{})
			}
		}
		done, err := gone(use.PodName, use.PodUID)
		if err != nil || !done {
			continue
		}
		kept := b.keep(use)
		logger.Info("block cache volume use ended", "use", id, "scope", use.Scope, "clean", use.Clean, "kept", kept)
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
	if err != nil || !use.Clean || !slices.Equal(manifest.Layers, use.Layers) || len(manifest.Layers) >= blockMaxLayers {
		_ = os.Remove(use.Overlay)
		return false
	}
	layer := filepath.Join(dir, "layer-"+use.ID+".asif")
	if err := os.Rename(use.Overlay, layer); err != nil {
		_ = os.Remove(use.Overlay)
		return false
	}
	manifest.Layers = append(manifest.Layers, layer)
	if err := writeJSONAtomically(filepath.Join(dir, "manifest.json"), manifest); err != nil {
		_ = os.Remove(layer)
		return false
	}
	return true
}

func valuesOf(uses map[string]*blockUse) []*blockUse {
	values := make([]*blockUse, 0, len(uses))
	for _, use := range uses {
		values = append(values, use)
	}
	return values
}
