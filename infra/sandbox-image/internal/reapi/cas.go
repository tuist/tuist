// Package reapi implements the bounded, single-action worker run in a fresh VM.
package reapi

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"fmt"
	"io"
	"strings"
	"sync"
	"sync/atomic"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	bs "google.golang.org/genproto/googleapis/bytestream"
	"google.golang.org/genproto/googleapis/rpc/errdetails"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
)

const MaxMetadata = 4 << 20
const MaxBlob = 1 << 30
const MaxTransfer = 8 << 30
const MaxEntries = 50_000
const MaxResponse = 128 << 10

type CAS struct {
	Instance    string
	Stream      bs.ByteStreamClient
	Actions     re.ActionCacheClient
	Blobs       re.ContentAddressableStorageClient
	noBatch     atomic.Bool
	mu          sync.Mutex
	transferred int64
}

func NewCAS(conn grpc.ClientConnInterface, instance string) *CAS {
	return &CAS{Instance: instance, Stream: bs.NewByteStreamClient(conn), Actions: re.NewActionCacheClient(conn), Blobs: re.NewContentAddressableStorageClient(conn)}
}

const inputBatchEntries = 128
const inputBatchBytes = 1 << 20
const inputBatchFileBytes = 64 << 10

var errBatchUnsupported = errors.New("CAS batch reads unsupported")

// ReadBatch holds at most one bounded response in memory. Duplicate inputs are
// requested once, but charged per file, just like the streaming download path.
func (c *CAS) ReadBatch(ctx context.Context, digests []*re.Digest) ([][]byte, error) {
	if c.Blobs == nil || c.noBatch.Load() {
		return nil, errBatchUnsupported
	}
	if len(digests) > inputBatchEntries {
		return nil, status.Error(codes.ResourceExhausted, "too many batch inputs")
	}
	var total int64
	unique := map[string]*re.Digest{}
	request := &re.BatchReadBlobsRequest{InstanceName: c.Instance, DigestFunction: re.DigestFunction_SHA256}
	for _, d := range digests {
		if !ValidDigest(d) || d.SizeBytes > inputBatchFileBytes {
			return nil, status.Error(codes.InvalidArgument, "invalid small input digest")
		}
		total += d.SizeBytes
		if old, ok := unique[d.Hash]; ok {
			if old.SizeBytes != d.SizeBytes {
				return nil, status.Error(codes.InvalidArgument, "inconsistent input digest size")
			}
		} else {
			unique[d.Hash] = d
			request.Digests = append(request.Digests, d)
		}
	}
	if total > inputBatchBytes {
		return nil, status.Error(codes.ResourceExhausted, "input batch too large")
	}
	if err := c.reserve(total); err != nil {
		return nil, err
	}
	// Identity only. Leave generous protobuf overhead below the worker's normal
	// metadata cap; a malformed peer cannot return an unbounded response.
	response, err := c.Blobs.BatchReadBlobs(ctx, request, grpc.MaxCallRecvMsgSize(2*inputBatchBytes))
	if status.Code(err) == codes.Unimplemented {
		c.noBatch.Store(true)
		c.mu.Lock()
		c.transferred -= total // No blob response; streaming will reserve instead.
		c.mu.Unlock()
		return nil, errBatchUnsupported
	}
	if err != nil {
		return nil, err
	}
	data := make(map[string][]byte, len(unique))
	for _, item := range response.GetResponses() {
		d := item.GetDigest()
		if !ValidDigest(d) {
			return nil, status.Error(codes.DataLoss, "invalid batch response digest")
		}
		want, ok := unique[d.Hash]
		_, duplicate := data[d.Hash]
		if !ok || want.SizeBytes != d.SizeBytes || duplicate || item.Status == nil {
			return nil, status.Error(codes.DataLoss, "unexpected batch response")
		}
		if err := status.FromProto(item.Status).Err(); err != nil {
			return nil, missingBlob(err, d)
		}
		h := sha256.Sum256(item.Data)
		if item.Compressor != re.Compressor_IDENTITY || int64(len(item.Data)) != d.SizeBytes || hex.EncodeToString(h[:]) != d.Hash {
			return nil, status.Error(codes.DataLoss, "batch CAS digest mismatch")
		}
		data[d.Hash] = item.Data
	}
	if len(data) != len(unique) {
		return nil, status.Error(codes.DataLoss, "incomplete batch response")
	}
	result := make([][]byte, len(digests))
	for i, d := range digests {
		result[i] = data[d.Hash]
	}
	return result, nil
}

func ValidDigest(d *re.Digest) bool {
	if d == nil || len(d.Hash) != 64 || strings.ToLower(d.Hash) != d.Hash || d.SizeBytes < 0 || d.SizeBytes > MaxBlob {
		return false
	}
	_, err := hex.DecodeString(d.Hash)
	return err == nil
}

func (c *CAS) reserve(n int64) error {
	c.mu.Lock()
	defer c.mu.Unlock()
	if n < 0 || n > MaxBlob || n > MaxTransfer-c.transferred {
		return status.Error(codes.ResourceExhausted, "action transfer budget exceeded")
	}
	c.transferred += n
	return nil
}

func (c *CAS) Read(ctx context.Context, d *re.Digest, out io.Writer) error {
	if !ValidDigest(d) {
		return status.Error(codes.InvalidArgument, "invalid SHA-256 digest")
	}
	if err := c.reserve(d.SizeBytes); err != nil {
		return err
	}
	r, err := c.Stream.Read(ctx, &bs.ReadRequest{ResourceName: fmt.Sprintf("%s/blobs/%s/%d", c.Instance, d.Hash, d.SizeBytes)})
	if err != nil {
		return missingBlob(err, d)
	}
	h := sha256.New()
	w := io.MultiWriter(out, h)
	var size int64
	for {
		part, err := r.Recv()
		if err == io.EOF {
			break
		}
		if err != nil {
			return missingBlob(err, d)
		}
		size += int64(len(part.Data))
		if size > d.SizeBytes {
			return status.Error(codes.DataLoss, "CAS blob exceeds digest size")
		}
		if _, err := w.Write(part.Data); err != nil {
			return err
		}
	}
	if size != d.SizeBytes || hex.EncodeToString(h.Sum(nil)) != d.Hash {
		return status.Error(codes.DataLoss, "CAS digest mismatch")
	}
	return nil
}

func missingBlob(err error, d *re.Digest) error {
	if status.Code(err) != codes.NotFound {
		return err
	}
	s, detailErr := status.New(codes.FailedPrecondition, "missing action input").WithDetails(&errdetails.PreconditionFailure{
		Violations: []*errdetails.PreconditionFailure_Violation{{Type: "MISSING", Subject: fmt.Sprintf("blobs/%s/%d", d.Hash, d.SizeBytes)}},
	})
	if detailErr != nil {
		return status.Error(codes.FailedPrecondition, "missing action input")
	}
	return s.Err()
}

type boundedBuffer struct{ data []byte }

func (b *boundedBuffer) Write(p []byte) (int, error) {
	if len(b.data)+len(p) > MaxMetadata {
		return 0, status.Error(codes.ResourceExhausted, "metadata too large")
	}
	b.data = append(b.data, p...)
	return len(p), nil
}

func (c *CAS) Message(ctx context.Context, d *re.Digest, m proto.Message) error {
	return c.Messages(ctx, []*re.Digest{d}, []proto.Message{m})
}

// Messages reads small protobufs with one unary batch call. Larger ones, or
// peers without BatchReadBlobs, use one ByteStream read each.
func (c *CAS) Messages(ctx context.Context, digests []*re.Digest, messages []proto.Message) error {
	batch := len(digests) <= inputBatchEntries
	var total int64
	for _, d := range digests {
		if !ValidDigest(d) || d.SizeBytes > MaxMetadata {
			return status.Error(codes.InvalidArgument, "invalid metadata digest")
		}
		total += d.SizeBytes
		batch = batch && d.SizeBytes <= inputBatchFileBytes
	}
	if batch && total <= inputBatchBytes {
		data, err := c.ReadBatch(ctx, digests)
		if err == nil {
			for i, b := range data {
				if err := proto.Unmarshal(b, messages[i]); err != nil {
					return status.Error(codes.InvalidArgument, "invalid CAS protobuf")
				}
			}
			return nil
		}
		if !errors.Is(err, errBatchUnsupported) {
			return err
		}
	}
	for i, d := range digests {
		var b boundedBuffer
		if err := c.Read(ctx, d, &b); err != nil {
			return err
		}
		if err := proto.Unmarshal(b.data, messages[i]); err != nil {
			return status.Error(codes.InvalidArgument, "invalid CAS protobuf")
		}
	}
	return nil
}

func (c *CAS) Write(ctx context.Context, r io.ReadSeeker) (*re.Digest, error) {
	if _, err := r.Seek(0, io.SeekStart); err != nil {
		return nil, err
	}
	h := sha256.New()
	n, err := io.Copy(h, io.LimitReader(r, MaxBlob+1))
	if err != nil {
		return nil, err
	}
	if err = c.reserve(n); err != nil {
		return nil, err
	}
	d := &re.Digest{Hash: hex.EncodeToString(h.Sum(nil)), SizeBytes: n}
	if _, err = r.Seek(0, io.SeekStart); err != nil {
		return nil, err
	}
	w, err := c.Stream.Write(ctx)
	if err != nil {
		return nil, err
	}
	// Each worker has a private VM, and each upload uses an independent stream.
	name := fmt.Sprintf("%s/uploads/%s/blobs/%s/%d", c.Instance, uploadID(), d.Hash, n)
	buf := make([]byte, 256<<10)
	var offset int64
	for {
		size, readErr := r.Read(buf)
		if readErr != nil && readErr != io.EOF {
			return nil, readErr
		}
		finish := offset+int64(size) == n
		if err = w.Send(&bs.WriteRequest{ResourceName: name, WriteOffset: offset, Data: buf[:size], FinishWrite: finish}); err != nil {
			return nil, err
		}
		offset += int64(size)
		if finish {
			break
		}
		if readErr == io.EOF {
			return nil, status.Error(codes.DataLoss, "output changed during upload")
		}
	}
	res, err := w.CloseAndRecv()
	if err != nil {
		return nil, err
	}
	if res.CommittedSize != n {
		return nil, status.Error(codes.DataLoss, "incomplete CAS upload")
	}
	return d, nil
}

func (c *CAS) WriteMessage(ctx context.Context, m proto.Message) (*re.Digest, error) {
	b, err := (proto.MarshalOptions{Deterministic: true}).Marshal(m)
	if err != nil {
		return nil, err
	}
	if len(b) > MaxMetadata {
		return nil, status.Error(codes.ResourceExhausted, "output metadata too large")
	}
	return c.Write(ctx, strings.NewReader(string(b)))
}

func uploadID() string { // UUIDs do not carry action or tenant information.
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}
