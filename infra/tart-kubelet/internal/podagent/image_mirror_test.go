package podagent

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/controller-runtime/pkg/client/fake"

	"github.com/tuist/tuist/infra/tart-kubelet/internal/tart"
)

const mirroredImage = "ghcr.io/tuist/tuist-runner:macos-26-6-0.32.0"

var testManifest = []byte(`{"schemaVersion":2,"mediaType":"application/vnd.oci.image.manifest.v1+json"}`)

func testManifestDigest() string {
	sum := sha256.Sum256(testManifest)
	return "sha256:" + hex.EncodeToString(sum[:])
}

// fakeMirror serves /v2/ and the test manifest for tuist/tuist-runner, the
// way a cache that holds the image answers.
func fakeMirror(t *testing.T, manifest http.HandlerFunc) *httptest.Server {
	t.Helper()
	mux := http.NewServeMux()
	mux.HandleFunc("/v2/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/v2/" {
			w.WriteHeader(http.StatusOK)
			return
		}
		if !strings.HasPrefix(r.URL.Path, "/v2/tuist/tuist-runner/manifests/") {
			http.NotFound(w, r)
			return
		}
		manifest(w, r)
	})
	srv := httptest.NewServer(mux)
	t.Cleanup(srv.Close)
	return srv
}

func servesManifest(w http.ResponseWriter, r *http.Request) {
	if r.Header.Get("Accept") != ociManifestMediaType {
		http.Error(w, "unexpected Accept", http.StatusBadRequest)
		return
	}
	w.Header().Set("Docker-Content-Digest", testManifestDigest())
	_, _ = w.Write(testManifest)
}

func mirrorFor(t *testing.T, srv *httptest.Server) ImageMirror {
	t.Helper()
	m, err := ParseImageMirror("ghcr.io=" + srv.URL)
	if err != nil {
		t.Fatal(err)
	}
	return m
}

func TestParseImageMirror(t *testing.T) {
	m, err := ParseImageMirror("ghcr.io=http://10.10.0.11:5000")
	if err != nil {
		t.Fatal(err)
	}
	if m.Upstream != "ghcr.io" || m.Endpoint.String() != "http://10.10.0.11:5000" || !m.insecure() {
		t.Fatalf("parsed %+v", m)
	}
	if m, err := ParseImageMirror("ghcr.io=https://images.example.com/"); err != nil || m.insecure() {
		t.Fatalf("an https endpoint must parse and not be insecure: %+v, %v", m, err)
	}
	for _, raw := range []string{"", "ghcr.io", "=http://x:5000", "ghcr.io=", "ghcr.io=10.10.0.11:5000", "ghcr.io=ftp://x", "ghcr.io=http://x/path"} {
		if _, err := ParseImageMirror(raw); err == nil {
			t.Errorf("ParseImageMirror(%q) accepted a malformed mirror", raw)
		}
	}
}

func TestSplitImageRef(t *testing.T) {
	for _, tc := range []struct {
		image                           string
		registry, repository, reference string
		ok                              bool
	}{
		{mirroredImage, "ghcr.io", "tuist/tuist-runner", "macos-26-6-0.32.0", true},
		{"ghcr.io/tuist/tuist-runner@sha256:abc", "ghcr.io", "tuist/tuist-runner", "sha256:abc", true},
		{"10.10.0.11:5000/tuist/tuist-runner:tag", "10.10.0.11:5000", "tuist/tuist-runner", "tag", true},
		{"tuist/tuist-runner:tag", "", "", "", false},
		{"ghcr.io/tuist/tuist-runner", "", "", "", false},
		{"img", "", "", "", false},
	} {
		registry, repository, reference, ok := splitImageRef(tc.image)
		if ok != tc.ok || registry != tc.registry || repository != tc.repository || reference != tc.reference {
			t.Errorf("splitImageRef(%q) = %q %q %q %v", tc.image, registry, repository, reference, ok)
		}
	}
}

// A cache that holds the image is pulled from by the digest it served, so
// the pull names exactly the manifest the probe saw, over plain HTTP.
func TestImageSourcesPullsFromAMirrorThatHoldsTheImage(t *testing.T) {
	srv := fakeMirror(t, servesManifest)
	mirror := mirrorFor(t, srv)
	s := &ImageSources{Mirrors: []ImageMirror{mirror}}

	pulls, err := s.sources(context.Background(), mirroredImage)
	if err != nil {
		t.Fatal(err)
	}
	want := mirror.Endpoint.Host + "/tuist/tuist-runner@" + testManifestDigest()
	if len(pulls) != 1 || pulls[0].ref != want || !pulls[0].insecure || pulls[0].mirror != srv.URL {
		t.Fatalf("pulls = %+v, want one insecure pull of %s", pulls, want)
	}
}

// Anything short of a mirror that holds the image leaves the upstream as
// the only source, which is what keeps the rack starting VMs when its
// storage node is down.
func TestImageSourcesFallsBackToTheUpstream(t *testing.T) {
	down := httptest.NewServer(http.NotFoundHandler())
	downURL := down.URL
	down.Close()

	for name, mirror := range map[string]func(t *testing.T) ImageMirror{
		"mirror down": func(t *testing.T) ImageMirror {
			m, err := ParseImageMirror("ghcr.io=" + downURL)
			if err != nil {
				t.Fatal(err)
			}
			return m
		},
		"image absent": func(t *testing.T) ImageMirror {
			return mirrorFor(t, fakeMirror(t, http.NotFound))
		},
		"mirror erroring": func(t *testing.T) ImageMirror {
			return mirrorFor(t, fakeMirror(t, func(w http.ResponseWriter, _ *http.Request) {
				http.Error(w, "boom", http.StatusInternalServerError)
			}))
		},
		"digest the body does not have": func(t *testing.T) ImageMirror {
			return mirrorFor(t, fakeMirror(t, func(w http.ResponseWriter, _ *http.Request) {
				w.Header().Set("Docker-Content-Digest", "sha256:"+strings.Repeat("0", 64))
				_, _ = w.Write(testManifest)
			}))
		},
	} {
		t.Run(name, func(t *testing.T) {
			s := &ImageSources{Mirrors: []ImageMirror{mirror(t)}, HTTP: &http.Client{Timeout: 2 * time.Second}}
			pulls, err := s.sources(context.Background(), mirroredImage)
			if err != nil {
				t.Fatalf("sources: %v", err)
			}
			if len(pulls) != 0 {
				t.Fatalf("pulls = %+v, want none so the upstream is pulled", pulls)
			}
		})
	}
}

func TestImageSourcesOnlyMirrorsTheirUpstream(t *testing.T) {
	srv := fakeMirror(t, servesManifest)
	s := &ImageSources{Mirrors: []ImageMirror{mirrorFor(t, srv)}}

	for _, image := range []string{"quay.io/tuist/tuist-runner:tag", "img", "tuist/tuist-runner:tag"} {
		pulls, err := s.sources(context.Background(), image)
		if err != nil || len(pulls) != 0 {
			t.Fatalf("sources(%q) = %+v, %v; want nothing to mirror", image, pulls, err)
		}
	}
	if pulls, err := (*ImageSources)(nil).sources(context.Background(), mirroredImage); err != nil || pulls != nil {
		t.Fatalf("a host without mirrors must pull from the upstream: %+v, %v", pulls, err)
	}
}

// A cache fetching the image holds the manifest request open until it has
// all of it. The host requeues instead of pulling the same image from the
// upstream beside it, and stops waiting once the sync timeout has passed.
func TestImageSourcesWaitsForASyncingMirrorThenGivesUp(t *testing.T) {
	release := make(chan struct{})
	srv := fakeMirror(t, func(w http.ResponseWriter, r *http.Request) {
		select {
		case <-release:
			servesManifest(w, r)
		case <-r.Context().Done():
		}
	})
	t.Cleanup(func() {
		select {
		case <-release:
		default:
			close(release)
		}
	})
	now := time.Date(2026, 10, 14, 15, 0, 0, 0, time.UTC)
	s := &ImageSources{
		Mirrors:     []ImageMirror{mirrorFor(t, srv)},
		HTTP:        &http.Client{Timeout: 100 * time.Millisecond},
		SyncTimeout: 30 * time.Minute,
		now:         func() time.Time { return now },
	}

	if _, err := s.sources(context.Background(), mirroredImage); !errors.Is(err, errMirrorSyncing) {
		t.Fatalf("first probe: err = %v, want errMirrorSyncing", err)
	}
	now = now.Add(29 * time.Minute)
	if _, err := s.sources(context.Background(), mirroredImage); !errors.Is(err, errMirrorSyncing) {
		t.Fatalf("probe within the timeout: err = %v, want errMirrorSyncing", err)
	}
	now = now.Add(time.Minute)
	pulls, err := s.sources(context.Background(), mirroredImage)
	if err != nil || len(pulls) != 0 {
		t.Fatalf("probe past the timeout = %+v, %v; want the upstream", pulls, err)
	}

	close(release)
	pulls, err = s.sources(context.Background(), mirroredImage)
	if err != nil || len(pulls) != 1 {
		t.Fatalf("probe once synced = %+v, %v; want the mirror", pulls, err)
	}
}

// fakeTartForGolden is a tart that has no golden yet, records every
// invocation, and fails pulls over plain HTTP when failInsecure is set.
func fakeTartForGolden(t *testing.T, failInsecure bool) (bin, log string) {
	t.Helper()
	dir := t.TempDir()
	log = filepath.Join(dir, "calls")
	fail := ""
	if failInsecure {
		fail = `if [ "$1" = pull ] && [ "$2" = --insecure ]; then echo 'connection reset' >&2; exit 1; fi` + "\n"
	}
	script := "#!/bin/sh\n" +
		"echo \"$@\" >> '" + log + "'\n" +
		"if [ \"$1\" = get ]; then echo 'the specified VM \"x\" does not exist' >&2; exit 1; fi\n" +
		fail +
		"exit 0\n"
	bin = filepath.Join(dir, "faketart")
	if err := os.WriteFile(bin, []byte(script), 0o755); err != nil {
		t.Fatal(err)
	}
	return bin, log
}

func tartCalls(t *testing.T, log string) []string {
	t.Helper()
	b, err := os.ReadFile(log)
	if err != nil {
		t.Fatal(err)
	}
	return strings.Split(strings.TrimSpace(string(b)), "\n")
}

// The golden keeps the name the Pod's image gives it wherever its bytes came
// from, so Node labels, affinity and the GC see nothing change.
func TestEnsureGoldenPullsThroughTheMirror(t *testing.T) {
	srv := fakeMirror(t, servesManifest)
	mirror := mirrorFor(t, srv)
	bin, log := fakeTartForGolden(t, false)
	r := &Reconciler{Tart: &tart.Client{Binary: bin}, Images: &ImageSources{Mirrors: []ImageMirror{mirror}}}

	name, materialized, err := r.ensureGolden(context.Background(), mirroredImage)
	if err != nil {
		t.Fatal(err)
	}
	if name != goldenVMName(mirroredImage) || !materialized {
		t.Fatalf("golden = %q materialized=%v, want %q", name, materialized, goldenVMName(mirroredImage))
	}
	ref := mirror.Endpoint.Host + "/tuist/tuist-runner@" + testManifestDigest()
	calls := tartCalls(t, log)
	want := []string{"get " + name + " --format json", "pull --insecure " + ref, "clone --insecure " + ref + " " + name}
	if strings.Join(calls, "\n") != strings.Join(want, "\n") {
		t.Fatalf("tart calls:\n%s\nwant:\n%s", strings.Join(calls, "\n"), strings.Join(want, "\n"))
	}
}

func TestEnsureGoldenFallsBackWhenTheMirrorPullFails(t *testing.T) {
	srv := fakeMirror(t, servesManifest)
	mirror := mirrorFor(t, srv)
	bin, log := fakeTartForGolden(t, true)
	r := &Reconciler{Tart: &tart.Client{Binary: bin}, Images: &ImageSources{Mirrors: []ImageMirror{mirror}}}

	name, _, err := r.ensureGolden(context.Background(), mirroredImage)
	if err != nil {
		t.Fatal(err)
	}
	calls := tartCalls(t, log)
	want := []string{
		"get " + name + " --format json",
		"pull --insecure " + mirror.Endpoint.Host + "/tuist/tuist-runner@" + testManifestDigest(),
		"pull " + mirroredImage,
		"clone " + mirroredImage + " " + name,
	}
	if strings.Join(calls, "\n") != strings.Join(want, "\n") {
		t.Fatalf("tart calls:\n%s\nwant:\n%s", strings.Join(calls, "\n"), strings.Join(want, "\n"))
	}
}

func TestEnsureGoldenRequeuesWhileTheMirrorSyncs(t *testing.T) {
	srv := fakeMirror(t, func(_ http.ResponseWriter, r *http.Request) { <-r.Context().Done() })
	bin, log := fakeTartForGolden(t, false)
	r := &Reconciler{Tart: &tart.Client{Binary: bin}, Images: &ImageSources{
		Mirrors: []ImageMirror{mirrorFor(t, srv)},
		HTTP:    &http.Client{Timeout: 100 * time.Millisecond},
	}}

	if _, _, err := r.ensureGolden(context.Background(), mirroredImage); !errors.Is(err, errMirrorSyncing) {
		t.Fatalf("err = %v, want errMirrorSyncing", err)
	}
	for _, call := range tartCalls(t, log) {
		if strings.HasPrefix(call, "pull") {
			t.Fatalf("pulled while the mirror was syncing: %q", call)
		}
	}
}

// An OCI entry pulled through a mirror is kept exactly as one pulled from
// the upstream would be.
func TestExpectedSetKeepsMirrorPulledImages(t *testing.T) {
	const node = "mini-1"
	pod := &corev1.Pod{
		ObjectMeta: metav1.ObjectMeta{Namespace: "tuist-runners", Name: "runner-xyz"},
		Spec: corev1.PodSpec{
			NodeName:   node,
			Containers: []corev1.Container{{Name: "runner", Image: mirroredImage}},
		},
	}
	scheme := runtime.NewScheme()
	if err := corev1.AddToScheme(scheme); err != nil {
		t.Fatal(err)
	}
	k := fake.NewClientBuilder().WithScheme(scheme).
		WithIndex(&corev1.Pod{}, "spec.nodeName", func(o client.Object) []string {
			return []string{o.(*corev1.Pod).Spec.NodeName}
		}).
		WithObjects(pod).Build()
	endpoint, _ := url.Parse("http://10.10.0.11:5000")
	c := &Collector{K8s: k, NodeName: node, Images: &ImageSources{Mirrors: []ImageMirror{{Upstream: "ghcr.io", Endpoint: endpoint}}}}

	expected, err := c.expectedSet(context.Background())
	if err != nil {
		t.Fatal(err)
	}
	listed := "10.10.0.11:5000/tuist/tuist-runner@" + testManifestDigest()
	if _, ok := expected.imageRepos[ociRepository(listed)]; !ok {
		t.Fatalf("mirror-pulled entry %q is not kept; kept %v", listed, expected.imageRepos)
	}
	if _, ok := expected.imageRepos["ghcr.io/tuist/tuist-runner"]; !ok {
		t.Fatalf("the upstream repository is no longer kept: %v", expected.imageRepos)
	}
}
