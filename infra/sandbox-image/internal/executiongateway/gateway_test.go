package executiongateway

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"strings"
	"sync/atomic"
	"testing"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	rpc "google.golang.org/genproto/googleapis/rpc/status"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"google.golang.org/grpc/test/bufconn"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/timestamppb"
)

type transport func(*http.Request) (*http.Response, error)

func (f transport) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }
func response(code int, body string) *http.Response {
	return &http.Response{StatusCode: code, Body: io.NopCloser(strings.NewReader(body)), Header: http.Header{}}
}

const id = "11111111-2222-3333-4444-555555555555"

func gateway(t *testing.T, roundtrip transport) (re.ExecutionClient, re.CapabilitiesClient) {
	t.Helper()
	return gatewayWith(t, New("https://control.example"), roundtrip)
}

func gatewayWith(t *testing.T, g *Gateway, roundtrip transport) (re.ExecutionClient, re.CapabilitiesClient) {
	t.Helper()
	g.Client.Transport = roundtrip
	l := bufconn.Listen(1 << 20)
	s := grpc.NewServer()
	g.Register(s)
	go s.Serve(l)
	t.Cleanup(s.Stop)
	c, err := grpc.NewClient("passthrough:///gateway", grpc.WithTransportCredentials(insecure.NewCredentials()), grpc.WithContextDialer(func(context.Context, string) (net.Conn, error) { return l.Dial() }))
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { c.Close() })
	return re.NewExecutionClient(c), re.NewCapabilitiesClient(c)
}
func authenticated() context.Context {
	return metadata.NewOutgoingContext(context.Background(), metadata.Pairs("authorization", "Bearer secret", "x-tuist-account-handle", "tuist"))
}

func TestExecuteAndReconnectAcrossGateways(t *testing.T) {
	started := timestamppb.New(time.UnixMicro(1793157000123956))
	b, _ := proto.Marshal(&re.ExecuteResponse{Result: &re.ActionResult{ExitCode: 7, ExecutionMetadata: &re.ExecutedActionMetadata{WorkerStartTimestamp: started}}})
	control := transport(func(r *http.Request) (*http.Response, error) {
		if r.Header.Get("Authorization") != "Bearer secret" || !strings.HasPrefix(r.URL.Path, "/api/remote-execution/tuist/app/") {
			t.Errorf("wrong auth/scope: %v", r.URL)
		}
		if r.Method == http.MethodPost {
			return response(202, `{"id":"`+id+`","state":"queued"}`), nil
		}
		return response(200, `{"id":"`+id+`","state":"completed","queued_at_unix_us":1793157000123456,"response":"`+base64.StdEncoding.EncodeToString(b)+`"}`), nil
	})
	client, _ := gateway(t, control)
	ctx, cancel := context.WithCancel(authenticated())
	stream, err := client.Execute(ctx, &re.ExecuteRequest{InstanceName: "app", ActionDigest: &re.Digest{Hash: strings.Repeat("a", 64), SizeBytes: 5}})
	if err != nil {
		t.Fatal(err)
	}
	first, err := stream.Recv()
	if err != nil {
		t.Fatal(err)
	}
	cancel()
	if first.Done {
		t.Fatal("queued operation completed")
	}
	other, _ := gateway(t, control)
	wait, err := other.WaitExecution(authenticated(), &re.WaitExecutionRequest{Name: first.Name})
	if err != nil {
		t.Fatal(err)
	}
	finished, err := wait.Recv()
	if err != nil {
		t.Fatal(err)
	}
	var result re.ExecuteResponse
	if !finished.Done || finished.GetResponse().UnmarshalTo(&result) != nil || result.Result.ExitCode != 7 {
		t.Fatalf("completion: %v", finished)
	}
	if got := result.Result.ExecutionMetadata.GetQueuedTimestamp().AsTime().UnixMicro(); got != 1793157000123456 {
		t.Fatalf("reconnected gateway lost precise admission time: %d", got)
	}
	if !proto.Equal(result.Result.ExecutionMetadata.WorkerStartTimestamp, started) {
		t.Fatal("gateway changed guest execution timing")
	}
}

func TestQueueTimePreservesCachedAndLegacyMetadata(t *testing.T) {
	for _, tc := range []struct {
		name     string
		queued   int64
		cached   bool
		noResult bool
	}{
		{"cached", 1793157000123456, true, false},
		{"legacy", 0, false, false},
		{"invalid", 9223372036854775807, false, false},
		{"failure", 1793157000123456, false, true},
	} {
		t.Run(tc.name, func(t *testing.T) {
			original := &re.ExecuteResponse{CachedResult: tc.cached, Status: &rpc.Status{}}
			if !tc.noResult {
				original.Result = &re.ActionResult{ExecutionMetadata: &re.ExecutedActionMetadata{
					QueuedTimestamp:      timestamppb.New(time.Unix(100, 0)),
					WorkerStartTimestamp: timestamppb.New(time.Unix(101, 0)),
				}}
			}
			b, _ := proto.Marshal(original)
			body, _ := json.Marshal(operation{ID: id, State: "completed", QueuedAtUnixUS: tc.queued, Response: base64.StdEncoding.EncodeToString(b)})
			client, _ := gateway(t, func(*http.Request) (*http.Response, error) { return response(200, string(body)), nil })
			stream, err := client.WaitExecution(authenticated(), &re.WaitExecutionRequest{Name: "accounts/tuist/projects/app/operations/" + id})
			if err != nil {
				t.Fatal(err)
			}
			finished, err := stream.Recv()
			if err != nil {
				t.Fatal(err)
			}
			var got re.ExecuteResponse
			if err := finished.GetResponse().UnmarshalTo(&got); err != nil {
				t.Fatal(err)
			}
			if !proto.Equal(original, &got) {
				t.Fatalf("metadata changed: %v", &got)
			}
		})
	}
}

func TestGatewayRejectsMissingDuplicateAndForeignCredentials(t *testing.T) {
	client, capabilities := gateway(t, func(*http.Request) (*http.Response, error) {
		t.Error("unauthorized request reached control plane")
		return response(500, ""), nil
	})
	for _, ctx := range []context.Context{context.Background(), metadata.NewOutgoingContext(context.Background(), metadata.Pairs("authorization", "Bearer a", "authorization", "Bearer b", "x-tuist-account-handle", "tuist"))} {
		_, err := capabilities.GetCapabilities(ctx, &re.GetCapabilitiesRequest{InstanceName: "app"})
		if status.Code(err) != codes.Unauthenticated {
			t.Fatalf("auth: %v", err)
		}
	}
	stream, err := client.WaitExecution(authenticated(), &re.WaitExecutionRequest{Name: "accounts/other/projects/app/operations/" + id})
	if err == nil {
		_, err = stream.Recv()
	}
	if status.Code(err) != codes.PermissionDenied {
		t.Fatalf("foreign operation: %v", err)
	}
}

func TestDisabledCapabilityAndBoundedResponse(t *testing.T) {
	_, caps := gateway(t, func(*http.Request) (*http.Response, error) { return response(403, `{}`), nil })
	if _, err := caps.GetCapabilities(authenticated(), &re.GetCapabilitiesRequest{InstanceName: "app"}); status.Code(err) != codes.PermissionDenied {
		t.Fatalf("disabled: %v", err)
	}
	_, caps = gateway(t, func(*http.Request) (*http.Response, error) { return response(200, strings.Repeat("x", 300000)), nil })
	if _, err := caps.GetCapabilities(authenticated(), &re.GetCapabilitiesRequest{InstanceName: "app"}); status.Code(err) != codes.ResourceExhausted {
		t.Fatalf("oversized: %v", err)
	}
}

func TestExecuteUsesBoundedStateChangeWait(t *testing.T) {
	polling := make(chan struct{})
	release := make(chan struct{})
	client, _ := gateway(t, func(r *http.Request) (*http.Response, error) {
		if r.Method == http.MethodPost {
			return response(202, `{"id":"`+id+`","state":"queued"}`), nil
		}
		if got := r.URL.Query().Get("after"); got != "queued" {
			t.Errorf("missing state cursor: %q", got)
		}
		close(polling)
		select {
		case <-release:
			return response(200, `{"id":"`+id+`","state":"completed"}`), nil
		case <-r.Context().Done():
			return nil, r.Context().Err()
		}
	})
	stream, err := client.Execute(authenticated(), &re.ExecuteRequest{InstanceName: "app", ActionDigest: &re.Digest{Hash: strings.Repeat("a", 64), SizeBytes: 5}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := stream.Recv(); err != nil {
		t.Fatal(err)
	}
	select {
	case <-polling:
	case <-time.After(500 * time.Millisecond):
		t.Fatal("gateway delayed the state-change subscription")
	}
	close(release)
	op, err := stream.Recv()
	if err != nil || !op.Done {
		t.Fatalf("completion: %v, %v", op, err)
	}
}

func TestOldControlPlaneCannotCauseBusyPolling(t *testing.T) {
	var reads atomic.Int32
	client, _ := gateway(t, func(r *http.Request) (*http.Response, error) {
		if r.Method == http.MethodGet {
			reads.Add(1)
		}
		return response(200, `{"id":"`+id+`","state":"queued"}`), nil
	})
	ctx, cancel := context.WithTimeout(authenticated(), 250*time.Millisecond)
	defer cancel()
	stream, err := client.Execute(ctx, &re.ExecuteRequest{InstanceName: "app", ActionDigest: &re.Digest{Hash: strings.Repeat("a", 64), SizeBytes: 5}})
	if err != nil {
		t.Fatal(err)
	}
	for err == nil {
		_, err = stream.Recv()
	}
	if n := reads.Load(); n > 3 {
		t.Fatalf("legacy control plane was busy-polled %d times", n)
	}
}

func TestDurableResultIsDeliveredBeforeCleanupAcrossGateways(t *testing.T) {
	b, _ := proto.Marshal(&re.ExecuteResponse{Result: &re.ActionResult{ExitCode: 0}})
	var reads atomic.Int32
	control := transport(func(r *http.Request) (*http.Response, error) {
		if r.Method == http.MethodPost {
			return response(202, `{"id":"`+id+`","state":"executing","done":false}`), nil
		}
		reads.Add(1)
		// Cleanup never finishes in this test. Returning a result must not
		// require a transition to completed or another control-plane read.
		return response(200, `{"id":"`+id+`","state":"cleaning","done":true,"response":"`+base64.StdEncoding.EncodeToString(b)+`"}`), nil
	})
	client, _ := gateway(t, control)
	ctx, cancel := context.WithTimeout(authenticated(), time.Second)
	defer cancel()
	stream, err := client.Execute(ctx, &re.ExecuteRequest{InstanceName: "app", ActionDigest: &re.Digest{Hash: strings.Repeat("a", 64), SizeBytes: 5}})
	if err != nil {
		t.Fatal(err)
	}
	if first, err := stream.Recv(); err != nil || first.Done {
		t.Fatalf("initial: %v %v", first, err)
	}
	finished, err := stream.Recv()
	if err != nil || !finished.Done {
		t.Fatalf("result: %v %v", finished, err)
	}
	if _, err := stream.Recv(); err != io.EOF {
		t.Fatalf("stream remained open: %v", err)
	}
	other, _ := gateway(t, control)
	resumed, err := other.WaitExecution(ctx, &re.WaitExecutionRequest{Name: finished.Name})
	if err != nil {
		t.Fatal(err)
	}
	result, err := resumed.Recv()
	if err != nil || !result.Done || !proto.Equal(result.GetResponse(), finished.GetResponse()) {
		t.Fatalf("reconnect: %v %v", result, err)
	}
	if reads.Load() != 2 {
		t.Fatalf("unexpected cleanup polling: %d", reads.Load())
	}
}

type actionCache struct {
	re.UnimplementedActionCacheServer
	updates chan *re.UpdateActionResultRequest
	auth    chan []string
}

func (a *actionCache) UpdateActionResult(ctx context.Context, r *re.UpdateActionResultRequest) (*re.ActionResult, error) {
	md, _ := metadata.FromIncomingContext(ctx)
	a.auth <- append(md.Get("authorization"), md.Get("x-tuist-account-handle")...)
	a.updates <- r
	return r.ActionResult, nil
}

func TestSuccessfulResultIsPublishedAfterTheClientHasIt(t *testing.T) {
	for _, test := range []struct {
		name      string
		cacheable bool
		exit      int32
		published bool
	}{{"cacheable", true, 0, true}, {"not cacheable", false, 0, false}, {"failed", true, 1, false}} {
		t.Run(test.name, func(t *testing.T) {
			cache := &actionCache{updates: make(chan *re.UpdateActionResultRequest, 1), auth: make(chan []string, 1)}
			l := bufconn.Listen(1 << 20)
			s := grpc.NewServer()
			re.RegisterActionCacheServer(s, cache)
			go s.Serve(l)
			t.Cleanup(s.Stop)
			g := New("https://control.example")
			var dialed atomic.Value
			g.Dial = func(endpoint string) (*grpc.ClientConn, error) {
				dialed.Store(endpoint)
				return grpc.NewClient("passthrough:///cache", grpc.WithTransportCredentials(insecure.NewCredentials()), grpc.WithContextDialer(func(context.Context, string) (net.Conn, error) { return l.Dial() }))
			}
			hash := strings.Repeat("a", 64)
			b, _ := proto.Marshal(&re.ExecuteResponse{Result: &re.ActionResult{ExitCode: test.exit}})
			op, _ := json.Marshal(map[string]any{"id": id, "state": "completed", "done": true, "response": base64.StdEncoding.EncodeToString(b),
				"cacheable": test.cacheable, "action_hash": hash, "action_size": 5, "cas_endpoint": "grpcs://cache.example"})
			client, _ := gatewayWith(t, g, func(*http.Request) (*http.Response, error) { return response(202, string(op)), nil })
			stream, err := client.Execute(authenticated(), &re.ExecuteRequest{InstanceName: "app", ActionDigest: &re.Digest{Hash: hash, SizeBytes: 5}})
			if err != nil {
				t.Fatal(err)
			}
			if result, err := stream.Recv(); err != nil || !result.Done {
				t.Fatalf("result: %v %v", result, err)
			}
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			g.Wait(ctx)
			if !test.published {
				if len(cache.updates) != 0 {
					t.Fatal("result was published")
				}
				return
			}
			var update *re.UpdateActionResultRequest
			select {
			case update = <-cache.updates:
			case <-ctx.Done():
				t.Fatal("result was not published")
			}
			if update.InstanceName != "app" || update.ActionDigest.Hash != hash || update.ActionDigest.SizeBytes != 5 || update.ActionResult.ExitCode != 0 {
				t.Fatalf("update: %v", update)
			}
			if auth := <-cache.auth; len(auth) != 2 || auth[0] != "Bearer secret" || auth[1] != "tuist" {
				t.Fatalf("credentials: %v", auth)
			}
			if dialed.Load() != "grpcs://cache.example" {
				t.Fatalf("endpoint: %v", dialed.Load())
			}
		})
	}
}

type blobStore struct {
	re.UnimplementedContentAddressableStorageServer
	blobs map[string][]byte
	auth  atomic.Value
}

func (b *blobStore) put(data []byte) *re.Digest {
	h := sha256.Sum256(data)
	d := &re.Digest{Hash: hex.EncodeToString(h[:]), SizeBytes: int64(len(data))}
	b.blobs[d.Hash] = data
	return d
}

func (b *blobStore) message(m proto.Message) *re.Digest {
	data, _ := proto.Marshal(m)
	return b.put(data)
}

func (b *blobStore) BatchReadBlobs(ctx context.Context, r *re.BatchReadBlobsRequest) (*re.BatchReadBlobsResponse, error) {
	md, _ := metadata.FromIncomingContext(ctx)
	b.auth.Store(append(md.Get("authorization"), md.Get("x-tuist-account-handle")...))
	response := &re.BatchReadBlobsResponse{}
	for _, d := range r.Digests {
		item := &re.BatchReadBlobsResponse_Response{Digest: d, Status: &rpc.Status{}}
		if data, ok := b.blobs[d.Hash]; ok {
			item.Data = data
		} else {
			item.Status.Code = int32(codes.NotFound)
		}
		response.Responses = append(response.Responses, item)
	}
	return response, nil
}

func TestExecuteSendsPrefetchedInputs(t *testing.T) {
	store := &blobStore{blobs: map[string][]byte{}}
	file := store.put([]byte("input"))
	leaf := store.message(&re.Directory{Files: []*re.FileNode{{Name: "input", Digest: file}}})
	root := store.message(&re.Directory{Directories: []*re.DirectoryNode{{Name: "out", Digest: leaf}}})
	command := store.message(&re.Command{Arguments: []string{"true"}})
	action := store.message(&re.Action{CommandDigest: command, InputRootDigest: root})
	l := bufconn.Listen(1 << 20)
	s := grpc.NewServer()
	re.RegisterContentAddressableStorageServer(s, store)
	go s.Serve(l)
	t.Cleanup(s.Stop)
	g := New("https://control.example")
	g.Dial = func(string) (*grpc.ClientConn, error) {
		return grpc.NewClient("passthrough:///cache", grpc.WithTransportCredentials(insecure.NewCredentials()), grpc.WithContextDialer(func(context.Context, string) (net.Conn, error) { return l.Dial() }))
	}
	bodies := make(chan map[string]any, 2)
	client, capabilities := gatewayWith(t, g, func(r *http.Request) (*http.Response, error) {
		if strings.HasSuffix(r.URL.Path, "/capabilities") {
			return response(200, `{"image":"sha-x","cas_endpoint":"grpcs://cache.example"}`), nil
		}
		var body map[string]any
		_ = json.NewDecoder(r.Body).Decode(&body)
		bodies <- body
		return response(202, `{"id":"`+id+`","state":"completed","done":true}`), nil
	})
	execute := func() map[string]any {
		stream, err := client.Execute(authenticated(), &re.ExecuteRequest{InstanceName: "app", ActionDigest: action})
		if err != nil {
			t.Fatal(err)
		}
		if result, err := stream.Recv(); err != nil || !result.Done {
			t.Fatalf("result: %v %v", result, err)
		}
		return <-bodies
	}
	if _, ok := execute()["inputs"]; ok {
		t.Fatal("prefetched before the project's cache endpoint was known")
	}
	if _, err := capabilities.GetCapabilities(authenticated(), &re.GetCapabilitiesRequest{InstanceName: "app"}); err != nil {
		t.Fatal(err)
	}
	encoded, _ := execute()["inputs"].(string)
	b, err := base64.StdEncoding.DecodeString(encoded)
	if err != nil {
		t.Fatal(err)
	}
	var seed re.BatchUpdateBlobsRequest
	if err := proto.Unmarshal(b, &seed); err != nil {
		t.Fatal(err)
	}
	got := map[string]bool{}
	for _, r := range seed.Requests {
		got[r.Digest.Hash] = string(r.Data) == string(store.blobs[r.Digest.Hash])
	}
	for _, d := range []*re.Digest{action, command, root, leaf, file} {
		if !got[d.Hash] {
			t.Fatalf("missing prefetched blob %s: %v", d.Hash, got)
		}
	}
	if auth, _ := store.auth.Load().([]string); len(auth) != 2 || auth[0] != "Bearer secret" || auth[1] != "tuist" {
		t.Fatalf("credentials: %v", auth)
	}
}
