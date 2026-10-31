// Package executor runs one authenticated action as an unprivileged command.
package executor

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"syscall"
	"time"

	re "github.com/bazelbuild/remote-apis/build/bazel/remote/execution/v2"
	worker "github.com/tuist/tuist/infra/sandbox-image/internal/reapi"
	"google.golang.org/grpc/metadata"
	"google.golang.org/protobuf/proto"
)

type request struct {
	Endpoint  string `json:"endpoint"`
	Account   string `json:"account"`
	Instance  string `json:"instance"`
	Hash      string `json:"hash"`
	Size      int64  `json:"size"`
	Image     string `json:"image"`
	SkipCache bool   `json:"skip_cache"`
}

type result struct {
	Response  string `json:"response"`
	Cacheable bool   `json:"cacheable"`
}

// Run uses a dedicated OS thread for the irreversible no_new_privs attribute.
// The goroutine exits while still locked, so Go destroys the thread rather
// than letting another agent operation inherit its changed security state.
func Run(ctx context.Context, requestJSON, token string) (string, error) {
	return (&Session{}).Run(ctx, requestJSON, token)
}

func (s *Session) Run(ctx context.Context, requestJSON, token string) (string, error) {
	type outcome struct {
		output string
		err    error
	}
	done := make(chan outcome, 1)
	go func() {
		if err := prepareExecution(); err != nil {
			done <- outcome{err: err}
			return
		}
		output, err := s.run(ctx, requestJSON, token)
		done <- outcome{output, err}
	}()
	r := <-done
	return r.output, r.err
}

func (s *Session) run(parent context.Context, requestJSON, token string) (string, error) {

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
	w := worker.Worker{CAS: worker.NewCAS(conn, r.Instance), Root: "/workspace/action", Image: r.Image, Credential: &syscall.Credential{Uid: 1000, Gid: 1000}}
	response, cacheable := w.Execute(ctx, &re.Digest{Hash: r.Hash, SizeBytes: r.Size}, r.SkipCache)
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
