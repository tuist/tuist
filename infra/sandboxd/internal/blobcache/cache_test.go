package blobcache

import (
	"bufio"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	repb "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"github.com/klauspost/compress/zstd"
	bs "google.golang.org/genproto/googleapis/bytestream"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
)

// fakeCAS serves blobs over ByteStream to the token of each instance.
type fakeCAS struct {
	bs.UnimplementedByteStreamServer
	repb.UnimplementedCapabilitiesServer
	mu       sync.Mutex
	blobs    map[string][]byte
	tokens   map[string]string // instance -> accepted token
	reads    map[string]int    // instance/hash -> reads
	corrupt  map[string]bool   // hash -> serve wrong bytes once
	release  chan struct{}     // when set, reads wait for it
	pace     time.Duration     // when set, reads send one byte per pace
	zstd     bool
	wire     []byte // non-nil replaces the encoded response
	sent     int
	identity bool // capabilities implemented, but no compression
	trailer  codes.Code
}

func (f *fakeCAS) GetCapabilities(context.Context, *repb.GetCapabilitiesRequest) (*repb.ServerCapabilities, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.identity {
		return &repb.ServerCapabilities{CacheCapabilities: &repb.CacheCapabilities{}}, nil
	}
	if !f.zstd {
		return nil, status.Error(codes.Unimplemented, "legacy CAS")
	}
	return &repb.ServerCapabilities{CacheCapabilities: &repb.CacheCapabilities{SupportedCompressors: []repb.Compressor_Value{repb.Compressor_ZSTD}}}, nil
}

func (f *fakeCAS) Read(r *bs.ReadRequest, s bs.ByteStream_ReadServer) error {
	parts := strings.Split(r.ResourceName, "/")
	instance, hash := parts[0], parts[len(parts)-2]
	md, _ := metadata.FromIncomingContext(s.Context())
	f.mu.Lock()
	f.reads[instance+"/"+hash]++
	ok := len(md.Get("authorization")) == 1 && md.Get("authorization")[0] == "Bearer "+f.tokens[instance]
	data, corrupt, release, pace := f.blobs[hash], f.corrupt[hash], f.release, f.pace
	wire, trailer := f.wire, f.trailer
	delete(f.corrupt, hash)
	f.mu.Unlock()
	if release != nil {
		<-release
	}
	if !ok {
		return status.Error(codes.PermissionDenied, "denied")
	}
	if corrupt {
		data = []byte(strings.Repeat("x", len(data)))
	}
	if parts[1] == "compressed-blobs" {
		enc, err := zstd.NewWriter(nil, zstd.WithEncoderConcurrency(1))
		if err != nil {
			return err
		}
		data = enc.EncodeAll(data, nil)
		enc.Close()
	}
	if wire != nil {
		data = wire
	}
	f.mu.Lock()
	f.sent += len(data)
	f.mu.Unlock()
	for ; pace > 0 && len(data) > 1; data = data[1:] {
		if err := s.Send(&bs.ReadResponse{Data: data[:1]}); err != nil {
			return err
		}
		time.Sleep(pace)
	}
	if err := s.Send(&bs.ReadResponse{Data: data}); err != nil {
		return err
	}
	return status.Error(trailer, "response trailer")
}

func (f *fakeCAS) put(data string) (string, int64) {
	h := sha256.Sum256([]byte(data))
	hash := hex.EncodeToString(h[:])
	f.mu.Lock()
	f.blobs[hash] = []byte(data)
	f.mu.Unlock()
	return hash, int64(len(data))
}

func (f *fakeCAS) readCount(instance, hash string) int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.reads[instance+"/"+hash]
}

func setup(t *testing.T, budget int64) (*Cache, *fakeCAS, string) {
	t.Helper()
	cas := &fakeCAS{blobs: map[string][]byte{}, tokens: map[string]string{"a": "token-a", "b": "token-b"}, reads: map[string]int{}, corrupt: map[string]bool{}}
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := grpc.NewServer()
	bs.RegisterByteStreamServer(server, cas)
	repb.RegisterCapabilitiesServer(server, cas)
	go server.Serve(l)
	t.Cleanup(server.Stop)
	c, err := New(filepath.Join(t.TempDir(), "blobs"), budget, nil, NewMetrics(nil))
	if err != nil {
		t.Fatal(err)
	}
	c.Filesystem = func(string) (uint64, uint64, error) { return 1 << 40, 1 << 40, nil }
	return c, cas, "grpc://" + l.Addr().String()
}

func readAll(t *testing.T, c *Cache, s Scope, hash string, size int64) (string, error) {
	t.Helper()
	f, err := c.Open(context.Background(), s, hash, size)
	if err != nil {
		return "", err
	}
	defer f.Close()
	b, err := io.ReadAll(f)
	return string(b), err
}

// guestRead makes one request on the guest's socket, as the executor does.
func guestRead(socket string, r Request) (string, error) {
	conn, err := net.Dial("unix", socket)
	if err != nil {
		return "", err
	}
	defer conn.Close()
	line, _ := json.Marshal(r)
	conn.Write(append(line, '\n'))
	reader := bufio.NewReader(conn)
	answer, err := reader.ReadSlice('\n')
	if err != nil {
		return "", err
	}
	var response Response
	json.Unmarshal(answer, &response)
	if !response.OK {
		return "", errors.New(response.Error)
	}
	body, err := io.ReadAll(reader)
	return string(body), err
}

func serve(t *testing.T, c *Cache, s Scope) (string, <-chan struct{}) {
	t.Helper()
	socket := filepath.Join(t.TempDir(), "v.sock_5001")
	l, err := net.Listen("unix", socket)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		c.Serve(ctx, l, s)
	}()
	t.Cleanup(func() {
		cancel()
		<-done
	})
	return socket, done
}

func TestGuestsShareOneDownloadAndReadRanges(t *testing.T) {
	c, cas, endpoint := setup(t, 1<<20)
	const blob = "0123456789abcdefghijklmnopqrstuvwxyz"
	hash, size := cas.put(blob)
	cas.release = make(chan struct{})
	socket, _ := serve(t, c, Scope{Endpoint: endpoint, Instance: "a", Token: "token-a"})
	var wg sync.WaitGroup
	got := make([]string, 4)
	errs := make([]error, 4)
	for i := range 4 {
		wg.Go(func() {
			got[i], errs[i] = guestRead(socket, Request{Op: "read", Hash: hash, Size: size, Offset: int64(i * 5), Length: 7})
		})
	}
	// Let the requests queue behind the one download before it completes.
	time.Sleep(100 * time.Millisecond)
	close(cas.release)
	wg.Wait()
	for i := range 4 {
		if errs[i] != nil || got[i] != blob[i*5:i*5+7] {
			t.Fatalf("range %d: %q %v", i, got[i], errs[i])
		}
	}
	if n := cas.readCount("a", hash); n != 1 {
		t.Fatalf("CAS reads %d, want 1", n)
	}
	if _, err := guestRead(socket, Request{Op: "read", Hash: hash, Size: size, Offset: 30, Length: 7}); err == nil {
		t.Fatal("a range past the end was served")
	}
}

func TestScopesDoNotShareBlobs(t *testing.T) {
	c, cas, endpoint := setup(t, 1<<20)
	hash, size := cas.put("shared input")
	if got, err := readAll(t, c, Scope{Endpoint: endpoint, Instance: "a", Token: "token-a"}, hash, size); err != nil || got != "shared input" {
		t.Fatalf("scope a: %q %v", got, err)
	}
	// Another project asks for the same digest with a credential its CAS
	// refuses: the cached copy must not answer for it.
	if _, err := readAll(t, c, Scope{Endpoint: endpoint, Instance: "b", Token: "stolen"}, hash, size); status.Code(err) != codes.PermissionDenied {
		t.Fatalf("scope b with a refused credential: %v", err)
	}
	if got, err := readAll(t, c, Scope{Endpoint: endpoint, Instance: "b", Token: "token-b"}, hash, size); err != nil || got != "shared input" {
		t.Fatalf("scope b: %q %v", got, err)
	}
}

func TestCorruptDownloadIsNotCached(t *testing.T) {
	c, cas, endpoint := setup(t, 1<<20)
	hash, size := cas.put("verified content")
	cas.corrupt[hash] = true
	s := Scope{Endpoint: endpoint, Instance: "a", Token: "token-a"}
	if _, err := readAll(t, c, s, hash, size); err == nil {
		t.Fatal("served a blob that does not match its digest")
	}
	if got, err := readAll(t, c, s, hash, size); err != nil || got != "verified content" || cas.readCount("a", hash) != 2 {
		t.Fatalf("after a corrupt download: %q %v, %d reads", got, err, cas.readCount("a", hash))
	}
}

func TestCompressedDownloads(t *testing.T) {
	enc, err := zstd.NewWriter(nil, zstd.WithEncoderConcurrency(1))
	if err != nil {
		t.Fatal(err)
	}
	defer enc.Close()
	blob := strings.Repeat("a compressible input with asymmetric contents!", 8192)
	encoded := enc.EncodeAll([]byte(blob), nil)
	for _, tc := range []struct {
		name     string
		wire     []byte
		bad      bool
		identity bool
		trailer  codes.Code
	}{
		{name: "negotiated"},
		{name: "identity only", identity: true},
		{name: "truncated frame", wire: encoded[:len(encoded)-1], bad: true},
		{name: "not zstd", wire: []byte(blob), bad: true},
		{name: "wrong digest", wire: enc.EncodeAll([]byte(strings.Repeat("x", len(blob))), nil), bad: true},
		{name: "short content", wire: enc.EncodeAll([]byte(blob[:len(blob)-1]), nil), bad: true},
		{name: "extra decoded byte", wire: enc.EncodeAll([]byte(blob+"x"), nil), bad: true},
		{name: "failed stream after complete frame", trailer: codes.Unavailable, bad: true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			c, cas, endpoint := setup(t, 1<<20)
			cas.zstd, cas.wire, cas.identity, cas.trailer = true, tc.wire, tc.identity, tc.trailer
			hash, size := cas.put(blob)
			s := Scope{Endpoint: endpoint, Instance: "a", Token: "token-a"}
			got, err := readAll(t, c, s, hash, size)
			if tc.bad {
				if err == nil {
					t.Fatal("invalid compressed response was cached")
				}
				files, _ := filepath.Glob(filepath.Join(c.Dir(), s.key(), "*"))
				if len(files) != 0 {
					t.Fatalf("failed fill left files: %v", files)
				}
				cas.mu.Lock()
				cas.wire, cas.trailer = nil, codes.OK
				cas.mu.Unlock()
				got, err = readAll(t, c, s, hash, size)
			}
			if err != nil || got != blob {
				t.Fatalf("decoded input: %v, %d bytes", err, len(got))
			}
			if !tc.bad && !tc.identity && cas.sent >= len(blob)/2 {
				t.Fatalf("did not use compression: %d wire bytes for %d decoded bytes", cas.sent, len(blob))
			}
			reads := cas.readCount("a", hash)
			if got, err := readAll(t, c, s, hash, size); err != nil || got != blob || cas.readCount("a", hash) != reads {
				t.Fatalf("cached decoded input: %v", err)
			}
		})
	}
}

func TestStalledDownloadFailsButSlowOneFinishes(t *testing.T) {
	for _, compressed := range []bool{false, true} {
		t.Run(fmt.Sprintf("compressed=%t", compressed), func(t *testing.T) {
			c, cas, endpoint := setup(t, 1<<20)
			cas.zstd = compressed
			c.stall = 300 * time.Millisecond
			s := Scope{Endpoint: endpoint, Instance: "a", Token: "token-a"}

			// A CAS that keeps sending finishes, however long the whole blob takes.
			slow, slowSize := cas.put("0123456789")
			cas.mu.Lock()
			cas.pace = 100 * time.Millisecond
			cas.mu.Unlock()
			if got, err := readAll(t, c, s, slow, slowSize); err != nil || got != "0123456789" {
				t.Fatalf("slow but steady download: %q %v", got, err)
			}

			// One that stops sending fails long before fillTimeout, so the guests
			// waiting on it read the blob from the CAS themselves.
			hash, size := cas.put("stalled content")
			release := make(chan struct{})
			cas.mu.Lock()
			cas.pace, cas.release = 0, release
			cas.mu.Unlock()
			started := time.Now()
			_, err := readAll(t, c, s, hash, size)
			if !errors.Is(err, errStalled) || time.Since(started) > 5*time.Second {
				t.Fatalf("stalled download: %v after %s", err, time.Since(started))
			}
			cas.mu.Lock()
			cas.release = nil
			cas.mu.Unlock()
			close(release)
			if got, err := readAll(t, c, s, hash, size); err != nil || got != "stalled content" || cas.readCount("a", hash) != 2 {
				t.Fatalf("after a stalled download: %q %v, %d reads", got, err, cas.readCount("a", hash))
			}
		})
	}
}

func TestEvictionKeepsTheBudget(t *testing.T) {
	c, cas, endpoint := setup(t, 25)
	s := Scope{Endpoint: endpoint, Instance: "a", Token: "token-a"}
	var hashes []string
	for i := range 3 {
		hash, size := cas.put(fmt.Sprintf("blob-%05d", i)) // 10 bytes
		hashes = append(hashes, hash)
		if _, err := readAll(t, c, s, hash, size); err != nil {
			t.Fatal(err)
		}
	}
	var files int
	filepath.Walk(c.Dir(), func(_ string, info os.FileInfo, _ error) error {
		if info != nil && info.Mode().IsRegular() {
			files++
		}
		return nil
	})
	if files != 2 {
		t.Fatalf("%d files cached within a 25-byte budget, want 2", files)
	}
	// The least recently used blob went first and downloads again.
	if _, err := readAll(t, c, s, hashes[0], 10); err != nil || cas.readCount("a", hashes[0]) != 2 || cas.readCount("a", hashes[2]) != 1 {
		t.Fatalf("reads after eviction: %v %v", cas.reads, err)
	}
	big, size := cas.put(strings.Repeat("z", 26))
	if _, err := readAll(t, c, s, big, size); !errors.Is(err, ErrFull) {
		t.Fatalf("blob over the budget: %v", err)
	}
}

func TestSealEndsServing(t *testing.T) {
	c, cas, endpoint := setup(t, 1<<20)
	hash, size := cas.put("input")
	socket, done := serve(t, c, Scope{Endpoint: endpoint, Instance: "a", Token: "token-a"})
	if _, err := guestRead(socket, Request{Op: "seal"}); err != nil {
		t.Fatal(err)
	}
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("still serving after the seal")
	}
	if _, err := guestRead(socket, Request{Op: "read", Hash: hash, Size: size, Length: size}); err == nil {
		t.Fatal("read served after the seal")
	}
}

func TestCacheStepsAsideWhenTheDiskIsShort(t *testing.T) {
	c, cas, endpoint := setup(t, 1<<20)
	var available atomic.Uint64
	available.Store(500)
	c.Filesystem = func(string) (uint64, uint64, error) { return 1000, available.Load(), nil }
	s := Scope{Endpoint: endpoint, Instance: "a", Token: "token-a"}
	first, size := cas.put("first-blob")
	if _, err := readAll(t, c, s, first, size); err != nil {
		t.Fatal(err)
	}
	// Runners filled the disk to 81%: the cache gives back what it holds and
	// sends the guest to the CAS rather than write more.
	available.Store(190)
	second, _ := cas.put("other-blob")
	if _, err := readAll(t, c, s, second, size); !errors.Is(err, ErrFull) {
		t.Fatalf("download under disk pressure: %v", err)
	}
	if _, err := os.Stat(filepath.Join(c.Dir(), s.key(), first+"-10")); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("cached blob kept under disk pressure: %v", err)
	}
	// 211 free leaves 201 after the write, above the 200 floor.
	available.Store(211)
	if got, err := readAll(t, c, s, second, size); err != nil || got != "other-blob" {
		t.Fatalf("after the pressure: %q %v", got, err)
	}
}
