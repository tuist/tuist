// Package blobcache keeps a node's copy of large remote-execution input blobs
// and serves byte ranges of them to execution guests over vsock, so the CAS
// sends each blob to a node once instead of once per action.
package blobcache

import (
	"container/list"
	"context"
	"crypto/sha256"
	"crypto/tls"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	bs "google.golang.org/genproto/googleapis/bytestream"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
)

// MaxBlob matches the executor's per-blob bound.
const MaxBlob = 1 << 30

// fillTimeout bounds one CAS download. It does not depend on the requesting
// action, whose cancellation must not fail the other actions waiting on it.
const fillTimeout = 5 * time.Minute

var (
	ErrInvalid = errors.New("invalid blob request")
	// ErrFull means every cached byte belongs to a download in flight; the
	// guest reads that blob from the CAS itself.
	ErrFull = errors.New("blob cache full")
)

// Scope is what an action may read: one project's CAS, with that project's
// credential. Cached blobs are never shared across scopes, so a cache hit
// grants nothing the credential would not.
type Scope struct {
	Endpoint string
	Account  string
	Instance string
	Token    string
}

func (s Scope) key() string {
	h := sha256.Sum256([]byte(s.Endpoint + "\n" + s.Account + "\n" + s.Instance))
	return hex.EncodeToString(h[:16])
}

type entry struct {
	key   string
	path  string
	size  int64
	ready chan struct{}
	err   error
	elem  *list.Element // in lru once ready
}

type Metrics struct {
	Requests     *prometheus.CounterVec
	FetchedBytes prometheus.Counter
	Bytes        prometheus.Gauge
}

func NewMetrics(registry prometheus.Registerer) *Metrics {
	m := &Metrics{
		Requests: prometheus.NewCounterVec(prometheus.CounterOpts{
			Name: "sandboxd_blob_cache_requests_total", Help: "Guest blob reads by outcome: hit, miss (downloaded or waited for a download) or error.",
		}, []string{"result"}),
		FetchedBytes: prometheus.NewCounter(prometheus.CounterOpts{
			Name: "sandboxd_blob_cache_fetched_bytes_total", Help: "Bytes the blob cache downloaded from CAS endpoints.",
		}),
		Bytes: prometheus.NewGauge(prometheus.GaugeOpts{
			Name: "sandboxd_blob_cache_bytes", Help: "Bytes held or reserved by the blob cache.",
		}),
	}
	if registry != nil {
		registry.MustRegister(m.Requests, m.FetchedBytes, m.Bytes)
	}
	return m
}

type Cache struct {
	dir     string
	budget  int64
	log     *slog.Logger
	metrics *Metrics
	// Dial opens a CAS connection; tests replace it.
	Dial func(endpoint string) (*grpc.ClientConn, error)

	mu      sync.Mutex
	entries map[string]*entry
	lru     list.List // ready entries, least recently used first
	used    int64     // ready and reserved bytes
	conns   map[string]*grpc.ClientConn
	tmp     int
}

// New empties dir and returns a cache bounded to budget bytes. Nothing in it
// survives a restart: the index of what each scope may read is in memory.
func New(dir string, budget int64, log *slog.Logger, metrics *Metrics) (*Cache, error) {
	if err := os.RemoveAll(dir); err != nil {
		return nil, err
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return nil, err
	}
	if log == nil {
		log = slog.Default()
	}
	return &Cache{dir: dir, budget: budget, log: log, metrics: metrics, Dial: Dial, entries: map[string]*entry{}, conns: map[string]*grpc.ClientConn{}}, nil
}

// Dir is where the cache keeps its files, for disk accounting.
func (c *Cache) Dir() string { return c.dir }

// Open returns the blob, downloading it with the scope's credential unless
// the scope already has it. Concurrent requests share one download. The file
// stays readable after an eviction removes its name.
func (c *Cache) Open(ctx context.Context, s Scope, hash string, size int64) (*os.File, error) {
	if !validHash(hash) || size <= 0 || size > MaxBlob {
		return nil, ErrInvalid
	}
	if size > c.budget {
		return nil, ErrFull
	}
	ns := s.key()
	name := hash + "-" + strconv.FormatInt(size, 10)
	key := ns + "/" + name
	result := "hit"
	for {
		c.mu.Lock()
		e, ok := c.entries[key]
		if !ok {
			var err error
			if e, err = c.reserve(key, filepath.Join(c.dir, ns, name), size); err != nil {
				c.mu.Unlock()
				c.count("error")
				return nil, err
			}
			go c.fill(e, s, hash)
		}
		c.mu.Unlock()
		select {
		case <-e.ready:
		default:
			result = "miss"
			select {
			case <-e.ready:
			case <-ctx.Done():
				c.count("error")
				return nil, ctx.Err()
			}
		}
		// A failed download is shared by everyone who waited for it.
		if e.err != nil {
			c.count("error")
			return nil, e.err
		}
		c.mu.Lock()
		if c.entries[key] != e {
			// Evicted between the download and this request; fetch again.
			c.mu.Unlock()
			continue
		}
		c.lru.MoveToBack(e.elem)
		f, err := os.Open(e.path)
		c.mu.Unlock()
		if err != nil {
			c.count("error")
			return nil, err
		}
		c.count(result)
		return f, nil
	}
}

func (c *Cache) count(result string) {
	if c.metrics != nil {
		c.metrics.Requests.WithLabelValues(result).Inc()
	}
}

// reserve evicts least recently used blobs until size fits and records a
// download in flight. c.mu is held.
func (c *Cache) reserve(key, path string, size int64) (*entry, error) {
	for c.used+size > c.budget {
		oldest := c.lru.Front()
		if oldest == nil {
			return nil, ErrFull
		}
		victim := oldest.Value.(*entry)
		c.lru.Remove(oldest)
		delete(c.entries, victim.key)
		c.used -= victim.size
		if err := os.Remove(victim.path); err != nil && !errors.Is(err, os.ErrNotExist) {
			c.log.Warn("evicting cached blob", "error", err)
		}
	}
	e := &entry{key: key, path: path, size: size, ready: make(chan struct{})}
	c.entries[key] = e
	c.used += size
	c.gauge()
	return e, nil
}

func (c *Cache) gauge() {
	if c.metrics != nil {
		c.metrics.Bytes.Set(float64(c.used))
	}
}

func (c *Cache) fill(e *entry, s Scope, hash string) {
	ctx, cancel := context.WithTimeout(context.Background(), fillTimeout)
	defer cancel()
	err := c.download(ctx, e, s, hash)
	c.mu.Lock()
	defer c.mu.Unlock()
	if err != nil {
		// Forget it so the next request downloads again.
		delete(c.entries, e.key)
		c.used -= e.size
		c.gauge()
		e.err = err
	} else {
		e.elem = c.lru.PushBack(e)
	}
	close(e.ready)
}

func (c *Cache) download(ctx context.Context, e *entry, s Scope, hash string) (err error) {
	conn, err := c.conn(s.Endpoint)
	if err != nil {
		return err
	}
	if err := os.MkdirAll(filepath.Dir(e.path), 0o700); err != nil {
		return err
	}
	c.mu.Lock()
	c.tmp++
	tmp := filepath.Join(filepath.Dir(e.path), ".download-"+strconv.Itoa(c.tmp))
	c.mu.Unlock()
	f, err := os.OpenFile(tmp, os.O_CREATE|os.O_EXCL|os.O_WRONLY, 0o600)
	if err != nil {
		return err
	}
	defer func() {
		if f != nil {
			f.Close()
		}
		if err != nil {
			os.Remove(tmp)
		}
	}()
	ctx = metadata.NewOutgoingContext(ctx, metadata.Pairs("authorization", "Bearer "+s.Token, "x-tuist-account-handle", s.Account))
	stream, err := bs.NewByteStreamClient(conn).Read(ctx, &bs.ReadRequest{ResourceName: fmt.Sprintf("%s/blobs/%s/%d", s.Instance, hash, e.size)})
	if err != nil {
		return err
	}
	h := sha256.New()
	var n int64
	for {
		part, err := stream.Recv()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		n += int64(len(part.Data))
		if n > e.size {
			return errors.New("CAS blob exceeds digest size")
		}
		h.Write(part.Data)
		if _, err := f.Write(part.Data); err != nil {
			return err
		}
	}
	if n != e.size || hex.EncodeToString(h.Sum(nil)) != hash {
		return errors.New("CAS digest mismatch")
	}
	if c.metrics != nil {
		c.metrics.FetchedBytes.Add(float64(n))
	}
	err = f.Close()
	f = nil
	if err != nil {
		return err
	}
	return os.Rename(tmp, e.path)
}

func (c *Cache) conn(endpoint string) (*grpc.ClientConn, error) {
	c.mu.Lock()
	defer c.mu.Unlock()
	if conn, ok := c.conns[endpoint]; ok {
		return conn, nil
	}
	conn, err := c.Dial(endpoint)
	if err != nil {
		return nil, err
	}
	c.conns[endpoint] = conn
	return conn, nil
}

// Dial opens a lazy connection to a grpc:// or grpcs:// CAS endpoint, as the
// guest executor does. Credentials are per-RPC metadata.
func Dial(endpoint string) (*grpc.ClientConn, error) {
	if len(endpoint) > 4096 {
		return nil, ErrInvalid
	}
	var transport credentials.TransportCredentials
	switch {
	case strings.HasPrefix(endpoint, "grpcs://"):
		transport = credentials.NewTLS(&tls.Config{MinVersion: tls.VersionTLS12})
		endpoint = strings.TrimPrefix(endpoint, "grpcs://")
	case strings.HasPrefix(endpoint, "grpc://"):
		transport = insecure.NewCredentials()
		endpoint = strings.TrimPrefix(endpoint, "grpc://")
	default:
		return nil, ErrInvalid
	}
	return grpc.NewClient(endpoint, grpc.WithTransportCredentials(transport))
}

func validHash(h string) bool {
	if len(h) != 64 {
		return false
	}
	for _, c := range h {
		if !('0' <= c && c <= '9' || 'a' <= c && c <= 'f') {
			return false
		}
	}
	return true
}
