package reapi

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
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

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	bs "google.golang.org/genproto/googleapis/bytestream"
	"google.golang.org/genproto/googleapis/rpc/errdetails"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/status"
	"google.golang.org/grpc/test/bufconn"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/durationpb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type memoryCAS struct {
	bs.UnimplementedByteStreamServer
	re.UnimplementedActionCacheServer
	re.UnimplementedContentAddressableStorageServer
	mu      sync.Mutex
	blobs   map[string][]byte
	actions map[string]*re.ActionResult
	writes  atomic.Int32
	// Set before issuing requests; only tests needing a read barrier use it.
	beforeRead   func(context.Context, string) error
	batchRead    func(context.Context, *re.BatchReadBlobsRequest) (*re.BatchReadBlobsResponse, error)
	beforeUpdate func()
	beforeWrite  func() error
}

func (m *memoryCAS) BatchReadBlobs(ctx context.Context, request *re.BatchReadBlobsRequest) (*re.BatchReadBlobsResponse, error) {
	if m.batchRead == nil {
		return nil, status.Error(codes.Unimplemented, "streaming only")
	}
	return m.batchRead(ctx, request)
}

func (m *memoryCAS) put(b []byte) *re.Digest {
	m.mu.Lock()
	defer m.mu.Unlock()
	h := sha256.Sum256(b)
	d := &re.Digest{Hash: hex.EncodeToString(h[:]), SizeBytes: int64(len(b))}
	m.blobs[d.Hash] = b
	return d
}
func (m *memoryCAS) message(t *testing.T, v proto.Message) *re.Digest {
	t.Helper()
	b, err := proto.Marshal(v)
	if err != nil {
		t.Fatal(err)
	}
	return m.put(b)
}
func (m *memoryCAS) Read(r *bs.ReadRequest, s bs.ByteStream_ReadServer) error {
	parts := strings.Split(r.ResourceName, "/")
	m.mu.Lock()
	b, ok := m.blobs[parts[len(parts)-2]]
	m.mu.Unlock()
	if m.beforeRead != nil {
		if err := m.beforeRead(s.Context(), parts[len(parts)-2]); err != nil {
			return err
		}
	}
	if !ok {
		return status.Error(codes.NotFound, "missing input")
	}
	return s.Send(&bs.ReadResponse{Data: b})
}
func (m *memoryCAS) Write(s bs.ByteStream_WriteServer) error {
	m.writes.Add(1)
	if m.beforeWrite != nil {
		if err := m.beforeWrite(); err != nil {
			return err
		}
	}
	var data []byte
	var resource string
	for {
		r, err := s.Recv()
		if err != nil {
			return err
		}
		if r.ResourceName != "" {
			resource = r.ResourceName
		}
		if int64(len(data)) != r.WriteOffset {
			return status.Error(codes.InvalidArgument, "offset")
		}
		data = append(data, r.Data...)
		if r.FinishWrite {
			break
		}
	}
	parts := strings.Split(resource, "/")
	h := sha256.Sum256(data)
	if hex.EncodeToString(h[:]) != parts[len(parts)-2] {
		return status.Error(codes.InvalidArgument, "digest")
	}
	m.put(data)
	return s.SendAndClose(&bs.WriteResponse{CommittedSize: int64(len(data))})
}
func (m *memoryCAS) GetActionResult(_ context.Context, r *re.GetActionResultRequest) (*re.ActionResult, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if result, ok := m.actions[r.ActionDigest.Hash]; ok {
		return proto.Clone(result).(*re.ActionResult), nil
	}
	return nil, status.Error(codes.NotFound, "miss")
}
func (m *memoryCAS) UpdateActionResult(_ context.Context, r *re.UpdateActionResultRequest) (*re.ActionResult, error) {
	if m.beforeUpdate != nil {
		m.beforeUpdate()
	}
	m.mu.Lock()
	defer m.mu.Unlock()
	m.actions[r.ActionDigest.Hash] = proto.Clone(r.ActionResult).(*re.ActionResult)
	return r.ActionResult, nil
}

func TestWorkerLeavesCachePublicationToCaller(t *testing.T) {
	w, m := harness(t)
	m.beforeUpdate = func() { t.Fatal("worker published to the action cache") }
	for _, test := range []struct {
		cmd        string
		doNotCache bool
		cacheable  bool
	}{{"true", false, true}, {"exit 3", false, false}, {"true", true, false}} {
		d := action(t, m, test.cmd, &re.Directory{}, nil)
		if test.doNotCache {
			var a re.Action
			proto.Unmarshal(m.blobs[d.Hash], &a)
			a.DoNotCache = true
			d = m.message(t, &a)
		}
		w.Root = filepath.Join(t.TempDir(), "action")
		response, cacheable := w.Execute(context.Background(), d, true)
		if response.Status.Code != 0 || cacheable != test.cacheable {
			t.Fatalf("%s: cacheable %v, response %v", test.cmd, cacheable, response)
		}
	}
}

// publish stands in for the gateway, which stores cacheable results.
func publish(t *testing.T, m *memoryCAS, d *re.Digest, response *re.ExecuteResponse, cacheable bool) {
	t.Helper()
	if !cacheable {
		t.Fatal("successful result is not cacheable")
	}
	if _, err := m.UpdateActionResult(context.Background(), &re.UpdateActionResultRequest{ActionDigest: d, ActionResult: response.Result}); err != nil {
		t.Fatal(err)
	}
}

func harness(t *testing.T) (*Worker, *memoryCAS) {
	t.Helper()
	memory := &memoryCAS{blobs: map[string][]byte{}, actions: map[string]*re.ActionResult{}}
	listener := bufconn.Listen(1 << 20)
	server := grpc.NewServer()
	bs.RegisterByteStreamServer(server, memory)
	re.RegisterActionCacheServer(server, memory)
	re.RegisterContentAddressableStorageServer(server, memory)
	go server.Serve(listener)
	t.Cleanup(server.Stop)
	conn, err := grpc.NewClient("passthrough:///cas", grpc.WithTransportCredentials(insecure.NewCredentials()), grpc.WithContextDialer(func(context.Context, string) (net.Conn, error) { return listener.Dial() }))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { conn.Close() })
	return &Worker{CAS: NewCAS(conn, "project"), Root: filepath.Join(t.TempDir(), "action"), Image: "sha-test"}, memory
}

func action(t *testing.T, m *memoryCAS, command string, inputs *re.Directory, outputs []string) *re.Digest {
	c := &re.Command{Arguments: []string{"/bin/sh", "-c", command}, OutputPaths: outputs, EnvironmentVariables: []*re.Command_EnvironmentVariable{{Name: "PATH", Value: "/usr/bin:/bin"}}}
	return m.message(t, &re.Action{CommandDigest: m.message(t, c), InputRootDigest: m.message(t, inputs), Platform: &re.Platform{Properties: []*re.Platform_Property{{Name: "OSFamily", Value: "Linux"}, {Name: "Arch", Value: "amd64"}, {Name: "tuist-image", Value: "sha-test"}}}})
}

func TestMissingInputRetainsBazelRetryDetails(t *testing.T) {
	w, m := harness(t)
	missing := &re.Digest{Hash: strings.Repeat("a", 64), SizeBytes: 5}
	d := action(t, m, "true", &re.Directory{Files: []*re.FileNode{{Name: "missing", Digest: missing}}}, nil)
	response, _ := w.Execute(context.Background(), d, true)
	s := status.FromProto(response.Status)
	if s.Code() != codes.FailedPrecondition || len(s.Details()) != 1 {
		t.Fatalf("missing input status: %v", response)
	}
	detail, ok := s.Details()[0].(*errdetails.PreconditionFailure)
	if !ok || len(detail.Violations) != 1 || detail.Violations[0].Type != "MISSING" || detail.Violations[0].Subject != "blobs/"+missing.Hash+"/5" {
		t.Fatalf("missing input details: %v", s.Details())
	}
}

func TestWorkerCompilesAndRunsCProgram(t *testing.T) {
	if _, err := os.Stat("/usr/bin/cc"); os.IsNotExist(err) {
		t.Skip("requires a C compiler (run on the native Linux CI runner)")
	}
	w, m := harness(t)
	source := m.put([]byte("#include <stdio.h>\nint main(void) { puts(\"remote compilation\"); return 0; }\n"))
	d := action(t, m, "/usr/bin/cc hello.c -o hello && ./hello", &re.Directory{Files: []*re.FileNode{{Name: "hello.c", Digest: source}}}, []string{"hello"})
	response, _ := w.Execute(context.Background(), d, true)
	if response.Status.Code != 0 || response.Result.GetExitCode() != 0 || len(response.Result.GetOutputFiles()) != 1 {
		t.Fatalf("compile and run: %v", response)
	}
	if !response.Result.OutputFiles[0].IsExecutable || string(m.blobs[response.Result.StdoutDigest.Hash]) != "remote compilation\n" {
		t.Fatalf("compiled output: %v", response.Result)
	}
}

func TestWorkerRoundTripAndCache(t *testing.T) {
	w, m := harness(t)
	d := action(t, m, "cat input > output; chmod +x output; mkdir -p tree/nested; cp input tree/nested/copy; printf 'compiler log'; printf 'warning' >&2", &re.Directory{Files: []*re.FileNode{{Name: "input", Digest: m.put([]byte("hello\n"))}}}, []string{"output", "tree"})
	response, cacheable := w.Execute(context.Background(), d, false)
	if response.Status.Code != 0 || response.Result.GetExitCode() != 0 {
		t.Fatalf("execute: %v", response)
	}
	result := response.Result
	timing := result.ExecutionMetadata
	timestamps := []*timestamppb.Timestamp{timing.WorkerStartTimestamp, timing.InputFetchStartTimestamp,
		timing.InputFetchCompletedTimestamp, timing.ExecutionStartTimestamp, timing.ExecutionCompletedTimestamp,
		timing.OutputUploadStartTimestamp, timing.OutputUploadCompletedTimestamp, timing.WorkerCompletedTimestamp}
	for i, timestamp := range timestamps {
		if timestamp == nil || timestamp.CheckValid() != nil || (i > 0 && timestamp.AsTime().Before(timestamps[i-1].AsTime())) {
			t.Fatalf("invalid worker phase chronology: %v", timing)
		}
	}
	if len(result.OutputFiles) != 1 || !result.OutputFiles[0].IsExecutable {
		t.Fatalf("outputs: %v", result)
	}
	if string(m.blobs[result.StdoutDigest.Hash]) != "compiler log" || string(m.blobs[result.StderrDigest.Hash]) != "warning" {
		t.Fatal("logs not uploaded")
	}
	if string(m.blobs[result.OutputFiles[0].Digest.Hash]) != "hello\n" {
		t.Fatal("wrong output")
	}
	var tree re.Tree
	if err := proto.Unmarshal(m.blobs[result.OutputDirectories[0].TreeDigest.Hash], &tree); err != nil {
		t.Fatal(err)
	}
	if len(tree.Root.Directories) != 1 || len(tree.Children) != 1 || tree.Children[0].Files[0].Name != "copy" {
		t.Fatalf("tree: %v", &tree)
	}
	publish(t, m, d, response, cacheable)
	w.Root = filepath.Join(t.TempDir(), "cached")
	response, _ = w.Execute(context.Background(), d, false)
	if !response.CachedResult || response.Status.Code != 0 {
		t.Fatalf("cache: %v", response)
	}
	if _, err := os.Stat(w.Root); !os.IsNotExist(err) {
		t.Fatal("cache hit created workspace")
	}
}

func TestWorkerFailureAndTimeout(t *testing.T) {
	for _, test := range []struct {
		name, cmd string
		timeout   time.Duration
		code      codes.Code
		exit      int32
	}{{"failure", "printf failed >&2; exit 7", 0, codes.OK, 7}, {"timeout", "sleep 30", 30 * time.Millisecond, codes.DeadlineExceeded, 124}} {
		t.Run(test.name, func(t *testing.T) {
			w, m := harness(t)
			d := action(t, m, test.cmd, &re.Directory{}, nil)
			if test.timeout > 0 {
				var a re.Action
				proto.Unmarshal(m.blobs[d.Hash], &a)
				a.Timeout = durationpb.New(test.timeout)
				d = m.message(t, &a)
			}
			r, _ := w.Execute(context.Background(), d, false)
			if r.Status.Code != int32(test.code) || r.Result.GetExitCode() != test.exit {
				t.Fatalf("response: %v", r)
			}
			if len(m.actions) != 0 {
				t.Fatal("failed action was cached")
			}
		})
	}
}

func TestWorkerRejectsUntrustedInput(t *testing.T) {
	for _, test := range []struct {
		name  string
		input func(*memoryCAS) *re.Directory
		code  codes.Code
	}{
		{"traversal", func(m *memoryCAS) *re.Directory {
			return &re.Directory{Files: []*re.FileNode{{Name: "../escape", Digest: m.put(nil)}}}
		}, codes.InvalidArgument},
		{"duplicate", func(m *memoryCAS) *re.Directory {
			return &re.Directory{Files: []*re.FileNode{{Name: "x", Digest: m.put(nil)}, {Name: "x", Digest: m.put(nil)}}}
		}, codes.InvalidArgument},
		{"symlink", func(m *memoryCAS) *re.Directory {
			return &re.Directory{Symlinks: []*re.SymlinkNode{{Name: "escape", Target: "/etc/passwd"}}}
		}, codes.InvalidArgument},
		{"corrupt", func(m *memoryCAS) *re.Directory {
			d := m.put([]byte("right"))
			m.blobs[d.Hash] = []byte("wrong")
			return &re.Directory{Files: []*re.FileNode{{Name: "x", Digest: d}}}
		}, codes.DataLoss},
	} {
		t.Run(test.name, func(t *testing.T) {
			w, m := harness(t)
			d := action(t, m, "touch executed", test.input(m), nil)
			r, _ := w.Execute(context.Background(), d, false)
			if r.Status.Code != int32(test.code) {
				t.Fatalf("response: %v", r)
			}
			if _, err := os.Stat(filepath.Join(w.Root, "executed")); !os.IsNotExist(err) {
				t.Fatal("invalid input executed")
			}
		})
	}
}

func TestWorkerRequiresImageAndExplicitEnvironment(t *testing.T) {
	w, m := harness(t)
	d := action(t, m, "printf '%s' \"${SBX_EXECUTION_TOKEN-unset}\"", &re.Directory{}, nil)
	r, _ := w.Execute(context.Background(), d, true)
	if r.Status.Code != 0 || string(m.blobs[r.Result.StdoutDigest.Hash]) != "unset" {
		t.Fatalf("environment: %v", r)
	}
	w.Image = "other"
	r, _ = w.Execute(context.Background(), d, false)
	if r.Status.Code != int32(codes.FailedPrecondition) {
		t.Fatalf("image: %v", r)
	}
}

func TestCASReadsOutputFromStart(t *testing.T) {
	w, m := harness(t)
	f, err := os.CreateTemp(t.TempDir(), "log")
	if err != nil {
		t.Fatal(err)
	}
	defer f.Close()
	io.WriteString(f, "all log bytes")
	d, err := w.CAS.Write(context.Background(), f)
	if err != nil {
		t.Fatal(err)
	}
	if string(m.blobs[d.Hash]) != "all log bytes" {
		t.Fatal("seek was not reset")
	}
}

func TestEmptyLogsDoNotUploadBlobs(t *testing.T) {
	w, m := harness(t)
	d := action(t, m, "true", &re.Directory{}, nil)
	result, cacheable := w.Execute(context.Background(), d, false)
	if result.Status.Code != 0 || result.Result.ExitCode != 0 {
		t.Fatalf("execution: %v", result)
	}
	if result.Result.StdoutDigest != nil || result.Result.StderrDigest != nil {
		t.Fatalf("empty logs have digests: %v", result.Result)
	}
	if m.writes.Load() != 0 {
		t.Fatal("silent action uploaded empty log blobs")
	}
	publish(t, m, d, result, cacheable)
	w.Root = filepath.Join(t.TempDir(), "cached")
	cached, _ := w.Execute(context.Background(), d, false)
	if !cached.CachedResult || !proto.Equal(cached.Result, m.actions[d.Hash]) {
		t.Fatalf("cached result changed: %v", cached)
	}
}

func TestInputDownloadsAreBoundedAndCompleteBeforeExecution(t *testing.T) {
	w, m := harness(t)
	dir := &re.Directory{}
	inputs := map[string]bool{}
	for i := range 32 {
		digest := m.put([]byte(fmt.Sprintf("input %d\n", i)))
		inputs[digest.Hash] = true
		dir.Files = append(dir.Files, &re.FileNode{Name: fmt.Sprintf("input-%02d", i), Digest: digest, IsExecutable: i%2 == 0})
	}
	barrier := make(chan struct{})
	var arrivals, active, peak atomic.Int32
	m.beforeRead = func(ctx context.Context, hash string) error {
		if !inputs[hash] {
			return nil
		}
		n := active.Add(1)
		defer active.Add(-1)
		for old := peak.Load(); n > old && !peak.CompareAndSwap(old, n); old = peak.Load() {
		}
		if arrivals.Add(1) == inputDownloadConcurrency {
			close(barrier)
		}
		select {
		case <-barrier:
			return nil
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	digest := action(t, m, "cat input-* > output", dir, []string{"output"})
	response, _ := w.Execute(ctx, digest, true)
	if response.Status.Code != 0 || response.Result.GetExitCode() != 0 {
		t.Fatalf("parallel materialization: %v", response)
	}
	if peak.Load() != inputDownloadConcurrency || arrivals.Load() != 32 {
		t.Fatalf("parallelism peak=%d, completed=%d", peak.Load(), arrivals.Load())
	}
	var expected strings.Builder
	for i, input := range dir.Files {
		fmt.Fprintf(&expected, "input %d\n", i)
		info, err := os.Stat(filepath.Join(w.Root, input.Name))
		if err != nil || (info.Mode()&0111 != 0) != input.IsExecutable {
			t.Fatalf("materialized mode for %s: %v %v", input.Name, info, err)
		}
	}
	if string(m.blobs[response.Result.OutputFiles[0].Digest.Hash]) != expected.String() {
		t.Fatal("command ran before inputs were completely materialized")
	}
}

func TestInputDownloadFailureCancelsPeersAndDoesNotExecute(t *testing.T) {
	w, m := harness(t)
	dir := &re.Directory{}
	inputs := map[string]bool{}
	for i := range inputDownloadConcurrency {
		digest := m.put([]byte(fmt.Sprintf("input %d", i)))
		inputs[digest.Hash] = true
		dir.Files = append(dir.Files, &re.FileNode{Name: fmt.Sprintf("input-%d", i), Digest: digest})
	}
	missing := dir.Files[0].Digest
	delete(m.blobs, missing.Hash)
	barrier := make(chan struct{})
	stopped := make(chan struct{}, inputDownloadConcurrency-1)
	var arrivals atomic.Int32
	m.beforeRead = func(ctx context.Context, hash string) error {
		if !inputs[hash] {
			return nil
		}
		if arrivals.Add(1) == inputDownloadConcurrency {
			close(barrier)
		}
		select {
		case <-barrier:
		case <-ctx.Done():
			return ctx.Err()
		}
		if hash == missing.Hash {
			return nil
		}
		<-ctx.Done()
		stopped <- struct{}{}
		return ctx.Err()
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	digest := action(t, m, "touch executed", dir, nil)
	response, _ := w.Execute(ctx, digest, true)
	if response.Status.Code != int32(codes.FailedPrecondition) {
		t.Fatalf("lost the original missing-input error: %v", response)
	}
	for range inputDownloadConcurrency - 1 {
		select {
		case <-stopped:
		case <-ctx.Done():
			t.Fatal("peer download did not cancel")
		}
	}
	if _, err := os.Stat(filepath.Join(w.Root, "executed")); !os.IsNotExist(err) {
		t.Fatal("command ran after input download failed")
	}
}

func TestConcurrentTransfersCannotExceedActionBudget(t *testing.T) {
	cas := &CAS{}
	var successes atomic.Int32
	var workers sync.WaitGroup
	for range 32 {
		workers.Go(func() {
			err := cas.reserve(MaxBlob)
			if err == nil {
				successes.Add(1)
			} else if status.Code(err) != codes.ResourceExhausted {
				t.Errorf("unexpected reservation error: %v", err)
			}
		})
	}
	workers.Wait()
	if int64(successes.Load()) != MaxTransfer/MaxBlob || cas.transferred != MaxTransfer {
		t.Fatalf("transfer limit escaped: successes=%d bytes=%d", successes.Load(), cas.transferred)
	}
}

// Each new blob costs the CAS a durable write; concurrent uploads share it.
func TestOutputsUploadConcurrently(t *testing.T) {
	w, m := harness(t)
	var inFlight atomic.Int32
	all := make(chan struct{})
	m.beforeWrite = func() error {
		if inFlight.Add(1) == 3 {
			close(all)
		}
		select {
		case <-all:
			return nil
		case <-time.After(2 * time.Second):
			return status.Error(codes.DeadlineExceeded, "outputs were uploaded one at a time")
		}
	}
	d := action(t, m, "printf a > a; printf b > b; printf c > c", &re.Directory{}, []string{"a", "b", "c"})
	result, _ := w.Execute(context.Background(), d, false)
	if result.Status.Code != 0 || len(result.Result.OutputFiles) != 3 {
		t.Fatalf("execution: %v", result)
	}
	for _, f := range result.Result.OutputFiles {
		if _, ok := m.blobs[f.Digest.Hash]; !ok {
			t.Fatalf("output %s missing from CAS", f.Path)
		}
	}
}

func TestIdenticalOutputsUploadOnce(t *testing.T) {
	w, m := harness(t)
	d := action(t, m, "printf same > a; printf same > b; mkdir c; printf same > c/d", &re.Directory{}, []string{"a", "b", "c"})
	result, _ := w.Execute(context.Background(), d, false)
	if result.Status.Code != 0 || len(result.Result.OutputFiles) != 2 || len(result.Result.OutputDirectories) != 1 {
		t.Fatalf("execution: %v", result)
	}
	// One file blob and one tree.
	if got := m.writes.Load(); got != 2 {
		t.Fatalf("uploaded %d blobs, want 2", got)
	}
}
