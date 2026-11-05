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

// The CAS acknowledges a new blob only once it is durable, and concurrent
// writes share that cost. Outputs are hashed while the result is assembled and
// uploaded together afterwards, each distinct blob once.
type outputUploads struct {
	cas  *CAS
	seen map[string]bool
	jobs []func(context.Context) error
}

func newOutputUploads(cas *CAS) *outputUploads {
	return &outputUploads{cas: cas, seen: map[string]bool{}}
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
	u.add(d, func(ctx context.Context) (*re.Digest, error) {
		f, err := root.Open(p)
		if err != nil {
			return nil, err
		}
		defer f.Close()
		return u.cas.Write(ctx, f)
	})
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
	if _, err = f.Seek(0, io.SeekStart); err != nil {
		return nil, err
	}
	d, err := digestReader(f)
	if err != nil {
		return nil, err
	}
	u.add(d, func(ctx context.Context) (*re.Digest, error) { return u.cas.Write(ctx, f) })
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
	u.add(d, func(ctx context.Context) (*re.Digest, error) { return u.cas.Write(ctx, bytes.NewReader(b)) })
	return d, nil
}

func (u *outputUploads) add(d *re.Digest, upload func(context.Context) (*re.Digest, error)) {
	if u.seen[d.Hash] {
		return
	}
	u.seen[d.Hash] = true
	u.jobs = append(u.jobs, func(ctx context.Context) error {
		got, err := upload(ctx)
		if err != nil {
			return err
		}
		if got.Hash != d.Hash || got.SizeBytes != d.SizeBytes {
			return status.Error(codes.DataLoss, "output changed during upload")
		}
		return nil
	})
}

func (u *outputUploads) send(ctx context.Context) error {
	g, ctx := errgroup.WithContext(ctx)
	g.SetLimit(outputUploadConcurrency)
	for _, job := range u.jobs {
		g.Go(func() error { return job(ctx) })
	}
	return g.Wait()
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
