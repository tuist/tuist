package sandbox

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"sort"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/checkout"
	"github.com/tuist/tuist/infra/sandboxd/internal/vm"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

// CacheImageSource copies the master of a saved runner-cache head onto this
// node: the node's runner-cache agent (checkout.Client). The agent lends the
// head's master, or the newest older master of its lineage when its node keeps
// only that, and returns the generation it lent; when that is one of held it
// copies nothing. dst must not exist.
type CacheImageSource interface {
	CacheImage(ctx context.Context, grant protocol.CacheGrant, held []int64, dst string, maxBytes int64) (int64, bool, error)
}

// ErrCacheCold is a cache grant whose lineage this node holds no master of.
// The agent never fetches one for a sandbox; the server picks nodes that hold it.
var ErrCacheCold = fmt.Errorf("%w: this node holds no copy of the granted cache", ErrCacheImage)

const (
	// Copied masters are named by their lineage and generation in
	// CACHE_IMAGE_DIR, beside any image an operator put there, which eviction
	// leaves alone.
	grantedImagePrefix = "rc-"
	partialImagePrefix = ".copy-"
	cacheCopyBudget    = 15 * time.Minute
)

// cacheImages tracks the copies in flight, one per lineage, and the images
// creates are using.
type cacheImages struct {
	source  CacheImageSource
	mu      sync.Mutex
	pins    map[string]int
	copying map[string]*cacheCopy
}

type cacheCopy struct {
	done       chan struct{}
	waiters    int
	name       string
	generation int64
	err        error
}

// grantedImageName names the copy of one generation of a lineage, so every
// create that gets that generation shares one copy on the node, whichever head
// it was granted. A generation names one master of its lineage, as it does in
// the agent's masters directory.
func grantedImageName(scope string, generation int64) string {
	sum := sha256.Sum256([]byte(scope))
	return grantedImagePrefix + hex.EncodeToString(sum[:20]) + "-" + strconv.FormatInt(generation, 10)
}

// heldGenerations lists the generations of the lineage this node has copies
// of. The caller holds cacheImages.mu.
func (m *Manager) heldGenerations(scope string) []int64 {
	prefix := strings.TrimSuffix(grantedImageName(scope, 0), "0")
	paths, _ := filepath.Glob(filepath.Join(m.cfg.CacheImageDir, prefix+"*"))
	var held []int64
	for _, path := range paths {
		if g, err := strconv.ParseInt(strings.TrimPrefix(filepath.Base(path), prefix), 10, 64); err == nil && g > 0 {
			held = append(held, g)
		}
	}
	return held
}

// pin keeps an image from eviction until the returned release. The caller
// holds cacheImages.mu.
func (c *cacheImages) pin(name string) func() {
	c.pins[name]++
	return func() {
		c.mu.Lock()
		if c.pins[name]--; c.pins[name] <= 0 {
			delete(c.pins, name)
		}
		c.mu.Unlock()
	}
}

// grantedCacheImage finds or copies the granted head's master into
// CACHE_IMAGE_DIR and pins it until release so eviction leaves it for this
// create. It returns the generation the image holds, which is older than the
// grant's when the node's agent keeps only an older master of the lineage.
// Concurrent creates of one lineage wait for a single copy.
func (m *Manager) grantedCacheImage(ctx context.Context, grant protocol.CacheGrant) (string, int64, func(), error) {
	c := &m.cacheImages
	if m.cfg.CacheImageDir == "" || m.cfg.CacheImagesBytes <= 0 || c.source == nil {
		return "", 0, nil, fmt.Errorf("%w: this daemon does not copy cache images", ErrCacheImage)
	}
	if grant.BaseGeneration <= 0 || grant.Scope == "" {
		return "", 0, nil, fmt.Errorf("%w: the grant names no saved head", ErrCacheImage)
	}
	use := func(name string, generation int64) (string, int64, func(), error) {
		release := c.pin(name)
		c.mu.Unlock()
		now := time.Now()
		_ = os.Chtimes(filepath.Join(m.cfg.CacheImageDir, name), now, now)
		return name, generation, release, nil
	}
	for {
		c.mu.Lock()
		if c.pins == nil {
			c.pins, c.copying = map[string]int{}, map[string]*cacheCopy{}
		}
		if name := grantedImageName(grant.Scope, grant.BaseGeneration); vm.Exists(filepath.Join(m.cfg.CacheImageDir, name)) {
			return use(name, grant.BaseGeneration)
		}
		running := c.copying[grant.Scope]
		if running == nil {
			running = &cacheCopy{done: make(chan struct{})}
			c.copying[grant.Scope] = running
			// The copies the agent may answer with stay while it decides.
			var releases []func()
			held := m.heldGenerations(grant.Scope)
			for _, g := range held {
				releases = append(releases, c.pin(grantedImageName(grant.Scope, g)))
			}
			c.mu.Unlock()
			// Detached, like a template build: a create that gives up does not
			// fail the others waiting on the same copy.
			running.name, running.generation, running.err = m.copyCacheImage(grant, held)
			for _, release := range releases {
				release()
			}
			c.mu.Lock()
			delete(c.copying, grant.Scope)
			close(running.done)
			if running.err != nil {
				c.mu.Unlock()
				return "", 0, nil, running.err
			}
			release := c.pin(running.name)
			m.evictCacheImages(time.Now())
			c.mu.Unlock()
			return running.name, running.generation, release, nil
		}
		running.waiters++
		c.mu.Unlock()
		select {
		case <-running.done:
		case <-ctx.Done():
			return "", 0, nil, ctx.Err()
		}
		if running.err != nil {
			return "", 0, nil, running.err
		}
		c.mu.Lock()
		if vm.Exists(filepath.Join(m.cfg.CacheImageDir, running.name)) {
			return use(running.name, running.generation)
		}
		c.mu.Unlock()
	}
}

func (m *Manager) copyCacheImage(grant protocol.CacheGrant, held []int64) (string, int64, error) {
	ctx, cancel := context.WithTimeout(context.Background(), cacheCopyBudget)
	defer cancel()
	start := time.Now()
	partial := filepath.Join(m.cfg.CacheImageDir, partialImagePrefix+grantedImageName(grant.Scope, grant.BaseGeneration))
	_ = os.Remove(partial)
	generation, copied, err := m.cacheImages.source.CacheImage(ctx, grant, held, partial, m.cfg.CacheImagesBytes)
	if errors.Is(err, checkout.ErrCold) {
		return "", 0, ErrCacheCold
	}
	if err == nil && (generation <= 0 || generation > grant.BaseGeneration || !copied && !slices.Contains(held, generation)) {
		err = fmt.Errorf("%w: the agent lent generation %d for a grant of %d", ErrCacheImage, generation, grant.BaseGeneration)
	}
	if err != nil {
		_ = os.Remove(partial)
		return "", 0, fmt.Errorf("copying the granted cache image: %w", err)
	}
	name := grantedImageName(grant.Scope, generation)
	if !copied {
		m.log.Info("cache image reused", "image", name, "generation", generation, "granted_generation", grant.BaseGeneration)
		return name, generation, nil
	}
	if err := os.Rename(partial, filepath.Join(m.cfg.CacheImageDir, name)); err != nil {
		_ = os.Remove(partial)
		return "", 0, fmt.Errorf("copying the granted cache image: %w", err)
	}
	m.log.Info("cache image copied", "image", name, "generation", generation, "granted_generation", grant.BaseGeneration, "bytes", allocatedBytes(filepath.Join(m.cfg.CacheImageDir, name)), "duration", time.Since(start))
	return name, generation, nil
}

// ExpireCacheImages removes copied masters unused for CacheImagesTTL.
func (m *Manager) ExpireCacheImages() {
	m.cacheImages.mu.Lock()
	defer m.cacheImages.mu.Unlock()
	m.evictCacheImages(time.Now())
}

// evictCacheImages removes copied masters unused for CacheImagesTTL and the
// least recently used beyond CACHE_IMAGES_GIB, never one a create has pinned.
// Sandboxes hold reflink clones, never the images, so a removed image costs
// only the next copy. The caller holds cacheImages.mu.
func (m *Manager) evictCacheImages(now time.Time) {
	entries, err := os.ReadDir(m.cfg.CacheImageDir)
	if err != nil {
		return
	}
	type image struct {
		name  string
		bytes int64
		used  time.Time
	}
	var images []image
	var total int64
	for _, e := range entries {
		info, err := e.Info()
		if !strings.HasPrefix(e.Name(), grantedImagePrefix) || err != nil || !info.Mode().IsRegular() {
			continue
		}
		bytes := allocatedBytes(filepath.Join(m.cfg.CacheImageDir, e.Name()))
		images = append(images, image{e.Name(), bytes, info.ModTime()})
		total += bytes
	}
	sort.Slice(images, func(i, j int) bool { return images[i].used.Before(images[j].used) })
	for _, img := range images {
		expired := m.cfg.CacheImagesTTL > 0 && now.Sub(img.used) > m.cfg.CacheImagesTTL
		if total <= m.cfg.CacheImagesBytes && !expired {
			continue
		}
		if m.cacheImages.pins[img.name] > 0 {
			continue
		}
		if err := os.Remove(filepath.Join(m.cfg.CacheImageDir, img.name)); err == nil {
			total -= img.bytes
			m.log.Info("cache image evicted", "image", img.name, "bytes", img.bytes)
		}
	}
}

// removePartialCacheImages removes copies a previous daemon left unfinished.
func (m *Manager) removePartialCacheImages() {
	if m.cfg.CacheImageDir == "" {
		return
	}
	partial, _ := filepath.Glob(filepath.Join(m.cfg.CacheImageDir, partialImagePrefix+"*"))
	for _, path := range partial {
		_ = os.Remove(path)
	}
}

func allocatedBytes(path string) int64 {
	var st syscall.Stat_t
	if err := syscall.Stat(path, &st); err != nil {
		return 0
	}
	return st.Blocks * 512
}
