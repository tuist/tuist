package main

// Local-only replication qualification for the pinned BuildBuddy peer protocol.
// Ordinary distributed REAPI frontends can fetch another node's copy and therefore
// cannot establish that each Pebble backend has actually retained the corpus.
// Field numbers are from proto/distributed_cache.proto and proto/resource.proto at
// 88af3f322ba21a8185061c6d61dd774c9d655d68. This codec is only a verifier, never the
// timed upload/read transport, which stays identical standard REAPI for all servers.
import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"io"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	"google.golang.org/grpc"
	"google.golang.org/protobuf/encoding/protowire"
	"google.golang.org/protobuf/proto"
)

type rawMessage []byte
type peerCodec struct{}

func (peerCodec) Name() string { return "proto" }
func (peerCodec) Marshal(v any) ([]byte, error) {
	p, ok := v.(*rawMessage)
	if !ok {
		return nil, fmt.Errorf("invalid raw request %T", v)
	}
	return []byte(*p), nil
}
func (peerCodec) Unmarshal(data []byte, v any) error {
	p, ok := v.(*rawMessage)
	if !ok {
		return fmt.Errorf("invalid raw response %T", v)
	}
	*p = append((*p)[:0], data...)
	return nil
}
func appendField(b []byte, n protowire.Number, v []byte) []byte {
	return protowire.AppendBytes(protowire.AppendTag(b, n, protowire.BytesType), v)
}
func resourceWire(instance string, d *re.Digest) ([]byte, error) {
	digest, err := proto.Marshal(d)
	if err != nil {
		return nil, err
	}
	b := appendField(nil, 1, digest)
	b = appendField(b, 2, []byte(instance))
	b = protowire.AppendVarint(protowire.AppendTag(b, 4, protowire.VarintType), 2) // CAS
	b = protowire.AppendVarint(protowire.AppendTag(b, 5, protowire.VarintType), uint64(re.DigestFunction_SHA256))
	return b, nil
}
func bytesFields(b []byte, field protowire.Number) ([][]byte, error) {
	var values [][]byte
	for len(b) > 0 {
		num, typ, n := protowire.ConsumeTag(b)
		if n < 0 {
			return nil, protowire.ParseError(n)
		}
		b = b[n:]
		if num == field {
			if typ != protowire.BytesType {
				return nil, fmt.Errorf("field %d has invalid type", num)
			}
			v, m := protowire.ConsumeBytes(b)
			if m < 0 {
				return nil, protowire.ParseError(m)
			}
			values = append(values, v)
			b = b[m:]
		} else {
			n := protowire.ConsumeFieldValue(num, typ, b)
			if n < 0 {
				return nil, protowire.ParseError(n)
			}
			b = b[n:]
		}
	}
	return values, nil
}
func localMissing(conn *grpc.ClientConn, instance string, digests []*re.Digest) (int, error) {
	total := 0
	for i := 0; i < len(digests); i += 512 {
		var request rawMessage
		for _, d := range digests[i:min(i+512, len(digests))] {
			r, err := resourceWire(instance, d)
			if err != nil {
				return 0, err
			}
			request = appendField(request, 3, r)
		}
		var response rawMessage
		ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		err := conn.Invoke(ctx, "/distributed_cache.DistributedCache/FindMissing", &request, &response, grpc.ForceCodec(peerCodec{}))
		cancel()
		if err != nil {
			return 0, err
		}
		fields, err := bytesFields(response, 1)
		if err != nil {
			return 0, err
		}
		total += len(fields)
	}
	return total, nil
}
func localDownload(ctx context.Context, conn *grpc.ClientConn, instance string, b blob) error {
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	resource, err := resourceWire(instance, b.digest)
	if err != nil {
		return err
	}
	request := rawMessage(appendField(nil, 6, resource))
	stream, err := conn.NewStream(ctx, &grpc.StreamDesc{ServerStreams: true}, "/distributed_cache.DistributedCache/Read", grpc.ForceCodec(peerCodec{}))
	if err != nil {
		return err
	}
	if err = stream.SendMsg(&request); err != nil {
		return err
	}
	if err = stream.CloseSend(); err != nil {
		return err
	}
	h := sha256.New()
	var n int64
	for {
		var response rawMessage
		err := stream.RecvMsg(&response)
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		refs, err := bytesFields(response, 2)
		if err != nil {
			return err
		}
		if len(refs) > 0 {
			return fmt.Errorf("local backend returned shared-storage reference, not local bytes")
		}
		data, err := bytesFields(response, 1)
		if err != nil {
			return err
		}
		for _, chunk := range data {
			n += int64(len(chunk))
			if n > b.digest.SizeBytes {
				return fmt.Errorf("oversized local read")
			}
			h.Write(chunk)
		}
	}
	if n != b.digest.SizeBytes || hex.EncodeToString(h.Sum(nil)) != b.digest.Hash {
		return fmt.Errorf("corrupt/short local replica read")
	}
	return nil
}
