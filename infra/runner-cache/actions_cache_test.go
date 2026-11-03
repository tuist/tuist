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

type fakeActionsIndex struct {
	mu        sync.Mutex
	entries   map[string]*ActionsEntry // by key
	reserved  map[string]string        // id -> key
	committed map[string]string        // id -> sha256
	stored    []string
	upload    ActionsUpload
	err       error
}

func newFakeActionsIndex() *fakeActionsIndex {
	return &fakeActionsIndex{entries: map[string]*ActionsEntry{}, reserved: map[string]string{}, committed: map[string]string{}}
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

func (f *fakeActionsIndex) Commit(_ context.Context, id string, size int64, sum string) (ActionsUpload, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.committed[id] = sum
	f.entries[f.reserved[id]] = &ActionsEntry{ID: id, Key: f.reserved[id], SizeBytes: size}
	return f.upload, nil
}

func (f *fakeActionsIndex) Stored(_ context.Context, id string) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.stored = append(f.stored, id)
	return nil
}

type actionsHarness struct {
	t      *testing.T
	cache  *ActionsCache
	index  *fakeActionsIndex
	server *httptest.Server
	free   uint64
	caller ActionsCaller
}

func newActionsHarness(t *testing.T) *actionsHarness {
	h := &actionsHarness{t: t, index: newFakeActionsIndex(), free: 1 << 40, caller: ActionsCaller{PodName: "pod", PodUID: "uid-1"}}
	h.cache = &ActionsCache{
		Index: h.index,
		Store: &ActionsStore{Root: t.TempDir(), Reserve: 1 << 20, FreeBytes: func(string) (uint64, error) { return h.free, nil }},
		Caller: func(_ context.Context, ip string) (ActionsCaller, error) {
			if ip != "127.0.0.1" || h.caller.PodUID == "" {
				return ActionsCaller{}, errors.New("not a runner")
			}
			return h.caller, nil
		},
	}
	h.server = httptest.NewServer(h.cache)
	t.Cleanup(h.server.Close)
	return h
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
	sum := sha256.Sum256(content)
	for _, recorded := range h.index.committed {
		if recorded != hex.EncodeToString(sum[:]) {
			t.Fatalf("committed digest %s", recorded)
		}
	}
}

func TestActionsCacheAssemblesStagedBlocksInListOrder(t *testing.T) {
	h := newActionsHarness(t)
	created := h.twirp("CreateCacheEntry", map[string]any{"key": "layer", "version": "v1"})
	upload := created["signed_upload_url"].(string)
	first, second := base64.StdEncoding.EncodeToString([]byte("block-1")), base64.StdEncoding.EncodeToString([]byte("block-2"))
	for id, content := range map[string]string{second: "world", first: "hello "} {
		if response := h.do(http.MethodPut, upload+"&comp=block&blockid="+url.QueryEscape(id), []byte(content), nil); response.StatusCode != http.StatusCreated {
			t.Fatalf("block answered %d", response.StatusCode)
		}
	}
	list := fmt.Sprintf(`<?xml version="1.0" encoding="utf-8"?><BlockList><Latest>%s</Latest><Latest>%s</Latest></BlockList>`, first, second)
	if response := h.do(http.MethodPut, upload+"&comp=blocklist", []byte(list), nil); response.StatusCode != http.StatusCreated {
		t.Fatalf("block list answered %d", response.StatusCode)
	}
	if answer := h.twirp("FinalizeCacheEntryUpload", map[string]any{"key": "layer", "version": "v1", "size_bytes": 11}); answer["ok"] != true {
		t.Fatalf("finalize refused: %v", answer)
	}
	if _, data := h.restore("layer", nil); string(data) != "hello world" {
		t.Fatalf("restored %q", data)
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
	h := newActionsHarness(t)
	h.cache.Upstream, _ = url.Parse(upstream.URL)

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

func TestActionsCacheServesAndFetchesAnEntryAnotherHostSaved(t *testing.T) {
	content := []byte("0123456789")
	storage := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		http.ServeContent(w, r, "", time.Time{}, bytes.NewReader(content))
	}))
	defer storage.Close()
	h := newActionsHarness(t)
	id := newEntryID()
	h.index.entries["deps"] = &ActionsEntry{ID: id, Key: "deps", SizeBytes: int64(len(content)), DownloadURL: storage.URL + "/object"}

	found := h.twirp("GetCacheEntryDownloadURL", map[string]any{"key": "deps", "version": "v1"})
	link := found["signed_download_url"].(string)
	if response := h.do(http.MethodHead, link, nil, nil); response.ContentLength != int64(len(content)) {
		t.Fatalf("HEAD reported %d bytes", response.ContentLength)
	}
	response := h.do(http.MethodGet, link, nil, map[string]string{"Range": "bytes=2-4"})
	data, _ := io.ReadAll(response.Body)
	if response.StatusCode != http.StatusPartialContent || string(data) != "234" {
		t.Fatalf("ranged read answered %d %q", response.StatusCode, data)
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go h.cache.Run(ctx)
	deadline := time.Now().Add(5 * time.Second)
	for !h.cache.Store.Has(id) && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if file, err := h.cache.Store.Open(id); err != nil {
		t.Fatalf("background fetch installed nothing: %v", err)
	} else if data, _ := io.ReadAll(file); !bytes.Equal(data, content) {
		t.Fatalf("installed %q", data)
	}
}

func TestActionsCacheCopiesCommittedEntriesToStorage(t *testing.T) {
	var received []byte
	var checksum string
	storage := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		received, _ = io.ReadAll(r.Body)
		checksum = r.Header.Get("x-amz-checksum-sha256")
	}))
	defer storage.Close()
	h := newActionsHarness(t)
	h.index.upload = ActionsUpload{URL: storage.URL + "/object", Checksum: "c2hh"}
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	go h.cache.Run(ctx)

	h.save("deps", []byte("payload"))
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		h.index.mu.Lock()
		stored := len(h.index.stored)
		h.index.mu.Unlock()
		if stored == 1 {
			break
		}
		time.Sleep(10 * time.Millisecond)
	}
	if string(received) != "payload" || checksum != "c2hh" || len(h.index.stored) != 1 {
		t.Fatalf("storage received %q with checksum %q, stored %v", received, checksum, h.index.stored)
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

func TestActionsStoreShedsLeastRecentlyUsedEntriesFirst(t *testing.T) {
	root := t.TempDir()
	free := uint64(0)
	store := &ActionsStore{Root: root, FreeBytes: func(string) (uint64, error) { return free, nil }}
	if err := os.MkdirAll(filepath.Join(root, "entries"), 0o700); err != nil {
		t.Fatal(err)
	}
	old, recent := newEntryID(), newEntryID()
	for i, id := range []string{old, recent} {
		path := filepath.Join(root, "entries", id)
		os.WriteFile(path, []byte("x"), 0o600)
		used := time.Now().Add(time.Duration(i-2) * time.Hour)
		os.Chtimes(path, used, used)
	}
	store.FreeBytes = func(string) (uint64, error) {
		if !store.Has(old) {
			free = 100
		}
		return free, nil
	}
	if !store.Shed(context.Background(), 100) {
		t.Fatal("shed nothing")
	}
	if store.Has(old) || !store.Has(recent) {
		t.Fatalf("shed the wrong entry: old=%v recent=%v", store.Has(old), store.Has(recent))
	}
}

func TestActionsStoreMaintenanceRemovesIdleEntriesAndAbandonedUploads(t *testing.T) {
	root := t.TempDir()
	store := &ActionsStore{Root: root, FreeBytes: func(string) (uint64, error) { return 1 << 40, nil }}
	idle, fresh, abandoned := newEntryID(), newEntryID(), newEntryID()
	os.MkdirAll(filepath.Join(root, "entries"), 0o700)
	for _, id := range []string{idle, fresh} {
		os.WriteFile(filepath.Join(root, "entries", id), []byte("x"), 0o600)
	}
	week := time.Now().Add(-8 * 24 * time.Hour)
	os.Chtimes(filepath.Join(root, "entries", idle), week, week)
	store.Begin(abandoned)
	os.Chtimes(filepath.Join(root, "uploads", abandoned), week, week)

	if err := store.Maintain(); err != nil {
		t.Fatal(err)
	}
	if store.Has(idle) || !store.Has(fresh) {
		t.Fatalf("idle=%v fresh=%v", store.Has(idle), store.Has(fresh))
	}
	if _, err := os.Stat(filepath.Join(root, "uploads", abandoned)); !os.IsNotExist(err) {
		t.Fatalf("abandoned upload kept: %v", err)
	}
}
