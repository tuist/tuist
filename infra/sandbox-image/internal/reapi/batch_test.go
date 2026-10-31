package reapi

import (
	"context"
	"fmt"
	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	rpc "google.golang.org/genproto/googleapis/rpc/status"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
	"os"
	"path/filepath"
	"sync/atomic"
	"testing"
)

func batchResponse(m *memoryCAS, r *re.BatchReadBlobsRequest) *re.BatchReadBlobsResponse {
	m.mu.Lock()
	defer m.mu.Unlock()
	response := &re.BatchReadBlobsResponse{}
	for i := len(r.Digests) - 1; i >= 0; i-- {
		d := r.Digests[i]
		data, ok := m.blobs[d.Hash]
		item := &re.BatchReadBlobsResponse_Response{Digest: d, Data: data, Status: &rpc.Status{}}
		if !ok {
			item.Status.Code = int32(codes.NotFound)
		}
		response.Responses = append(response.Responses, item)
	}
	return response
}
func TestBatchMaterializationBoundsAndModes(t *testing.T) {
	w, m := harness(t)
	var batches, streams atomic.Int32
	m.batchRead = func(_ context.Context, r *re.BatchReadBlobsRequest) (*re.BatchReadBlobsResponse, error) {
		batches.Add(1)
		var total int64
		for _, d := range r.Digests {
			total += d.SizeBytes
		}
		if len(r.Digests) > inputBatchEntries || total > inputBatchBytes || r.InstanceName != "project" || r.DigestFunction != re.DigestFunction_SHA256 || len(r.AcceptableCompressors) != 0 {
			t.Error("unbounded/incorrect batch")
		}
		return batchResponse(m, r), nil
	}
	files := []*re.FileNode{}
	for i := 0; i < 260; i++ {
		files = append(files, &re.FileNode{Name: fmt.Sprintf("file%03d", i), Digest: m.put([]byte(fmt.Sprintf("input%d", i))), IsExecutable: i%2 == 0})
	}
	files = append(files, &re.FileNode{Name: "duplicate", Digest: files[0].Digest}, &re.FileNode{Name: "large", Digest: m.put(make([]byte, inputBatchFileBytes+1))})
	m.beforeRead = func(_ context.Context, hash string) error {
		streams.Add(1)
		if hash != files[len(files)-1].Digest.Hash {
			t.Error("small file streamed")
		}
		return nil
	}
	dir := t.TempDir()
	root, err := os.OpenRoot(dir)
	if err != nil {
		t.Fatal(err)
	}
	defer root.Close()
	if err := w.materializeFiles(context.Background(), root, "", files); err != nil {
		t.Fatal(err)
	}
	if batches.Load() != 3 || streams.Load() != 1 {
		t.Fatalf("batches=%d streams=%d", batches.Load(), streams.Load())
	}
	var total int64
	for _, f := range files {
		total += f.Digest.SizeBytes
		b, err := os.ReadFile(filepath.Join(dir, f.Name))
		if err != nil {
			t.Fatal(err)
		}
		if string(b) != string(m.blobs[f.Digest.Hash]) {
			t.Fatal("wrong contents")
		}
		info, _ := os.Stat(filepath.Join(dir, f.Name))
		if (info.Mode()&0111 != 0) != f.IsExecutable {
			t.Fatal("wrong mode")
		}
	}
	if w.CAS.transferred != total {
		t.Fatalf("budget=%d want=%d", w.CAS.transferred, total)
	}
}
func TestBatchResponseValidation(t *testing.T) {
	for _, test := range []struct {
		name   string
		code   codes.Code
		mutate func(*re.BatchReadBlobsResponse)
	}{
		{"corrupt", codes.DataLoss, func(r *re.BatchReadBlobsResponse) { r.Responses[0].Data = []byte("bad") }},
		{"missing", codes.DataLoss, func(r *re.BatchReadBlobsResponse) { r.Responses = nil }},
		{"duplicate", codes.DataLoss, func(r *re.BatchReadBlobsResponse) { r.Responses = append(r.Responses, r.Responses[0]) }},
		{"nil status", codes.DataLoss, func(r *re.BatchReadBlobsResponse) { r.Responses[0].Status = nil }},
		{"wrong size", codes.DataLoss, func(r *re.BatchReadBlobsResponse) {
			r.Responses[0].Digest = proto.Clone(r.Responses[0].Digest).(*re.Digest)
			r.Responses[0].Digest.SizeBytes++
		}},
		{"unknown", codes.DataLoss, func(r *re.BatchReadBlobsResponse) {
			r.Responses[0].Digest = &re.Digest{Hash: fmt.Sprintf("%064d", 0), SizeBytes: 1}
		}},
		{"compressed", codes.DataLoss, func(r *re.BatchReadBlobsResponse) { r.Responses[0].Compressor = re.Compressor_ZSTD }},
		{"not found", codes.FailedPrecondition, func(r *re.BatchReadBlobsResponse) { r.Responses[0].Status.Code = int32(codes.NotFound) }},
		{"denied", codes.PermissionDenied, func(r *re.BatchReadBlobsResponse) { r.Responses[0].Status.Code = int32(codes.PermissionDenied) }},
		{"oversized", codes.ResourceExhausted, func(r *re.BatchReadBlobsResponse) { r.Responses[0].Data = make([]byte, 3*inputBatchBytes) }},
	} {
		t.Run(test.name, func(t *testing.T) {
			w, m := harness(t)
			d := m.put([]byte("a"))
			var streams atomic.Int32
			m.beforeRead = func(context.Context, string) error { streams.Add(1); return nil }
			m.batchRead = func(_ context.Context, r *re.BatchReadBlobsRequest) (*re.BatchReadBlobsResponse, error) {
				res := batchResponse(m, r)
				test.mutate(res)
				return res, nil
			}
			_, err := w.CAS.ReadBatch(context.Background(), []*re.Digest{d, d})
			if status.Code(err) != test.code {
				t.Fatalf("got %v", err)
			}
			if test.code == codes.FailedPrecondition && len(status.Convert(err).Details()) != 1 {
				t.Fatal("missing retry details")
			}
			if streams.Load() != 0 {
				t.Fatal("unsafe fallback")
			}
		})
	}
}
func TestBatchFallbackReservesOnce(t *testing.T) {
	w, m := harness(t)
	d := m.put([]byte("abc"))
	var calls atomic.Int32
	m.batchRead = func(context.Context, *re.BatchReadBlobsRequest) (*re.BatchReadBlobsResponse, error) {
		calls.Add(1)
		return nil, status.Error(codes.Unimplemented, "unsupported")
	}
	root, err := os.OpenRoot(t.TempDir())
	if err != nil {
		t.Fatal(err)
	}
	defer root.Close()
	for i := 0; i < 2; i++ {
		if err := w.materializeFiles(context.Background(), root, "", []*re.FileNode{{Name: fmt.Sprintf("a%d", i), Digest: d}, {Name: fmt.Sprintf("b%d", i), Digest: d}}); err != nil {
			t.Fatal(err)
		}
	}
	if calls.Load() != 1 || w.CAS.transferred != 12 {
		t.Fatalf("calls=%d budget=%d", calls.Load(), w.CAS.transferred)
	}
}
func TestBatchBudgetAndCancellation(t *testing.T) {
	w, m := harness(t)
	d := m.put([]byte("abc"))
	var calls atomic.Int32
	m.batchRead = func(ctx context.Context, _ *re.BatchReadBlobsRequest) (*re.BatchReadBlobsResponse, error) {
		calls.Add(1)
		<-ctx.Done()
		return nil, status.FromContextError(ctx.Err()).Err()
	}
	w.CAS.transferred = MaxTransfer - 5
	if _, err := w.CAS.ReadBatch(context.Background(), []*re.Digest{d, d}); status.Code(err) != codes.ResourceExhausted {
		t.Fatalf("budget: %v", err)
	}
	if calls.Load() != 0 {
		t.Fatal("RPC exceeded budget")
	}
	w.CAS.transferred = 0
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := w.CAS.ReadBatch(ctx, []*re.Digest{d, d}); status.Code(err) != codes.Canceled {
		t.Fatalf("cancel: %v", err)
	}
	a := action(t, m, "touch should-not-run", &re.Directory{}, nil)
	if response, _ := w.Execute(ctx, a, true); codes.Code(response.Status.Code) != codes.Canceled {
		t.Fatalf("cancel response: %v", response)
	}
}

func TestBatchByteBoundAndActiveCancellation(t *testing.T) {
	t.Run("byte bound", func(t *testing.T) {
		w, m := harness(t)
		d := m.put(make([]byte, inputBatchFileBytes))
		var calls atomic.Int32
		m.batchRead = func(_ context.Context, r *re.BatchReadBlobsRequest) (*re.BatchReadBlobsResponse, error) {
			calls.Add(1)
			return batchResponse(m, r), nil
		}
		files := []*re.FileNode{}
		for i := 0; i < 35; i++ {
			files = append(files, &re.FileNode{Name: fmt.Sprint(i), Digest: d})
		}
		root, err := os.OpenRoot(t.TempDir())
		if err != nil {
			t.Fatal(err)
		}
		defer root.Close()
		if err := w.materializeFiles(context.Background(), root, "", files); err != nil {
			t.Fatal(err)
		}
		if calls.Load() != 3 || w.CAS.transferred != 35*inputBatchFileBytes {
			t.Fatalf("calls=%d transferred=%d", calls.Load(), w.CAS.transferred)
		}
	})
	t.Run("active cancellation", func(t *testing.T) {
		w, m := harness(t)
		d := m.put([]byte("a"))
		started := make(chan struct{})
		stopped := make(chan struct{})
		m.batchRead = func(ctx context.Context, _ *re.BatchReadBlobsRequest) (*re.BatchReadBlobsResponse, error) {
			close(started)
			<-ctx.Done()
			close(stopped)
			return nil, status.FromContextError(ctx.Err()).Err()
		}
		a := action(t, m, "printf should-not-run", &re.Directory{Files: []*re.FileNode{{Name: "a", Digest: d}, {Name: "b", Digest: d}}}, nil)
		ctx, cancel := context.WithCancel(context.Background())
		defer cancel()
		response := make(chan *re.ExecuteResponse, 1)
		go func() { r, _ := w.Execute(ctx, a, true); response <- r }()
		<-started
		cancel()
		if r := <-response; codes.Code(r.Status.Code) != codes.Canceled {
			t.Fatalf("response %v", r)
		}
		<-stopped
		if m.writes.Load() != 0 {
			t.Fatal("command output uploaded after cancellation")
		}
	})
}

func TestInputTreeUsesUnaryReadsAndBatchesSubdirectories(t *testing.T) {
	w, m := harness(t)
	var batches, streams atomic.Int32
	m.batchRead = func(_ context.Context, r *re.BatchReadBlobsRequest) (*re.BatchReadBlobsResponse, error) {
		batches.Add(1)
		return batchResponse(m, r), nil
	}
	m.beforeRead = func(context.Context, string) error { streams.Add(1); return nil }
	leaf := &re.Directory{Files: []*re.FileNode{{Name: "input", Digest: m.put([]byte("chained\n"))}}}
	sibling := &re.Directory{Files: []*re.FileNode{{Name: "other", Digest: m.put([]byte("other\n"))}}}
	middle := &re.Directory{Directories: []*re.DirectoryNode{{Name: "leaf", Digest: m.message(t, leaf)}, {Name: "sibling", Digest: m.message(t, sibling)}}}
	root := &re.Directory{Directories: []*re.DirectoryNode{{Name: "out", Digest: m.message(t, middle)}}}
	d := action(t, m, "cat out/leaf/input out/sibling/other > result", root, []string{"result"})
	response, _ := w.Execute(context.Background(), d, true)
	if response.Status.Code != 0 || response.Result.GetExitCode() != 0 {
		t.Fatalf("execute: %v", response)
	}
	// The action; its command with the input root; out; out's two subdirectories
	// together; then each leaf directory's file.
	if batches.Load() != 6 || streams.Load() != 0 {
		t.Fatalf("batches=%d streams=%d", batches.Load(), streams.Load())
	}
	if string(m.blobs[response.Result.OutputFiles[0].Digest.Hash]) != "chained\nother\n" {
		t.Fatal("wrong output")
	}
}
