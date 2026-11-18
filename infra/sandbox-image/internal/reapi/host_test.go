package reapi

import (
	"bytes"
	"context"
	"io"
	"os"
	"os/exec"
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
