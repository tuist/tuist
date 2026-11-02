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
)

type request struct {
	Endpoint string `json:"endpoint"`
	Account  string `json:"account"`
	Instance string `json:"instance"`
	Hash     string `json:"hash"`
	Size     int64  `json:"size"`
	Image    string `json:"image"`
	Inputs   string `json:"inputs"`
	// Set when the gateway stores small outputs itself before answering.
	InlineOutputs bool `json:"inline_outputs"`
}

const actionMemoryLimit = 256 << 20

// Base64 of this many bytes stays within the control plane's result bound
// next to the largest response.
const inlineOutputBytes = 48 << 10

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
	Outputs   string `json:"outputs,omitempty"`
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
	if r.InlineOutputs {
		w.InlineBytes = inlineOutputBytes
	}
	w.CAS.Seed(r.Inputs)
	response, cacheable := w.Execute(ctx, &re.Digest{Hash: r.Hash, SizeBytes: r.Size})
	return encodeResult(response, cacheable, w.Inlined())
}

// The gateway publishes cacheable results after answering the client.
func encodeResult(response *re.ExecuteResponse, cacheable bool, inlined *re.BatchUpdateBlobsRequest) (string, error) {
	b, err := proto.Marshal(response)
	if err != nil {
		return "", err
	}
	r := result{Response: base64.StdEncoding.EncodeToString(b), Cacheable: cacheable}
	if len(inlined.GetRequests()) > 0 {
		encoded, err := proto.Marshal(inlined)
		if err != nil {
			return "", err
		}
		r.Outputs = base64.StdEncoding.EncodeToString(encoded)
	}
	out, err := json.Marshal(r)
	if err != nil {
		return "", err
	}
	return string(out) + "\n", nil
}
