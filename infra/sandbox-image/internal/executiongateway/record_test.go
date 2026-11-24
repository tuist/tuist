package executiongateway

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"io"
	"net"
	"net/http"
	"reflect"
	"strings"
	"testing"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	bs "google.golang.org/genproto/googleapis/bytestream"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/test/bufconn"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/durationpb"
	"google.golang.org/protobuf/types/known/timestamppb"
)

// byteStore serves the blob store's blobs over ByteStream too, honoring
// read_offset and read_limit and sending 16 KiB chunks as Kura does.
type byteStore struct {
	bs.UnimplementedByteStreamServer
	store *blobStore
}

func (b *byteStore) Read(r *bs.ReadRequest, s bs.ByteStream_ReadServer) error {
	parts := strings.Split(r.ResourceName, "/")
	data := b.store.blobs[parts[len(parts)-2]]
	data = data[min(r.ReadOffset, int64(len(data))):]
	if r.ReadLimit > 0 && int64(len(data)) > r.ReadLimit {
		data = data[:r.ReadLimit]
	}
	for len(data) > 0 {
		n := min(len(data), 16<<10)
		if err := s.Send(&bs.ReadResponse{Data: data[:n]}); err != nil {
			return err
		}
		data = data[n:]
	}
	return nil
}

func TestExecutedActionIsRecordedAfterTheClientHasItsResult(t *testing.T) {
	store := &blobStore{blobs: map[string][]byte{}}
	command := store.message(&re.Command{
		Arguments: []string{"gcc", "-c", "foo.c", "--api_token=abc", "--password", "hunter2", "-o", "bazel-out/foo.o"},
		EnvironmentVariables: []*re.Command_EnvironmentVariable{
			{Name: "PATH", Value: "/usr/bin"}, {Name: "AWS_SECRET_ACCESS_KEY", Value: "s3cr3t"},
		},
		OutputPaths:      []string{"bazel-out/foo.o"},
		WorkingDirectory: "pkg",
	})
	action := store.message(&re.Action{CommandDigest: command, InputRootDigest: store.message(&re.Directory{}), Timeout: durationpb.New(90 * time.Second), Platform: &re.Platform{Properties: []*re.Platform_Property{{Name: "OSFamily", Value: "Linux"}}}})
	// Larger than a record keeps, so only its start is sent.
	stderr := store.put([]byte(strings.Repeat("e", maxRecordLog+10)))
	queued := time.UnixMicro(1793157000000000)
	b, _ := proto.Marshal(&re.ExecuteResponse{Result: &re.ActionResult{
		ExitCode: 1, StdoutRaw: []byte("compiled"), StderrDigest: stderr,
		ExecutionMetadata: &re.ExecutedActionMetadata{Worker: "firecracker-linux-amd64", WorkerStartTimestamp: timestamppb.New(queued.Add(time.Second)), ExecutionStartTimestamp: timestamppb.New(queued.Add(2 * time.Second)), ExecutionCompletedTimestamp: timestamppb.New(queued.Add(5 * time.Second))},
	}})

	g := New("https://control.example")
	l := bufconn.Listen(1 << 20)
	s := grpc.NewServer()
	re.RegisterContentAddressableStorageServer(s, store)
	bs.RegisterByteStreamServer(s, &byteStore{store: store})
	go s.Serve(l)
	t.Cleanup(s.Stop)
	g.Dial = func(string) (*grpc.ClientConn, error) {
		return grpc.NewClient("passthrough:///cache", grpc.WithTransportCredentials(insecure.NewCredentials()), grpc.WithContextDialer(func(context.Context, string) (net.Conn, error) { return l.Dial() }))
	}
	posted := make(chan *http.Request, 1)
	bodies := make(chan []byte, 1)
	client, _ := gatewayWith(t, g, func(r *http.Request) (*http.Response, error) {
		switch {
		case strings.HasSuffix(r.URL.Path, "/capabilities"):
			return response(200, `{"cas_endpoint":"cache"}`), nil
		case strings.HasSuffix(r.URL.Path, "/actions"):
			body, _ := io.ReadAll(r.Body)
			posted <- r
			bodies <- body
			return response(202, `{"accepted":1}`), nil
		}
		return response(200, `{"id":"`+id+`","state":"completed","sandbox_id":"vm-1","queued_at_unix_us":1793157000000000,"response":"`+base64.StdEncoding.EncodeToString(b)+`"}`), nil
	})

	request, _ := proto.Marshal(&re.RequestMetadata{ToolDetails: &re.ToolDetails{ToolName: "bazel", ToolVersion: "8.4.0"}, ToolInvocationId: "inv-1", ActionMnemonic: "CppCompile", TargetId: "//pkg:foo", ConfigurationId: "k8-fastbuild"})
	ctx := metadata.AppendToOutgoingContext(authenticated(), requestMetadataHeader, string(request))
	stream, err := client.Execute(ctx, &re.ExecuteRequest{InstanceName: "app", ActionDigest: action})
	if err != nil {
		t.Fatal(err)
	}
	if done, err := stream.Recv(); err != nil || !done.Done {
		t.Fatalf("result: %v %v", done, err)
	}

	var r *http.Request
	select {
	case r = <-posted:
	case <-time.After(5 * time.Second):
		t.Fatal("no record was sent")
	}
	if r.URL.Path != "/api/remote-execution/tuist/app/actions" || r.Header.Get("Authorization") != "Bearer secret" {
		t.Fatalf("record sent to %s with %q", r.URL.Path, r.Header.Get("Authorization"))
	}
	var body struct{ Actions []actionRecord }
	if err := json.Unmarshal(<-bodies, &body); err != nil || len(body.Actions) != 1 {
		t.Fatalf("records: %v %v", body, err)
	}
	got := body.Actions[0]
	if got.OperationID != id || got.ActionHash != action.Hash || got.InvocationID != "inv-1" || got.Mnemonic != "CppCompile" ||
		got.Target != "//pkg:foo" || got.ToolVersion != "8.4.0" || got.ExecutionPath != "scheduled" || got.SandboxID != "vm-1" ||
		got.MemoryGB != 4 || got.TimeoutMS != 90_000 || got.ExitCode != 1 || got.WorkingDirectory != "pkg" {
		t.Fatalf("record identity and outcome: %+v", got)
	}
	if want := []string{"gcc", "-c", "foo.c", "--api_token=****", "--password", "****", "-o", "bazel-out/foo.o"}; !reflect.DeepEqual(got.Arguments, want) {
		t.Fatalf("arguments: %q", got.Arguments)
	}
	if want := []pair{{"PATH", "/usr/bin"}, {"AWS_SECRET_ACCESS_KEY", "****"}}; !reflect.DeepEqual(got.Environment, want) {
		t.Fatalf("environment: %v", got.Environment)
	}
	if !reflect.DeepEqual(got.OutputPaths, []string{"bazel-out/foo.o"}) || !reflect.DeepEqual(got.Platform, []pair{{"OSFamily", "Linux"}}) {
		t.Fatalf("outputs and platform: %v %v", got.OutputPaths, got.Platform)
	}
	if got.Stdout != "compiled" || got.StdoutTruncated || len(got.Stderr) != maxRecordLog || !got.StderrTruncated || got.StderrSize != maxRecordLog+10 {
		t.Fatalf("logs: %q %v %d %v %d", got.Stdout, got.StdoutTruncated, len(got.Stderr), got.StderrTruncated, got.StderrSize)
	}
	if got.Timestamps["queued"] != queued.UnixMicro() || got.Timestamps["execution_completed"] != queued.Add(5*time.Second).UnixMicro() {
		t.Fatalf("timestamps: %v", got.Timestamps)
	}
	if _, ok := got.Timestamps["output_upload_start"]; ok {
		t.Fatal("an unreported phase was recorded")
	}
}

func TestActionWithoutAnInvocationIsNotSent(t *testing.T) {
	sent := make(chan struct{}, 1)
	b, _ := proto.Marshal(&re.ExecuteResponse{Result: &re.ActionResult{}})
	client, _ := gateway(t, func(r *http.Request) (*http.Response, error) {
		if strings.HasSuffix(r.URL.Path, "/actions") {
			sent <- struct{}{}
		}
		return response(200, `{"id":"`+id+`","state":"completed","response":"`+base64.StdEncoding.EncodeToString(b)+`"}`), nil
	})
	stream, err := client.Execute(authenticated(), &re.ExecuteRequest{InstanceName: "app", ActionDigest: &re.Digest{Hash: strings.Repeat("a", 64), SizeBytes: 5}})
	if err != nil {
		t.Fatal(err)
	}
	if _, err := stream.Recv(); err != nil {
		t.Fatal(err)
	}
	select {
	case <-sent:
		t.Fatal("a record no invocation can find was sent")
	case <-time.After(2 * recordFlush):
	}
}

func TestMaskArguments(t *testing.T) {
	got := maskArguments([]string{"--keep_going", "--api-key", "k", "AUTH_TOKEN=t", "-Dpassword=p", "--monkey=banana", "--output=key.txt", "--secret"})
	want := []string{"--keep_going", "--api-key", masked, "AUTH_TOKEN=" + masked, "-Dpassword=" + masked, "--monkey=" + masked, "--output=key.txt", "--secret"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("got %q", got)
	}
}
