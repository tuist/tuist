package blobcache

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"syscall"
	"time"
)

// An inputs image is an ext4 workspace image holding a scope's most requested
// blobs under InputsDir, named <hash>-<size>. sandboxd swaps a reflink clone
// of it in as an execution VM's workspace, and the guest executor hard-links
// those inputs into the action root instead of reading them over vsock. The
// blobs come only from the scope's own verified cache entries, so an image
// holds nothing its scope's credential could not read.
const (
	// InputsDir is the image's directory of blobs, relative to the
	// workspace. It is root's alone (0700), so an action reaches a blob
	// only through the hard link the executor makes for its own input.
	InputsDir = ".sbx-inputs"
	// hotRequests is how many requests make a blob worth an image.
	hotRequests = 2
	// maxImageBlobBytes bounds the blob bytes in one image.
	maxImageBlobBytes = 4 << 30
	// maxImages bounds how many scopes keep an image.
	maxImages = 4
	// rebuildInterval spaces a scope's rebuilds.
	rebuildInterval = time.Minute
	buildTimeout    = 5 * time.Minute
)

type image struct {
	path      string
	bytes     int64 // workspace size it was built for
	allocated int64 // bytes it takes on disk, counted in the budget
	blobs     []string
	usedAt    time.Time
}

type imageState struct {
	current  *image
	building bool
	builtAt  time.Time
}

// Image returns the scope's inputs image for a workspace of the given size,
// if one is built, and starts a rebuild in the background when the scope's
// hot blobs changed since the last one.
func (c *Cache) Image(s Scope, workspaceBytes int64) (string, bool) {
	ns := s.key()
	c.mu.Lock()
	defer c.mu.Unlock()
	if c.images == nil {
		c.images = map[string]*imageState{}
	}
	st := c.images[ns]
	if st == nil {
		st = &imageState{}
		c.images[ns] = st
	}
	if !st.building && time.Since(st.builtAt) >= rebuildInterval {
		hot := c.hot(ns)
		if len(hot) > 0 && (st.current == nil || st.current.bytes != workspaceBytes || !slices.Equal(names(hot), st.current.blobs)) {
			st.building = true
			st.builtAt = time.Now()
			go c.buildImage(ns, workspaceBytes, hot)
		}
	}
	if st.current == nil || st.current.bytes != workspaceBytes {
		return "", false
	}
	st.current.usedAt = time.Now()
	return st.current.path, true
}

// hot lists the scope's ready blobs requested at least hotRequests times,
// most requested first, within maxImageBlobBytes, in name order. c.mu is held.
func (c *Cache) hot(ns string) []*entry {
	var hot []*entry
	for key, e := range c.entries {
		if strings.HasPrefix(key, ns+"/") && e.elem != nil && e.hits >= hotRequests {
			hot = append(hot, e)
		}
	}
	slices.SortFunc(hot, func(a, b *entry) int { return b.hits - a.hits })
	var total int64
	kept := hot[:0]
	for _, e := range hot {
		if total+e.size > maxImageBlobBytes {
			continue
		}
		total += e.size
		kept = append(kept, e)
	}
	slices.SortFunc(kept, func(a, b *entry) int { return strings.Compare(a.key, b.key) })
	return kept
}

func names(entries []*entry) []string {
	out := make([]string, len(entries))
	for i, e := range entries {
		out[i] = e.key
	}
	return out
}

func (c *Cache) buildImage(ns string, workspaceBytes int64, hot []*entry) {
	start := time.Now()
	img, err := c.writeImage(ns, workspaceBytes, hot)
	c.mu.Lock()
	defer c.mu.Unlock()
	st := c.images[ns]
	st.building = false
	if err == nil {
		err = c.installImage(st, img)
	}
	if err != nil {
		if img != nil {
			os.Remove(img.path)
		}
		c.log.Warn("building inputs image", "scope", ns, "error", err)
		return
	}
	c.log.Info("built inputs image", "scope", ns, "blobs", len(img.blobs), "allocated_bytes", img.allocated, "duration", time.Since(start))
}

// writeImage hard-links the blobs into a staging tree beside the cache files
// and formats a sparse image around it. A blob evicted meanwhile is left out.
func (c *Cache) writeImage(ns string, workspaceBytes int64, hot []*entry) (*image, error) {
	c.mu.Lock()
	c.tmp++
	staging := filepath.Join(c.dir, ".image-"+strconv.Itoa(c.tmp))
	c.mu.Unlock()
	defer os.RemoveAll(staging)
	inputs := filepath.Join(staging, InputsDir)
	if err := os.MkdirAll(inputs, 0o700); err != nil {
		return nil, err
	}
	if err := os.Chmod(staging, 0o755); err != nil {
		return nil, err
	}
	var linked []string
	for _, e := range hot {
		dst := filepath.Join(inputs, filepath.Base(e.path))
		if err := os.Link(e.path, dst); err != nil {
			continue
		}
		// Read-only for the action; the guest sets the executable bit.
		if err := os.Chmod(dst, 0o444); err != nil {
			return nil, err
		}
		linked = append(linked, e.key)
	}
	if len(linked) == 0 {
		return nil, fmt.Errorf("every hot blob was evicted")
	}
	path := filepath.Join(c.dir, ns+".inputs-"+strconv.FormatInt(time.Now().UnixNano(), 10)+".ext4")
	img := &image{path: path, bytes: workspaceBytes, blobs: linked}
	f, err := os.OpenFile(path, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return nil, err
	}
	err = f.Truncate(workspaceBytes)
	if closeErr := f.Close(); err == nil {
		err = closeErr
	}
	if err != nil {
		return img, err
	}
	ctx, cancel := context.WithTimeout(context.Background(), buildTimeout)
	defer cancel()
	mkfs := c.Mkfs
	if mkfs == nil {
		mkfs = runMkfs
	}
	if err := mkfs(ctx, path, staging); err != nil {
		return img, err
	}
	var st syscall.Stat_t
	if err := syscall.Stat(path, &st); err != nil {
		return img, err
	}
	img.allocated = st.Blocks * 512
	return img, nil
}

// installImage makes img the scope's image, counting it in the budget, and
// removes the image it replaces and, past maxImages, the least recently used
// other scope's. Clones in jails keep their data. c.mu is held.
func (c *Cache) installImage(st *imageState, img *image) error {
	if c.used+img.allocated > c.budget {
		return ErrFull
	}
	c.dropImage(st)
	st.current = img
	img.usedAt = time.Now()
	c.used += img.allocated
	for c.imageCount() > maxImages {
		c.dropImage(c.oldestImage(st))
	}
	c.gauge()
	return nil
}

// oldestImage returns the scope whose image was used least recently, other
// than except, or nil without one. c.mu is held.
func (c *Cache) oldestImage(except *imageState) *imageState {
	var oldest *imageState
	for _, st := range c.images {
		if st.current != nil && st != except && (oldest == nil || st.current.usedAt.Before(oldest.current.usedAt)) {
			oldest = st
		}
	}
	return oldest
}

func (c *Cache) imageCount() int {
	n := 0
	for _, st := range c.images {
		if st.current != nil {
			n++
		}
	}
	return n
}

// dropImage removes the scope's current image. c.mu is held.
func (c *Cache) dropImage(st *imageState) {
	if st == nil || st.current == nil {
		return
	}
	c.used -= st.current.allocated
	os.Remove(st.current.path)
	st.current = nil
}

func runMkfs(ctx context.Context, image, root string) error {
	out, err := exec.CommandContext(ctx, "mkfs.ext4", "-q", "-F", "-L", "workspace",
		"-E", "lazy_itable_init=0,lazy_journal_init=0,nodiscard", "-d", root, image).CombinedOutput()
	if err != nil {
		return fmt.Errorf("mkfs.ext4: %w: %s", err, strings.TrimSpace(string(out)))
	}
	return nil
}
