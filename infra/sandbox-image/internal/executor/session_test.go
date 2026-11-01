package executor

import (
	"context"
	"net"
	"sync/atomic"
	"testing"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"google.golang.org/grpc"
	"google.golang.org/grpc/metadata"
)

type countingListener struct {
	net.Listener
	accepted atomic.Int32
}

func (l *countingListener) Accept() (net.Conn, error) {
	c, e := l.Listener.Accept()
	if e == nil {
		l.accepted.Add(1)
	}
	return c, e
}

type preparedCAS struct {
	re.UnimplementedCapabilitiesServer
	calls chan string
}

func (s *preparedCAS) GetCapabilities(ctx context.Context, _ *re.GetCapabilitiesRequest) (*re.ServerCapabilities, error) {
	values := metadata.ValueFromIncomingContext(ctx, "authorization")
	value := ""
	if len(values) > 0 {
		value = values[0]
	}
	s.calls <- value
	return &re.ServerCapabilities{}, nil
}
func casServer(t *testing.T) (string, *countingListener, chan string) {
	t.Helper()
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	counting := &countingListener{Listener: listener}
	calls := make(chan string, 10)
	server := grpc.NewServer()
	re.RegisterCapabilitiesServer(server, &preparedCAS{calls: calls})
	go server.Serve(counting)
	t.Cleanup(server.Stop)
	return "grpc://" + listener.Addr().String(), counting, calls
}
func TestPreparedConnectionHasNoCredentialAndIsConsumedOnce(t *testing.T) {
	endpoint, listener, calls := casServer(t)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	session := &Session{}
	if err := session.Prepare(ctx, endpoint); err != nil {
		t.Fatal(err)
	}
	select {
	case <-calls:
		t.Fatal("preparation issued an RPC")
	default:
	}
	conn, err := session.takeClient(endpoint)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	for _, token := range []string{"first-request", "second-request"} {
		rpcCtx := metadata.AppendToOutgoingContext(ctx, "authorization", token)
		if _, err := re.NewCapabilitiesClient(conn).GetCapabilities(rpcCtx, &re.GetCapabilitiesRequest{}); err != nil {
			t.Fatal(err)
		}
		if got := <-calls; got != token {
			t.Fatalf("credential=%q", got)
		}
	}
	if listener.accepted.Load() != 1 {
		t.Fatalf("connections=%d", listener.accepted.Load())
	}
	if _, err := session.takeClient(endpoint); err == nil {
		t.Fatal("session reused by another action")
	}
	if err := session.Prepare(ctx, endpoint); err == nil {
		t.Fatal("used session prepared again")
	}
}
func TestPreparedEndpointChangeDoesNotSendCredentialsToOldEndpoint(t *testing.T) {
	old, _, oldCalls := casServer(t)
	current, _, currentCalls := casServer(t)
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	session := &Session{}
	if err := session.Prepare(ctx, old); err != nil {
		t.Fatal(err)
	}
	conn, err := session.takeClient(current)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if _, err := re.NewCapabilitiesClient(conn).GetCapabilities(metadata.AppendToOutgoingContext(ctx, "authorization", "current-only"), &re.GetCapabilitiesRequest{}); err != nil {
		t.Fatal(err)
	}
	if got := <-currentCalls; got != "current-only" {
		t.Fatal("wrong current credential")
	}
	select {
	case <-oldCalls:
		t.Fatal("old endpoint received an RPC")
	default:
	}
}
func TestFailedPreparationClosesConnectionAndAllowsFreshFallback(t *testing.T) {
	endpoint, _, _ := casServer(t)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	session := &Session{}
	if err := session.Prepare(ctx, endpoint); err == nil {
		t.Fatal("cancelled preparation succeeded")
	}
	if session.conn != nil {
		t.Fatal("failed preparation retained a connection")
	}
	conn, err := session.takeClient(endpoint)
	if err != nil {
		t.Fatal(err)
	}
	conn.Close()
}
