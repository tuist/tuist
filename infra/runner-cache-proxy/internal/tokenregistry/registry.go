// Package tokenregistry maps a guest's NAT source IP to that guest's
// cache token. The host agent (tart-kubelet on macOS, runners-controller
// on Linux) stages one file per active guest, named by source IP, under a
// root-owned directory; the proxy watches it and injects the matching
// token as the bearer to the cache-gateway. The guest itself never holds
// a cache secret and cannot forge another guest's source identity.
package tokenregistry

import (
	"context"
	"net/netip"
	"os"
	"path/filepath"
	"sync/atomic"

	"github.com/fsnotify/fsnotify"
)

// Registry is a lock-free, snapshot-based source-IP to token map backed
// by a watched directory.
type Registry struct {
	dir  string
	snap atomic.Pointer[map[netip.Addr][]byte]
}

// New builds a Registry over a staging directory.
func New(dir string) *Registry {
	r := &Registry{dir: dir}
	empty := map[netip.Addr][]byte{}
	r.snap.Store(&empty)
	return r
}

// Load scans the staging directory and atomically replaces the snapshot.
// Each file is named by the guest source IP; its content is the token.
func (r *Registry) Load() error {
	entries, err := os.ReadDir(r.dir)
	if err != nil {
		if os.IsNotExist(err) {
			empty := map[netip.Addr][]byte{}
			r.snap.Store(&empty)
			return nil
		}
		return err
	}
	next := make(map[netip.Addr][]byte, len(entries))
	for _, e := range entries {
		if e.IsDir() {
			continue
		}
		addr, perr := netip.ParseAddr(e.Name())
		if perr != nil {
			continue // ignore files that are not IP-named
		}
		data, rerr := os.ReadFile(filepath.Join(r.dir, e.Name()))
		if rerr != nil {
			continue
		}
		token := trimSpace(data)
		if len(token) == 0 {
			continue
		}
		next[addr] = token
	}
	r.snap.Store(&next)
	return nil
}

// Lookup returns the cache token staged for a guest source IP. A miss
// means the proxy fails open (forwards CacheService to genuine GitHub
// with the original token rather than failing the workflow).
func (r *Registry) Lookup(ip netip.Addr) ([]byte, bool) {
	m := *r.snap.Load()
	tok, ok := m[ip]
	return tok, ok
}

// Size reports the number of staged tokens (for metrics).
func (r *Registry) Size() int {
	return len(*r.snap.Load())
}

// Watch reloads the snapshot whenever the staging directory changes, until
// ctx is cancelled. It performs an initial Load before watching.
func (r *Registry) Watch(ctx context.Context) error {
	if err := r.Load(); err != nil {
		return err
	}
	w, err := fsnotify.NewWatcher()
	if err != nil {
		return err
	}
	defer w.Close()
	if err := os.MkdirAll(r.dir, 0o700); err != nil {
		return err
	}
	if err := w.Add(r.dir); err != nil {
		return err
	}
	for {
		select {
		case <-ctx.Done():
			return nil
		case _, ok := <-w.Events:
			if !ok {
				return nil
			}
			_ = r.Load()
		case _, ok := <-w.Errors:
			if !ok {
				return nil
			}
		}
	}
}

func trimSpace(b []byte) []byte {
	start, end := 0, len(b)
	for start < end && isSpace(b[start]) {
		start++
	}
	for end > start && isSpace(b[end-1]) {
		end--
	}
	return b[start:end]
}

func isSpace(c byte) bool {
	return c == ' ' || c == '\t' || c == '\n' || c == '\r'
}
