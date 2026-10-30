package podagent

import (
	"context"
	"errors"
	"sort"
	"time"

	"sigs.k8s.io/controller-runtime/pkg/log"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

// Following a runner image release.
//
// A release moves a pool's `spec.image` to a new digest, and the GC reaps a
// golden no pool runs on its next pass. On a stacked rack host the golden's
// read-only base then has no other reference, so `tart prune --gc` drops it,
// and the first Pod of that image on the host pulls the whole image again
// where the new overlay alone would do. After the release of 2026-10-22
// 13:00 UTC the GC freed about 60 GiB per reaped golden on each rack host;
// the next pull took 10 to 23 seconds on hosts that still held the base and
// 9.5 to 12.8 minutes on hosts that did not.
//
// So a host that holds a pool's previous image pulls the pool's current one
// before the GC lets the previous one go: the runners-controller records the
// previous image in the pool's `status.previousImage`, and while the host
// holds that golden and not the current one, the GC keeps the previous golden
// and its cached image and pulls the current one in the background. The
// next pass after the pull reaps the previous golden as superseded.

// defaultFollowTimeout bounds how long a superseded golden is kept for its
// successor's pull, so an image that cannot be pulled does not pin it.
const defaultFollowTimeout = 2 * time.Hour

// succession is a pool's move from one image to another.
type succession struct {
	previous string
	current  string
}

// planFollow returns the images this host should pull to follow a release,
// and marks the previous goldens the pass keeps until they are pulled.
func (c *Collector) planFollow(expected *expectedSet, vms []tart.VM, now time.Time) []string {
	if c.Goldens == nil || len(expected.successions) == 0 {
		return nil
	}
	local := map[string]bool{}
	for _, vm := range vms {
		if vm.Source == "local" && isGoldenVMName(vm.Name) {
			local[vm.Name] = true
		}
	}
	timeout := c.FollowTimeout
	if timeout <= 0 {
		timeout = defaultFollowTimeout
	}

	c.followMu.Lock()
	defer c.followMu.Unlock()
	if c.followSince == nil {
		c.followSince = map[string]time.Time{}
	}
	for previous := range c.followSince {
		if _, ok := expected.successions[previous]; !ok {
			delete(c.followSince, previous)
		}
	}

	seen := map[string]bool{}
	var images []string
	for previous, s := range expected.successions {
		if !local[previous] || local[goldenVMName(s.current)] {
			delete(c.followSince, previous)
			continue
		}
		since, ok := c.followSince[previous]
		if !ok {
			since = now
			c.followSince[previous] = now
		}
		if now.Sub(since) >= timeout {
			continue
		}
		expected.following[previous] = struct{}{}
		expected.addImage(s.previous, c.Images)
		if !seen[s.current] {
			seen[s.current] = true
			images = append(images, s.current)
		}
	}
	sort.Strings(images)
	return images
}

// startFollow pulls images in the background, one at a time, unless a
// follow is already running; the next pass picks up whatever it misses.
func (c *Collector) startFollow(ctx context.Context, images []string) {
	if len(images) == 0 {
		return
	}
	c.followMu.Lock()
	if c.followRunning {
		c.followMu.Unlock()
		return
	}
	c.followRunning = true
	c.followWG.Add(1)
	c.followMu.Unlock()

	go func() {
		defer func() {
			c.followMu.Lock()
			c.followRunning = false
			c.followMu.Unlock()
			c.followWG.Done()
		}()
		ctx, cancel := context.WithTimeout(ctx, defaultPrewarmTimeout)
		defer cancel()
		logger := log.FromContext(ctx).WithName("gc")
		for _, image := range images {
			if free, err := c.hostDiskFree(); err == nil && free < prewarmMinFreePercent {
				logger.Info("stopping runner image follow on disk space", "freePercent", free, "floorPercent", prewarmMinFreePercent, "image", image)
				return
			}
			started := time.Now()
			name, pulled, err := c.Goldens.ensureGolden(ctx, image)
			if err != nil {
				if errors.Is(err, errMirrorSyncing) {
					logger.Info("runner image follow waits for the image cache", "image", image)
				} else {
					logger.Error(err, "follow runner image", "image", image)
				}
				if ctx.Err() != nil {
					return
				}
				continue
			}
			logger.Info("followed runner image", "image", image, "golden", name, "pulled", pulled, "duration", time.Since(started).String())
		}
	}()
}
