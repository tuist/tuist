package sandbox

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/checkout"
	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

// CacheImageSource copies the master of a saved runner-cache head onto this
// node: the node's runner-cache agent (checkout.Client). dst must not exist.
type CacheImageSource interface {
	CacheImage(ctx context.Context, grant protocol.CacheGrant, dst string, maxBytes int64) error
}

// ErrCacheCold is a cache grant whose master this node does not hold. The
// agent never fetches one for a sandbox; the server picks nodes that hold it.
var ErrCacheCold = fmt.Errorf("%w: this node holds no copy of the granted cache", ErrCacheImage)

const (
	// Copied masters are named by their head in CACHE_IMAGE_DIR, beside any
	// image an operator put there, which eviction leaves alone.
	grantedImagePrefix = "rc-"
	partialImagePrefix = ".copy-"
	cacheCopyBudget    = 15 * time.Minute
)

// cacheImages tracks the copies in flight and the images creates are using.
type cacheImages struct {
	source  CacheImageSource
	mu      sync.Mutex
	pins    map[string]int
	copying map[string]*cacheCopy
}

type cacheCopy struct {
	done chan struct{}
	err  error
}

// grantedImageName names a granted head's master, so every create granted the
// same head shares one copy on the node.
func grantedImageName(g protocol.CacheGrant) string {
	sum := sha256.Sum256(fmt.Appendf(nil, "%s\x00%d\x00%s\x00%s", g.Scope, g.BaseGeneration, g.ImageDigest, g.ContentDigest))
	return grantedImagePrefix + hex.EncodeToString(sum[:20])
}

// grantedCacheImage has the agent copy the granted master into CACHE_IMAGE_DIR
// unless it is there already, and pins it until release so eviction leaves it
// for this create. Concurrent creates of one head wait for a single copy.
func (m *Manager) grantedCacheImage(ctx context.Context, grant protocol.CacheGrant) (string, func(), error) {
	c := &m.cacheImages
	if m.cfg.CacheImageDir == "" || m.cfg.CacheImagesBytes <= 0 || c.source == nil {
		return "", nil, fmt.Errorf("%w: this daemon does not copy cache images", ErrCacheImage)
	}
	if grant.BaseGeneration <= 0 || grant.Scope == "" {
		return "", nil, fmt.Errorf("%w: the grant names no saved head", ErrCacheImage)
	}
	name := grantedImageName(grant)
	path := filepath.Join(m.cfg.CacheImageDir, name)
	c.mu.Lock()
	if c.pins == nil {
		c.pins, c.copying = map[string]int{}, map[string]*cacheCopy{}
	}
	c.pins[name]++
	c.mu.Unlock()
	release := func() {
		c.mu.Lock()
		if c.pins[name]--; c.pins[name] <= 0 {
			delete(c.pins, name)
		}
		c.mu.Unlock()
	}
	for {
		c.mu.Lock()
		if _, err := os.Lstat(path); err == nil {
			c.mu.Unlock()
			now := time.Now()
			_ = os.Chtimes(path, now, now)
			return name, release, nil
		}
		running := c.copying[name]
		if running == nil {
			running = &cacheCopy{done: make(chan struct{})}
			c.copying[name] = running
			c.mu.Unlock()
			// Detached, like a template build: a create that gives up does not
			// fail the others waiting on the same copy.
			running.err = m.copyCacheImage(grant, path)
			c.mu.Lock()
			delete(c.copying, name)
			close(running.done)
			if running.err == nil {
				m.evictCacheImages(time.Now())
			}
			c.mu.Unlock()
		} else {
			c.mu.Unlock()
			select {
			case <-running.done:
			case <-ctx.Done():
				release()
				return "", nil, ctx.Err()
			}
		}
		if running.err != nil {
			release()
			return "", nil, running.err
		}
	}
}

func (m *Manager) copyCacheImage(grant protocol.CacheGrant, path string) error {
	ctx, cancel := context.WithTimeout(context.Background(), cacheCopyBudget)
	defer cancel()
	start := time.Now()
	partial := filepath.Join(filepath.Dir(path), partialImagePrefix+filepath.Base(path))
	_ = os.Remove(partial)
	err := m.cacheImages.source.CacheImage(ctx, grant, partial, m.cfg.CacheImagesBytes)
	if errors.Is(err, checkout.ErrCold) {
		return ErrCacheCold
	}
	if err != nil {
		_ = os.Remove(partial)
		return fmt.Errorf("copying the granted cache image: %w", err)
	}
	if err := os.Rename(partial, path); err != nil {
		_ = os.Remove(partial)
		return err
	}
	m.log.Info("cache image copied", "image", filepath.Base(path), "bytes", allocatedBytes(path), "duration", time.Since(start))
	return nil
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
