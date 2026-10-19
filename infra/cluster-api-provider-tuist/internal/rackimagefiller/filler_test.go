package rackimagefiller

import (
	"context"
	"io"
	"log"
	"net/http/httptest"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"github.com/go-logr/logr"
	"github.com/google/go-containerregistry/pkg/name"
	"github.com/google/go-containerregistry/pkg/registry"
	v1 "github.com/google/go-containerregistry/pkg/v1"
	"github.com/google/go-containerregistry/pkg/v1/empty"
	"github.com/google/go-containerregistry/pkg/v1/mutate"
	"github.com/google/go-containerregistry/pkg/v1/random"
	"github.com/google/go-containerregistry/pkg/v1/remote"
)

const gib = int64(1) << 30

// rack is an upstream registry and the cache's, both in memory.
type rack struct {
	upstream string
	cache    string
	state    string
	now      time.Time
	free     int64
}

func newRack(t *testing.T) *rack {
	t.Helper()
	up := httptest.NewServer(registry.New(registry.Logger(log.New(io.Discard, "", 0))))
	t.Cleanup(up.Close)
	cache := httptest.NewServer(registry.New(registry.Logger(log.New(io.Discard, "", 0))))
	t.Cleanup(cache.Close)
	return &rack{
		upstream: strings.TrimPrefix(up.URL, "http://"),
		cache:    strings.TrimPrefix(cache.URL, "http://"),
		state:    filepath.Join(t.TempDir(), "state.json"),
		now:      time.Date(2026, 10, 18, 9, 0, 0, 0, time.UTC),
		free:     100 * gib,
	}
}

func (r *rack) filler(images ...string) *Filler {
	return &Filler{
		Config: Config{
			Images:      images,
			Registry:    r.cache,
			StateFile:   r.state,
			FreeBytes:   func() (int64, error) { return r.free, nil },
			DailyBudget: 100 * gib,
			MinBackoff:  10 * time.Minute,
			MaxBackoff:  6 * time.Hour,
		},
		Log: logr.Discard(),
		Now: func() time.Time { return r.now },
	}
}

// push puts img upstream as repo:tag and returns its reference.
func (r *rack) push(t *testing.T, repoTag string, img v1.Image) string {
	t.Helper()
	ref := r.upstream + "/" + repoTag
	tag, err := name.NewTag(ref)
	if err != nil {
		t.Fatal(err)
	}
	if err := remote.Write(tag, img); err != nil {
		t.Fatal(err)
	}
	return ref
}

func (r *rack) cachedDigest(t *testing.T, repoTag string) (v1.Hash, bool) {
	t.Helper()
	tag, err := name.NewTag(r.cache + "/" + repoTag)
	if err != nil {
		t.Fatal(err)
	}
	desc, err := remote.Head(tag)
	if err != nil {
		return v1.Hash{}, false
	}
	return desc.Digest, true
}

func digestOf(t *testing.T, img v1.Image) v1.Hash {
	t.Helper()
	d, err := img.Digest()
	if err != nil {
		t.Fatal(err)
	}
	return d
}

func layers(t *testing.T, n int, size int64) []v1.Layer {
	t.Helper()
	var out []v1.Layer
	for range n {
		l, err := random.Layer(size, "application/vnd.cirruslabs.tart.disk.v2")
		if err != nil {
			t.Fatal(err)
		}
		out = append(out, l)
	}
	return out
}

func image(t *testing.T, ls ...v1.Layer) v1.Image {
	t.Helper()
	img, err := mutate.AppendLayers(empty.Image, ls...)
	if err != nil {
		t.Fatal(err)
	}
	return img
}

func pass(t *testing.T, f *Filler) Result {
	t.Helper()
	result, err := f.Pass(context.Background())
	if err != nil {
		t.Fatalf("Pass: %v", err)
	}
	return result
}

func TestCopiesTheWantedImagesWithTheUpstreamDigest(t *testing.T) {
	r := newRack(t)
	img := image(t, layers(t, 3, 1024)...)
	ref := r.push(t, "tuist/tuist-runner:macos-27-1-0.36.1", img)
	f := r.filler(ref)

	if got := pass(t, f)[ref]; got != Copied {
		t.Fatalf("first pass = %s, want %s", got, Copied)
	}
	if got, ok := r.cachedDigest(t, "tuist/tuist-runner:macos-27-1-0.36.1"); !ok || got != digestOf(t, img) {
		t.Fatalf("cache holds %v (%v), want the upstream digest %v", got, ok, digestOf(t, img))
	}
	if got := pass(t, f)[ref]; got != Held {
		t.Fatalf("second pass = %s, want %s with nothing to copy", got, Held)
	}
}

// A release rebuilds part of a disk: an image sharing blobs with one the
// cache holds is charged, and fetches, only the blobs it adds.
func TestChargesOnlyTheBlobsTheCacheLacks(t *testing.T) {
	r := newRack(t)
	shared := layers(t, 3, 4096)
	first := r.push(t, "tuist/tuist-runner:macos-27-1-0.36.0", image(t, shared...))
	second := r.push(t, "tuist/tuist-runner:macos-27-1-0.36.1", image(t, append(shared, layers(t, 1, 4096)...)...))

	pass(t, r.filler(first))
	before := r.downloaded(t)
	if got := pass(t, r.filler(first, second))[second]; got != Copied {
		t.Fatalf("second image = %s, want %s", got, Copied)
	}
	if charged := r.downloaded(t) - before; charged <= 0 || charged >= 3*4096 {
		t.Fatalf("charged %d bytes for one new 4 KiB layer beside three shared ones", charged)
	}
}

func (r *rack) downloaded(t *testing.T) int64 {
	t.Helper()
	st, err := (&Filler{Config: Config{StateFile: r.state}}).loadState(r.now)
	if err != nil {
		t.Fatal(err)
	}
	return st.Downloaded
}

// The incident this package exists for: an image that does not fit is never
// fetched at all, not fetched and thrown away on every pass.
func TestDoesNotFetchAnImageThatDoesNotFit(t *testing.T) {
	r := newRack(t)
	ref := r.push(t, "tuist/tuist-runner:macos-27-1-0.36.1", image(t, layers(t, 2, 8192)...))
	r.free = 8192
	f := r.filler(ref)
	f.Config.Reserve = 1024

	for range 3 {
		if got := pass(t, f)[ref]; got != NoSpace {
			t.Fatalf("pass = %s, want %s", got, NoSpace)
		}
	}
	if _, ok := r.cachedDigest(t, "tuist/tuist-runner:macos-27-1-0.36.1"); ok {
		t.Fatal("an image that does not fit was written to the cache")
	}
	if got := r.downloaded(t); got != 0 {
		t.Fatalf("downloaded %d bytes for an image that does not fit", got)
	}
}

// Room is made by deleting what the cache no longer wants, never what a
// wanted tag points at, and the copy waits for the registry to free it.
func TestEvictsWhatIsNoLongerWantedToMakeRoom(t *testing.T) {
	r := newRack(t)
	oldImg := image(t, layers(t, 2, 8192)...)
	old := r.push(t, "tuist/tuist-runner:macos-27-1-0.36.0", oldImg)
	keptImg := image(t, layers(t, 1, 1024)...)
	kept := r.push(t, "tuist/tuist-runner:macos-26-6-0.36.1", keptImg)
	// The same manifest under the tag a release re-tagged it with.
	aliasRef := r.push(t, "tuist/tuist-runner:macos-26-6-0.36.0", keptImg)
	pass(t, r.filler(old, kept, aliasRef))

	next := r.push(t, "tuist/tuist-runner:macos-27-1-0.36.1", image(t, layers(t, 2, 8192)...))
	r.free = 4096
	f := r.filler(next, kept)

	if got := pass(t, f)[next]; got != Evicting {
		t.Fatalf("pass = %s, want %s", got, Evicting)
	}
	if _, ok := r.cachedDigest(t, "tuist/tuist-runner:macos-27-1-0.36.0"); ok {
		t.Fatal("the image no longer wanted was kept")
	}
	for _, tag := range []string{"macos-26-6-0.36.1", "macos-26-6-0.36.0"} {
		if _, ok := r.cachedDigest(t, "tuist/tuist-runner:"+tag); !ok {
			t.Fatalf("%s was evicted, but a wanted tag points at its manifest", tag)
		}
	}

	r.free = 100 * gib
	if got := pass(t, f)[next]; got != Copied {
		t.Fatalf("pass once the registry freed the space = %s, want %s", got, Copied)
	}
}

func TestStaysWithinTheDailyBudget(t *testing.T) {
	r := newRack(t)
	ref := r.push(t, "tuist/tuist-runner:macos-27-1-0.36.1", image(t, layers(t, 2, 8192)...))
	f := r.filler(ref)
	f.Config.DailyBudget = 4096

	if got := pass(t, f)[ref]; got != OverBudget {
		t.Fatalf("pass = %s, want %s", got, OverBudget)
	}
	if _, ok := r.cachedDigest(t, "tuist/tuist-runner:macos-27-1-0.36.1"); ok {
		t.Fatal("an image over the budget was written to the cache")
	}

	r.now = r.now.Add(24 * time.Hour)
	f.Config.DailyBudget = 100 * gib
	if got := pass(t, f)[ref]; got != Copied {
		t.Fatalf("pass on the next day = %s, want %s", got, Copied)
	}
}

// A failing image waits, doubling, and the wait survives a restart.
func TestBacksOffAFailingImageAcrossRestarts(t *testing.T) {
	r := newRack(t)
	missing := r.upstream + "/tuist/tuist-runner:macos-27-1-0.99.0"

	if got := pass(t, r.filler(missing))[missing]; got != Failed {
		t.Fatalf("first pass = %s, want %s", got, Failed)
	}
	r.now = r.now.Add(5 * time.Minute)
	if got := pass(t, r.filler(missing))[missing]; got != BackingOff {
		t.Fatalf("pass 5m later, from a restarted filler = %s, want %s", got, BackingOff)
	}
	r.now = r.now.Add(10 * time.Minute)
	if got := pass(t, r.filler(missing))[missing]; got != Failed {
		t.Fatalf("pass after the first backoff = %s, want another attempt", got)
	}
	r.now = r.now.Add(15 * time.Minute)
	if got := pass(t, r.filler(missing))[missing]; got != BackingOff {
		t.Fatalf("pass 15m after the second failure = %s, want the doubled 20m wait", got)
	}
}

// When the volume holds only one, the image listed first wins.
func TestTheFirstImageWinsWhenOnlyOneFits(t *testing.T) {
	r := newRack(t)
	first := r.push(t, "tuist/tuist-runner:macos-27-1-0.36.1", image(t, layers(t, 1, 8192)...))
	second := r.push(t, "tuist/tuist-runner:macos-27-0-0.36.1", image(t, layers(t, 1, 8192)...))
	r.free = 12 * 1024
	f := &Filler{Config: r.filler().Config, Log: logr.Discard(), Now: func() time.Time { return r.now }}
	f.Config.Images = []string{first, second}
	f.Config.FreeBytes = func() (int64, error) {
		if _, ok := r.cachedDigest(t, "tuist/tuist-runner:macos-27-1-0.36.1"); ok {
			return r.free - 8192, nil
		}
		return r.free, nil
	}

	result := pass(t, f)
	if result[first] != Copied || result[second] != NoSpace {
		t.Fatalf("result = %v, want the first copied and the second without space", result)
	}
}

// A repository no wanted image lives in any more is emptied as well, not
// left holding space forever.
func TestEvictsRepositoriesNothingWantsAnyMore(t *testing.T) {
	r := newRack(t)
	dropped := r.push(t, "cirruslabs/debian:latest", image(t, layers(t, 2, 8192)...))
	pass(t, r.filler(dropped))

	next := r.push(t, "tuist/tuist-runner:macos-27-1-0.36.1", image(t, layers(t, 2, 8192)...))
	r.free = 4096
	if got := pass(t, r.filler(next))[next]; got != Evicting {
		t.Fatalf("pass = %s, want %s", got, Evicting)
	}
	if _, ok := r.cachedDigest(t, "cirruslabs/debian:latest"); ok {
		t.Fatal("an image in a repository nothing wants any more was kept")
	}
}
