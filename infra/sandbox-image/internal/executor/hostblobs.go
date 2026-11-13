package executor

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
)

// hostBlobPort is the host vsock port of sandboxd's node blob cache
// (infra/sandboxd/internal/blobcache).
const hostBlobPort = 5001

const sealTimeout = 5 * time.Second

// hostBlobs reads input blobs from the node's cache over vsock. The host
// serves only the action's own CAS scope, only while its exec runs, and only
// until Seal.
type hostBlobs struct {
	dial func() (net.Conn, error)
}

type hostRequest struct {
	Op     string `json:"op"`
	Hash   string `json:"hash,omitempty"`
	Size   int64  `json:"size,omitempty"`
	Offset int64  `json:"offset,omitempty"`
	Length int64  `json:"length,omitempty"`
}

type hostResponse struct {
	OK    bool   `json:"ok"`
	Error string `json:"error"`
}

// call sends one request on conn and returns it positioned after the host's
// answer, with the function that closes it.
func call(ctx context.Context, conn net.Conn, r hostRequest) (*bufio.Reader, func(), error) {
	stop := context.AfterFunc(ctx, func() { conn.Close() })
	closeConn := func() {
		stop()
		conn.Close()
	}
	line, _ := json.Marshal(r)
	if _, err := conn.Write(append(line, '\n')); err != nil {
		closeConn()
		return nil, nil, err
	}
	reader := bufio.NewReader(conn)
	answer, err := reader.ReadSlice('\n')
	if err != nil {
		closeConn()
		return nil, nil, err
	}
	var response hostResponse
	if err := json.Unmarshal(answer, &response); err != nil || !response.OK {
		closeConn()
		if response.Error != "" {
			return nil, nil, errors.New("host blob cache: " + response.Error)
		}
		return nil, nil, errors.New("host blob cache: invalid answer")
	}
	return reader, closeConn, nil
}

func (h hostBlobs) ReadBlob(ctx context.Context, d *re.Digest, offset, length int64, out io.Writer) error {
	conn, err := h.dial()
	if err != nil {
		return err
	}
	reader, closeConn, err := call(ctx, conn, hostRequest{Op: "read", Hash: d.Hash, Size: d.SizeBytes, Offset: offset, Length: length})
	if err != nil {
		return err
	}
	defer closeConn()
	if _, err := io.CopyN(out, reader, length); err != nil {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		return err
	}
	return nil
}

// Seal succeeds without a host listener: nothing serves this VM then.
func (h hostBlobs) Seal(parent context.Context) error {
	ctx, cancel := context.WithTimeout(parent, sealTimeout)
	defer cancel()
	conn, err := h.dial()
	if err != nil {
		return nil
	}
	_, closeConn, err := call(ctx, conn, hostRequest{Op: "seal"})
	if err != nil {
		return err
	}
	closeConn()
	return nil
}
