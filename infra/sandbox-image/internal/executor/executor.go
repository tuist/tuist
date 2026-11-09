// Package executor runs one authenticated action as an unprivileged command.
package executor

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"runtime/debug"
	"syscall"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	worker "github.com/tuist/tuist/infra/sandbox-image/internal/reapi"
	"google.golang.org/grpc/metadata"
	"google.golang.org/protobuf/proto"
	"google.golang.org/protobuf/types/known/anypb"
	"google.golang.org/protobuf/types/known/structpb"
)

type request struct {
	Endpoint string `json:"endpoint"`
	Account  string `json:"account"`
	Instance string `json:"instance"`
	Hash     string `json:"hash"`
	Size     int64  `json:"size"`
	Image    string `json:"image"`
	Inputs   string `json:"inputs"`
}

const actionMemoryLimit = 256 << 20

// ConfigureRuntime prepares an agent that will run one action and then be
// destroyed with its VM: collecting garbage would only add pauses, so the Go
// runtime collects only near the limit. It runs once, before the template
// snapshot, so restored VMs pay nothing per action.
func ConfigureRuntime() {
	debug.SetGCPercent(-1)
	debug.SetMemoryLimit(actionMemoryLimit)
}

type result struct {
	Response  string `json:"response"`
	Cacheable bool   `json:"cacheable"`
}

// Run executes one action. Only its command runs under no_new_privs; see
// startWithoutNewPrivileges.
func Run(ctx context.Context, requestJSON, token string) (string, error) {
	return (&Session{}).Run(ctx, requestJSON, token)
}

func (s *Session) Run(parent context.Context, requestJSON, token string) (string, error) {
	var r request
	if err := json.Unmarshal([]byte(requestJSON), &r); err != nil {
		return "", err
	}
	if token == "" {
		return "", fmt.Errorf("missing execution credential")
	}
	conn, err := s.takeClient(r.Endpoint)
	if err != nil {
		return "", err
	}
	defer conn.Close()
	ctx, cancel := context.WithTimeout(parent, 12*time.Minute)
	defer cancel()
	ctx = metadata.NewOutgoingContext(ctx, metadata.Pairs("authorization", "Bearer "+token, "x-tuist-account-handle", r.Account))
	w := worker.Worker{CAS: worker.NewCAS(conn, r.Instance), Root: actionRoot, Image: r.Image, Credential: &syscall.Credential{Uid: 1000, Gid: 1000}, Start: startWithoutNewPrivileges}
	w.CAS.Seed(r.Inputs)
	w.CAS.Host = hostBlobs{dial: dialHost}
	response, cacheable := w.Execute(ctx, &re.Digest{Hash: r.Hash, SizeBytes: r.Size})
	if md := response.GetResult().GetExecutionMetadata(); md != nil {
		if timings, err := casReadTimings(w.CAS, r.Endpoint, s.reused); err == nil {
			md.AuxiliaryMetadata = append(md.AuxiliaryMetadata, timings)
		}
	}
	b, err := proto.Marshal(response)
	if err != nil {
		return "", err
	}
	// The gateway publishes cacheable results after answering the client.
	out, err := json.Marshal(result{Response: base64.StdEncoding.EncodeToString(b), Cacheable: cacheable})
	if err != nil {
		return "", err
	}
	return string(out) + "\n", nil
}

// casReadTimingsKind marks the auxiliary metadata executiongateway logs with an
// action's phases, to attribute slow input fetches to individual CAS reads.
const casReadTimingsKind = "tuist.cas_reads"

func casReadTimings(cas *worker.CAS, endpoint string, reused bool) (*anypb.Any, error) {
	fields := cas.ReadTimings()
	fields["kind"] = casReadTimingsKind
	fields["endpoint"] = endpoint
	fields["prepared_connection"] = reused
	s, err := structpb.NewStruct(fields)
	if err != nil {
		return nil, err
	}
	return anypb.New(s)
}
