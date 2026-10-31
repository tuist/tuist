package executor

import (
	"context"
	"io"
	"net"
	"os/exec"
	"strings"
	"syscall"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	worker "github.com/tuist/tuist/infra/sandbox-image/internal/reapi"
	bs "google.golang.org/genproto/googleapis/bytestream"
	rpc "google.golang.org/genproto/googleapis/rpc/status"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
)

// A guest restored from the template snapshot faults in every page on first
// touch. Preparation runs the action's shell and CAS client paths once, before
// any credential or input exists, so the action does not pay for that. Both
// steps are best-effort.
func warm(ctx context.Context) {
	cmd := exec.CommandContext(ctx, "/bin/sh", "-c", "cat /dev/null")
	cmd.Dir = "/"
	cmd.Env = []string{"PATH=/usr/bin:/bin"}
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true, Credential: &syscall.Credential{Uid: 1000, Gid: 1000}}
	_ = cmd.Run()
	warmCAS(ctx)
}

// warmCAS reads and writes through the CAS client against an in-process server
// on loopback; nothing leaves the guest.
func warmCAS(ctx context.Context) {
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return
	}
	s := grpc.NewServer()
	re.RegisterContentAddressableStorageServer(s, &loopbackCAS{})
	bs.RegisterByteStreamServer(s, &loopbackCAS{})
	go func() { _ = s.Serve(l) }()
	defer s.Stop()
	conn, err := worker.Dial("grpc://" + l.Addr().String())
	if err != nil {
		return
	}
	defer conn.Close()
	cas := worker.NewCAS(conn, "warm")
	_, _ = cas.ReadBatch(ctx, []*re.Digest{{Hash: strings.Repeat("0", 64), SizeBytes: 1}})
	_, _ = cas.Write(ctx, strings.NewReader("warm"))
}

type loopbackCAS struct {
	re.UnimplementedContentAddressableStorageServer
	bs.UnimplementedByteStreamServer
}

func (loopbackCAS) BatchReadBlobs(_ context.Context, r *re.BatchReadBlobsRequest) (*re.BatchReadBlobsResponse, error) {
	response := &re.BatchReadBlobsResponse{}
	for _, d := range r.Digests {
		response.Responses = append(response.Responses, &re.BatchReadBlobsResponse_Response{Digest: d, Status: &rpc.Status{Code: int32(codes.NotFound)}})
	}
	return response, nil
}

func (loopbackCAS) Write(s bs.ByteStream_WriteServer) error {
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
