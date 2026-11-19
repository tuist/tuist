package reapi

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
)

// HostBlobs is the node's blob cache: sandboxd downloads each large input
// once per node, with the action's own CAS scope and credential, and serves
// byte ranges of it over vsock.
type HostBlobs interface {
	// ReadBlob writes length bytes of the blob from offset to out.
	ReadBlob(ctx context.Context, d *re.Digest, offset, length int64, out io.Writer) error
	// Seal ends the host's serving for this action. It runs before the
	// command, so the build cannot read the project's CAS through the host.
	Seal(ctx context.Context) error
}

// rewindable is an input file a failed host read can be reset in, so the
// blob is read again from the CAS.
type rewindable interface {
	io.Writer
	Truncate(int64) error
	Seek(int64, int) (int64, error)
}

// readHost copies a whole blob from the host and verifies it like a CAS read.
func (c *CAS) readHost(ctx context.Context, d *re.Digest, out io.Writer) (err error) {
	started := time.Now()
	read := casRead{rpc: "host", blobs: 1, bytes: d.SizeBytes, peer: "host"}
	defer func() {
		read.took = time.Since(started)
		read.code = status.Code(err)
		c.observeRead(read)
	}()
	h := sha256.New()
	counted := &countingWriter{w: io.MultiWriter(out, h)}
	if err := c.Host.ReadBlob(ctx, d, 0, d.SizeBytes, counted); err != nil {
		return err
	}
	if counted.n != d.SizeBytes || hex.EncodeToString(h.Sum(nil)) != d.Hash {
		return status.Error(codes.DataLoss, "host blob digest mismatch")
	}
	return nil
}

// SealHost closes the host channel; see HostBlobs.Seal.
func (c *CAS) SealHost(ctx context.Context) error {
	if c.Host == nil {
		return nil
	}
	return c.Host.Seal(ctx)
}

type countingWriter struct {
	w io.Writer
	n int64
}

func (c *countingWriter) Write(p []byte) (int, error) {
	n, err := c.w.Write(p)
	c.n += int64(n)
	return n, err
}
