package executor

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"net"
	"strings"
	"testing"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
)

// fakeHostServer answers each connection like sandboxd's blob cache and
// records the requests it got.
func fakeHostServer(t *testing.T, blob []byte, requests chan<- hostRequest) func() (net.Conn, error) {
	return func() (net.Conn, error) {
		guest, host := net.Pipe()
		go func() {
			defer host.Close()
			line, err := bufio.NewReader(host).ReadSlice('\n')
			if err != nil {
				return
			}
			var r hostRequest
			if err := json.Unmarshal(line, &r); err != nil {
				t.Error(err)
				return
			}
			requests <- r
			switch {
			case r.Op == "seal":
				host.Write([]byte(`{"ok":true}` + "\n"))
			case r.Op == "read" && r.Size == int64(len(blob)):
				host.Write([]byte(`{"ok":true}` + "\n"))
				host.Write(blob[r.Offset : r.Offset+r.Length])
			default:
				host.Write([]byte(`{"error":"blob cache full"}` + "\n"))
			}
		}()
		return guest, nil
	}
}

func TestHostBlobsProtocol(t *testing.T) {
	blob := []byte("0123456789")
	requests := make(chan hostRequest, 4)
	h := hostBlobs{dial: fakeHostServer(t, blob, requests)}
	d := &re.Digest{Hash: strings.Repeat("a", 64), SizeBytes: 10}

	var out bytes.Buffer
	if err := h.ReadBlob(context.Background(), d, 3, 4, &out); err != nil || out.String() != "3456" {
		t.Fatalf("ranged read: %q %v", out.String(), err)
	}
	if r := <-requests; r != (hostRequest{Op: "read", Hash: d.Hash, Size: 10, Offset: 3, Length: 4}) {
		t.Fatalf("request: %+v", r)
	}
	if err := h.ReadBlob(context.Background(), &re.Digest{Hash: d.Hash, SizeBytes: 11}, 0, 11, &out); err == nil || !strings.Contains(err.Error(), "blob cache full") {
		t.Fatalf("host error: %v", err)
	}
	<-requests
	if err := h.Seal(context.Background()); err != nil {
		t.Fatal(err)
	}
	if r := <-requests; r.Op != "seal" {
		t.Fatalf("seal request: %+v", r)
	}
	// No listener on the host: nothing serves this VM, so there is nothing to seal.
	none := hostBlobs{dial: func() (net.Conn, error) { return nil, errors.New("connection reset") }}
	if err := none.Seal(context.Background()); err != nil {
		t.Fatalf("seal without a listener: %v", err)
	}
}
