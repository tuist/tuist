package podagent

import (
	"context"
	"fmt"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"time"
)

// startHostKuraProcess is the default ProcessStarter: it execs the kura binary
// on the host with a per-account, plaintext-peering configuration and returns a
// handle that health-checks over HTTP and terminates on Stop.
//
// Ports are the reserved block base (cache HTTP), base+1 (gRPC), base+2
// (internal/peer). No KURA_INTERNAL_TLS_* is set, so Kura peers over plaintext
// http (see plan §3.2); KURA_PEERS points at the account's EM peer when present,
// with bootstrap enabled so the node catches up from EM before serving.
func startHostKuraProcess(ctx context.Context, binary string, spec KuraSpec) (KuraProcess, error) {
	tmpDir := filepath.Join(spec.DataDir, "tmp")
	if err := os.MkdirAll(tmpDir, 0o755); err != nil {
		return nil, fmt.Errorf("create kura tmp dir: %w", err)
	}

	httpPort := spec.Port

	// The process outlives this ctx (it is a persistent per-account node), so it
	// is started with context.Background(); Stop() terminates it.
	cmd := exec.Command(binary)
	cmd.Env = hostKuraEnv(spec, tmpDir)
	if err := cmd.Start(); err != nil {
		return nil, fmt.Errorf("exec kura: %w", err)
	}

	return &execKuraProcess{cmd: cmd, readyURL: "http://127.0.0.1:" + strconv.Itoa(httpPort) + "/ready"}, nil
}

// hostKuraEnv builds the environment for a per-account host Kura. The ports are
// the reserved block base (cache HTTP), base+1 (gRPC), base+2 (internal/peer);
// no KURA_INTERNAL_TLS_* is set so peering is plaintext http; KURA_PEERS points
// at the account's EM peer when present, with bootstrap enabled so the node
// catches up from EM before serving. The OTEL identity vars are REQUIRED — kura
// exits at startup with "missing required environment variables" without them.
func hostKuraEnv(spec KuraSpec, tmpDir string) []string {
	bootstrap := "false"
	if spec.PeerURL != "" {
		bootstrap = "true"
	}
	return append(os.Environ(),
		"KURA_DATA_DIR="+spec.DataDir,
		"KURA_TMP_DIR="+tmpDir,
		"KURA_TENANT_ID="+spec.AccountID,
		"KURA_REGION=runner-local",
		"KURA_PORT="+strconv.Itoa(spec.Port),
		"KURA_GRPC_PORT="+strconv.Itoa(spec.Port+1),
		"KURA_INTERNAL_PORT="+strconv.Itoa(spec.Port+2),
		"KURA_NODE_URL=http://127.0.0.1:"+strconv.Itoa(spec.Port+2),
		"KURA_PEERS="+spec.PeerURL,
		"KURA_BOOTSTRAP_ENABLED="+bootstrap,
		"KURA_ACCELERATED_FILE_SERVING_ENABLED=false",
		"KURA_OTEL_SERVICE_NAME=tuist-runner-host-kura",
		"KURA_OTEL_DEPLOYMENT_ENVIRONMENT=runner-local",
	)
}

type execKuraProcess struct {
	cmd      *exec.Cmd
	readyURL string
}

func (p *execKuraProcess) Ready(ctx context.Context) bool {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, p.readyURL, nil)
	if err != nil {
		return false
	}
	client := &http.Client{Timeout: 2 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return false
	}
	defer resp.Body.Close()
	return resp.StatusCode == http.StatusOK
}

func (p *execKuraProcess) Stop() error {
	if p.cmd.Process == nil {
		return nil
	}
	// Signal, then reap so the child does not linger as a zombie.
	_ = p.cmd.Process.Kill()
	_, _ = p.cmd.Process.Wait()
	return nil
}
