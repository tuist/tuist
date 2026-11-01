package executor

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"io"
	"net"
	"os"
	"syscall"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	worker "github.com/tuist/tuist/infra/sandbox-image/internal/reapi"
	bs "google.golang.org/genproto/googleapis/bytestream"
	rpc "google.golang.org/genproto/googleapis/rpc/status"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/proto"
)

const warmRoot = "/workspace/warm"

// A guest restored from the template snapshot faults in every page on first
// touch. Preparation executes one throwaway action through the worker, before
// any credential or input exists, so the admitted action does not pay for
// that. The action's CAS is an in-process server on loopback; nothing leaves
// the guest. It is best-effort.
func warm(ctx context.Context) {
	_, _ = warmAction(ctx, warmRoot, &syscall.Credential{Uid: 1000, Gid: 1000})
	_ = os.RemoveAll(warmRoot)
}

func warmAction(ctx context.Context, root string, credential *syscall.Credential) (*re.ExecuteResponse, error) {
	cas := loopbackCAS{blobs: map[string][]byte{}}
	input := cas.put([]byte("warm\n"))
	inputRoot := cas.putMessage(&re.Directory{Files: []*re.FileNode{{Name: "in", Digest: input}}})
	command := cas.putMessage(&re.Command{
		Arguments:            []string{"/bin/sh", "-c", "cat in > out"},
		EnvironmentVariables: []*re.Command_EnvironmentVariable{{Name: "PATH", Value: "/usr/bin:/bin"}},
		OutputPaths:          []string{"out"},
	})
	action := cas.putMessage(&re.Action{CommandDigest: command, InputRootDigest: inputRoot, Platform: &re.Platform{Properties: []*re.Platform_Property{
		{Name: "Arch", Value: "amd64"}, {Name: "OSFamily", Value: "Linux"}, {Name: "tuist-image", Value: "warm"},
	}}})

	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	s := grpc.NewServer()
	re.RegisterContentAddressableStorageServer(s, &cas)
	re.RegisterActionCacheServer(s, &cas)
	bs.RegisterByteStreamServer(s, &cas)
	go func() { _ = s.Serve(l) }()
	defer s.Stop()
	conn, err := worker.Dial("grpc://" + l.Addr().String())
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	w := worker.Worker{CAS: worker.NewCAS(conn, "warm"), Root: root, Image: "warm", Credential: credential}
	response, _ := w.Execute(ctx, action, false)
	return response, nil
}

type loopbackCAS struct {
	re.UnimplementedContentAddressableStorageServer
	re.UnimplementedActionCacheServer
	bs.UnimplementedByteStreamServer
	blobs map[string][]byte
}

func (c *loopbackCAS) put(b []byte) *re.Digest {
	h := sha256.Sum256(b)
	d := &re.Digest{Hash: hex.EncodeToString(h[:]), SizeBytes: int64(len(b))}
	c.blobs[d.Hash] = b
	return d
}

func (c *loopbackCAS) putMessage(m proto.Message) *re.Digest {
	b, _ := proto.Marshal(m)
	return c.put(b)
}

func (c *loopbackCAS) BatchReadBlobs(_ context.Context, r *re.BatchReadBlobsRequest) (*re.BatchReadBlobsResponse, error) {
	response := &re.BatchReadBlobsResponse{}
	for _, d := range r.Digests {
		item := &re.BatchReadBlobsResponse_Response{Digest: d, Status: &rpc.Status{}}
		if b, ok := c.blobs[d.Hash]; ok {
			item.Data = b
		} else {
			item.Status.Code = int32(codes.NotFound)
		}
		response.Responses = append(response.Responses, item)
	}
	return response, nil
}

func (c *loopbackCAS) GetActionResult(context.Context, *re.GetActionResultRequest) (*re.ActionResult, error) {
	return nil, status.Error(codes.NotFound, "not found")
}

func (c *loopbackCAS) Write(s bs.ByteStream_WriteServer) error {
	var size int64
	for {
		r, err := s.Recv()
		if err == io.EOF {
			break
		}
		if err != nil {
			return err
		}
		size += int64(len(r.Data))
		if r.FinishWrite {
			break
		}
	}
	return s.SendAndClose(&bs.WriteResponse{CommittedSize: size})
}
