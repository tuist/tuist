// Package rackimagefiller keeps a rack's VM image cache filled: it copies the
// runner images a rack wants from their upstream registry into the plain
// registry on the rack's storage node, which the rack's minis pull golden
// bases from.
//
// The cache never fetches on its own. A copy is planned before a byte moves:
// the blobs the cache lacks are counted against the space left on its volume
// and against a daily download budget, and an image that does not fit is
// skipped rather than half fetched. Blobs are copied one at a time and the
// manifest last, so a mini never sees a partial image, a copy that fails
// keeps the blobs it finished, and an image that shares blobs with one the
// cache holds (a release rebuilds only part of a disk) downloads only the
// rest. A failing image backs off for hours, and the budget caps what any
// mistake can cost a day.
package rackimagefiller

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sort"
	"time"

	"github.com/go-logr/logr"
	"github.com/google/go-containerregistry/pkg/name"
	v1 "github.com/google/go-containerregistry/pkg/v1"
	"github.com/google/go-containerregistry/pkg/v1/remote"
	"github.com/google/go-containerregistry/pkg/v1/remote/transport"
)

// Config is what a Filler copies and within which bounds.
type Config struct {
	// Images are the upstream references the cache holds, in priority order:
	// when the volume cannot hold them all, the first ones win.
	Images []string
	// Registry is the cache's registry, as a reference's registry part
	// (`10.10.0.11:5000`), spoken to over plain HTTP.
	Registry string
	// StateFile keeps the day's downloaded bytes and each image's backoff
	// across restarts, so a crashing filler cannot spend the budget twice.
	StateFile string
	// FreeBytes reports the space left on the cache's volume.
	FreeBytes func() (int64, error)
	// Reserve is left free on the volume beyond any copy.
	Reserve int64
	// DailyBudget caps the bytes downloaded per UTC day.
	DailyBudget int64
	// MinBackoff and MaxBackoff bound how long a failing image waits: the
	// wait doubles from MinBackoff with each consecutive failure.
	MinBackoff time.Duration
	MaxBackoff time.Duration
	// Remote are extra options for every registry call (transport, auth).
	Remote []remote.Option
}

// Result is what one Pass did to each image, keyed by upstream reference.
type Result map[string]Outcome

// Outcome is how a Pass left one image.
type Outcome string

const (
	// Held: the cache already holds the image at the upstream's digest.
	Held Outcome = "held"
	// Copied: the image was copied in this pass.
	Copied Outcome = "copied"
	// NoSpace: the blobs the cache lacks do not fit on its volume, even
	// after evicting what it no longer wants.
	NoSpace Outcome = "no_space"
	// Evicting: images the cache no longer wants were deleted to make room;
	// the registry frees their blobs at its next collection.
	Evicting Outcome = "evicting"
	// OverBudget: the copy would exceed the day's download budget.
	OverBudget Outcome = "over_budget"
	// BackingOff: the image failed recently and waits before trying again.
	BackingOff Outcome = "backing_off"
	// Failed: resolving or copying the image failed.
	Failed Outcome = "failed"
)

// Filler runs passes over its Config.
type Filler struct {
	Config Config
	Log    logr.Logger
	// Now is the clock; nil means time.Now.
	Now func() time.Time
	// HTTP checks the cache for blobs; nil means a client with a 30s timeout.
	HTTP *http.Client
}

type state struct {
	Day        string             `json:"day"`
	Downloaded int64              `json:"downloaded"`
	Failures   map[string]failure `json:"failures,omitempty"`
}

type failure struct {
	Count int       `json:"count"`
	Until time.Time `json:"until"`
}

// Pass brings the cache as close to Config.Images as its volume and the day's
// budget allow, and reports what it did. It returns an error only when its
// state cannot be read or written; a failing image is an Outcome.
func (f *Filler) Pass(ctx context.Context) (Result, error) {
	now := f.now()
	st, err := f.loadState(now)
	if err != nil {
		return nil, err
	}
	result := Result{}
	wanted := map[string]v1.Hash{}
	var lacking []planned

	for _, image := range f.Config.Images {
		if fail, ok := st.Failures[image]; ok && now.Before(fail.Until) {
			result[image] = BackingOff
			continue
		}
		plan, err := f.plan(ctx, image)
		if err != nil {
			f.recordFailure(st, image, now)
			f.Log.Error(err, "resolve runner image", "image", image)
			result[image] = Failed
			continue
		}
		wanted[plan.target.String()] = plan.digest
		if plan.held {
			delete(st.Failures, image)
			result[image] = Held
			continue
		}
		lacking = append(lacking, plan)
	}

	counted := map[v1.Hash]bool{}
	evicted := false
	for _, plan := range lacking {
		missing := int64(0)
		for _, blob := range plan.missing {
			if !counted[blob.digest] {
				missing += blob.size
			}
		}
		free, err := f.Config.FreeBytes()
		if err != nil {
			return result, fmt.Errorf("measure the cache's free space: %w", err)
		}
		if missing > free-f.Config.Reserve {
			if !evicted {
				evicted = f.evict(ctx, wanted)
			}
			if evicted {
				result[plan.image] = Evicting
			} else {
				result[plan.image] = NoSpace
			}
			f.Log.Info("runner image does not fit the cache", "image", plan.image, "missingBytes", missing, "freeBytes", free, "reserveBytes", f.Config.Reserve, "evicting", evicted)
			continue
		}
		if st.Downloaded+missing > f.Config.DailyBudget {
			result[plan.image] = OverBudget
			f.Log.Info("runner image is over the day's download budget", "image", plan.image, "missingBytes", missing, "downloadedBytes", st.Downloaded, "budgetBytes", f.Config.DailyBudget)
			continue
		}
		copied, err := f.copy(ctx, plan)
		// The progress counts blobs the cache already held as written, so the
		// budget is charged what the plan found missing, and on a failure no
		// more than was written.
		charged := missing
		if err != nil {
			charged = min(copied, missing)
		}
		st.Downloaded += charged
		if err != nil {
			f.recordFailure(st, plan.image, now)
			f.Log.Error(err, "copy runner image", "image", plan.image, "copiedBytes", copied, "nextAttempt", st.Failures[plan.image].Until)
			result[plan.image] = Failed
		} else {
			delete(st.Failures, plan.image)
			for _, blob := range plan.missing {
				counted[blob.digest] = true
			}
			f.Log.Info("copied runner image", "image", plan.image, "digest", plan.digest.String(), "copiedBytes", copied)
			result[plan.image] = Copied
		}
		if err := f.saveState(st); err != nil {
			return result, err
		}
	}
	return result, f.saveState(st)
}

type blob struct {
	digest v1.Hash
	size   int64
}

type planned struct {
	image   string
	source  name.Reference
	target  name.Reference
	digest  v1.Hash
	img     v1.Image
	held    bool
	missing []blob
}

// plan resolves image upstream and works out what the cache lacks of it.
func (f *Filler) plan(ctx context.Context, image string) (planned, error) {
	source, err := name.ParseReference(image)
	if err != nil {
		return planned{}, err
	}
	target, err := f.target(source)
	if err != nil {
		return planned{}, err
	}
	desc, err := remote.Get(source, f.options(ctx)...)
	if err != nil {
		return planned{}, fmt.Errorf("resolve %s: %w", source, err)
	}
	img, err := desc.Image()
	if err != nil {
		return planned{}, fmt.Errorf("%s is not an image manifest: %w", source, err)
	}
	p := planned{image: image, source: source, target: target, digest: desc.Digest, img: img}

	if held, err := remote.Head(target, f.options(ctx)...); err == nil && held.Digest == desc.Digest {
		p.held = true
		return p, nil
	}
	manifest, err := img.Manifest()
	if err != nil {
		return planned{}, err
	}
	seen := map[v1.Hash]bool{}
	for _, d := range append([]v1.Descriptor{manifest.Config}, manifest.Layers...) {
		if seen[d.Digest] {
			continue
		}
		seen[d.Digest] = true
		present, err := f.hasBlob(ctx, target.Context(), d.Digest)
		if err != nil {
			return planned{}, err
		}
		if !present {
			p.missing = append(p.missing, blob{digest: d.Digest, size: d.Size})
		}
	}
	return p, nil
}

func (f *Filler) hasBlob(ctx context.Context, repo name.Repository, digest v1.Hash) (bool, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodHead, fmt.Sprintf("http://%s/v2/%s/blobs/%s", f.Config.Registry, repo.RepositoryStr(), digest), nil)
	if err != nil {
		return false, err
	}
	resp, err := f.httpClient().Do(req)
	if err != nil {
		return false, fmt.Errorf("check %s in the cache: %w", digest, err)
	}
	_ = resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusOK:
		return true, nil
	case http.StatusNotFound:
		return false, nil
	default:
		return false, fmt.Errorf("check %s in the cache: HEAD answered %d", digest, resp.StatusCode)
	}
}

func (f *Filler) httpClient() *http.Client {
	if f.HTTP != nil {
		return f.HTTP
	}
	return &http.Client{Timeout: 30 * time.Second}
}

// copy writes the image's blobs into the cache, skipping the ones it holds,
// and its manifest last. It returns the bytes it wrote, also on failure.
func (f *Filler) copy(ctx context.Context, p planned) (int64, error) {
	updates := make(chan v1.Update, 16)
	done := make(chan int64)
	go func() {
		var written int64
		for u := range updates {
			written = u.Complete
		}
		done <- written
	}()
	err := remote.Write(p.target, p.img, append(f.options(ctx), remote.WithProgress(updates), remote.WithJobs(4))...)
	written := <-done
	return written, err
}

// evict deletes the cache's images that no Config.Images entry wants, keeping
// any manifest a wanted tag points at, and reports whether it deleted any.
func (f *Filler) evict(ctx context.Context, wanted map[string]v1.Hash) bool {
	keep := map[v1.Hash]bool{}
	repos := map[string]name.Repository{}
	for ref, digest := range wanted {
		keep[digest] = true
		if r, err := name.ParseReference(ref, name.Insecure); err == nil {
			repos[r.Context().String()] = r.Context()
		}
	}
	// Every repository the cache holds, so one no Config.Images entry names
	// any more is emptied too.
	if registry, err := name.NewRegistry(f.Config.Registry, name.Insecure); err == nil {
		held, err := remote.Catalog(ctx, registry, f.Config.Remote...)
		if err != nil {
			f.Log.Error(err, "list the cache's repositories")
		}
		for _, n := range held {
			repo := registry.Repo(n)
			repos[repo.String()] = repo
		}
	}
	names := make([]string, 0, len(repos))
	for n := range repos {
		names = append(names, n)
	}
	sort.Strings(names)

	deleted := false
	for _, n := range names {
		repo := repos[n]
		tags, err := remote.List(repo, f.options(ctx)...)
		if isNotFound(err) {
			continue
		}
		if err != nil {
			f.Log.Error(err, "list the cache's tags", "repository", repo.String())
			continue
		}
		for _, tag := range tags {
			ref := repo.Tag(tag)
			if _, ok := wanted[ref.String()]; ok {
				continue
			}
			head, err := remote.Head(ref, f.options(ctx)...)
			if err != nil || keep[head.Digest] {
				continue
			}
			// The tag first: deleting a manifest by digest does not take the
			// tags pointing at it away in every registry.
			if err := remote.Delete(ref, f.options(ctx)...); err != nil {
				f.Log.Error(err, "evict an image the cache no longer wants", "image", ref.String())
				continue
			}
			if err := remote.Delete(repo.Digest(head.Digest.String()), f.options(ctx)...); err != nil && !isNotFound(err) {
				f.Log.Error(err, "evict an image the cache no longer wants", "image", ref.String(), "digest", head.Digest.String())
				continue
			}
			f.Log.Info("evicted an image the cache no longer wants", "image", ref.String(), "digest", head.Digest.String())
			deleted = true
		}
	}
	return deleted
}

// target is where source lives in the cache: the same repository and tag (or
// digest) under the cache's registry.
func (f *Filler) target(source name.Reference) (name.Reference, error) {
	repo := f.Config.Registry + "/" + source.Context().RepositoryStr()
	switch r := source.(type) {
	case name.Tag:
		return name.NewTag(repo+":"+r.TagStr(), name.Insecure)
	case name.Digest:
		return name.NewDigest(repo+"@"+r.DigestStr(), name.Insecure)
	default:
		return nil, fmt.Errorf("unsupported reference %s", source)
	}
}

func (f *Filler) options(ctx context.Context) []remote.Option {
	return append([]remote.Option{remote.WithContext(ctx)}, f.Config.Remote...)
}

func (f *Filler) recordFailure(st *state, image string, now time.Time) {
	fail := st.Failures[image]
	fail.Count++
	wait := f.Config.MinBackoff
	for i := 1; i < fail.Count && wait < f.Config.MaxBackoff; i++ {
		wait *= 2
	}
	if wait > f.Config.MaxBackoff {
		wait = f.Config.MaxBackoff
	}
	fail.Until = now.Add(wait)
	st.Failures[image] = fail
}

func (f *Filler) now() time.Time {
	if f.Now != nil {
		return f.Now().UTC()
	}
	return time.Now().UTC()
}

func (f *Filler) loadState(now time.Time) (*state, error) {
	st := &state{}
	raw, err := os.ReadFile(f.Config.StateFile)
	switch {
	case err == nil:
		if err := json.Unmarshal(raw, st); err != nil {
			return nil, fmt.Errorf("read %s: %w", f.Config.StateFile, err)
		}
	case !errors.Is(err, os.ErrNotExist):
		return nil, err
	}
	if day := now.Format(time.DateOnly); st.Day != day {
		st.Day = day
		st.Downloaded = 0
	}
	if st.Failures == nil {
		st.Failures = map[string]failure{}
	}
	return st, nil
}

func (f *Filler) saveState(st *state) error {
	raw, err := json.Marshal(st)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(f.Config.StateFile), 0o755); err != nil {
		return err
	}
	tmp := f.Config.StateFile + ".tmp"
	if err := os.WriteFile(tmp, raw, 0o644); err != nil {
		return err
	}
	return os.Rename(tmp, f.Config.StateFile)
}

func isNotFound(err error) bool {
	var terr *transport.Error
	return errors.As(err, &terr) && terr.StatusCode == http.StatusNotFound
}
