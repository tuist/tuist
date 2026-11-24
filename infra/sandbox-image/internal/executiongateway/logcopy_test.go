package executiongateway

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"strings"
	"testing"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"github.com/prometheus/client_golang/prometheus/testutil"
	bs "google.golang.org/genproto/googleapis/bytestream"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/test/bufconn"
	"google.golang.org/protobuf/proto"
)

const logTail = 40 << 10

// logGateway runs an action whose stderr is longer than a record keeps. The
// control plane answers each record with an upload of the stderr's last
// logTail bytes; storage handles those uploads.
func logGateway(t *testing.T, storage transport) (*Gateway, func(), []byte, chan struct{}) {
	t.Helper()
	store := &blobStore{blobs: map[string][]byte{}}
	var lines strings.Builder
	for i := 0; lines.Len() < 100<<10; i++ {
		fmt.Fprintf(&lines, "line %d\n", i)
	}
	stderr := []byte(lines.String())
	digest := store.put(stderr)
	action := store.message(&re.Action{CommandDigest: store.message(&re.Command{Arguments: []string{"cc"}}), InputRootDigest: store.message(&re.Directory{})})
	b, _ := proto.Marshal(&re.ExecuteResponse{Result: &re.ActionResult{ExitCode: 1, StderrDigest: digest}})

	g := New("https://control.example")
	g.LogUploads.Transport = storage
	l := bufconn.Listen(1 << 20)
	s := grpc.NewServer()
	re.RegisterContentAddressableStorageServer(s, store)
	bs.RegisterByteStreamServer(s, &byteStore{store: store})
	go s.Serve(l)
	t.Cleanup(s.Stop)
	g.Dial = func(string) (*grpc.ClientConn, error) {
		return grpc.NewClient("passthrough:///cache", grpc.WithTransportCredentials(insecure.NewCredentials()), grpc.WithContextDialer(func(context.Context, string) (net.Conn, error) { return l.Dial() }))
	}
	posted := make(chan struct{}, 16)
	client, _ := gatewayWith(t, g, func(r *http.Request) (*http.Response, error) {
		switch {
		case strings.HasSuffix(r.URL.Path, "/capabilities"):
			return response(200, `{"cas_endpoint":"cache"}`), nil
		case strings.HasSuffix(r.URL.Path, "/actions"):
			var body struct{ Actions []actionRecord }
			_ = json.NewDecoder(r.Body).Decode(&body)
			posted <- struct{}{}
			if len(body.Actions) != 1 || body.Actions[0].StderrHash != digest.Hash || body.Actions[0].StdoutHash != "" {
				t.Errorf("the record does not name the long stream: %+v", body.Actions)
			}
			size := int64(len(stderr))
			answer, _ := json.Marshal(map[string]any{"accepted": 1, "log_uploads": []logUpload{{Hash: digest.Hash, Size: size, Offset: size - logTail, Length: logTail, URL: "https://storage.example/logs/stderr?signature=1"}}})
			return response(202, string(answer)), nil
		}
		return response(200, `{"id":"`+id+`","state":"completed","response":"`+base64.StdEncoding.EncodeToString(b)+`"}`), nil
	})
	request, _ := proto.Marshal(&re.RequestMetadata{ToolInvocationId: "inv-1", ActionMnemonic: "CppCompile"})
	execute := func() {
		ctx := metadata.AppendToOutgoingContext(authenticated(), requestMetadataHeader, string(request))
		stream, err := client.Execute(ctx, &re.ExecuteRequest{InstanceName: "app", ActionDigest: action})
		if err != nil {
			t.Fatal(err)
		}
		if done, err := stream.Recv(); err != nil || !done.Done {
			t.Fatalf("result: %v %v", done, err)
		}
	}
	return g, execute, stderr, posted
}

func TestLongLogTailIsCopiedToStorageOverItsOwnConnection(t *testing.T) {
	uploads := make(chan *http.Request, 1)
	bodies := make(chan []byte, 1)
	g, execute, stderr, _ := logGateway(t, func(r *http.Request) (*http.Response, error) {
		body, _ := io.ReadAll(r.Body)
		uploads <- r
		bodies <- body
		return response(200, ""), nil
	})
	execute()

	var r *http.Request
	select {
	case r = <-uploads:
	case <-time.After(5 * time.Second):
		t.Fatal("the log was not copied")
	}
	if r.Method != http.MethodPut || r.URL.String() != "https://storage.example/logs/stderr?signature=1" || r.ContentLength != logTail || r.Header.Get("Authorization") != "" {
		t.Fatalf("upload: %s %s length %d auth %q", r.Method, r.URL, r.ContentLength, r.Header.Get("Authorization"))
	}
	if body := <-bodies; string(body) != string(stderr[len(stderr)-logTail:]) {
		t.Fatalf("uploaded %d bytes that are not the stream's end", len(body))
	}
	deadline := time.Now().Add(time.Second)
	for testutil.ToFloat64(g.metrics.logCopies.WithLabelValues("copied")) != 1 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if testutil.ToFloat64(g.metrics.logCopies.WithLabelValues("copied")) != 1 || testutil.ToFloat64(g.metrics.logBytes) != logTail {
		t.Fatal("the copy was not counted")
	}
	g.mu.Lock()
	shared := g.conns["cache"]
	g.mu.Unlock()
	if copying := g.logs.conns["cache"]; copying == nil || copying == shared {
		t.Fatal("copies read the cache over the client's connection")
	}
}

// Storage that never answers holds both copiers and fills the queue; neither
// execution nor records wait for it, and copies past the queue are dropped.
func TestStuckLogCopiesNeverHoldUpExecution(t *testing.T) {
	release := make(chan struct{})
	t.Cleanup(func() { close(release) })
	g, execute, _, posted := logGateway(t, func(r *http.Request) (*http.Response, error) {
		<-release
		return nil, fmt.Errorf("released")
	})

	for i := range 3 {
		started := time.Now()
		execute()
		if elapsed := time.Since(started); elapsed > time.Second {
			t.Fatalf("execution %d took %v behind stuck copies", i, elapsed)
		}
		select {
		case <-posted:
		case <-time.After(5 * time.Second):
			t.Fatalf("the record of execution %d was not sent", i)
		}
	}

	started := time.Now()
	scope := recordScope{"tuist", "app", "Bearer secret"}
	upload := logUpload{Hash: strings.Repeat("a", 64), Size: 10, Length: 10, URL: "https://storage.example/x"}
	for range logCopyQueue + 50 {
		g.copyLog(scope, upload)
	}
	if elapsed := time.Since(started); elapsed > 100*time.Millisecond {
		t.Fatalf("queueing copies took %v", elapsed)
	}
	if len(g.logs.queue) != logCopyQueue || testutil.ToFloat64(g.metrics.logCopies.WithLabelValues("dropped")) < 50 {
		t.Fatalf("queue %d, dropped %v", len(g.logs.queue), testutil.ToFloat64(g.metrics.logCopies.WithLabelValues("dropped")))
	}
}

func TestOutOfBoundsLogUploadsAreRefused(t *testing.T) {
	g := New("https://control.example")
	scope := recordScope{"tuist", "app", "Bearer secret"}
	hash := strings.Repeat("a", 64)
	for _, u := range []logUpload{
		{Hash: hash, Size: maxLogCopy + 1, Length: maxLogCopy + 1, URL: "https://storage.example/x"},
		{Hash: hash, Size: 10, Offset: 5, Length: 10, URL: "https://storage.example/x"},
		{Hash: hash, Size: 10, Length: 10, URL: "http://storage.example/x"},
		{Hash: "../" + hash[3:], Size: 10, Length: 10, URL: "https://storage.example/x"},
	} {
		g.copyLog(scope, u)
	}
	if testutil.ToFloat64(g.metrics.logCopies.WithLabelValues("refused")) != 4 || len(g.logs.queue) != 0 {
		t.Fatal("an out-of-bounds upload was queued")
	}
}

func TestByteRateSpacesWritesWithoutBursting(t *testing.T) {
	r := byteRate{perSecond: 10_000}
	started := time.Now()
	for range 5 {
		if err := r.wait(context.Background(), 1_000); err != nil {
			t.Fatal(err)
		}
	}
	// 100ms a write; the first starts at once.
	if elapsed := time.Since(started); elapsed < 400*time.Millisecond || elapsed > 700*time.Millisecond {
		t.Fatalf("5 writes of a tenth of the rate took %v", elapsed)
	}
	// The next write is due in 100ms; a cancelled wait does not sleep until then.
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if r.wait(ctx, 1) == nil {
		t.Fatal("a cancelled wait did not stop")
	}
}
