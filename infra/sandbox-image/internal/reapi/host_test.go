package reapi

import (
	"bytes"
	"context"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"testing"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
)

type fakeHost struct {
	mu     sync.Mutex
	blobs  map[string][]byte
	reads  []string
	sealed bool
}

func (h *fakeHost) ReadBlob(_ context.Context, d *re.Digest, offset, length int64, out io.Writer) error {
	h.mu.Lock()
	h.reads = append(h.reads, d.Hash)
	b := h.blobs[d.Hash]
	sealed := h.sealed
	h.mu.Unlock()
	if sealed || b == nil {
		return io.ErrUnexpectedEOF
	}
	_, err := out.Write(b[offset : offset+length])
	return err
}

func (h *fakeHost) Seal(context.Context) error {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.sealed = true
	return nil
}

func (h *fakeHost) state() ([]string, bool) {
	h.mu.Lock()
	defer h.mu.Unlock()
	return append([]string{}, h.reads...), h.sealed
}

func TestHostServesStreamedInputsAndIsSealedBeforeTheCommand(t *testing.T) {
	w, m := harness(t)
	large := m.put(bytes.Repeat([]byte("toolchain"), 30_000))
	small := m.put([]byte("small\n"))
	host := &fakeHost{blobs: map[string][]byte{large.Hash: m.blobs[large.Hash]}}
	w.CAS.Host = host
	m.batchRead = func(_ context.Context, r *re.BatchReadBlobsRequest) (*re.BatchReadBlobsResponse, error) {
		return batchResponse(m, r), nil
	}
	var casStreams atomic.Int32
	m.beforeRead = func(context.Context, string) error { casStreams.Add(1); return nil }
	w.Start = func(cmd *exec.Cmd) error {
		if _, sealed := host.state(); !sealed {
			t.Error("command started before the host channel was sealed")
		}
		return cmd.Start()
	}
	inputs := &re.Directory{Files: []*re.FileNode{{Name: "lib.so", Digest: large}, {Name: "small", Digest: small}}}
	response, _ := w.Execute(context.Background(), action(t, m, "cat lib.so small > output", inputs, []string{"output"}))
	if response.Status.Code != 0 || response.Result.GetExitCode() != 0 {
		t.Fatalf("execution: %v", response)
	}
	if got := m.blobs[response.Result.OutputFiles[0].Digest.Hash]; !bytes.Equal(got, append(append([]byte{}, m.blobs[large.Hash]...), "small\n"...)) {
		t.Fatal("output differs from the inputs")
	}
	// Small files keep using batched CAS reads; only the large one is the host's.
	if reads, _ := host.state(); len(reads) != 1 || reads[0] != large.Hash || casStreams.Load() != 0 {
		t.Fatalf("host reads %v, CAS streams %d", reads, casStreams.Load())
	}
}

func TestCorruptHostBlobIsReadFromTheCASInstead(t *testing.T) {
	w, m := harness(t)
	first := m.put(bytes.Repeat([]byte("a"), 200_000))
	second := m.put(bytes.Repeat([]byte("b"), 200_000))
	// Same length, wrong content: only the digest check can catch it.
	host := &fakeHost{blobs: map[string][]byte{first.Hash: bytes.Repeat([]byte("x"), 200_000), second.Hash: m.blobs[second.Hash]}}
	w.CAS.Host = host
	// Inputs download concurrently, so read one after the other to see that a
	// read starting after a failed host read no longer asks the host.
	read := func(d *re.Digest) []byte {
		f, err := os.CreateTemp(t.TempDir(), "input")
		if err != nil {
			t.Fatal(err)
		}
		defer f.Close()
		if err := w.CAS.Read(context.Background(), d, f); err != nil {
			t.Fatal(err)
		}
		b, err := os.ReadFile(f.Name())
		if err != nil {
			t.Fatal(err)
		}
		return b
	}
	if !bytes.Equal(read(first), m.blobs[first.Hash]) || !bytes.Equal(read(second), m.blobs[second.Hash]) {
		t.Fatal("a corrupt host read reached the workspace")
	}
	if reads, _ := host.state(); len(reads) != 1 {
		t.Fatalf("host reads %v", reads)
	}
}

func TestInputsImageBlobsAreLinkedReadOnlyAndTheRestDownloaded(t *testing.T) {
	w, m := harness(t)
	inputs := filepath.Join(filepath.Dir(w.Root), "inputs")
	if err := os.Mkdir(inputs, 0o700); err != nil {
		t.Fatal(err)
	}
	w.Inputs = inputs
	shared := m.put(bytes.Repeat([]byte("toolchain"), 30_000))
	missing := m.put(bytes.Repeat([]byte("missing"), 30_000))
	wrongSize := m.put(bytes.Repeat([]byte("decoy"), 30_000))
	name := func(d *re.Digest) string { return filepath.Join(inputs, d.Hash+"-"+strconv.FormatInt(d.SizeBytes, 10)) }
	if err := os.WriteFile(name(shared), m.blobs[shared.Hash], 0o444); err != nil {
		t.Fatal(err)
	}
	// A file under a digest's name but of another size is never trusted.
	if err := os.WriteFile(name(wrongSize), []byte("short"), 0o444); err != nil {
		t.Fatal(err)
	}
	var mu sync.Mutex
	read := map[string]int{}
	m.beforeRead = func(_ context.Context, resource string) error {
		mu.Lock()
		defer mu.Unlock()
		for _, d := range []*re.Digest{shared, missing, wrongSize} {
			if strings.Contains(resource, d.Hash) {
				read[d.Hash]++
			}
		}
		return nil
	}
	tree := &re.Directory{Files: []*re.FileNode{
		{Name: "decoy", Digest: wrongSize},
		{Name: "lib.so", Digest: shared},
		{Name: "missing", Digest: missing},
		{Name: "other", Digest: shared},
		{Name: "tool", Digest: shared, IsExecutable: true},
	}}
	var linked, copied, other os.FileInfo
	w.Start = func(cmd *exec.Cmd) error {
		var err error
		if linked, err = os.Stat(filepath.Join(w.Root, "lib.so")); err != nil {
			return err
		}
		if other, err = os.Stat(filepath.Join(w.Root, "other")); err != nil {
			return err
		}
		if copied, err = os.Stat(filepath.Join(w.Root, "tool")); err != nil {
			return err
		}
		return cmd.Start()
	}
	response, _ := w.Execute(context.Background(), action(t, m, "cat decoy lib.so missing other tool > output", tree, []string{"output"}))
	if response.Status.Code != 0 || response.Result.GetExitCode() != 0 {
		t.Fatalf("execution: %v", response)
	}
	var want []byte
	for _, d := range []*re.Digest{wrongSize, shared, missing, shared, shared} {
		want = append(want, m.blobs[d.Hash]...)
	}
	if got := m.blobs[response.Result.OutputFiles[0].Digest.Hash]; !bytes.Equal(got, want) {
		t.Fatal("output differs from the inputs")
	}
	source, err := os.Stat(name(shared))
	if err != nil {
		t.Fatal(err)
	}
	if !os.SameFile(linked, source) || !os.SameFile(other, source) || linked.Mode().Perm() != 0o444 {
		t.Fatalf("shared input not linked read-only: lib.so %v, other %v", linked.Mode(), other.Mode())
	}
	// The executable path of the same digest is a copy with its own mode.
	if os.SameFile(copied, source) || copied.Mode().Perm()&0o111 == 0 {
		t.Fatalf("executable path shares the read-only inode: %v", copied.Mode())
	}
	if read[shared.Hash] != 0 || read[missing.Hash] != 1 || read[wrongSize.Hash] != 1 {
		t.Fatalf("CAS reads %v: want only the missing and the wrong-size blob", read)
	}
}
