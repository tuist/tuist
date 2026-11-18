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
	worker "github.com/tuist/tuist/infra/sandbox-image/internal/reapi"
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
	// Drive and Bytes answer a tree request: the input drive the image is
	// attached to and the image's size.
	Drive *int  `json:"drive"`
	Bytes int64 `json:"bytes"`
}

// call sends one request on conn and returns it positioned after the host's
// answer, with the answer and the function that closes it.
func call(ctx context.Context, conn net.Conn, r any) (*bufio.Reader, hostResponse, func(), error) {
	stop := context.AfterFunc(ctx, func() { conn.Close() })
	closeConn := func() {
		stop()
		conn.Close()
	}
	line, _ := json.Marshal(r)
	var response hostResponse
	if _, err := conn.Write(append(line, '\n')); err != nil {
		closeConn()
		return nil, response, nil, err
	}
	reader := bufio.NewReader(conn)
	answer, err := reader.ReadSlice('\n')
	if err != nil {
		closeConn()
		return nil, response, nil, err
	}
	if err := json.Unmarshal(answer, &response); err != nil || !response.OK {
		closeConn()
		if response.Error != "" {
			return nil, response, nil, errors.New("host blob cache: " + response.Error)
		}
		return nil, response, nil, errors.New("host blob cache: invalid answer")
	}
	return reader, response, closeConn, nil
}

func (h hostBlobs) ReadBlob(ctx context.Context, d *re.Digest, offset, length int64, out io.Writer) error {
	conn, err := h.dial()
	if err != nil {
		return err
	}
	reader, _, closeConn, err := call(ctx, conn, hostRequest{Op: "read", Hash: d.Hash, Size: d.SizeBytes, Offset: offset, Length: length})
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
	_, _, closeConn, err := call(ctx, conn, hostRequest{Op: "seal"})
	if err != nil {
		return err
	}
	closeConn()
	return nil
}

// hostTrees mounts the node's input tree images (reapi.InputTrees) on the
// same channel, which the seal also ends.
type hostTrees struct {
	dial func() (net.Conn, error)
	// mount mounts the image attached to the input drive at dir.
	mount func(drive int, bytes int64, dir, scratch string) error
	// failed stops asking once a mount failed: the guest cannot use images.
	failed bool
}

type treeNote struct {
	Hash  string `json:"hash"`
	Size  int64  `json:"size"`
	Bytes int64  `json:"bytes"`
}

func (h *hostTrees) Mount(ctx context.Context, d *re.Digest, dir, scratch string) bool {
	if h.failed {
		return false
	}
	conn, err := h.dial()
	if err != nil {
		return false
	}
	_, response, closeConn, err := call(ctx, conn, hostRequest{Op: "tree", Hash: d.GetHash(), Size: d.GetSizeBytes()})
	if err != nil {
		return false
	}
	closeConn()
	if response.Drive == nil || *response.Drive < 0 {
		return false
	}
	if err := h.mount(*response.Drive, response.Bytes, dir, scratch); err != nil {
		h.failed = true
		return false
	}
	return true
}

func (h *hostTrees) Note(ctx context.Context, trees []worker.InputTree) {
	notes := make([]treeNote, len(trees))
	for i, t := range trees {
		notes[i] = treeNote{Hash: t.Digest.GetHash(), Size: t.Digest.GetSizeBytes(), Bytes: t.Bytes}
	}
	conn, err := h.dial()
	if err != nil {
		return
	}
	if _, _, closeConn, err := call(ctx, conn, struct {
		Op    string     `json:"op"`
		Trees []treeNote `json:"trees"`
	}{"trees", notes}); err == nil {
		closeConn()
	}
}
