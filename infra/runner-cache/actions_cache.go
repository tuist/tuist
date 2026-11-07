package cachevolumes

import (
	"context"
	"crypto/hmac"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"encoding/xml"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net"
	"net/http"
	"net/http/httputil"
	"net/url"
	"strconv"
	"strings"
	"sync"
	"time"
)

// GitHubResultsURL is the results service whose cache the mirror stands in for.
// Every other request to it passes through unchanged.
const GitHubResultsURL = "https://results-receiver.actions.githubusercontent.com"

const (
	actionsCacheService = "/twirp/github.actions.results.api.v1.CacheService/"
	actionsBlobPrefix   = "/actions-cache/blobs/"
	// ActionsHealthPath answers 200 while this host serves the cache. The runner's
	// node shim points jobs here only after it answered.
	ActionsHealthPath = "/actions-cache/healthz"
	actionsURLTTL     = 6 * time.Hour
	actionsServerWait = 5 * time.Second
)

// ActionsCaller is the runner Pod a request came from.
type ActionsCaller struct {
	PodName string
	PodUID  string
}

// ActionsEntry is a committed entry the index matched.
type ActionsEntry struct {
	ID        string `json:"id"`
	Key       string `json:"key"`
	SizeBytes int64  `json:"size_bytes"`
	// DownloadURL reads the copy in object storage; empty until one exists.
	DownloadURL string `json:"download_url"`
}

// ActionsUpload is where a committed entry is copied in object storage. An
// empty URL keeps it on this host only.
type ActionsUpload struct {
	URL      string `json:"upload_url"`
	Checksum string `json:"checksum"`
}

// ActionsIndex is the server's index of a repository's entries. It scopes
// every request by the job the caller's runner executes.
type ActionsIndex interface {
	Lookup(ctx context.Context, caller ActionsCaller, key string, restoreKeys []string, version string) (*ActionsEntry, error)
	// Reserve returns ErrConflict when the job's ref already holds key and version.
	Reserve(ctx context.Context, caller ActionsCaller, id, key, version string) error
	Commit(ctx context.Context, id string, size int64, sha256 string) (ActionsUpload, error)
	Stored(ctx context.Context, id string) error
}

// ActionsCache serves GitHub's cache v2 protocol to runner Pods on this host.
// Any failure answers as a miss or a refused save, never an error a client
// retries, so a job falls back to building what it would have restored.
type ActionsCache struct {
	Index ActionsIndex
	Store *ActionsStore
	// Caller resolves a request's source address to a live runner Pod here.
	Caller func(ctx context.Context, ip string) (ActionsCaller, error)
	// Upstream receives every request that is not a cache request.
	Upstream *url.URL
	// Client copies entries to and from object storage.
	Client *http.Client
	// Record counts an operation by result and the bytes it moved.
	Record func(operation, result string, bytes int64, start time.Time)
	Log    *slog.Logger

	once      sync.Once
	key       []byte
	proxy     *httputil.ReverseProxy
	mu        sync.Mutex
	saves     map[actionsSave]actionsPending
	remote    map[string]actionsRemote
	replicate chan actionsReplication
	fetches   chan actionsRemote
}

type actionsSave struct{ pod, key, version string }

type actionsPending struct {
	id    string
	since time.Time
}

type actionsRemote struct {
	id    string
	url   string
	size  int64
	until time.Time
}

type actionsReplication struct {
	id     string
	upload ActionsUpload
}

func (c *ActionsCache) init() {
	c.once.Do(func() {
		c.key = make([]byte, 32)
		if _, err := rand.Read(c.key); err != nil {
			panic(err)
		}
		upstream := c.Upstream
		if upstream == nil {
			upstream, _ = url.Parse(GitHubResultsURL)
		}
		c.proxy = &httputil.ReverseProxy{
			Rewrite: func(r *httputil.ProxyRequest) {
				r.SetURL(upstream)
				r.Out.Host = upstream.Host
			},
			FlushInterval: -1,
		}
		c.saves = map[actionsSave]actionsPending{}
		c.remote = map[string]actionsRemote{}
		c.replicate = make(chan actionsReplication, 256)
		c.fetches = make(chan actionsRemote, 256)
	})
}

// ActionsCachePath reports whether path belongs to the mirror.
func ActionsCachePath(path string) bool {
	return strings.HasPrefix(path, "/twirp/") || strings.HasPrefix(path, "/actions-cache/")
}

// Run copies committed entries to object storage and fetches entries other
// hosts saved, one at a time each, until ctx ends.
func (c *ActionsCache) Run(ctx context.Context) {
	c.init()
	go func() {
		for {
			select {
			case <-ctx.Done():
				return
			case job := <-c.replicate:
				c.copyOut(ctx, job)
			}
		}
	}()
	for {
		select {
		case <-ctx.Done():
			return
		case remote := <-c.fetches:
			c.fetch(ctx, remote)
		}
	}
}

func (c *ActionsCache) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	c.init()
	switch {
	case r.URL.Path == ActionsHealthPath && (r.Method == http.MethodGet || r.Method == http.MethodHead):
		w.WriteHeader(http.StatusOK)
	case strings.HasPrefix(r.URL.Path, actionsCacheService) && r.Method == http.MethodPost:
		c.serveTwirp(w, r, strings.TrimPrefix(r.URL.Path, actionsCacheService))
	case strings.HasPrefix(r.URL.Path, "/twirp/") && r.Method == http.MethodPost:
		start := time.Now()
		c.proxy.ServeHTTP(w, r)
		c.record("proxy", "ok", 0, start)
	case strings.HasPrefix(r.URL.Path, actionsBlobPrefix):
		c.serveBlob(w, r, strings.TrimPrefix(r.URL.Path, actionsBlobPrefix))
	default:
		http.NotFound(w, r)
	}
}

func (c *ActionsCache) serveTwirp(w http.ResponseWriter, r *http.Request, method string) {
	if method != "CreateCacheEntry" && method != "FinalizeCacheEntryUpload" && method != "GetCacheEntryDownloadURL" {
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusNotFound)
		json.NewEncoder(w).Encode(map[string]string{"code": "bad_route", "msg": "unsupported method"})
		return
	}
	var request struct {
		Key         string          `json:"key"`
		RestoreKeys []string        `json:"restore_keys"`
		Version     string          `json:"version"`
		RawSize     json.RawMessage `json:"size_bytes"`
	}
	answer := map[string]any{"ok": false}
	defer func() {
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(answer)
	}()
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 64<<10)).Decode(&request); err != nil {
		return
	}
	ctx, cancel := context.WithTimeout(r.Context(), actionsServerWait)
	defer cancel()
	ip, _, _ := net.SplitHostPort(r.RemoteAddr)
	caller, err := c.Caller(ctx, ip)
	if err != nil {
		c.record(actionsOperation(method), "unknown_caller", 0, time.Now())
		return
	}
	switch method {
	case "GetCacheEntryDownloadURL":
		c.lookup(ctx, r, caller, request.Key, request.RestoreKeys, request.Version, answer)
	case "CreateCacheEntry":
		c.reserve(ctx, r, caller, request.Key, request.Version, answer)
	case "FinalizeCacheEntryUpload":
		size, err := protoInt64(request.RawSize)
		if err == nil {
			c.finalize(ctx, caller, request.Key, request.Version, size, answer)
		}
	}
}

func (c *ActionsCache) lookup(ctx context.Context, r *http.Request, caller ActionsCaller, key string, restoreKeys []string, version string, answer map[string]any) {
	start := time.Now()
	entry, err := c.Index.Lookup(ctx, caller, key, restoreKeys, version)
	switch {
	case err != nil:
		c.fail("lookup", start, err)
		return
	case entry == nil:
		c.record("lookup", "miss", 0, start)
		return
	case c.Store.Has(entry.ID):
		c.record("lookup", "local", 0, start)
	case entry.DownloadURL != "":
		remote := actionsRemote{id: entry.ID, url: entry.DownloadURL, size: entry.SizeBytes, until: time.Now().Add(actionsURLTTL)}
		c.mu.Lock()
		c.remote[entry.ID] = remote
		c.mu.Unlock()
		select {
		case c.fetches <- remote:
		default:
		}
		c.record("lookup", "storage", 0, start)
	default:
		c.record("lookup", "elsewhere", 0, start)
		return
	}
	answer["ok"] = true
	answer["signed_download_url"] = c.blobURL(r, "d", entry.ID, caller)
	answer["matched_key"] = entry.Key
}

func (c *ActionsCache) reserve(ctx context.Context, r *http.Request, caller ActionsCaller, key, version string, answer map[string]any) {
	start := time.Now()
	id := newEntryID()
	err := c.Store.Begin(id)
	if err == nil {
		err = c.Index.Reserve(ctx, caller, id, key, version)
	}
	if errors.Is(err, ErrConflict) {
		c.Store.Remove(id)
		c.record("reserve", "exists", 0, start)
		answer["message"] = "cache entry already exists"
		return
	}
	if err != nil {
		c.Store.Remove(id)
		c.fail("reserve", start, err)
		return
	}
	c.mu.Lock()
	for save, pending := range c.saves {
		if time.Since(pending.since) > actionsURLTTL {
			delete(c.saves, save)
		}
	}
	c.saves[actionsSave{caller.PodUID, key, version}] = actionsPending{id: id, since: time.Now()}
	c.mu.Unlock()
	c.record("reserve", "ok", 0, start)
	answer["ok"] = true
	answer["signed_upload_url"] = c.blobURL(r, "u", id, caller)
}

func (c *ActionsCache) finalize(ctx context.Context, caller ActionsCaller, key, version string, size int64, answer map[string]any) {
	start := time.Now()
	save := actionsSave{caller.PodUID, key, version}
	c.mu.Lock()
	pending, ok := c.saves[save]
	delete(c.saves, save)
	c.mu.Unlock()
	if !ok {
		c.record("finalize", "unknown", 0, start)
		return
	}
	sum, err := c.Store.Seal(pending.id, size)
	if err != nil {
		c.Store.Remove(pending.id)
		c.fail("finalize", start, err)
		return
	}
	upload, err := c.Index.Commit(ctx, pending.id, size, sum)
	if err != nil {
		c.Store.Remove(pending.id)
		c.fail("finalize", start, err)
		return
	}
	if upload.URL != "" {
		select {
		case c.replicate <- actionsReplication{id: pending.id, upload: upload}:
		default:
		}
	}
	c.record("finalize", "ok", size, start)
	answer["ok"] = true
	answer["entry_id"] = actionsEntryNumber(pending.id)
}

// serveBlob implements the parts of Azure Blob Storage the cache clients use:
// Put Blob, Put Block and Put Block List to save, and ranged reads to restore.
func (c *ActionsCache) serveBlob(w http.ResponseWriter, r *http.Request, id string) {
	query := r.URL.Query()
	operation := query.Get("op")
	ip, _, _ := net.SplitHostPort(r.RemoteAddr)
	caller, err := c.Caller(r.Context(), ip)
	if err != nil || !c.validBlobURL(operation, id, query.Get("exp"), query.Get("sig"), caller) {
		http.Error(w, "AuthenticationFailed", http.StatusForbidden)
		return
	}
	switch {
	case operation == "u" && r.Method == http.MethodPut:
		c.serveUpload(w, r, id, query)
	case operation == "d" && (r.Method == http.MethodGet || r.Method == http.MethodHead):
		c.serveDownload(w, r, id)
	default:
		http.Error(w, "UnsupportedHttpVerb", http.StatusMethodNotAllowed)
	}
}

func (c *ActionsCache) serveUpload(w http.ResponseWriter, r *http.Request, id string, query url.Values) {
	// An upload can outlast the server's read timeout for metadata requests.
	controller := http.NewResponseController(w)
	_ = controller.SetReadDeadline(time.Now().Add(30 * time.Minute))
	_ = controller.SetWriteDeadline(time.Now().Add(30 * time.Minute))
	start := time.Now()
	var written int64
	var err error
	switch query.Get("comp") {
	case "":
		written, err = c.Store.PutBlob(r.Context(), id, r.Body)
	case "block":
		written, err = c.Store.PutBlock(r.Context(), id, query.Get("blockid"), r.Body)
	case "blocklist":
		var blocks []string
		blocks, err = blockList(io.LimitReader(r.Body, 8<<20))
		if err == nil {
			err = c.Store.CommitBlocks(r.Context(), id, blocks)
		}
	default:
		err = ErrActionsUpload
	}
	if err != nil {
		c.fail("upload", start, err)
		// Neither client retries a 4xx: a host that cannot take the entry
		// refuses the save at once.
		status := http.StatusBadRequest
		if errors.Is(err, ErrCapacity) {
			status = http.StatusRequestEntityTooLarge
		}
		http.Error(w, "InvalidInput", status)
		return
	}
	c.record("upload", "ok", written, start)
	w.Header().Set("ETag", `"`+id+`"`)
	w.Header().Set("Last-Modified", time.Now().UTC().Format(http.TimeFormat))
	w.Header().Set("x-ms-request-id", newEntryID())
	w.WriteHeader(http.StatusCreated)
}

func (c *ActionsCache) serveDownload(w http.ResponseWriter, r *http.Request, id string) {
	_ = http.NewResponseController(w).SetWriteDeadline(time.Now().Add(30 * time.Minute))
	if r.Header.Get("Range") == "" && r.Header.Get("x-ms-range") != "" {
		r.Header.Set("Range", r.Header.Get("x-ms-range"))
	}
	start := time.Now()
	if file, err := c.Store.Open(id); err == nil {
		defer file.Close()
		w.Header().Set("Content-Type", "application/octet-stream")
		w.Header().Set("ETag", `"`+id+`"`)
		http.ServeContent(w, r, "", time.Time{}, file)
		c.record("download", "local", contentLength(w), start)
		return
	}
	c.mu.Lock()
	remote, ok := c.remote[id]
	c.mu.Unlock()
	if !ok || time.Now().After(remote.until) {
		http.Error(w, "BlobNotFound", http.StatusNotFound)
		return
	}
	w.Header().Set("Content-Type", "application/octet-stream")
	w.Header().Set("Accept-Ranges", "bytes")
	w.Header().Set("ETag", `"`+id+`"`)
	if r.Method == http.MethodHead {
		w.Header().Set("Content-Length", strconv.FormatInt(remote.size, 10))
		w.WriteHeader(http.StatusOK)
		return
	}
	request, err := http.NewRequestWithContext(r.Context(), http.MethodGet, remote.url, nil)
	if err != nil {
		http.Error(w, "InternalError", http.StatusBadGateway)
		return
	}
	if ranges := r.Header.Get("Range"); ranges != "" {
		request.Header.Set("Range", ranges)
	}
	response, err := c.client().Do(request)
	if err != nil {
		c.fail("download", start, err)
		http.Error(w, "InternalError", http.StatusBadGateway)
		return
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK && response.StatusCode != http.StatusPartialContent {
		c.fail("download", start, &RemoteError{Operation: "download", StatusCode: response.StatusCode})
		http.Error(w, "BlobNotFound", http.StatusNotFound)
		return
	}
	for _, header := range []string{"Content-Length", "Content-Range"} {
		if value := response.Header.Get(header); value != "" {
			w.Header().Set(header, value)
		}
	}
	w.WriteHeader(response.StatusCode)
	written, _ := io.Copy(w, response.Body)
	c.record("download", "storage", written, start)
}

// copyOut uploads a committed entry to object storage, then tells the server.
func (c *ActionsCache) copyOut(ctx context.Context, job actionsReplication) {
	start := time.Now()
	err := func() error {
		file, err := c.Store.Open(job.id)
		if err != nil {
			return err
		}
		defer file.Close()
		info, err := file.Stat()
		if err != nil {
			return err
		}
		ctx, cancel := context.WithTimeout(ctx, time.Hour)
		defer cancel()
		request, err := http.NewRequestWithContext(ctx, http.MethodPut, job.upload.URL, file)
		if err != nil {
			return err
		}
		request.ContentLength = info.Size()
		if job.upload.Checksum != "" {
			request.Header.Set("x-amz-checksum-sha256", job.upload.Checksum)
		}
		response, err := c.client().Do(request)
		if err != nil {
			return err
		}
		io.Copy(io.Discard, io.LimitReader(response.Body, 64<<10))
		response.Body.Close()
		if response.StatusCode/100 != 2 {
			return &RemoteError{Operation: "upload", StatusCode: response.StatusCode}
		}
		stored, cancel := context.WithTimeout(ctx, 30*time.Second)
		defer cancel()
		return c.Index.Stored(stored, job.id)
	}()
	if err != nil {
		c.fail("replicate", start, err)
		return
	}
	c.record("replicate", "ok", 0, start)
}

// fetch copies an entry another host saved into this one's free space.
func (c *ActionsCache) fetch(ctx context.Context, remote actionsRemote) {
	if c.Store.Has(remote.id) || time.Now().After(remote.until) {
		return
	}
	start := time.Now()
	err := func() error {
		ctx, cancel := context.WithTimeout(ctx, time.Hour)
		defer cancel()
		request, err := http.NewRequestWithContext(ctx, http.MethodGet, remote.url, nil)
		if err != nil {
			return err
		}
		response, err := c.client().Do(request)
		if err != nil {
			return err
		}
		defer response.Body.Close()
		if response.StatusCode != http.StatusOK {
			return &RemoteError{Operation: "download", StatusCode: response.StatusCode}
		}
		return c.Store.Install(ctx, remote.id, remote.size, response.Body)
	}()
	if errors.Is(err, ErrCapacity) {
		c.record("fetch", "no_room", 0, start)
		return
	}
	if err != nil {
		c.fail("fetch", start, err)
		return
	}
	c.record("fetch", "ok", remote.size, start)
}

func (c *ActionsCache) client() *http.Client {
	if c.Client != nil {
		return c.Client
	}
	return http.DefaultClient
}

func (c *ActionsCache) record(operation, result string, bytes int64, start time.Time) {
	if c.Record != nil {
		c.Record(operation, result, bytes, start)
	}
}

func (c *ActionsCache) fail(operation string, start time.Time, err error) {
	c.record(operation, Result(err), 0, start)
	logger(c.Log).Warn("actions cache operation failed", "operation", operation, "error", signedURL.ReplaceAllString(err.Error(), "<url>"))
}

// blobURL is a link to entry id on this host for the caller, which the clients
// extend with Azure's `comp` and `blockid` parameters.
func (c *ActionsCache) blobURL(r *http.Request, operation, id string, caller ActionsCaller) string {
	expires := strconv.FormatInt(time.Now().Add(actionsURLTTL).Unix(), 10)
	query := url.Values{"op": {operation}, "exp": {expires}, "sig": {c.signature(operation, id, expires, caller)}}
	return (&url.URL{Scheme: "http", Host: r.Host, Path: actionsBlobPrefix + id, RawQuery: query.Encode()}).String()
}

func (c *ActionsCache) validBlobURL(operation, id, expires, signature string, caller ActionsCaller) bool {
	seconds, err := strconv.ParseInt(expires, 10, 64)
	if err != nil || time.Now().Unix() > seconds || !actionsEntryID.MatchString(id) {
		return false
	}
	expected := c.signature(operation, id, expires, caller)
	return hmac.Equal([]byte(expected), []byte(signature))
}

func (c *ActionsCache) signature(operation, id, expires string, caller ActionsCaller) string {
	mac := hmac.New(sha256.New, c.key)
	fmt.Fprintf(mac, "%s\n%s\n%s\n%s", operation, id, expires, caller.PodUID)
	return hex.EncodeToString(mac.Sum(nil))
}

func actionsOperation(method string) string {
	switch method {
	case "CreateCacheEntry":
		return "reserve"
	case "FinalizeCacheEntryUpload":
		return "finalize"
	default:
		return "lookup"
	}
}

// blockList reads a Put Block List body in order, whatever list each ID names.
func blockList(body io.Reader) ([]string, error) {
	decoder := xml.NewDecoder(body)
	var blocks []string
	for {
		token, err := decoder.Token()
		if err == io.EOF {
			return blocks, nil
		}
		if err != nil {
			return nil, ErrActionsUpload
		}
		start, ok := token.(xml.StartElement)
		if !ok || (start.Name.Local != "Latest" && start.Name.Local != "Committed" && start.Name.Local != "Uncommitted") {
			continue
		}
		var id string
		if err := decoder.DecodeElement(&id, &start); err != nil {
			return nil, ErrActionsUpload
		}
		blocks = append(blocks, strings.TrimSpace(id))
		if len(blocks) > actionsMaxBlocks {
			return nil, ErrActionsUpload
		}
	}
}

// protoInt64 reads an int64 the protobuf JSON mapping sends as a string or a number.
func protoInt64(raw json.RawMessage) (int64, error) {
	var text string
	if err := json.Unmarshal(raw, &text); err == nil {
		return strconv.ParseInt(text, 10, 64)
	}
	var number int64
	err := json.Unmarshal(raw, &number)
	return number, err
}

func contentLength(w http.ResponseWriter) int64 {
	length, _ := strconv.ParseInt(w.Header().Get("Content-Length"), 10, 64)
	return length
}

func newEntryID() string {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		panic(err)
	}
	b[6] = b[6]&0x0f | 0x40
	b[8] = b[8]&0x3f | 0x80
	return fmt.Sprintf("%x-%x-%x-%x-%x", b[0:4], b[4:6], b[6:8], b[8:10], b[10:16])
}

// actionsEntryNumber is the int64 entry ID the protocol answers a save with,
// derived from the entry's UUID. Clients only log it.
func actionsEntryNumber(id string) string {
	number, _ := strconv.ParseUint(strings.ReplaceAll(id, "-", "")[:15], 16, 64)
	return strconv.FormatUint(number, 10)
}
