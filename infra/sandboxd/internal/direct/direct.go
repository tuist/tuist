// Package direct serves claims of claimed execs (DIRECT_EXEC_ADDR) to the
// execution gateway, so an action's request and result skip the server. A
// claim is authorized by its single-use nonce, which the server issues to
// the gateway with the claim; the network policy admits only gateway Pods.
package direct

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"time"

	"github.com/tuist/tuist/infra/sandboxd/internal/sandbox"
)

const (
	maxRequestBytes = 4 << 20
	// The server replies to the gateway while its exec is on the way here.
	registrationWait = 2 * time.Second
)

type Claimer interface {
	Claim(ctx context.Context, sandboxID string, nonce []byte, value string, registration time.Duration) (sandbox.ClaimOutcome, error)
}

type claimRequest struct {
	SandboxID string `json:"sandbox_id"`
	Nonce     []byte `json:"nonce"`
	Value     string `json:"value"`
}

type claimResponse struct {
	ExitCode int    `json:"exit_code"`
	Stdout   []byte `json:"stdout"`
}

func NewHandler(claims Claimer) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /v1/claims", func(w http.ResponseWriter, r *http.Request) {
		var req claimRequest
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, maxRequestBytes)).Decode(&req); err != nil || req.SandboxID == "" || len(req.Nonce) != 32 {
			http.Error(w, "invalid claim", http.StatusBadRequest)
			return
		}
		outcome, err := claims.Claim(r.Context(), req.SandboxID, req.Nonce, req.Value, registrationWait)
		switch {
		case errors.Is(err, sandbox.ErrClaimRefused):
			http.Error(w, "no such claim", http.StatusNotFound)
			return
		case err != nil:
			http.Error(w, "claim interrupted", http.StatusServiceUnavailable)
			return
		case outcome.Err != nil:
			http.Error(w, "exec failed", http.StatusBadGateway)
			return
		}
		w.Header().Set("Content-Type", "application/json")
		_ = json.NewEncoder(w).Encode(claimResponse{ExitCode: outcome.ExitCode, Stdout: outcome.Stdout})
	})
	return mux
}
