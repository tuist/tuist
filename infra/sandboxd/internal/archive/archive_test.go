package archive

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/klauspost/compress/zstd"
)

func writeSparse(t *testing.T, path string, size int64, blocks map[int64][]byte) *os.File {
	t.Helper()
	f, err := os.Create(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := f.Truncate(size); err != nil {
		t.Fatal(err)
	}
	for offset, data := range blocks {
		if _, err := f.WriteAt(data, offset); err != nil {
			t.Fatal(err)
		}
	}
	t.Cleanup(func() { f.Close() })
	return f
}

func archiveOf(t *testing.T, sources []Source) ([]byte, int64) {
	t.Helper()
	var buf bytes.Buffer
	stored, err := Write(&buf, Header{Template: "default", Tag: "t1", WorkspaceGB: 1}, sources)
	if err != nil {
		t.Fatal(err)
	}
	return buf.Bytes(), stored
}

var limits = map[string]int64{"rootfs.ext4": 1 << 30, "workspace.ext4": 1 << 30}

func TestRoundTripKeepsContentAndSkipsZeros(t *testing.T) {
	src := t.TempDir()
	payload := bytes.Repeat([]byte("workspace"), 1000)
	workspace := writeSparse(t, filepath.Join(src, "workspace.ext4"), 64<<20, map[int64][]byte{
		0:          []byte("superblock"),
		40 << 20:   payload,
		64<<20 - 3: []byte("end"),
	})
	rootfs := writeSparse(t, filepath.Join(src, "rootfs.ext4"), 8<<20, map[int64][]byte{4096: []byte("rootfs")})
	// A written but all-zero region costs nothing either.
	if _, err := rootfs.WriteAt(make([]byte, 3<<20), 4<<20); err != nil {
		t.Fatal(err)
	}

	data, stored := archiveOf(t, []Source{{Name: "rootfs.ext4", File: rootfs}, {Name: "workspace.ext4", File: workspace}})
	if stored > 5*blockSize {
		t.Fatalf("stored %d bytes of a mostly empty 64 MiB image", stored)
	}
	if len(data) > 1<<20 {
		t.Fatalf("archive is %d bytes", len(data))
	}

	dst := t.TempDir()
	header, err := Extract(bytes.NewReader(data), dst, limits)
	if err != nil {
		t.Fatal(err)
	}
	if header.Template != "default" || header.Tag != "t1" || header.WorkspaceGB != 1 {
		t.Fatalf("header %+v", header)
	}
	for _, name := range []string{"rootfs.ext4", "workspace.ext4"} {
		want, _ := os.ReadFile(filepath.Join(src, name))
		got, _ := os.ReadFile(filepath.Join(dst, name))
		if !bytes.Equal(want, got) {
			t.Fatalf("%s differs after the round trip", name)
		}
	}
}

func TestExtractRefusesUnexpectedOrIncompleteArchives(t *testing.T) {
	src := t.TempDir()
	rootfs := writeSparse(t, filepath.Join(src, "rootfs.ext4"), 1<<20, map[int64][]byte{0: []byte("x")})
	workspace := writeSparse(t, filepath.Join(src, "workspace.ext4"), 1<<20, nil)
	full, _ := archiveOf(t, []Source{{Name: "rootfs.ext4", File: rootfs}, {Name: "workspace.ext4", File: workspace}})
	onlyRootfs, _ := archiveOf(t, []Source{{Name: "rootfs.ext4", File: rootfs}})

	cases := map[string]struct {
		data   []byte
		limits map[string]int64
	}{
		"missing file":   {onlyRootfs, limits},
		"unexpected":     {full, map[string]int64{"rootfs.ext4": 1 << 30}},
		"oversized":      {full, map[string]int64{"rootfs.ext4": 1024, "workspace.ext4": 1 << 30}},
		"truncated":      {full[:len(full)-8], limits},
		"not an archive": {[]byte("hello"), limits},
	}
	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			if _, err := Extract(bytes.NewReader(tc.data), t.TempDir(), tc.limits); err == nil {
				t.Fatal("extract must fail")
			}
		})
	}

	t.Run("block outside the file", func(t *testing.T) {
		var raw bytes.Buffer
		raw.WriteString(magic)
		raw.Write([]byte{2, '{', '}'})
		raw.Write([]byte{recordFile, 11})
		raw.WriteString("rootfs.ext4")
		raw.Write([]byte{4, recordData, 3, 2, 'a', 'b', recordEnd, recordFinal})
		var compressed bytes.Buffer
		enc, _ := zstd.NewWriter(&compressed)
		enc.Write(raw.Bytes())
		enc.Close()
		if _, err := Extract(&compressed, t.TempDir(), map[string]int64{"rootfs.ext4": 1 << 20}); !errors.Is(err, ErrInvalid) {
			t.Fatalf("got %v", err)
		}
	})
}

// fakeStore accepts presigned part PUTs and serves the assembled object.
type fakeStore struct {
	mu       sync.Mutex
	parts    map[int][]byte
	failPart int
	fails    int
}

func (s *fakeStore) handler(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	defer s.mu.Unlock()
	switch r.Method {
	case http.MethodPut:
		number, _ := strconv.Atoi(r.URL.Query().Get("partNumber"))
		if number == s.failPart && s.fails > 0 {
			s.fails--
			w.WriteHeader(http.StatusServiceUnavailable)
			return
		}
		data, _ := io.ReadAll(r.Body)
		s.parts[number] = data
		sum := sha256.Sum256(data)
		w.Header().Set("ETag", `"`+hex.EncodeToString(sum[:8])+`"`)
	case http.MethodGet:
		w.Write(s.object())
	}
}

func (s *fakeStore) object() []byte {
	var out []byte
	for i := 1; i <= len(s.parts); i++ {
		out = append(out, s.parts[i]...)
	}
	return out
}

func partURLs(base string, n int) []string {
	urls := make([]string, n)
	for i := range urls {
		urls[i] = fmt.Sprintf("%s/archive?partNumber=%d&X-Amz-Signature=secret", base, i+1)
	}
	return urls
}

func TestUploadAndDownload(t *testing.T) {
	putRetryBackoff = time.Millisecond
	store := &fakeStore{parts: map[int][]byte{}, failPart: 2, fails: 1}
	server := httptest.NewServer(http.HandlerFunc(store.handler))
	defer server.Close()
	ctx := context.Background()

	payload := bytes.Repeat([]byte("0123456789"), 1000)
	up, err := NewUploader(ctx, server.Client(), partURLs(server.URL, 5), 4096)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := up.Write(payload); err != nil {
		t.Fatal(err)
	}
	if err := up.Close(); err != nil {
		t.Fatal(err)
	}
	if parts := up.Parts(); len(parts) != 3 || parts[1].PartNumber != 2 || parts[1].ETag == "" {
		t.Fatalf("parts %+v", parts)
	}
	if !bytes.Equal(store.object(), payload) || up.Bytes() != int64(len(payload)) {
		t.Fatal("the store must hold exactly what was written")
	}

	var got []byte
	err = Download(ctx, server.Client(), server.URL+"/archive", up.Bytes(), up.SHA256(), func(r io.Reader) error {
		got, err = io.ReadAll(r)
		return err
	})
	if err != nil || !bytes.Equal(got, payload) {
		t.Fatalf("download: %v", err)
	}

	err = Download(ctx, server.Client(), server.URL+"/archive", up.Bytes(), strings.Repeat("0", 64), func(r io.Reader) error {
		_, err := io.Copy(io.Discard, r)
		return err
	})
	if err == nil || !strings.Contains(err.Error(), "checksum") {
		t.Fatalf("a checksum mismatch must fail, got %v", err)
	}
	if err := Download(ctx, server.Client(), server.URL+"/archive", up.Bytes()+1, up.SHA256(), func(io.Reader) error { return nil }); err == nil {
		t.Fatal("a size mismatch must fail")
	}
}

func TestUploadRefusesToOutgrowItsParts(t *testing.T) {
	store := &fakeStore{parts: map[int][]byte{}}
	server := httptest.NewServer(http.HandlerFunc(store.handler))
	defer server.Close()
	up, err := NewUploader(context.Background(), server.Client(), partURLs(server.URL, 2), 1024)
	if err != nil {
		t.Fatal(err)
	}
	_, err = up.Write(make([]byte, 4096))
	if !errors.Is(err, ErrTooLarge) {
		t.Fatalf("got %v", err)
	}
	up.Close()
}

func TestTransportErrorsNeverCarryTheSignedURL(t *testing.T) {
	putRetryBackoff = time.Millisecond
	server := httptest.NewServer(http.NotFoundHandler())
	server.Close()
	up, err := NewUploader(context.Background(), server.Client(), partURLs(server.URL, 1), 16)
	if err != nil {
		t.Fatal(err)
	}
	up.Write([]byte("data"))
	err = up.Close()
	if err == nil || strings.Contains(err.Error(), "secret") || strings.Contains(err.Error(), server.URL) {
		t.Fatalf("got %v", err)
	}
	err = Download(context.Background(), server.Client(), server.URL+"/archive?X-Amz-Signature=secret", 1, "", func(io.Reader) error { return nil })
	if err == nil || strings.Contains(err.Error(), "secret") {
		t.Fatalf("got %v", err)
	}
}
