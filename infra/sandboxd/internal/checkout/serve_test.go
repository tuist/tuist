package checkout

import (
	"archive/tar"
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"path/filepath"
	"sync"
	"testing"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/pkg/protocol"
)

type fakeAgent struct {
	mu        sync.Mutex
	tree      []byte
	seedErr   error
	exportErr error
	seeds     []protocol.CheckoutGrant
	exports   [][]byte
	readErr   error
}

func (f *fakeAgent) Seed(_ context.Context, grant protocol.CheckoutGrant) (io.ReadCloser, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.seeds = append(f.seeds, grant)
	if f.seedErr != nil {
		return nil, f.seedErr
	}
	return io.NopCloser(bytes.NewReader(f.tree)), nil
}

func (f *fakeAgent) Export(_ context.Context, _ protocol.CheckoutGrant, export io.Reader) error {
	data, err := io.ReadAll(export)
	f.mu.Lock()
	defer f.mu.Unlock()
	f.exports = append(f.exports, data)
	f.readErr = err
	if err != nil {
		return err
	}
	return f.exportErr
}

func (f *fakeAgent) calls() ([]protocol.CheckoutGrant, [][]byte, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return append([]protocol.CheckoutGrant(nil), f.seeds...), append([][]byte(nil), f.exports...), f.readErr
}

var testGrant = protocol.CheckoutGrant{ID: "11111111-1111-4111-8111-111111111111", Scope: "scope", Commit: "0123456789abcdef0123456789abcdef01234567", Path: "/workspace/repo"}

// serve arms a listener the way the manager does and returns its socket path.
func serve(t *testing.T, agent Agent, limits Limits) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "v.sock_5002")
	l, err := net.Listen("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		Serve(ctx, l, agent, testGrant, limits, nil)
	}()
	t.Cleanup(func() {
		cancel()
		<-done
	})
	return path
}

// ask sends one request line, then body, without closing its write side
// (Firecracker never passes a guest's shutdown on), and returns the answer
// line and whatever follows it until the host closes.
func ask(t *testing.T, path, line string, body []byte) (Response, []byte) {
	t.Helper()
	conn, err := net.Dial("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	conn.SetDeadline(time.Now().Add(10 * time.Second))
	if _, err := conn.Write(append([]byte(line+"\n"), body...)); err != nil {
		t.Fatal(err)
	}
	reader := bufio.NewReader(conn)
	answer, err := reader.ReadBytes('\n')
	if err != nil {
		t.Fatalf("no answer: %v", err)
	}
	var response Response
	if err := json.Unmarshal(answer, &response); err != nil {
		t.Fatalf("answer %q: %v", answer, err)
	}
	rest, _ := io.ReadAll(reader)
	return response, rest
}

func exportArchive(t *testing.T, pack []byte) []byte {
	t.Helper()
	var buffer bytes.Buffer
	archive := tar.NewWriter(&buffer)
	for _, entry := range []struct {
		name string
		data []byte
	}{{"head", []byte(testGrant.Commit + "\n")}, {"pack", pack}} {
		if err := archive.WriteHeader(&tar.Header{Name: entry.name, Mode: 0o644, Size: int64(len(entry.data)), Typeflag: tar.TypeReg}); err != nil {
			t.Fatal(err)
		}
		archive.Write(entry.data)
	}
	if err := archive.Close(); err != nil {
		t.Fatal(err)
	}
	return buffer.Bytes()
}

func TestSeedRelaysTheAgentsTreeOncePerArming(t *testing.T) {
	agent := &fakeAgent{tree: []byte("tree bytes")}
	path := serve(t, agent, Limits{})
	response, rest := ask(t, path, `{"op":"seed"}`, nil)
	if !response.OK || string(rest) != "tree bytes" {
		t.Fatalf("seed: %+v %q", response, rest)
	}
	if seeds, _, _ := agent.calls(); len(seeds) != 1 || seeds[0] != testGrant {
		t.Fatalf("the agent was asked for %+v, not the server's grant", seeds)
	}
	if response, rest := ask(t, path, `{"op":"seed"}`, nil); response.OK || response.Error == "" || len(rest) != 0 {
		t.Fatalf("second seed: %+v %q", response, rest)
	}
	if seeds, _, _ := agent.calls(); len(seeds) != 1 {
		t.Fatal("a second seed reached the agent")
	}
}

func TestSeedAnswersColdAndErrors(t *testing.T) {
	for name, tc := range map[string]struct {
		err  error
		want string
	}{
		"cold":  {ErrCold, "cold"},
		"error": {errors.New("checkout agent answered 503: busy http://internal"), "unavailable"},
	} {
		t.Run(name, func(t *testing.T) {
			path := serve(t, &fakeAgent{seedErr: tc.err}, Limits{})
			response, rest := ask(t, path, `{"op":"seed"}`, nil)
			if response.OK || response.Error != tc.want || len(rest) != 0 {
				t.Fatalf("%+v %q", response, rest)
			}
		})
	}
}

func TestSeedStopsAtItsBound(t *testing.T) {
	path := serve(t, &fakeAgent{tree: bytes.Repeat([]byte("x"), 100)}, Limits{SeedBytes: 64})
	response, rest := ask(t, path, `{"op":"seed"}`, nil)
	if !response.OK || len(rest) != 64 {
		t.Fatalf("relayed %d bytes past a 64-byte bound: %+v", len(rest), response)
	}
}

func TestExportForwardsExactlyTheArchiveAndAnswersOnce(t *testing.T) {
	agent := &fakeAgent{}
	path := serve(t, agent, Limits{})
	archive := exportArchive(t, []byte("PACK"))
	// Bytes after the end-of-archive blocks are not the export's.
	response, _ := ask(t, path, `{"op":"export"}`, append(append([]byte(nil), archive...), "trailing"...))
	if !response.OK {
		t.Fatalf("export: %+v", response)
	}
	if _, exports, _ := agent.calls(); len(exports) != 1 || !bytes.Equal(exports[0], archive) {
		t.Fatalf("the agent received %d exports, want exactly the %d-byte archive", len(exports), len(archive))
	}
	if response, _ := ask(t, path, `{"op":"export"}`, archive); response.OK || response.Error == "" {
		t.Fatalf("second export: %+v", response)
	}
	if _, exports, _ := agent.calls(); len(exports) != 1 {
		t.Fatal("a second export reached the agent")
	}
}

func TestExportRefusals(t *testing.T) {
	t.Run("agent refuses", func(t *testing.T) {
		path := serve(t, &fakeAgent{exportErr: errors.New("checkout agent answered 400: invalid export")}, Limits{})
		if response, _ := ask(t, path, `{"op":"export"}`, exportArchive(t, []byte("PACK"))); response.OK || response.Error != "export refused" {
			t.Fatalf("%+v", response)
		}
	})
	t.Run("past its bound", func(t *testing.T) {
		agent := &fakeAgent{}
		path := serve(t, agent, Limits{ExportBytes: 2048})
		if response, _ := ask(t, path, `{"op":"export"}`, exportArchive(t, bytes.Repeat([]byte("p"), 4096))); response.OK {
			t.Fatalf("an export past its bound was accepted: %+v", response)
		}
		if _, _, readErr := agent.calls(); readErr == nil {
			t.Fatal("the agent's stream ended cleanly instead of failing")
		}
	})
	t.Run("not an archive", func(t *testing.T) {
		agent := &fakeAgent{}
		path := serve(t, agent, Limits{})
		if response, _ := ask(t, path, `{"op":"export"}`, bytes.Repeat([]byte("garbage!"), 128)); response.OK {
			t.Fatalf("%+v", response)
		}
		if _, _, readErr := agent.calls(); readErr == nil {
			t.Fatal("the agent's stream ended cleanly instead of failing")
		}
	})
	t.Run("too slow", func(t *testing.T) {
		path := serve(t, &fakeAgent{}, Limits{ExportTimeout: 200 * time.Millisecond})
		conn, err := net.Dial("unix", path)
		if err != nil {
			t.Fatal(err)
		}
		defer conn.Close()
		conn.Write([]byte(`{"op":"export"}` + "\n"))
		conn.SetReadDeadline(time.Now().Add(5 * time.Second))
		if _, err := io.ReadAll(conn); err != nil {
			t.Fatalf("the host kept a stalled export open: %v", err)
		}
	})
}

func TestRejectsOtherRequests(t *testing.T) {
	agent := &fakeAgent{tree: []byte("tree")}
	path := serve(t, agent, Limits{})
	for line, want := range map[string]string{`{"op":"read"}`: "unknown op", `seed`: "invalid request"} {
		if response, rest := ask(t, path, line, nil); response.Error != want || len(rest) != 0 {
			t.Errorf("%s: %+v %q", line, response, rest)
		}
	}
	// An overlong line is closed unanswered.
	conn, err := net.Dial("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	conn.Write(append(bytes.Repeat([]byte(" "), 2*maxRequestLine), '\n'))
	conn.SetReadDeadline(time.Now().Add(5 * time.Second))
	if rest, err := io.ReadAll(conn); err != nil || len(rest) != 0 {
		t.Fatalf("overlong request answered %q %v", rest, err)
	}
	if seeds, exports, _ := agent.calls(); len(seeds) != 0 || len(exports) != 0 {
		t.Fatal("a rejected request reached the agent")
	}
}

func TestDisarmClosesTheListener(t *testing.T) {
	path := filepath.Join(t.TempDir(), "v.sock_5002")
	l, err := net.Listen("unix", path)
	if err != nil {
		t.Fatal(err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})
	go func() {
		defer close(done)
		Serve(ctx, l, &fakeAgent{}, testGrant, Limits{}, nil)
	}()
	cancel()
	select {
	case <-done:
	case <-time.After(5 * time.Second):
		t.Fatal("Serve did not return after its context ended")
	}
	if conn, err := net.Dial("unix", path); err == nil {
		conn.Close()
		t.Fatal("still accepting after disarm")
	}
}
