package reapi

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"os"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"golang.org/x/sync/errgroup"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
)

const outputUploadConcurrency = 8

// Upper bound on one inlined blob's protobuf framing around its data.
const inlineEntryBytes = 96

// The CAS acknowledges a new blob only once it is durable, and concurrent
// writes share that cost. Outputs are hashed while the result is assembled and
// uploaded together afterwards, each distinct blob once. Blobs that fit the
// inline budget are returned to the caller instead, which stores them in the
// CAS before it answers the client.
type outputUploads struct {
	cas     *CAS
	seen    map[string]bool
	pending []pendingOutput
	budget  int
	inlined *re.BatchUpdateBlobsRequest
}

type pendingOutput struct {
	digest *re.Digest
	open   func() (outputReader, error)
}

type outputReader interface {
	io.ReadSeeker
	io.Closer
}

type unclosed struct{ io.ReadSeeker }

func (unclosed) Close() error { return nil }

func newOutputUploads(cas *CAS, inlineBytes int) *outputUploads {
	return &outputUploads{cas: cas, seen: map[string]bool{}, budget: inlineBytes, inlined: &re.BatchUpdateBlobsRequest{}}
}

func (u *outputUploads) file(root *os.Root, p string) (*re.Digest, error) {
	f, err := root.Open(p)
	if err != nil {
		return nil, err
	}
	defer f.Close()
	d, err := digestReader(f)
	if err != nil {
		return nil, err
	}
	u.add(d, func() (outputReader, error) { return root.Open(p) })
	return d, nil
}

// REAPI represents an empty log with neither inline bytes nor a digest. Avoid
// an authenticated CAS upload for the common case of a silent compiler.
// Non-empty logs still live in CAS, outside the bounded control-plane response.
func (u *outputUploads) log(f *os.File) (*re.Digest, error) {
	info, err := f.Stat()
	if err != nil || info.Size() == 0 {
		return nil, err
	}
	d, err := digestReader(io.NewSectionReader(f, 0, info.Size()))
	if err != nil {
		return nil, err
	}
	u.add(d, func() (outputReader, error) { return unclosed{io.NewSectionReader(f, 0, d.SizeBytes)}, nil })
	return d, nil
}

func (u *outputUploads) message(m proto.Message) (*re.Digest, error) {
	b, err := (proto.MarshalOptions{Deterministic: true}).Marshal(m)
	if err != nil {
		return nil, err
	}
	if len(b) > MaxMetadata {
		return nil, status.Error(codes.ResourceExhausted, "output metadata too large")
	}
	d, err := digestReader(bytes.NewReader(b))
	if err != nil {
		return nil, err
	}
	u.add(d, func() (outputReader, error) { return unclosed{bytes.NewReader(b)}, nil })
	return d, nil
}

func (u *outputUploads) add(d *re.Digest, open func() (outputReader, error)) {
	if u.seen[d.Hash] {
		return
	}
	u.seen[d.Hash] = true
	u.pending = append(u.pending, pendingOutput{digest: d, open: open})
}

func (u *outputUploads) send(ctx context.Context) error {
	g, ctx := errgroup.WithContext(ctx)
	g.SetLimit(outputUploadConcurrency)
	var uploads []pendingOutput
	for _, o := range u.pending {
		cost := o.digest.SizeBytes + inlineEntryBytes
		if cost > int64(u.budget) {
			uploads = append(uploads, o)
			continue
		}
		u.budget -= int(cost)
		if err := u.inline(o); err != nil {
			return err
		}
	}
	for _, o := range uploads {
		g.Go(func() error {
			r, err := o.open()
			if err != nil {
				return err
			}
			defer r.Close()
			got, err := u.cas.Write(ctx, r)
			if err != nil {
				return err
			}
			return unchanged(o.digest, got)
		})
	}
	return g.Wait()
}

func (u *outputUploads) inline(o pendingOutput) error {
	r, err := o.open()
	if err != nil {
		return err
	}
	defer r.Close()
	b, err := io.ReadAll(io.LimitReader(r, o.digest.SizeBytes+1))
	if err != nil {
		return err
	}
	got, err := digestReader(bytes.NewReader(b))
	if err != nil {
		return err
	}
	if err = unchanged(o.digest, got); err != nil {
		return err
	}
	u.inlined.Requests = append(u.inlined.Requests, &re.BatchUpdateBlobsRequest_Request{Digest: o.digest, Data: b})
	return nil
}

func unchanged(want, got *re.Digest) error {
	if got.Hash != want.Hash || got.SizeBytes != want.SizeBytes {
		return status.Error(codes.DataLoss, "output changed during upload")
	}
	return nil
}

func digestReader(r io.Reader) (*re.Digest, error) {
	h := sha256.New()
	n, err := io.Copy(h, io.LimitReader(r, MaxBlob+1))
	if err != nil {
		return nil, err
	}
	if n > MaxBlob {
		return nil, status.Error(codes.ResourceExhausted, "output too large")
	}
	return &re.Digest{Hash: hex.EncodeToString(h.Sum(nil)), SizeBytes: n}, nil
}
