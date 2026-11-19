package cachevolumes

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"testing"
	"time"
)

// fakeObjectStore stands in for the entry's store: it takes PUTs whose
// x-amz-checksum-sha256 matches the body, as Garage does, and serves ranged reads.
type fakeObjectStore struct {
	mu      sync.Mutex
	objects map[string][]byte
	status  int
	server  *httptest.Server
}

func newFakeObjectStore(t *testing.T) *fakeObjectStore {
	store := &fakeObjectStore{objects: map[string][]byte{}}
	store.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		store.mu.Lock()
		defer store.mu.Unlock()
		if store.status != 0 {
			w.WriteHeader(store.status)
			return
		}
		switch r.Method {
		case http.MethodPut:
			body, _ := io.ReadAll(r.Body)
			sum := sha256.Sum256(body)
			if r.Header.Get("x-amz-checksum-sha256") != base64.StdEncoding.EncodeToString(sum[:]) {
				w.WriteHeader(http.StatusBadRequest)
				return
			}
			store.objects[r.URL.Path] = body
		case http.MethodGet:
			object, ok := store.objects[r.URL.Path]
			if !ok {
				http.NotFound(w, r)
				return
			}
			http.ServeContent(w, r, "", time.Time{}, bytes.NewReader(object))
		}
	}))
	t.Cleanup(store.server.Close)
	return store
}

type fakeActionsIndex struct {
	mu       sync.Mutex
	store    *fakeObjectStore
	entries  map[string]*ActionsEntry // committed, by key
	reserved map[string]string        // id -> key
	sizes    map[string]int64         // id -> size
	err      error
	disabled map[string]bool // Pod UIDs whose account keeps GitHub's cache
	asked    int             // Enabled calls
}

func newFakeActionsIndex(store *fakeObjectStore) *fakeActionsIndex {
	return &fakeActionsIndex{store: store, entries: map[string]*ActionsEntry{}, reserved: map[string]string{}, sizes: map[string]int64{}}
}

func (f *fakeActionsIndex) Lookup(_ context.Context, _ ActionsCaller, key string, restoreKeys []string, _ string) (*ActionsEntry, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return nil, f.err
	}
	for _, candidate := range append([]string{key}, restoreKeys...) {
		for stored, entry := range f.entries {
			if strings.HasPrefix(stored, candidate) {
				return entry, nil
			}
		}
	}
	return nil, nil
}

func (f *fakeActionsIndex) Enabled(_ context.Context, caller ActionsCaller) (bool, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.asked++
	if f.err != nil {
		return false, f.err
	}
	return !f.disabled[caller.PodUID], nil
}

func (f *fakeActionsIndex) Reserve(_ context.Context, _ ActionsCaller, id, key, _ string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.err != nil {
		return f.err
	}
	if _, ok := f.entries[key]; ok {
		return ErrConflict
	}
	f.reserved[id] = key
	return nil
}

func (f *fakeActionsIndex) Upload(_ context.Context, id string, size int64, sum string) (ActionsUpload, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	digest, err := hex.DecodeString(sum)
	if err != nil {
		return ActionsUpload{}, err
	}
	f.sizes[id] = size
	return ActionsUpload{URL: f.store.server.URL + "/" + id, Checksum: base64.StdEncoding.EncodeToString(digest)}, nil
}

func (f *fakeActionsIndex) Commit(_ context.Context, id string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.store.mu.Lock()
	_, stored := f.store.objects["/"+id]
	f.store.mu.Unlock()
	if !stored {
		return &RemoteError{Operation: "commit", StatusCode: http.StatusConflict}
	}
	f.entries[f.reserved[id]] = &ActionsEntry{ID: id, Key: f.reserved[id], SizeBytes: f.sizes[id], DownloadURL: f.store.server.URL + "/" + id}
	return nil
}

func (f *fakeActionsIndex) committed(key string) bool {
	f.mu.Lock()
	defer f.mu.Unlock()
	_, ok := f.entries[key]
	return ok
}

type actionsHarness struct {
	t      *testing.T
	cache  *ActionsCache
	index  *fakeActionsIndex
	store  *fakeObjectStore
	server *httptest.Server
	free   uint64
	caller ActionsCaller
	// github stands in for GitHub's results service: it answers lookups with
	// githubAnswer and records what it was asked.
	github       *httptest.Server
	githubMu     sync.Mutex
	githubAnswer string
	githubAsked  []string
}

func newActionsHarness(t *testing.T, configure ...func(*ActionsCache)) *actionsHarness {
	store := newFakeObjectStore(t)
	h := &actionsHarness{t: t, store: store, index: newFakeActionsIndex(store), free: 1 << 40, caller: ActionsCaller{PodName: "pod", PodUID: "uid-1"}, githubAnswer: `{"ok":false}`}
	h.github = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		h.githubMu.Lock()
		defer h.githubMu.Unlock()
		h.githubAsked = append(h.githubAsked, fmt.Sprintf("%s %s %s", r.URL.Path, r.Header.Get("Authorization"), body))
		w.Header().Set("Content-Type", "application/json")
		fmt.Fprint(w, h.githubAnswer)
	}))
	t.Cleanup(h.github.Close)
	upstream, _ := url.Parse(h.github.URL)
	h.cache = &ActionsCache{
		Upstream: upstream,
		Index:    h.index,
		Store:    &ActionsStore{Root: t.TempDir(), Reserve: 1 << 20, FreeBytes: func(string) (uint64, error) { return h.free, nil }},
		StoreURL: store.server.URL,
		Caller: func(_ context.Context, ip string) (ActionsCaller, error) {
			if ip != "127.0.0.1" || h.caller.PodUID == "" {
				return ActionsCaller{}, errors.New("not a runner")
			}
			return h.caller, nil
		},
	}
	for _, apply := range configure {
		apply(h.cache)
	}
	h.server = httptest.NewServer(h.cache)
	t.Cleanup(h.server.Close)
	ctx, cancel := context.WithCancel(context.Background())
	t.Cleanup(cancel)
	go h.cache.Run(ctx)
	return h
}

// settle waits until the staged upload of every finalized save is gone, copied
// to the store or dropped.
func (h *actionsHarness) settle() {
	h.t.Helper()
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		uploads, _ := os.ReadDir(filepath.Join(h.cache.Store.Root, "uploads"))
		if len(uploads) == 0 {
			return
		}
		time.Sleep(10 * time.Millisecond)
	}
	h.t.Fatal("staged uploads were not copied")
}

func (h *actionsHarness) twirp(method string, body any) map[string]any {
	h.t.Helper()
	data, _ := json.Marshal(body)
	request, _ := http.NewRequest(http.MethodPost, h.server.URL+actionsCacheService+method, bytes.NewReader(data))
	request.Header.Set("Content-Type", "application/json")
	request.Header.Set("Authorization", "Bearer token")
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		h.t.Fatal(err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		h.t.Fatalf("%s answered %d", method, response.StatusCode)
	}
	var answer map[string]any
	if err := json.NewDecoder(response.Body).Decode(&answer); err != nil {
		h.t.Fatal(err)
	}
	return answer
}

func (h *actionsHarness) do(method, target string, body []byte, header map[string]string) *http.Response {
	h.t.Helper()
	request, _ := http.NewRequest(method, target, bytes.NewReader(body))
	for name, value := range header {
		request.Header.Set(name, value)
	}
	response, err := http.DefaultClient.Do(request)
	if err != nil {
		h.t.Fatal(err)
	}
	h.t.Cleanup(func() { response.Body.Close() })
	return response
}

func (h *actionsHarness) save(key string, content []byte) string {
	h.t.Helper()
	created := h.twirp("CreateCacheEntry", map[string]any{"key": key, "version": "v1"})
	if created["ok"] != true {
		h.t.Fatalf("reserve refused: %v", created)
	}
	upload := created["signed_upload_url"].(string)
	if response := h.do(http.MethodPut, upload, content, map[string]string{"x-ms-blob-type": "BlockBlob"}); response.StatusCode != http.StatusCreated {
		h.t.Fatalf("upload answered %d", response.StatusCode)
	}
	finalized := h.twirp("FinalizeCacheEntryUpload", map[string]any{"key": key, "version": "v1", "size_bytes": fmt.Sprint(len(content))})
	if finalized["ok"] != true {
		h.t.Fatalf("finalize refused: %v", finalized)
	}
	h.settle()
	return upload
}

func (h *actionsHarness) restore(key string, header map[string]string) (int, []byte) {
	h.t.Helper()
	found := h.twirp("GetCacheEntryDownloadURL", map[string]any{"key": key, "restore_keys": []string{}, "version": "v1"})
	if found["ok"] != true {
		return 0, nil
	}
	response := h.do(http.MethodGet, found["signed_download_url"].(string), nil, header)
	data, _ := io.ReadAll(response.Body)
	return response.StatusCode, data
}

func TestActionsCacheSavesAndRestoresAnEntry(t *testing.T) {
	h := newActionsHarness(t)
	content := bytes.Repeat([]byte("cache"), 1000)
	h.save("deps-linux", content)

	status, data := h.restore("deps-linux", nil)
	if status != http.StatusOK || !bytes.Equal(data, content) {
		t.Fatalf("restored %d with %d bytes", status, len(data))
	}
	status, data = h.restore("deps", map[string]string{"x-ms-range": "bytes=5-9"})
	if status != http.StatusPartialContent || string(data) != "cache" {
		t.Fatalf("ranged restore answered %d %q", status, data)
	}
	if uploads, _ := os.ReadDir(filepath.Join(h.cache.Store.Root, "uploads")); len(uploads) != 0 {
		t.Fatalf("kept %d staged uploads after the copy", len(uploads))
	}
}

func TestActionsCacheAssemblesStagedBlocksInListOrder(t *testing.T) {
	h := newActionsHarness(t)
	created := h.twirp("CreateCacheEntry", map[string]any{"key": "layer", "version": "v1"})
	upload := created["signed_upload_url"].(string)
	first, second, unlisted := base64.StdEncoding.EncodeToString([]byte("block-1")), base64.StdEncoding.EncodeToString([]byte("block-2")), base64.StdEncoding.EncodeToString([]byte("block-3"))
	for id, content := range map[string]string{second: "world", first: "hello ", unlisted: "dropped"} {
		if response := h.do(http.MethodPut, upload+"&comp=block&blockid="+url.QueryEscape(id), []byte(content), nil); response.StatusCode != http.StatusCreated {
			t.Fatalf("block answered %d", response.StatusCode)
		}
	}
	// A list may name a block twice and leave staged blocks out.
	list := fmt.Sprintf(`<?xml version="1.0" encoding="utf-8"?><BlockList><Latest>%s</Latest><Latest>%s</Latest><Latest>%s</Latest></BlockList>`, first, second, first)
	if response := h.do(http.MethodPut, upload+"&comp=blocklist", []byte(list), nil); response.StatusCode != http.StatusCreated {
		t.Fatalf("block list answered %d", response.StatusCode)
	}
	if answer := h.twirp("FinalizeCacheEntryUpload", map[string]any{"key": "layer", "version": "v1", "size_bytes": 17}); answer["ok"] != true {
		t.Fatalf("finalize refused: %v", answer)
	}
	h.settle()
	// The store refuses a PUT whose body does not match the digest.
	if _, data := h.restore("layer", nil); string(data) != "hello worldhello " {
		t.Fatalf("restored %q", data)
	}
	if uploads, _ := os.ReadDir(filepath.Join(h.cache.Store.Root, "uploads")); len(uploads) != 0 {
		t.Fatalf("kept %d staged uploads after the copy", len(uploads))
	}
}

func TestActionsCacheRefusesAnExistingKeyAndAWrongSize(t *testing.T) {
	h := newActionsHarness(t)
	h.save("deps", []byte("one"))
	if answer := h.twirp("CreateCacheEntry", map[string]any{"key": "deps", "version": "v1"}); answer["ok"] != false || answer["message"] == nil {
		t.Fatalf("reserved an existing key: %v", answer)
	}

	created := h.twirp("CreateCacheEntry", map[string]any{"key": "other", "version": "v1"})
	h.do(http.MethodPut, created["signed_upload_url"].(string), []byte("abc"), nil)
	if answer := h.twirp("FinalizeCacheEntryUpload", map[string]any{"key": "other", "version": "v1", "size_bytes": "4"}); answer["ok"] != false {
		t.Fatalf("finalized a short upload: %v", answer)
	}
	if answer := h.twirp("GetCacheEntryDownloadURL", map[string]any{"key": "other", "version": "v1"}); answer["ok"] != false {
		t.Fatalf("restored an unfinished save: %v", answer)
	}
}

func TestActionsCacheMissesWhenTheIndexOrCallerFails(t *testing.T) {
	h := newActionsHarness(t)
	h.save("deps", []byte("one"))
	h.index.err = errors.New("server down")
	if answer := h.twirp("GetCacheEntryDownloadURL", map[string]any{"key": "deps", "version": "v1"}); answer["ok"] != false {
		t.Fatalf("answered without the index: %v", answer)
	}
	if answer := h.twirp("CreateCacheEntry", map[string]any{"key": "new", "version": "v1"}); answer["ok"] != false {
		t.Fatalf("reserved without the index: %v", answer)
	}
	h.index.err = nil
	h.caller = ActionsCaller{}
	if answer := h.twirp("GetCacheEntryDownloadURL", map[string]any{"key": "deps", "version": "v1"}); answer["ok"] != false {
		t.Fatalf("answered an unknown caller: %v", answer)
	}
}

func TestActionsCacheLinksAreBoundToTheirPod(t *testing.T) {
	h := newActionsHarness(t)
	h.save("deps", []byte("one"))
	found := h.twirp("GetCacheEntryDownloadURL", map[string]any{"key": "deps", "version": "v1"})
	link := found["signed_download_url"].(string)

	h.caller = ActionsCaller{PodName: "other", PodUID: "uid-2"}
	if response := h.do(http.MethodGet, link, nil, nil); response.StatusCode != http.StatusForbidden {
		t.Fatalf("another pod read the entry: %d", response.StatusCode)
	}
	h.caller = ActionsCaller{PodName: "pod", PodUID: "uid-1"}
	if response := h.do(http.MethodGet, strings.Replace(link, "op=d", "op=u", 1), []byte("x"), nil); response.StatusCode != http.StatusForbidden {
		t.Fatalf("a download link was accepted for an upload: %d", response.StatusCode)
	}
}

func TestActionsCachePassesOtherResultsRequestsToGitHub(t *testing.T) {
	upstream := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		fmt.Fprintf(w, "%s %s %s", r.URL.Path, r.Header.Get("Authorization"), body)
	}))
	defer upstream.Close()
	h := newActionsHarness(t, func(c *ActionsCache) { c.Upstream, _ = url.Parse(upstream.URL) })

	path := "/twirp/github.actions.results.api.v1.ArtifactService/CreateArtifact"
	response := h.do(http.MethodPost, h.server.URL+path, []byte(`{"name":"logs"}`), map[string]string{"Authorization": "Bearer token"})
	data, _ := io.ReadAll(response.Body)
	if string(data) != path+` Bearer token {"name":"logs"}` {
		t.Fatalf("upstream saw %q", data)
	}
	response = h.do(http.MethodPost, h.server.URL+actionsCacheService+"ListCacheEntries", []byte(`{}`), nil)
	if response.StatusCode != http.StatusNotFound {
		t.Fatalf("an unsupported cache method answered %d", response.StatusCode)
	}
}

func TestActionsCacheDoesNotCommitAnEntryTheStoreRefused(t *testing.T) {
	h := newActionsHarness(t)
	h.store.status = http.StatusForbidden // Garage's answer once the bucket quota is reached
	h.save("deps", []byte("payload"))

	if h.index.committed("deps") {
		t.Fatal("committed an entry the store refused")
	}
	if answer := h.twirp("GetCacheEntryDownloadURL", map[string]any{"key": "deps", "version": "v1"}); answer["ok"] != false {
		t.Fatalf("restored an entry the store refused: %v", answer)
	}
}

func TestActionsCacheHealthFollowsTheStore(t *testing.T) {
	h := newActionsHarness(t)
	health := func() int {
		response := h.do(http.MethodGet, h.server.URL+ActionsHealthPath, nil, nil)
		return response.StatusCode
	}
	deadline := time.Now().Add(5 * time.Second)
	for health() != http.StatusOK && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if status := health(); status != http.StatusOK {
		t.Fatalf("health answered %d with the store up", status)
	}

	h.cache.reachable.Store(time.Now().Add(-time.Minute).UnixNano())
	h.store.server.Close()
	h.cache.probe(context.Background())
	if status := health(); status != http.StatusServiceUnavailable {
		t.Fatalf("health answered %d with the store down", status)
	}
}

func TestActionsCacheHealthOnlyAnswersForEnabledAccounts(t *testing.T) {
	h := newActionsHarness(t)
	h.cache.reachable.Store(time.Now().UnixNano())
	health := func() int {
		return h.do(http.MethodGet, h.server.URL+ActionsHealthPath, nil, nil).StatusCode
	}
	// Until the server answers, such as for a job GitHub has not reported yet,
	// the job stays on GitHub's cache and the next probe asks again.
	h.index.err = errors.New("execution pending")
	if status := health(); status != http.StatusServiceUnavailable {
		t.Fatalf("health answered %d without the server's answer", status)
	}
	h.index.err = nil
	h.index.disabled = map[string]bool{"uid-1": true}
	waitFor := func(want int) {
		t.Helper()
		deadline := time.Now().Add(5 * time.Second)
		for health() != want && time.Now().Before(deadline) {
			time.Sleep(10 * time.Millisecond)
		}
		if status := health(); status != want {
			t.Fatalf("health answered %d, want %d", status, want)
		}
	}
	waitFor(http.StatusServiceUnavailable)

	h.caller = ActionsCaller{PodName: "other", PodUID: "uid-2"}
	waitFor(http.StatusOK)
	h.index.mu.Lock()
	asked := h.index.asked
	h.index.mu.Unlock()
	health()
	h.index.mu.Lock()
	defer h.index.mu.Unlock()
	if h.index.asked != asked {
		t.Fatal("asked the server again for a Pod it already answered for")
	}
}

func TestActionsCacheAsksGitHubWhatTheMirrorMisses(t *testing.T) {
	h := newActionsHarness(t)
	h.save("deps-new", []byte("mirror"))
	h.githubAnswer = `{"ok":true,"signed_download_url":"https://github.example/blob","matched_key":"deps-old"}`

	if answer := h.twirp("GetCacheEntryDownloadURL", map[string]any{"key": "deps-new", "version": "v1"}); !strings.HasPrefix(answer["signed_download_url"].(string), h.server.URL) {
		t.Fatalf("a mirror hit was not served by the mirror: %v", answer)
	}
	if len(h.githubAsked) != 0 {
		t.Fatalf("asked GitHub about a mirror hit: %v", h.githubAsked)
	}

	request := map[string]any{"key": "deps-old", "restore_keys": []string{"old-"}, "version": "v2"}
	answer := h.twirp("GetCacheEntryDownloadURL", request)
	if answer["signed_download_url"] != "https://github.example/blob" || answer["matched_key"] != "deps-old" {
		t.Fatalf("a miss was not answered from GitHub: %v", answer)
	}
	sent, _ := json.Marshal(request)
	if want := actionsCacheService + "GetCacheEntryDownloadURL Bearer token " + string(sent); h.githubAsked[0] != want {
		t.Fatalf("GitHub was asked %q, want %q", h.githubAsked[0], want)
	}

	h.index.err = errors.New("server down")
	if answer := h.twirp("GetCacheEntryDownloadURL", map[string]any{"key": "deps-new", "version": "v1"}); answer["matched_key"] != "deps-old" {
		t.Fatalf("a lookup the index could not answer was not asked of GitHub: %v", answer)
	}
	h.index.err = nil

	h.github.Close()
	if answer := h.twirp("GetCacheEntryDownloadURL", map[string]any{"key": "deps-old", "version": "v1"}); answer["ok"] != false {
		t.Fatalf("an unreachable GitHub did not answer a miss: %v", answer)
	}
}

func TestActionsCacheRefusesAnUploadWithoutRoom(t *testing.T) {
	h := newActionsHarness(t)
	created := h.twirp("CreateCacheEntry", map[string]any{"key": "deps", "version": "v1"})
	h.free = 1 << 10
	if response := h.do(http.MethodPut, created["signed_upload_url"].(string), []byte("data"), nil); response.StatusCode != http.StatusRequestEntityTooLarge {
		t.Fatalf("upload without room answered %d", response.StatusCode)
	}
}

func TestActionsStoreMaintenanceRemovesAbandonedUploads(t *testing.T) {
	root := t.TempDir()
	store := &ActionsStore{Root: root, FreeBytes: func(string) (uint64, error) { return 1 << 40, nil }}
	abandoned, fresh := newEntryID(), newEntryID()
	store.Begin(abandoned)
	store.Begin(fresh)
	hourAgo := time.Now().Add(-2 * time.Hour)
	os.Chtimes(filepath.Join(root, "uploads", abandoned), hourAgo, hourAgo)

	if err := store.Maintain(); err != nil {
		t.Fatal(err)
	}
	if _, err := os.Stat(filepath.Join(root, "uploads", abandoned)); !os.IsNotExist(err) {
		t.Fatalf("abandoned upload kept: %v", err)
	}
	if _, err := os.Stat(filepath.Join(root, "uploads", fresh)); err != nil {
		t.Fatalf("fresh upload removed: %v", err)
	}
}
